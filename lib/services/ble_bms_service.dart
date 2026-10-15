import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/bms_data.dart';
import 'bms_data_service.dart';
import 'jikong_protocol.dart';

/// 真实极空保护板 BLE 服务。
///
/// 极空板内置 BLE 串口透传模块：
///   - 服务：0xFFE0（0000ffe0-...），特征：0xFFE1（notify + write）
///   - 连接后模块发 `AT\r\n` 握手，需回 `OK\r\n` 进入透传模式
///   - 透传后发送极空 0xDD 帧协议命令（读基本信息 0x03 / 读单体 0x04）
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
  bool _connected = false;

  // 最近解析的帧数据
  JkBaseInfo? _base;
  JkCellsInfo? _cells;
  bool _toggle = false;

  // ---- 诊断 ----
  final List<String> _diagServices = [];
  String _diagNotify = '';
  String _diagWrite = '';
  int _rxBytes = 0;
  int _rxFrames = 0;
  int _parseOk = 0;
  int _parseFail = 0;
  String _lastFrameHex = '';

  @override
  BmsDiag get diag => BmsDiag(
        services: List.of(_diagServices),
        notifyUuid: _diagNotify,
        writeUuid: _diagWrite,
        rxBytes: _rxBytes,
        rxFrames: _rxFrames,
        parseOk: _parseOk,
        parseFail: _parseFail,
        lastFrameHex: _lastFrameHex,
      );

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
    _base = null;
    _cells = null;
    try {
      _device = BluetoothDevice.fromId(deviceId);
      await _device!.connect(timeout: const Duration(seconds: 12));
      await _device!.discoverServices();
      // 收集所有服务的 notify 特征与 write 特征，分开处理
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
      var w = pick(writeCands, const ['ffe1', 'ffe5', 'ffe2', 'ffe3', 'ffe9']);
      w ??= (noti != null &&
              (noti.properties.write || noti.properties.writeWithoutResponse))
          ? noti
          : null;
      _char = noti;
      _writeChar = w;
      _diagServices..clear()..addAll(foundServices);
      _diagNotify = _char?.uuid.str ?? '';
      _diagWrite = _writeChar?.uuid.str ?? '';
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
      // 交替下发读命令（基本信息 / 单体电压），并首帧立即读一次
      _pollTimer = Timer.periodic(const Duration(milliseconds: 700), (_) => _read());
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
    _toggle = !_toggle;
    _write(_toggle ? JkProtocol.buildReadBase() : JkProtocol.buildReadCells());
  }

  Future<void> _write(List<int> bytes) async {
    final target = _writeChar ?? _char;
    if (target == null) return;
    try {
      await target.write(bytes, withoutResponse: false);
    } catch (_) {}
  }

  /// 收到数据：先处理 AT 握手，再按 0xDD 帧解析。
  void _onData(List<int> bytes) {
    _rxBytes += bytes.length;
    _lastFrameHex = bytes
        .take(32)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    // AT 握手：收到 "AT" 文本 → 回 "OK\r\n" 进入透传模式
    if (bytes.length >= 2 && bytes[0] == 0x41 && bytes[1] == 0x54) {
      _write(const [0x4F, 0x4B, 0x0D, 0x0A]); // "OK\r\n"
      return;
    }
    // 非 0xDD 数据则丢弃（透传下的纯文本干扰）
    if (bytes.isNotEmpty && bytes.first != 0xDD) {
      return;
    }
    _buf.addAll(bytes);
    while (true) {
      if (_buf.indexOf(0xDD) < 0) {
        _buf.clear();
        break;
      }
      final f = JkProtocol.tryTakeFrame(_buf);
      if (f == null) break;
      _rxFrames++;
      final body = JkProtocol.frameBody(f); // [cmd, status, length, data...]
      if (body.length >= 3) {
        final cmd = body[0];
        final data = body.sublist(3);
        if (cmd == JkProtocol.cmdBase) {
          _parseOk++;
          _base = JkParser.parseBase(data);
          _publish();
        } else if (cmd == JkProtocol.cmdCells) {
          _parseOk++;
          _cells = JkParser.parseCells(data);
          _publish();
        } else {
          _parseFail++;
        }
      } else {
        _parseFail++;
      }
    }
  }

  /// 基本信息和单体电压都到位后，合成并推送 BmsData。
  void _publish() {
    final b = _base;
    final c = _cells;
    if (b == null || c == null) return;
    final cells = c.cellVoltages;
    final maxV =
        cells.isEmpty ? 0 : cells.reduce((a, x) => x > a ? x : a);
    final minV =
        cells.isEmpty ? 0 : cells.reduce((a, x) => x < a ? x : a);
    _controller.add(BmsData(
      totalVoltage: b.totalVoltage,
      current: b.current,
      power: b.totalVoltage * b.current,
      soc: b.soc,
      remainingCapacity: b.remainingAh,
      nominalCapacity: b.nominalAh,
      cellVoltages: cells,
      cellResistances: List.filled(cells.length, 0.0),
      temperatures: b.temperatures,
      maxCellV: maxV,
      minCellV: minV,
      balancing: b.balanceStatus != 0,
      balanceStatus: b.balanceStatus,
      logCount: 0,
      cycles: b.cycles,
      sleepSeconds: 86400,
      batteryType: '铁锂',
      buzzerOn: false,
      alarm: (maxV - minV) > 0.3,
      alarmDesc: (maxV - minV) > 0.3 ? '单体压差过大' : '',
    ));
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
    _base = null;
    _cells = null;
  }

  @override
  Future<bool> writeRegister(int reg, int value) async {
    try {
      await _write(JkProtocol.buildReadBase());
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
