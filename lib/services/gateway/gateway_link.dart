import 'egp.dart';

/// 手机 ↔ ESP32 网关的通信方式。
enum LinkMode {
  /// 蓝牙 GATT（ESP32 作为外设，手机作为中心）。
  ble,

  /// 局域网：ESP32 已连上路由器，手机与它同网段，走 TCP。
  lan,

  /// 热点：ESP32 未配网，自建热点，手机连它的 AP 后走 TCP。
  ap,
}

/// 链路状态。
enum LinkState { disconnected, connecting, connected, failed }

/// 扫描/已知到的一个网关。
class GatewayDevice {
  final String name;
  /// 蓝牙模式为 MAC 地址；TCP 模式为 IP。
  final String id;
  final int rssi;
  final LinkMode mode;
  final String? ip;

  const GatewayDevice({
    required this.name,
    required this.id,
    this.rssi = 0,
    this.mode = LinkMode.ble,
    this.ip,
  });

  String get label => name.trim().isEmpty ? id : name;
}

/// 到 ESP32 网关的一条链路（蓝牙或 TCP）。
///
/// 链路只负责把 [EgFrame] 可靠地送到对面，不关心载荷语义：
/// 保护板字节流、逆变器字节流、控制 JSON 都走同一套多路复用。
abstract class GatewayLink {
  /// 展示名称。
  String get name;

  /// 链路地址：蓝牙为 MAC，TCP 为 `ip:port`。
  String get address;

  LinkMode get mode;

  LinkState get state;

  bool get isConnected => state == LinkState.connected;

  /// 收到的帧。
  Stream<EgFrame> get frames;

  /// 连接失败原因（最近一次）。
  String? get lastError;

  Future<bool> connect();

  Future<void> disconnect();

  /// 发送一帧。返回是否已交给底层。
  Future<bool> send(int port, List<int> payload);

  void dispose();
}
