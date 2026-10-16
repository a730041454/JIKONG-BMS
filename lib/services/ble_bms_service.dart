import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
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
  /// 收到保护板 device 帧时回调其蓝牙密码（用于同步到应用设置密码）。
  ValueChanged<String>? onBluetoothPassword;

  BleBmsService({
    this.serviceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb',
    this.charUuid = '0000ffe1-0000-1000-8000-00805f9b34fb',
    this.cellCount = 16,
    this.onBluetoothPassword,
  });

  BluetoothDevice? _device;
  BluetoothCharacteristic? _char; // notify：订阅数据
  BluetoothCharacteristic? _writeChar; // write：下发命令
  StreamSubscription? _sub;
  Timer? _pollTimer;
  final List<int> _buf = [];
  bool _connected = false;

  // 最近解析的帧数据
  JkCellInfo? _cell;
  JkDeviceInfo? _deviceInfo;
  int _readTick = 0;

  // ---- 诊断 ----
  final List<String> _diagServices = [];
  String _diagNotify = '';
  String _diagWrite = '';
  int _rxBytes = 0;
  int _rxFrames = 0;
  int _parseOk = 0;
  int _parseFail = 0;
  String _lastFrameHex = '';
  String _rxLog = '';
  String _sentHex = '';
  Timer? _handshakeTimer;

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
        rxLog: _rxLog,
        sentHex: _sentHex,
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
    _cell = null;
    _deviceInfo = null;
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
      // 关键：先发 0x97 唤醒(wakeup)，再发一次 0x96 读实时数据。
      // 极空 HW15 新固件必须先唤醒；唤醒+读一次后板子会持续被动推送 cell 帧，
      // 因此不再周期下发查询指令（周期查询会使保护板蜂鸣器持续响）。
      _write(JkProtocol.buildReadDevice()); // 0x97 唤醒 + 设备信息
      await Future.delayed(const Duration(milliseconds: 250));
      _read(); // 0x96 读实时数据（之后板子持续被动推送）
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
    _readTick++;
    _write(JkProtocol.buildReadCell());
    if (_readTick % 20 == 0) {
      _write(JkProtocol.buildReadDevice());
    }
  }

  /// 页面切换时按当前页发送对应的参数读请求（一次性低频，非周期查询）。
  ///   page 0=实时/1=首页 → cell+device；page 2=参数设置 → settings+cell。
  void requestPage(int page) {
    if (!_connected) return;
    _write(JkProtocol.buildReadCell());
    if (page == 2) {
      _write(JkProtocol.buildReadSettings());
    } else {
      _write(JkProtocol.buildReadDevice());
    }
  }

  Future<void> _write(List<int> bytes) async {
    final target = _writeChar ?? _char;
    if (target == null) return;
    _sentHex = bytes
        .take(48)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    try {
      await target.write(bytes, withoutResponse: false);
    } catch (_) {}
  }

  /// 收到数据：记录原始字节；先处理 AT 握手，再按 0xDD 帧解析。
  void _onData(List<int> bytes) {
    _rxBytes += bytes.length;
    _lastFrameHex = bytes
        .take(32)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    // 记录所有原始字节，便于确认板子推送格式（含非 0xDD 数据）
    final hex = bytes
        .take(80)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    _rxLog = (_rxLog.isEmpty ? '' : '$_rxLog ') + hex;
    if (_rxLog.length > 560) {
      _rxLog = _rxLog.substring(_rxLog.length - 560);
    }
    // AT 提示帧忽略（极空板连接后持续发，非数据，无需回显）
    if (bytes.length >= 2 && bytes[0] == 0x41 && bytes[1] == 0x54) {
      return;
    }
    // JK02(55AA) 拼帧解析
    _buf.addAll(bytes);
    while (true) {
      final f = JkProtocol.tryTakeFrame(_buf);
      if (f == null) break;
      _rxFrames++;
      final type = f[4];
      try {
        if (type == JkProtocol.typeCell) {
          _parseOk++;
          _cell = JkParser.parseCell(f);
          _publish();
        } else if (type == JkProtocol.typeDevice) {
          _parseOk++;
          _deviceInfo = JkParser.parseDevice(f);
          final pwd = _deviceInfo?.bluetoothPassword ?? '';
          if (pwd.isNotEmpty) onBluetoothPassword?.call(pwd);
        } else {
          _parseFail++;
        }
      } catch (_) {
        _parseFail++;
      }
    }
  }

  /// 实时数据到位后合成并推送 BmsData。
  void _publish() {
    final c = _cell;
    if (c == null) return;
    final cells = c.cellVoltages;
    // 最高/最低只在已连接单体中计算（排除未连接的 0 值）
    final active = cells.where((x) => x > 0.1).toList();
    final maxV = active.isEmpty ? 0.0 : active.reduce((a, x) => x > a ? x : a);
    final minV = active.isEmpty ? 0.0 : active.reduce((a, x) => x < a ? x : a);
    _controller.add(BmsData(
      totalVoltage: c.totalVoltage,
      current: c.current,
      // 功率显示为绝对值（电流放电为负，功率只反映量值）
      power: (c.totalVoltage * c.current).abs(),
      soc: c.soc,
      remainingCapacity: c.remainingAh,
      nominalCapacity: c.nominalAh,
      cellVoltages: cells,
      cellResistances: c.cellResistances,
      temperatures: c.temperatures,
      maxCellV: maxV,
      minCellV: minV,
      balancing: c.balancingActive,
      chargeMos: c.chargeMos,
      dischargeMos: c.dischargeMos,
      balanceStatus: c.balancingActive ? 1 : 0,
      logCount: 0,
      cycles: c.cycles,
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
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
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
    _cell = null;
    _deviceInfo = null;
  }

  @override
  Future<bool> writeRegister(int reg, int value) async {
    try {
      await _write(JkProtocol.buildWriteRegister(reg, JkProtocol.u32le(value)));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 下发 MOS 开关写指令（充电 0x1D / 放电 0x1E / 均衡 0x1F）。
  Future<bool> setMos({
    bool? charge,
    bool? discharge,
    bool? balance,
  }) async {
    try {
      if (charge != null) {
        await _write(JkProtocol.buildChargeMos(charge));
        await Future.delayed(const Duration(milliseconds: 60));
      }
      if (discharge != null) {
        await _write(JkProtocol.buildDischargeMos(discharge));
        await Future.delayed(const Duration(milliseconds: 60));
      }
      if (balance != null) {
        await _write(JkProtocol.buildBalanceMos(balance));
        await Future.delayed(const Duration(milliseconds: 60));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 写串数（settings 偏移 114）。
  Future<bool> writeCellCount(int cells) async {
    try {
      await _write(JkProtocol.buildWriteCellCount(cells));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 写标称容量（settings 偏移 130，Ah → mAh）。
  Future<bool> writeCapacity(double ah) async {
    try {
      await _write(JkProtocol.buildWriteCapacity(ah));
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
