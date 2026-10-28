import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'egp.dart';
import 'gateway_link.dart';

/// 蓝牙链路：手机作为中心连接 ESP32 网关。
///
/// GATT 布局（ESP32 固件需保持一致）：
///   服务  0000fde0-0000-1000-8000-00805f9b34fb
///   写特征 0000fde1-...  手机 → 网关（EGP 帧分块写入）
///   通知特征 0000fde2-... 网关 → 手机（EGP 帧分块通知）
///
/// 帧头 0xA5 0x5A 用于在通知流里定位帧边界，块大小不超过 MTU-3。
class BleGatewayLink extends GatewayLink {
  static const String serviceUuid = '0000fde0-0000-1000-8000-00805f9b34fb';
  static const String txUuid = '0000fde1-0000-1000-8000-00805f9b34fb';
  static const String rxUuid = '0000fde2-0000-1000-8000-00805f9b34fb';

  /// 网关广播名前缀，用于扫描时识别。
  static const String namePrefix = 'GNZK-';

  final String deviceId;
  final String displayName;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _tx;
  BluetoothCharacteristic? _rx;
  StreamSubscription? _sub;
  final _frames = StreamController<EgFrame>.broadcast();
  final EgDecoder _decoder = EgDecoder();

  LinkState _state = LinkState.disconnected;
  String? _lastError;
  int _chunkSize = 20;

  BleGatewayLink({required this.deviceId, required this.displayName});

  @override
  String get name => displayName;

  @override
  String get address => deviceId;

  @override
  LinkMode get mode => LinkMode.ble;

  @override
  LinkState get state => _state;

  @override
  Stream<EgFrame> get frames => _frames.stream;

  @override
  String? get lastError => _lastError;

  /// 扫描附近的网关。全量扫描后按「广播了网关服务」或「名字带 GNZK-」过滤。
  ///
  /// 空列表一定有原因（适配器没开 / 没权限 / 扫过了没命中），原因放在
  /// [lastScanError] 里给界面提示，不要再静默返回空列表。
  static String? lastScanError;

  static Future<List<GatewayDevice>> scanGateways({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    lastScanError = null;
    final results = <ScanResult>[];
    StreamSubscription<List<ScanResult>>? sub;
    try {
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        if (state == BluetoothAdapterState.unauthorized) {
          lastScanError = '蓝牙权限被拒：系统设置里给「附近的设备」允许后再扫';
          return [];
        }
        lastScanError = '手机蓝牙没开，已请求打开，开好后请再点一次扫描';
        await FlutterBluePlus.turnOn();
        return [];
      }
      sub = FlutterBluePlus.scanResults.listen((r) {
        results
          ..clear()
          ..addAll(r);
      });
      await FlutterBluePlus.startScan(timeout: timeout);
      await Future.delayed(const Duration(milliseconds: 900));
    } catch (e) {
      lastScanError = '蓝牙扫描没跑起来：$e';
    }
    await sub?.cancel();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    final seen = <String, GatewayDevice>{};
    for (final r in results) {
      final name = r.device.platformName.isNotEmpty
          ? r.device.platformName
          : r.advertisementData.advName;
      final advertises = r.advertisementData.serviceUuids
          .any((u) => u.toString().toLowerCase().contains('fde0'));
      if (!advertises && !name.startsWith(namePrefix)) continue;
      seen[r.device.remoteId.str] = GatewayDevice(
        name: name.isEmpty ? r.device.remoteId.str : name,
        id: r.device.remoteId.str,
        rssi: r.rssi,
        mode: LinkMode.ble,
      );
    }
    final list = seen.values.toList();
    if (list.isEmpty) {
      lastScanError = results.isEmpty
          ? '没扫到任何蓝牙设备：确认手机蓝牙已开、网关已上电并停在蓝牙腿（串口按 b）'
          : '扫到 ${results.length} 个蓝牙设备，但没有网关：'
              '大概率是网关还在 WiFi 腿（BLE 没起），串口按 b 切到蓝牙腿';
    }
    list.sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  @override
  Future<bool> connect() async {
    _lastError = null;
    _state = LinkState.connecting;
    _decoder.reset();
    try {
      _device = BluetoothDevice.fromId(deviceId);
      await _device!.connect(timeout: const Duration(seconds: 12));
      await _device!.discoverServices();

      BluetoothCharacteristic? tx;
      BluetoothCharacteristic? rx;
      // Guid.str 返回最短形式（'fde2'），不是常量里的 128 位写法；用 Guid 比较，
      // 它的 == 会先归一化成 128 位，两种形式都能命中。
      final Guid writeUuid = Guid(txUuid);
      final Guid notifyUuid = Guid(rxUuid);
      for (final s in _device!.servicesList) {
        for (final c in s.characteristics) {
          if (c.uuid == writeUuid) {
            tx = c;
          } else if (c.uuid == notifyUuid) {
            rx = c;
          }
        }
      }
      if (rx == null) {
        _lastError = '网关未提供通知特征($rxUuid)，请确认连的是 ESP32 网关';
        await _cleanup();
        _state = LinkState.failed;
        return false;
      }
      if (tx == null) {
        _lastError = '网关未提供写特征($txUuid)';
        await _cleanup();
        _state = LinkState.failed;
        return false;
      }
      _tx = tx;
      _rx = rx;
      await _rx!.setNotifyValue(true);
      _sub = _rx!.onValueReceived.listen(_onBytes);

      // 协商 MTU：成功则按 MTU-3 分块，否则退回 20 字节。
      _chunkSize = 20;
      try {
        final mtu = await _device!.requestMtu(247);
        if (mtu > 23) _chunkSize = mtu - 3;
      } catch (_) {
        // 部分机型不支持协商，20 字节分块同样可用
      }

      _state = LinkState.connected;
      return true;
    } catch (e) {
      _lastError = '蓝牙连接失败：$e';
      await _cleanup();
      _state = LinkState.failed;
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
    final tx = _tx;
    if (tx == null || _state != LinkState.connected) return false;
    final frame = EgCodec.encode(port, payload);
    final withoutResponse =
        !tx.properties.write && tx.properties.writeWithoutResponse;
    try {
      for (var i = 0; i < frame.length; i += _chunkSize) {
        final end =
            (i + _chunkSize > frame.length) ? frame.length : i + _chunkSize;
        await tx.write(frame.sublist(i, end), withoutResponse: withoutResponse);
        if (!withoutResponse) {
          // 带响应的写要等回执，否则会压垮 BLE 队列
          await Future.delayed(const Duration(milliseconds: 6));
        }
      }
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
      if (_rx != null) await _rx!.setNotifyValue(false);
    } catch (_) {}
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _tx = null;
    _rx = null;
    _decoder.reset();
  }

  @override
  void dispose() {
    _cleanup();
    _frames.close();
  }
}
