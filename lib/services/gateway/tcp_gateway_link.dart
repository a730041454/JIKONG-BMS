import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'egp.dart';
import 'gateway_link.dart';

/// TCP 链路：局域网模式与热点模式共用，仅目标地址不同。
///
///  - 局域网：ESP32 已连上路由器，手机与它同网段 → `ip:8266`
///  - 热点：ESP32 未配网自建 AP，手机连其热点 → 通常是 `192.168.4.1:8266`
///
/// 线上传输与蓝牙完全相同的 EGP 帧流。
class TcpGatewayLink extends GatewayLink {
  static const int defaultPort = 8266;

  final String host;
  final int port;
  final LinkMode linkMode;

  Socket? _socket;
  StreamSubscription? _sub;
  final _frames = StreamController<EgFrame>.broadcast();
  final EgDecoder _decoder = EgDecoder();

  LinkState _state = LinkState.disconnected;
  String? _lastError;

  TcpGatewayLink({
    required this.host,
    this.port = defaultPort,
    this.linkMode = LinkMode.lan,
  });

  @override
  String get name => host;

  @override
  String get address => '$host:$port';

  @override
  LinkMode get mode => linkMode;

  @override
  LinkState get state => _state;

  @override
  Stream<EgFrame> get frames => _frames.stream;

  @override
  String? get lastError => _lastError;

  @override
  Future<bool> connect() async {
    _lastError = null;
    _state = LinkState.connecting;
    _decoder.reset();
    try {
      final sock = await Socket.connect(host, port,
          timeout: const Duration(seconds: 6));
      sock.setOption(SocketOption.tcpNoDelay, true);
      _socket = sock;
      _sub = sock.listen(
        _onBytes,
        onError: (Object e) {
          _lastError = '网络错误：$e';
          _state = LinkState.failed;
        },
        onDone: () {
          if (_state == LinkState.connected) {
            _state = LinkState.disconnected;
          }
        },
        cancelOnError: true,
      );
      _state = LinkState.connected;
      return true;
    } catch (e) {
      _lastError = '连接 $host:$port 失败：$e';
      _state = LinkState.failed;
      await _cleanup();
      return false;
    }
  }

  void _onBytes(List<int> bytes) {
    for (final f in _decoder.feed(bytes)) {
      if (!_frames.isClosed) _frames.add(f);
    }
  }

  @override
  Future<bool> send(int port, List<int> payload) async {
    final sock = _socket;
    if (sock == null || _state != LinkState.connected) return false;
    try {
      sock.add(EgCodec.encode(port, payload));
      await sock.flush();
      return true;
    } catch (e) {
      _lastError = '发送失败：$e';
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _state = LinkState.disconnected;
    await _cleanup();
  }

  Future<void> _cleanup() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _decoder.reset();
  }

  @override
  void dispose() {
    _cleanup();
    _frames.close();
  }
}

/// 局域网自动发现：向广播地址发 UDP 探测，网关回 JSON 自我介绍。
class GatewayDiscovery {
  GatewayDiscovery._();

  static const int discoveryPort = TcpGatewayLink.defaultPort;
  static const String probe = 'EGP_DISCOVER';

  /// 扫描同网段内的网关。返回结果按信号强度/顺序排列。
  static Future<List<GatewayDevice>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final found = <String, GatewayDevice>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket!.receive();
        if (dg == null) return;
        try {
          final map = jsonDecode(utf8.decode(dg.data));
          if (map is! Map) return;
          final ip = (map['ip'] ?? dg.address.address).toString();
          final name = (map['name'] ?? 'ESP32 网关').toString();
          found[ip] = GatewayDevice(
            name: name,
            id: ip,
            ip: ip,
            mode: LinkMode.lan,
            rssi: 0,
          );
        } catch (_) {
          // 不是网关应答，忽略
        }
      });
      socket.send(utf8.encode(probe), InternetAddress('255.255.255.255'),
          discoveryPort);
      await Future.delayed(timeout);
    } catch (_) {
      // 无网络权限或被系统限制，交由用户手填 IP
    } finally {
      socket?.close();
    }
    return found.values.toList();
  }
}
