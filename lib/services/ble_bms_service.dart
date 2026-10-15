import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/bms_data.dart';
import 'bms_data_service.dart';
import 'jikong_protocol.dart';

/// 真实极空保护板 BLE 服务。
///
/// 极空板常见 UUID：
///   - 服务：0xFFE0（0000ffe0-0000-1000-8000-00805f9b34fb）
///   - 特征：0xFFE1（0000ffe1-...，notify + write）
/// 部分型号使用 ffe5/ffe9。若你的板子不同，改 [serviceUuid]/[charUuid]。
class BleBmsService extends BmsDataService {
  final _controller = StreamController<BmsData>.broadcast();
  final String serviceUuid;
  final String charUuid;
  final int cellCount;

  BleBmsService({
    this.serviceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb',
    this.charUuid = '0000ffe1-0000-1000-8000-00805f9b34fb',
    this.cellCount = 16,
  });

  BluetoothDevice? _device;
  BluetoothCharacteristic? _char; // notify：订阅数据
  BluetoothCharacteristic? _writeChar; // write：下发命令
  StreamSubscription? _sub;
  Timer? _pollTimer;
  final List<int> _buf = [];
  final JkStatusParser _parser = JkStatusParser();
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  String? lastError;

  @override
  Stream<BmsData> get dataStream => _controller.stream;

  @override
  Future<List<BmsDevice>> scan({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final results = <ScanResult>[];
    StreamSubscription<List<ScanResult>>? sub;
    try {
      sub = FlutterBluePlus.scanResults.listen((r) {
        results
          ..clear()
          ..addAll(r);
      });
      // 全量扫描（不过滤服务 UUID），兼容不同板子的广播服务
      await FlutterBluePlus.startScan(timeout: timeout);
      await Future.delayed(const Duration(milliseconds: 900));
    } catch (_) {
      // 无权限或已停止扫描，忽略
    }
    await sub?.cancel();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    final seen = <String, BmsDevice>{};
    for (final r in results) {
      final name = r.device.platformName.isNotEmpty
          ? r.device.platformName
          : r.device.remoteId.str;
      seen[r.device.remoteId.str] =
          BmsDevice(name: name, id: r.device.remoteId.str, rssi: r.rssi);
    }
    return seen.values.toList();
  }

  @override
  Future<bool> connect(String deviceId) async {
    lastError = null;
    try {
      _device = BluetoothDevice.fromId(deviceId);
      await _device!.connect(timeout: const Duration(seconds: 12));
      await _device!.discoverServices();
      // 收集所有服务的 notify 特征与 write 特征，分开处理：
      //  - notify 特征：订阅，板子在这里推送数据（优先 ffe1，次选任意）
      //  - write 特征：下发读命令（优先 ffe5/ffe2/ffe3/ffe1，次选任意可写）
      final foundServices = <String>[];
      final notiCands = <BluetoothCharacteristic>[];
      final writeCands = <BluetoothCharacteristic>[];
      for (final s in _device!.servicesList) {
        foundServices.add(s.uuid.str);
        for (final c in s.characteristics) {
          final p = c.properties;
          if (p.notify || p.indicate) notiCands.add(c);
          if (p.write || p.writeWithoutResponse) writeCands.add(c);
        }
      }
      BluetoothCharacteristic? pick(
          List<BluetoothCharacteristic> cands, List<String> pref) {
        BluetoothCharacteristic? first;
        for (final c in cands) {
          first ??= c;
          final u = c.uuid.str.toLowerCase();
          if (pref.any((x) => u.contains(x))) return c;
        }
        return first;
      }
      final noti = pick(notiCands, const ['ffe1', 'ffe5', 'ffe9']);
      var w = pick(writeCands, const ['ffe5', 'ffe2', 'ffe3', 'ffe1', 'ffe9']);
      // 若没有任何独立可写特征，退而用 notify 特征本身发命令
      w ??= (noti != null &&
              (noti.properties.write || noti.properties.writeWithoutResponse))
          ? noti
          : null;
      _char = noti;
      _writeChar = w;
      if (_char == null) {
        lastError =
            '未找到可通知特征(数据上报)。板子服务: ${foundServices.isEmpty ? "无" : foundServices.join(", ")}';
        try {
          await _device!.disconnect();
        } catch (_) {}
        return false;
      }
      if (_writeChar == null) {
        lastError = '未找到可写特征(发命令)，将尝试只订阅数据';
      }
      await _char!.setNotifyValue(true);
      _sub = _char!.onValueReceived.listen(_onData);
      _connected = true;
      // 周期性下发读命令（写到 write 特征），并首帧立即读一次
      _pollTimer = Timer.periodic(const Duration(milliseconds: 800), (_) => _read());
      _read();
      return true;
    } catch (e) {
      lastError = '连接异常：$e';
      try {
        await _device?.disconnect();
      } catch (_) {}
      return false;
    }
  }

  void _read() {
    _write(JkProtocol.buildReadCommand(reg: 0x00, count: 0x60));
  }

  Future<void> _write(List<int> bytes) async {
    final target = _writeChar ?? _char;
    if (target == null) return;
    try {
      await target.write(bytes, withoutResponse: false);
    } catch (_) {}
  }

  /// 累积字节流，按 55 AA 帧头 + 长度拆帧并解析。
  void _onData(List<int> bytes) {
    _buf.addAll(bytes);
    while (true) {
      if (_buf.length < 6) break;
      // 对齐帧头
      final h = _buf.indexOf(0x55);
      if (h < 0) {
        _buf.clear();
        break;
      }
      if (h > 0) {
        _buf.removeRange(0, h);
      }
      final len = _buf[2] | (_buf[3] << 8);
      if (_buf.length < 4 + len + 2) break;
      final frame = List.of(_buf.sublist(0, 4 + len + 2));
      _buf.removeRange(0, 4 + len + 2);
      final payload = JkProtocol.parseTelemetry(frame);
      if (payload != null) {
        final p = JkStatusParser(cellCount: cellCount).parse(payload);
        _controller.add(_toData(p));
      }
    }
  }

  BmsData _toData(JkParsedStatus p) {
    final maxV = p.maxCellV, minV = p.minCellV;
    final delta = maxV - minV;
    final balancing = p.balanceStatus != 0;
    return BmsData(
      totalVoltage: p.totalVoltage,
      current: p.current,
      power: p.power,
      soc: p.soc,
      remainingCapacity: p.remainingCapacity,
      nominalCapacity: p.nominalCapacity,
      cellVoltages: p.cellVoltages,
      cellResistances:
          List.filled(p.cellVoltages.length, 0.0), // 均衡线电阻需对应寄存器
      temperatures: p.temperatures,
      maxCellV: maxV,
      minCellV: minV,
      balancing: balancing,
      balanceStatus: p.balanceStatus,
      logCount: 0,
      cycles: p.cycles,
      sleepSeconds: 86400,
      batteryType: '铁锂',
      buzzerOn: false,
      alarm: delta > 0.3,
      alarmDesc: delta > 0.3 ? '单体压差过大' : '',
    );
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _sub?.cancel();
    _sub = null;
    try {
      if (_char != null) await _char!.setNotifyValue(false);
    } catch (_) {}
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _char = null;
    _writeChar = null;
    _buf.clear();
  }

  @override
  Future<bool> writeRegister(int reg, int value) async {
    try {
      await _write(JkProtocol.buildWriteRegister(reg, value));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    disconnect();
    _controller.close();
  }
}
