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

  StreamSubscription<BmsData>? _sub;

  bool get useMock => _useMock;
  bool get alarm => data?.alarm ?? false;
  double get maxCellV => data?.maxCellV ?? 0;
  double get minCellV => data?.minCellV ?? 0;
  double get totalVoltage => data?.totalVoltage ?? 0;
  double get current => data?.current ?? 0;
  double get power => data?.power ?? 0;
  double get soc => data?.soc ?? 0;
  double get maxTemp => data?.maxTemp ?? 0;
  double get remaining => data?.remainingCapacity ?? 0;

  /// 状态文本 key。
  String get stateKey {
    if (alarm) return 'st_alarm';
    if (charging) return 'st_charging';
    if (discharging) return 'st_discharging';
    return 'st_idle';
  }

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
    _sub = service.dataStream.listen((d) {
      data = d;
      // 由协议电流推断充/放（模拟服务会覆盖）
      if (!useMock) {
        charging = d.current > 0.1;
        discharging = d.current < -0.1;
      }
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

  Future<bool> connect(String deviceId, {bool auto = false}) async {
    final ok = await service.connect(deviceId);
    if (ok) {
      connected = true;
      deviceName = auto ? 'JK-BMS' : deviceName;
      rememberDevice(deviceId);
      // 模拟：给模拟设备补个名
      if (useMock && (deviceName.isEmpty || deviceName == 'JK-BMS')) {
        deviceName = deviceId;
      }
      notifyListeners();
    }
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

  // ---- 首页开关 ----
  void toggleCharge() {
    charging = !charging;
    if (useMock) (service as MockBmsService).setCharge(charging);
    notifyListeners();
  }

  void toggleDischarge() {
    discharging = !discharging;
    if (useMock) (service as MockBmsService).setDischarge(discharging);
    notifyListeners();
  }

  void toggleBalance() {
    balancing = !balancing;
    if (useMock) (service as MockBmsService).setBalance(balancing);
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
