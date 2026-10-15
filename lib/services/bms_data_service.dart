import 'dart:async';

import '../models/bms_data.dart';

/// 可发现的 BLE 设备。
class BmsDevice {
  final String name;
  final String id;
  final int rssi;
  BmsDevice({required this.name, required this.id, required this.rssi});
}

/// 连接诊断信息（帮助定位"能连上但无数据"）。
class BmsDiag {
  final List<String> services; // 板子暴露的服务 UUID
  final String notifyUuid; // 已订阅的 notify 特征
  final String writeUuid; // 已使用的 write 特征
  final int rxBytes; // 累计收到的字节数
  final int rxFrames; // 累计收到的数据帧数
  final int parseOk; // 解析成功帧数
  final int parseFail; // 解析失败帧数
  final String lastFrameHex; // 最近一帧原始字节(hex)
  final String rxLog; // 最近收到的全部原始字节(hex)，用于确认板子推送格式
  final String sentHex; // 最近一次下发的字节(hex)

  const BmsDiag({
    this.services = const [],
    this.notifyUuid = '',
    this.writeUuid = '',
    this.rxBytes = 0,
    this.rxFrames = 0,
    this.parseOk = 0,
    this.parseFail = 0,
    this.lastFrameHex = '',
    this.rxLog = '',
    this.sentHex = '',
  });

  static const empty = BmsDiag();
}

/// BMS 数据服务抽象。真实 BLE 与模拟服务均实现此接口。
abstract class BmsDataService {
  /// 实时数据流（连接后每秒推送）。
  Stream<BmsData> get dataStream;

  /// 当前是否已连接。
  bool get isConnected;

  /// 最近一次连接失败的原因（无则 null），用于界面提示。
  String? get lastError;

  /// 连接诊断信息。
  BmsDiag get diag => BmsDiag.empty;

  /// 扫描发现设备。
  Future<List<BmsDevice>> scan({Duration timeout = const Duration(seconds: 6)});

  /// 连接指定设备（id 为 BLE 地址）。
  Future<bool> connect(String deviceId);

  /// 断开连接。
  Future<void> disconnect();

  /// 写入某寄存器（协议写命令）。返回是否成功。
  Future<bool> writeRegister(int reg, int value);

  /// 释放资源。
  void dispose();
}
