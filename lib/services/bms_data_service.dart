import 'dart:async';

import '../models/bms_data.dart';

/// 可发现的 BLE 设备。
class BmsDevice {
  final String name;
  final String id;
  final int rssi;
  BmsDevice({required this.name, required this.id, required this.rssi});
}

/// BMS 数据服务抽象。真实 BLE 与模拟服务均实现此接口。
abstract class BmsDataService {
  /// 实时数据流（连接后每秒推送）。
  Stream<BmsData> get dataStream;

  /// 当前是否已连接。
  bool get isConnected;

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
