import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bms_data.dart';
import '../models/inverter_data.dart';
import '../models/saved_device.dart';
import '../services/bms_data_service.dart';
import '../services/gateway/gateway_link.dart';
import '../services/gateway/gateway_manager.dart';
import '../services/gateway/ble_gateway_link.dart';
import '../services/gateway/tcp_gateway_link.dart';
import '../services/gateway_bms_service.dart';
import '../services/inverter/inverter_params.dart';
import '../services/inverter_service.dart';
import '../services/jikong_protocol.dart';
import '../services/mock_bms_service.dart';
import '../services/mock_inverter.dart';

/// 全局应用状态（Provider）。
///
/// 通讯全部经 ESP32 网关：蓝牙（GATT）或局域网/热点 TCP，网关再转发
/// 保护板（UART1）与逆变器（UART2）的字节流。
class AppState extends ChangeNotifier {
  final GatewayManager gateway = GatewayManager();

  /// 保护板数据服务（真机走网关，预览走模拟）。
  late final BmsDataService service;

  /// 逆变器数据服务（真机走网关 INV 端口轮询）。
  late final InverterService inverter;

  GatewayBmsService? _bms;
  MockInverterSource? _mockInv;

  final bool _useMock;

  AppState({bool useMock = false}) : _useMock = useMock {
    if (useMock) {
      final m = MockBmsService();
      service = m;
      m.start();
      _mockInv = MockInverterSource();
      _mockInv!.stream.listen((_) => notifyListeners());
      _mockInv!.start();
      inverter = InverterService(gateway);
    } else {
      final gw = GatewayBmsService(gateway);
      _bms = gw;
      service = gw;
      inverter = InverterService(gateway);
      inverter.stream.listen((_) => notifyListeners());
    }
    _init();
  }

  // ---- 连接 ----
  String deviceName = '';
  String? rememberedDeviceId;
  List<SavedDevice> savedDevices = [];
  BmsData? data;

  /// 通信方式：蓝牙 / 局域网 / 网关热点。
  LinkMode get linkMode => gateway.mode;

  bool get connected => _useMock || gateway.isConnected;

  /// 网关自报状态（固件版本、WiFi、IP 等）。
  Map<String, dynamic>? get gatewayInfo => gateway.gatewayInfo;

  // ---- 界面 ----
  bool isEn = false;
  bool isDark = true;

  // ---- 密码 ----
  String password = '123456';
  bool pwdUnlocked = false;

  // ---- 核心参数 ----
  int cells = 16;
  double nominal = 100;

  // ---- 首页开关（充电/放电/均衡）----
  bool charging = false;
  bool discharging = false;
  bool balancing = true;
  bool precharge = false;

  /// 最近一次 settings 帧（使能开关 + 参数值）。
  JkSettings? settings;

  /// 点击开关后的短暂保持：避免推流帧里的旧状态把开关立即弹回去。
  final Map<String, bool> _holdFlags = {};
  final Map<String, Timer?> _holdTimers = {};

  void _hold(String key) {
    _holdFlags[key] = true;
    _holdTimers[key]?.cancel();
    _holdTimers[key] =
        Timer(const Duration(seconds: 3), () => _holdFlags[key] = false);
  }

  bool _isHeld(String key) => _holdFlags[key] == true;

  /// 最近一次连接失败的原因（界面提示用）。
  String? connectError;

  StreamSubscription<BmsData>? _sub;

  bool get useMock => _useMock;
  BmsDiag get diag => service.diag;
  bool get alarm => data?.alarm ?? false;
  double get maxCellV => data?.maxCellV ?? 0;
  double get minCellV => data?.minCellV ?? 0;
  double get totalVoltage => data?.totalVoltage ?? 0;
  double get current => data?.current ?? 0;
  double get power => (data?.power ?? 0).abs();
  double get soc => data?.soc ?? 0;
  double get maxTemp => data?.maxTemp ?? 0;
  double get remaining => data?.remainingCapacity ?? 0;
  double get balanceCurrent => data?.balanceCurrent ?? 0;

  // ---- 逆变器 ----
  InverterData get inv =>
      _useMock ? (_mockInv?.data ?? InverterData.empty) : inverter.data;
  Map<String, double> get invSettings =>
      _useMock ? (_mockInv?.settings ?? const {}) : inverter.settings;
  InvLinkKind get invKind => inverter.kind;
  String get invProtocolLabel => inverter.protocolLabel;

  /// 状态文本 key（按当前电流判断：≥+0.2A 充电中，≤-0.2A 放电中，其余空闲）。
  String get stateKey {
    if (alarm) return 'st_alarm';
    final c = data?.current ?? 0;
    if (c >= 0.2) return 'st_charging';
    if (c <= -0.2) return 'st_discharging';
    return 'st_idle';
  }

  /// 放电剩余时间（小时）= 剩余容量 / |电流|。
  double get remainingHours {
    final c = data?.current ?? 0;
    final r = data?.remainingCapacity ?? 0;
    if (c.abs() < 0.1 || r <= 0) return 0;
    return r / c.abs();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    isEn = prefs.getBool('jk_lang') ?? false;
    isDark = prefs.getBool('jk_dark') ?? true;
    password = prefs.getString('jk_pwd') ?? '123456';
    savedDevices = _loadSavedDevices(prefs);
    rememberedDeviceId = prefs.getString('jk_device');
    if ((rememberedDeviceId == null || rememberedDeviceId!.isEmpty) &&
        savedDevices.isNotEmpty) {
      rememberedDeviceId = savedDevices.first.id;
    }
    cells = prefs.getInt('jk_cells') ?? 16;
    nominal = prefs.getDouble('jk_cap') ?? 100;
    final invMode = prefs.getString('jk_inv_link');
    if (invMode == 'ascii') {
      _pendingInvKind = InvLinkKind.ascii;
    }
    if (_useMock) {
      final m = service;
      if (m is MockBmsService) {
        m.cells = cells;
        m.nominal = nominal;
        _mockInv!.cells = cells;
        _mockInv!.nominal = nominal;
      }
    }
    // 授权密码固定以应用设置里的密码为准（默认 123456），
    // 不用保护板 device 帧里的蓝牙密码覆盖，避免解析偏差导致正确密码被拒。
    _bms?.onSettings = (s) {
      settings = s;
      if (s.cellCount > 0) cells = s.cellCount;
      if (s.capacityAh > 0) nominal = s.capacityAh;
      notifyListeners();
    };
    _sub = service.dataStream.listen((d) {
      data = d;
      // 开关状态 = settings 帧里的使能位；点击后 3 秒内保持用户意图，
      // 之后以保护板回读为准。
      if (!_useMock) {
        if (!_isHeld('chg')) charging = d.chargeMos;
        if (!_isHeld('dis')) discharging = d.dischargeMos;
        if (!_isHeld('bal')) balancing = d.balancing;
        precharge = d.prechargeMos;
        if (d.nominalCapacity > 0) nominal = d.nominalCapacity;
        final n = d.cellVoltages.where((v) => v > 0.1).length;
        if (n > 0) cells = n;
      }
      notifyListeners();
    });
    notifyListeners();
    // 记住过网关则自动重连
    final r = rememberedDeviceId;
    if (r != null && r.isNotEmpty && !_useMock) {
      unawaited(connectSaved(r));
    }
  }

  InvLinkKind? _pendingInvKind;

  /// 扫描附近的网关（蓝牙广播）。
  Future<List<GatewayDevice>> scanGateways() async {
    if (_useMock) return MockGateways.list;
    return BleGatewayLink.scanGateways(timeout: const Duration(seconds: 6));
  }

  /// 局域网内发现网关（UDP 广播）。
  Future<List<GatewayDevice>> discoverLan() async {
    if (_useMock) return MockGateways.lan;
    return GatewayDiscovery.discover();
  }

  /// 按已保存设备的类型重连：MAC 走蓝牙，点分十进制走 TCP。
  Future<bool> connectSaved(String id, {String? name}) async {
    final mode = _isIpAddress(id) ? LinkMode.lan : LinkMode.ble;
    return connectGateway(mode: mode, id: id, name: name ?? '');
  }

  static bool _isIpAddress(String s) =>
    RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(s);

  /// 连接网关；成功后启动保护板握手与逆变器轮询。
  Future<bool> connectGateway({
    required LinkMode mode,
    required String id,
    String name = '',
    int port = TcpGatewayLink.defaultPort,
  }) async {
    connectError = null;
    final saved = _savedById(id);
    final display = (name.isNotEmpty ? name : (saved?.name ?? '')).trim().isNotEmpty
        ? (name.isNotEmpty ? name.trim() : saved!.name.trim())
        : id;
    final ok = await gateway.connect(mode: mode, id: id, name: display, port: port);
    if (ok) {
      deviceName = display;
      await rememberDevice(id, name: display);
      final k = _pendingInvKind;
      if (k != null) {
        _pendingInvKind = null;
        await inverter.setKind(k);
      }
      unawaited(gateway.queryStatus());
      await _bms?.handshake();
      inverter.start();
    } else {
      connectError = gateway.lastError ?? '连接失败';
    }
    notifyListeners();
    return ok;
  }

  Future<void> disconnectGateway() async {
    inverter.stop();
    await gateway.disconnect();
    deviceName = '';
    data = null;
    notifyListeners();
  }

  SavedDevice? _savedById(String id) {
    for (final d in savedDevices) {
      if (d.id == id) return d;
    }
    return null;
  }

  List<SavedDevice> _loadSavedDevices(SharedPreferences prefs) {
    final raw = prefs.getString('jk_devices');
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List)
            .map(SavedDevice.fromJson)
            .whereType<SavedDevice>()
            .toList();
        list.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
        if (list.isNotEmpty) return list;
      } catch (_) {
        // 数据损坏时退回旧的单设备记录
      }
    }
    final legacy = prefs.getString('jk_device');
    if (legacy != null && legacy.isNotEmpty) {
      return [SavedDevice(id: legacy)];
    }
    return [];
  }

  String _encodeDevices() =>
      jsonEncode(savedDevices.map((d) => d.toJson()).toList());

  /// 连接成功后写入已保存网关列表（同一地址只保留一条，最近使用排最前）。
  Future<void> rememberDevice(String id, {String name = ''}) async {
    rememberedDeviceId = id;
    final old = _savedById(id);
    final n = name.trim().isNotEmpty ? name.trim() : (old?.name ?? '');
    savedDevices.removeWhere((d) => d.id == id);
    savedDevices.insert(
      0,
      SavedDevice(
          id: id, name: n, lastUsed: DateTime.now().millisecondsSinceEpoch),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jk_device', id);
    await prefs.setString('jk_devices', _encodeDevices());
  }

  Future<void> removeSavedDevice(String id) async {
    savedDevices.removeWhere((d) => d.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jk_devices', _encodeDevices());
    if (rememberedDeviceId == id) {
      rememberedDeviceId = savedDevices.isEmpty ? null : savedDevices.first.id;
      final next = rememberedDeviceId;
      if (next == null) {
        await prefs.remove('jk_device');
      } else {
        await prefs.setString('jk_device', next);
      }
    }
    notifyListeners();
  }

  // ---- 首页开关 ----
  /// 点击开关：立即按用户意图更新界面，同时下发写指令（0x1D/0x1E/0x1F），
  /// 350ms 后单独回读 settings 帧，3 秒后以保护板回读状态为准。
  void toggleCharge() =>
      _toggleMos('chg', !charging, (s, t) => s.setMos(charge: t));

  void toggleDischarge() =>
      _toggleMos('dis', !discharging, (s, t) => s.setMos(discharge: t));

  void toggleBalance() =>
      _toggleMos('bal', !balancing, (s, t) => s.setMos(balance: t));

  void _toggleMos(String key, bool target,
      Future<bool> Function(GatewayBmsService, bool) action) {
    if (_useMock) {
      final m = service;
      if (m is MockBmsService) {
        switch (key) {
          case 'chg':
            m.setCharge(target);
          case 'dis':
            m.setDischarge(target);
          case 'bal':
            m.setBalance(target);
        }
      }
      switch (key) {
        case 'chg':
          charging = target;
        case 'dis':
          discharging = target;
        case 'bal':
          balancing = target;
      }
      notifyListeners();
      return;
    }
    final s = _bms;
    if (s == null) return;
    switch (key) {
      case 'chg':
        charging = target;
      case 'dis':
        discharging = target;
      case 'bal':
        balancing = target;
    }
    _hold(key);
    notifyListeners();
    unawaited(action(s, target).then((_) async {
      await Future.delayed(const Duration(milliseconds: 350));
      s.refreshSettings();
    }));
  }

  // ---- 保护板设置参数（settings 帧）----
  /// 参数当前值（未收到 settings 帧时返回 null，界面回退演示值）。
  double? settingsValue(String key) => settings?.values[key];

  /// 写单个参数并回读校验。
  Future<bool> writeParam(String key, double value) async {
    bool ok = false;
    if (_useMock) {
      ok = true;
    } else {
      final s = _bms;
      if (s != null) {
        ok = await s.writeParam(key, value);
        if (ok) {
          await Future.delayed(const Duration(milliseconds: 500));
          s.refreshSettings();
        }
      }
    }
    final cur = settings;
    if (ok && cur != null) {
      settings = JkSettings(
        values: Map<String, double>.of(cur.values)..[key] = value,
        cellCount: key == 'core_cells' ? value.round() : cur.cellCount,
        capacityAh: key == 'core_cap' ? value : cur.capacityAh,
        chargeEnabled: cur.chargeEnabled,
        dischargeEnabled: cur.dischargeEnabled,
        balanceEnabled: cur.balanceEnabled,
      );
    }
    notifyListeners();
    return ok;
  }

  // ---- 逆变器 ----
  /// 切换逆变器接入协议（同时改网关 UART2 波特率）。
  Future<void> setInverterLink(InvLinkKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'jk_inv_link', kind == InvLinkKind.ascii ? 'ascii' : 'modbus');
    if (_useMock) {
      _mockInv!.ascii = kind == InvLinkKind.ascii;
      notifyListeners();
      return;
    }
    await inverter.setKind(kind);
    notifyListeners();
  }

  Future<bool> writeInverterParam(String key, double value) async {
    if (_useMock) {
      _mockInv!.settings[key] = value;
      notifyListeners();
      return true;
    }
    final ok = await inverter.writeParam(key, value);
    if (ok) {
      final p = invParamByKey(key);
      if (p != null) invSettingsMirror[key] = value;
      inverter.requestSettings();
    }
    notifyListeners();
    return ok;
  }

  /// 写成功后的本地镜像，用于设备暂未回读时仍能显示用户刚设定的值。
  final Map<String, double> invSettingsMirror = {};

  double? invSettingValue(String key) =>
      invSettingsMirror[key] ?? invSettings[key];

  /// 控制类指令（开机 / 清除故障 / 锂电激活）。
  Future<bool> sendInverterControl(String commandText) async {
    if (_useMock) return true;
    return inverter.sendControl(commandText);
  }

  /// 手动回读一次逆变器设置区（参数页「读取逆变器参数」）。
  void readInverterSettings() {
    if (_useMock) return;
    inverter.requestSettings();
  }

  // ---- 网关配网 ----
  Future<List<Map<String, dynamic>>> gatewayScanWifi() => gateway.scanWifi();

  Future<Map<String, dynamic>?> gatewayConnectWifi(String ssid, String pass) async {
    final r = await gateway.connectWifi(ssid, pass);
    notifyListeners();
    return r;
  }

  Future<Map<String, dynamic>?> gatewayDisconnectWifi() async {
    final r = await gateway.disconnectWifi();
    notifyListeners();
    return r;
  }

  Future<Map<String, dynamic>?> gatewayStatus() async {
    final r = await gateway.queryStatus();
    notifyListeners();
    return r;
  }

  Future<bool> renameGateway(String name) async {
    final n = name.trim();
    if (n.isEmpty) return false;
    if (_useMock) {
      deviceName = n;
      notifyListeners();
      return true;
    }
    final r = await gateway.setGatewayName(n);
    final ok = r?['ok'] == true;
    if (ok) {
      deviceName = n;
      await rememberDevice(rememberedDeviceId ?? '', name: n);
    }
    notifyListeners();
    return ok;
  }

  // ---- 语言 / 主题 ----
  Future<void> setLanguage(bool en) async {
    isEn = en;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('jk_lang', en);
    notifyListeners();
  }

  Future<void> setDark(bool dark) async {
    isDark = dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('jk_dark', dark);
    notifyListeners();
  }

  // ---- 密码 ----
  /// 授权设置验证通过后解锁本次会话的参数写入。
  void unlock() {
    pwdUnlocked = true;
    notifyListeners();
  }

  /// 重新上锁（离开参数页时）。
  void lock() {
    pwdUnlocked = false;
    notifyListeners();
  }

  Future<void> setPassword(String pwd) async {
    password = pwd.isEmpty ? '123456' : pwd;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jk_pwd', password);
    notifyListeners();
  }

  // ---- 核心参数 ----
  Future<void> saveCore({int? cellCount, double? capacity}) async {
    if (cellCount != null) cells = cellCount.clamp(1, 32);
    if (capacity != null) nominal = capacity;
    if (_useMock) {
      final m = service;
      if (m is MockBmsService) {
        m.cells = cells;
        m.nominal = nominal;
      }
      _mockInv!.cells = cells;
      _mockInv!.nominal = nominal;
    } else {
      // 真实模式：串数/容量写入保护板 settings 寄存器（偏移 114/130），
      // 写完请求 settings 帧，以保护板返回的数据为准刷新。
      final s = _bms;
      if (s != null) {
        if (cellCount != null) await s.writeCellCount(cells);
        if (capacity != null) await s.writeCapacity(nominal);
        requestPage(1);
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('jk_cells', cells);
    await prefs.setDouble('jk_cap', nominal);
    notifyListeners();
  }

  /// 页面切换时向保护板请求当前页对应数据（一次性低频）。
  void requestPage(int index) {
    if (_useMock) return;
    _bms?.requestPage(index);
    if (index == 2) inverter.requestSettings();
  }

  @override
  void dispose() {
    for (final t in _holdTimers.values) t?.cancel();
    _sub?.cancel();
    _mockInv?.dispose();
    inverter.dispose();
    service.dispose();
    gateway.dispose();
    super.dispose();
  }
}
