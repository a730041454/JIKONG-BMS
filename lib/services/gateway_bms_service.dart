import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/bms_data.dart';
import 'bms_data_service.dart';
import 'gateway/egp.dart';
import 'gateway/gateway_manager.dart';
import 'jikong_protocol.dart';

/// 保护板数据服务：数据经 ESP32 网关中继，协议解析仍在手机端。
///
/// 与直连保护板的区别只有传输层：
///   - 下行：JK02 命令帧 → 网关 BMS 端口
///   - 上行：网关 BMS 端口的字节流 → 剥帧 → 解析
///
/// 保护板会在 0x97 + 0x96 之后持续推送 0x02 帧；若接的是纯 UART 板子不会主动推，
/// 由网关固件按轮询间隔补发 0x96（见 GatewayManager 的 poll 设置）。
class GatewayBmsService extends BmsDataService {
  final GatewayManager gateway;
  final _controller = StreamController<BmsData>.broadcast();

  StreamSubscription? _sub;
  final List<int> _buf = [];

  JkCellInfo? _cell;
  JkDeviceInfo? _deviceInfo;
  JkSettings? _settings;

  /// device 帧里的板子信息（序列号、硬件版本等），未收到时为 null。
  JkDeviceInfo? get deviceInfo => _deviceInfo;

  /// 收到 settings 帧时回调（开关使能位与参数值）。
  ValueChanged<JkSettings>? onSettings;

  // ---- 诊断 ----
  int _rxBytes = 0;
  int _rxFrames = 0;
  int _parseOk = 0;
  int _parseFail = 0;
  String _lastFrameHex = '';
  String _rxLog = '';
  String _sentHex = '';

  GatewayBmsService(this.gateway) {
    _sub = gateway.framesFor(EgPort.bms).listen((f) => _onData(f.payload));
  }

  @override
  BmsDiag get diag => BmsDiag(
        services: [gateway.linkName],
        notifyUuid: gateway.mode.name,
        writeUuid: 'EGP:${EgPort.bms}',
        rxBytes: _rxBytes,
        rxFrames: _rxFrames,
        parseOk: _parseOk,
        parseFail: _parseFail,
        lastFrameHex: _lastFrameHex,
        rxLog: _rxLog,
        sentHex: _sentHex,
      );

  @override
  bool get isConnected => gateway.isConnected;

  @override
  String? get lastError => gateway.lastError;

  @override
  Stream<BmsData> get dataStream => _controller.stream;

  /// 链路建立后触发一次握手：0x97 唤醒 + 0x96 读实时数据。
  Future<void> handshake() async {
    await _write(JkProtocol.buildReadDevice());
    await Future.delayed(const Duration(milliseconds: 400));
    await _write(JkProtocol.buildReadCell());
  }

  Future<void> _write(List<int> bytes) async {
    _sentHex = bytes
        .take(48)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    await gateway.send(EgPort.bms, bytes);
  }

  /// 页面切换时按当前页发送对应的读请求（一次性低频，非周期查询）。
  void requestPage(int page) {
    if (!gateway.isConnected) return;
    _write(JkProtocol.buildReadCell());
    if (page != 2) {
      _write(JkProtocol.buildReadDevice());
    }
  }

  /// 收到保护板字节流：JK02 回复帧固定 300 字节，帧头 55AAEB90 / AA55EB90。
  ///
  /// 保护板的 `AT\r\n` 保活字节不单独剥离——帧扫描器会跳过非帧头字节，
  /// 这样即使保活被拆到两个分片里也不会误切帧。
  void _onData(List<int> bytes) {
    _rxBytes += bytes.length;
    _lastFrameHex = bytes
        .take(32)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    final hex = bytes
        .take(80)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    _rxLog = (_rxLog.isEmpty ? '' : '$_rxLog ') + hex;
    if (_rxLog.length > 560) {
      _rxLog = _rxLog.substring(_rxLog.length - 560);
    }

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
        } else if (type == JkProtocol.typeSettings) {
          _parseOk++;
          _settings = JkParser.parseSettings(f);
          onSettings?.call(_settings!);
          _publish();
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
    final st = _settings;
    final cells = c.cellVoltages;
    // 最高/最低只在已连接单体中计算（排除未连接的 0 值）
    final active = cells.where((x) => x > 0.1).toList();
    final maxV = active.isEmpty ? 0.0 : active.reduce((a, x) => x > a ? x : a);
    final minV = active.isEmpty ? 0.0 : active.reduce((a, x) => x < a ? x : a);
    _controller.add(BmsData(
      totalVoltage: c.totalVoltage,
      current: c.current,
      power: (c.totalVoltage * c.current).abs(),
      soc: c.soc,
      remainingCapacity: c.remainingAh,
      nominalCapacity: c.nominalAh,
      cellVoltages: cells,
      cellResistances: c.cellResistances,
      temperatures: c.temperatures,
      maxCellV: maxV,
      minCellV: minV,
      balancing: st?.balanceEnabled ?? c.balancingActive,
      balanceCurrent: c.balanceCurrent,
      chargeMos: st?.chargeEnabled ?? c.chargeMos,
      dischargeMos: st?.dischargeEnabled ?? c.dischargeMos,
      prechargeMos: c.precharge,
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

  /// 写单个设置参数（按参数表换算系数与写入长度）。
  Future<bool> writeParam(String key, double value) async {
    JkParamDef? def;
    for (final p in kJkParams) {
      if (p.key == key) {
        def = p;
        break;
      }
    }
    if (def == null) return false;
    try {
      await _write(JkProtocol.buildWriteParam(def, value));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 单独回读 settings 帧（0x96），用于写后校验开关/参数。
  void refreshSettings() {
    if (!gateway.isConnected) return;
    _write(JkProtocol.buildReadCell());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _controller.close();
  }
}
