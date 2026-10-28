import '../models/bms_data.dart';
import 'gateway/gateway_link.dart';

/// 连接诊断信息（帮助定位"能连上但无数据"）。
class BmsDiag {
  final List<String> services; // 网关暴露的服务 UUID
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

/// 保护板数据服务抽象。
///
/// 真机实现是 [GatewayBmsService]：数据经 ESP32 网关中继后到达，
/// 协议解析仍在手机端完成；模拟实现用于无硬件时预览界面。
abstract class BmsDataService {
  /// 实时数据流（连接后由保护板推流驱动）。
  Stream<BmsData> get dataStream;

  /// 当前是否已连接。
  bool get isConnected;

  /// 最近一次连接失败的原因（无则 null），用于界面提示。
  String? get lastError;

  /// 连接诊断信息。
  BmsDiag get diag => BmsDiag.empty;

  /// 写单个寄存器（协议写命令）。返回是否成功。
  Future<bool> writeRegister(int reg, int value);

  /// 释放资源。
  void dispose();
}

/// 供界面使用的网关扫描结果。
typedef ScannedGateway = GatewayDevice;
