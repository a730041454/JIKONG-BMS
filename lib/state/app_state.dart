import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bms_data.dart';
import '../services/bms_data_service.dart';
import '../services/ble_bms_service.dart' as _ble;
import '../services/mock_bms_service.dart';

/// 全局应用状态（Provider）。
class AppState extends ChangeNotifier {
  final BmsDataService service;
  final bool _useMock;

  AppState({BmsDataService? service, bool useMock = false})
      : service = service ?? (useMock ? MockBmsService() : BleFactory.create()),
        _useMock = useMock {
    _init();
  }

  // ---- 连接 ----
  bool connected = false;
  String deviceName = '';
  String? rememberedDeviceId;
  BmsData? data;

  // ---- 界面 ----
  bool isEn = false;
  bool isDark = true;

  // ---- 密码 ----
  bool pwdEnabled = true;
  String password = '123456';
  bool pwdUnlocked = false;

  // ---- 核心参数 ----
  int cells = 16;
  double nominal = 100;

  // ---- 首页开关（充电/放电/均衡）----
  bool charging = false;
  bool discharging = false;
  bool balancing = true;

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

  /// 状态文本 key（按当前电流判断：≥+1A 充电中，≤-1A 放电中，其余空闲）。
  String get stateKey {
    if (alarm) return 'st_alarm';
    final c = data?.current ?? 0;
    if (c >= 1.0) return 'st_charging';
    if (c <= -1.0) return 'st_discharging';
    return 'st_idle';
  }

  /// 放电剩余时间（小时）= 剩余容量 / |电流|（充电中返回充满预计时间）。
  double get remainingHours {
    final c = data?.current ?? 0;
    final r = data?.remainingCapacity ?? 0;
    if (c.abs() < 0.1 || r <= 0) return 0;
    return r / c.abs();
  }

  // 历史数据（图表模式用，最多 60 点）
  final List<double> histSoc = [];
  final List<double> histVoltage = [];
  final List<double> histCurrent = [];

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    isEn = prefs.getBool('jk_lang') ?? false;
    isDark = prefs.getBool('jk_dark') ?? true;
    pwdEnabled = prefs.getBool('jk_pwd_en') ?? true;
    password = prefs.getString('jk_pwd') ?? '123456';
    rememberedDeviceId = prefs.getString('jk_device');
    cells = prefs.getInt('jk_cells') ?? 16;
    nominal = prefs.getDouble('jk_cap') ?? 100;
    if (service is MockBmsService) {
      final m = service as MockBmsService;
      m.cells = cells;
      m.nominal = nominal;
    }
    // 同步保护板蓝牙密码：连接后收到 device 帧时，把应用设置密码更新为保护板密码
    if (service is _ble.BleBmsService) {
      (service as _ble.BleBmsService).onBluetoothPassword = (pwd) {
        if (pwd.isNotEmpty) password = pwd;
        notifyListeners();
      };
    }
    _sub = service.dataStream.listen((d) {
      data = d;
      // 首页充电/放电开关状态：以保护板 MOS 为准，同时按电流判断（放电为负、充电为正），
      // 保证开关随实际负载状态更新。
      if (!useMock) {
        discharging = d.dischargeMos || d.current <= -1.0;
        charging = d.chargeMos || d.current >= 1.0;
        balancing = d.balancing;
        // 串数 / 容量以保护板数据为准
        if (d.nominalCapacity > 0) nominal = d.nominalCapacity;
        final n = d.cellVoltages.where((v) => v > 0.1).length;
        if (n > 0) cells = n;
      }
      // 记录历史（图表模式）
      final hist = (v, List<double> list) {
        list.add(v);
        if (list.length > 60) list.removeAt(0);
      };
      hist(d.soc, histSoc);
      hist(d.totalVoltage, histVoltage);
      hist(d.current, histCurrent);
      notifyListeners();
    });
    // 记住设备则自动重连
    final r = rememberedDeviceId;
    if (r != null && r.isNotEmpty) {
      unawaited(connect(r, auto: true));
    }
    notifyListeners();
  }

  Future<List<BmsDevice>> scan() => service.scan();

  /// 页面切换时向保护板请求当前页对应数据（一次性低频）。
  void requestPage(int index) {
    if (service is _ble.BleBmsService) {
      (service as _ble.BleBmsService).requestPage(index);
    }
  }

  Future<bool> connect(String deviceId, {bool auto = false}) async {
    connectError = null;
    final ok = await service.connect(deviceId);
    if (ok) {
      connected = true;
      deviceName = auto ? 'JK-BMS' : deviceName;
      rememberDevice(deviceId);
      // 模拟：给模拟设备补个名
      if (useMock && (deviceName.isEmpty || deviceName == 'JK-BMS')) {
        deviceName = deviceId;
      }
    } else {
      connectError = service.lastError ?? '连接失败';
    }
    notifyListeners();
    return ok;
  }

  void rememberDevice(String id) async {
    rememberedDeviceId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jk_device', id);
  }

  Future<void> disconnect() async {
    await service.disconnect();
    connected = false;
    data = null;
    deviceName = '';
    notifyListeners();
  }

  // ---- 首页开关（状态以保护板数据为准）----
  /// 真实模式下开关由保护板控制，本地不覆盖其状态。
  void toggleCharge() {
    charging = !charging;
    if (useMock) {
      (service as MockBmsService).setCharge(charging);
    }
    notifyListeners();
  }

  void toggleDischarge() {
    discharging = !discharging;
    if (useMock) {
      (service as MockBmsService).setDischarge(discharging);
    }
    notifyListeners();
  }

  void toggleBalance() {
    balancing = !balancing;
    if (useMock) {
      (service as MockBmsService).setBalance(balancing);
    }
    notifyListeners();
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
  Future<void> setPwdEnabled(bool on) async {
    pwdEnabled = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('jk_pwd_en', on);
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
    if (useMock) {
      final m = service as MockBmsService;
      m.cells = cells;
      m.nominal = nominal;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('jk_cells', cells);
    await prefs.setDouble('jk_cap', nominal);
    notifyListeners();
  }

  void dispose() {
    _sub?.cancel();
    service.dispose();
    super.dispose();
  }
}

/// BLE 真实服务工厂（隔离 flutter_blue_plus 依赖，便于替换）。
class BleFactory {
  BleFactory._();
  static BmsDataService create() => _ble.BleBmsService();
}
