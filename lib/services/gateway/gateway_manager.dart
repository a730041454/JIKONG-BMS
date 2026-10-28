import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'egp.dart';
import 'gateway_link.dart';
import 'ble_gateway_link.dart';
import 'tcp_gateway_link.dart';

/// 网关连接管理：持有当前链路、按端口分发帧、承载控制通道的请求/响应。
///
/// 端口分工：
///   [EgPort.bms]  保护板字节流（极空 JK02 协议）
///   [EgPort.inv]  逆变器字节流（Modbus RTU 或 RS232-ASCII）
///   [EgPort.ctrl] 控制通道，JSON 文本
class GatewayManager extends ChangeNotifier {
  GatewayLink? _link;
  StreamSubscription? _sub;

  final Map<int, StreamController<EgFrame>> _portStreams = {};
  final Map<int, Completer<Map<String, dynamic>?>> _pending = {};
  int _reqId = 0;

  /// 网关自报信息（固件版本、WiFi 状态、IP 等）。
  Map<String, dynamic>? gatewayInfo;

  /// 当前使用的通信方式。
  LinkMode mode = LinkMode.ble;

  /// 最近一次的连接目标：蓝牙为 MAC，TCP 为 IP。
  String targetId = '';

  /// 目标显示名。
  String targetName = '';

  /// TCP 端口。
  int targetPort = TcpGatewayLink.defaultPort;

  String? lastError;

  LinkState get state => _link?.state ?? LinkState.disconnected;

  bool get isConnected => _link?.isConnected ?? false;

  String get linkName => _link?.name ?? targetName;

  /// 取某个端口的帧流。
  Stream<EgFrame> framesFor(int port) {
    return _portStreams
        .putIfAbsent(port, () => StreamController<EgFrame>.broadcast())
        .stream;
  }

  /// 切换通信方式并连接。蓝牙传设备 MAC，TCP 传 IP。
  Future<bool> connect({
    required LinkMode mode,
    required String id,
    String name = '',
    int port = TcpGatewayLink.defaultPort,
  }) async {
    await disconnect();
    this.mode = mode;
    targetId = id;
    targetName = name;
    targetPort = port;

    final link = mode == LinkMode.ble
        ? BleGatewayLink(deviceId: id, displayName: name.isEmpty ? id : name)
        : TcpGatewayLink(
            host: id,
            port: port,
            linkMode: mode == LinkMode.ap ? LinkMode.ap : LinkMode.lan,
          );
    _link = link;
    _sub = link.frames.listen(_onFrame);
    notifyListeners();

    final ok = await link.connect();
    lastError = link.lastError;
    notifyListeners();
    return ok;
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await _link?.disconnect();
    _link = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
    notifyListeners();
  }

  /// 发送一帧到指定端口。
  Future<bool> send(int port, List<int> payload) async {
    final link = _link;
    if (link == null) return false;
    final ok = await link.send(port, payload);
    if (!ok) lastError = link.lastError;
    return ok;
  }

  void _onFrame(EgFrame frame) {
    if (frame.port == EgPort.ctrl) {
      _onControl(frame);
      return;
    }
    final c = _portStreams[frame.port];
    if (c != null && !c.isClosed) c.add(frame);
  }

  void _onControl(EgFrame frame) {
    Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(frame.text);
      if (decoded is! Map) return;
      map = decoded.cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final id = map['id'];
    if (id is int) {
      final c = _pending.remove(id);
      if (c != null && !c.isCompleted) {
        c.complete(map);
        return;
      }
    }
    // 主动上报（状态变化等）
    final result = map['result'];
    if (result is Map) {
      gatewayInfo = result.cast<String, dynamic>();
    } else if (map['event'] != null) {
      gatewayInfo = map.cast<String, dynamic>();
    }
    notifyListeners();
  }

  /// 发送一条控制指令并等待应答。
  ///
  /// 应答带相同 `id`；超时返回 null。
  Future<Map<String, dynamic>?> control(
    Map<String, dynamic> cmd, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final link = _link;
    if (link == null || !link.isConnected) return null;
    final id = ++_reqId;
    final payload = <String, dynamic>{'id': id, ...cmd};
    final c = Completer<Map<String, dynamic>?>();
    _pending[id] = c;
    try {
      final ok = await send(EgPort.ctrl, utf8.encode(jsonEncode(payload)));
      if (!ok) {
        _pending.remove(id);
        return null;
      }
      return await c.future.timeout(timeout, onTimeout: () {
        _pending.remove(id);
        return null;
      });
    } catch (_) {
      _pending.remove(id);
      return null;
    }
  }

  /// 网关状态（固件版本、WiFi、IP）。
  Future<Map<String, dynamic>?> queryStatus() =>
      control({'cmd': 'status'}, timeout: const Duration(seconds: 6));

  /// 扫描附近 WiFi（需要网关已连接）。
  Future<List<Map<String, dynamic>>> scanWifi() async {
    final r = await control({'cmd': 'wifi_scan'},
        timeout: const Duration(seconds: 15));
    final aps = r?['result']?['aps'];
    if (aps is List) {
      return aps.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
  }

  /// 让网关连接指定 WiFi。
  Future<Map<String, dynamic>?> connectWifi(String ssid, String pass) =>
      control({'cmd': 'wifi_connect', 'ssid': ssid, 'pass': pass},
          timeout: const Duration(seconds: 25));

  /// 让网关断开 WiFi（回到热点模式）。
  Future<Map<String, dynamic>?> disconnectWifi() =>
      control({'cmd': 'wifi_disconnect'});

  /// 设置网关某个串口的波特率（逆变器协议切换时用）。
  Future<Map<String, dynamic>?> setUartBaud(int uartIndex, int baud) =>
      control({'cmd': 'set_uart', 'port': uartIndex, 'baud': baud});

  /// 修改网关蓝牙名称。
  Future<Map<String, dynamic>?> setGatewayName(String name) =>
      control({'cmd': 'set_name', 'name': name});

  @override
  void dispose() {
    _sub?.cancel();
    _link?.dispose();
    for (final c in _portStreams.values) {
      c.close();
    }
    _portStreams.clear();
    super.dispose();
  }
}
