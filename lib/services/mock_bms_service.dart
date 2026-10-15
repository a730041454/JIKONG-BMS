import 'dart:async';
import 'dart:math';

import '../models/bms_data.dart';
import 'bms_data_service.dart';

/// 模拟数据服务（无真板子时用于预览 / 自测）。
/// 替换为 [BleBmsService] 即接入真实极空协议数据。
class MockBmsService extends BmsDataService {
  final _controller = StreamController<BmsData>.broadcast();
  final _random = Random();

  @override
  String? get lastError => null;

  int _cells = 16;
  double _nominal = 100;
  double _soc = 88;
  bool _connected = false;
  bool _charging = false;
  bool _discharging = false;
  bool _balancing = true;
  double _temp = 25.7;
  Timer? _timer;
  int _elapsed = 0;
  final _devices = <BmsDevice>[
    BmsDevice(name: 'JK-B2A16S20P', id: 'A4:C1:38:2B:7D:10', rssi: -48),
    BmsDevice(name: 'JK-B1A8S20P', id: 'A4:C1:38:5E:9A:22', rssi: -62),
    BmsDevice(name: 'BT-SERIAL-04', id: '30:AE:A4:11:0C:77', rssi: -75),
    BmsDevice(name: 'JK-B2A20S', id: 'A4:C1:38:9F:11:38', rssi: -80),
  ];

  double get nominal => _nominal;
  set nominal(double v) => _nominal = v;
  int get cells => _cells;
  set cells(int v) => _cells = v;

  void setCharge(bool on) => _charging = on;
  void setDischarge(bool on) => _discharging = on;
  void setBalance(bool on) => _balancing = on;

  double _rnd(double a, double b) => a + _random.nextDouble() * (b - a);

  BmsData _makeData() {
    final cells = <double>[];
    for (var i = 0; i < _cells; i++) {
      cells.add(3.47 + _rnd(-0.09, 0.10));
    }
    final totalV = cells.reduce((a, b) => a + b);
    final maxV = cells.reduce((a, b) => a > b ? a : b);
    final minV = cells.reduce((a, b) => a < b ? a : b);
    final res = <double>[];
    for (var i = 0; i < _cells; i++) {
      res.add(0.320 + _rnd(-0.006, 0.008));
    }
    final temps = <double>[
      _temp + _rnd(-0.4, 0.4),
      _temp - 1.2 + _rnd(-0.3, 0.3),
      _temp - 1.4 + _rnd(-0.3, 0.3),
    ];
    return BmsData(
      totalVoltage: totalV,
      current: _current,
      power: totalV * _current,
      soc: _soc,
      remainingCapacity: _soc / 100 * _nominal,
      nominalCapacity: _nominal,
      cellVoltages: cells,
      cellResistances: res,
      temperatures: temps,
      maxCellV: maxV,
      minCellV: minV,
      balancing: _balancing,
      balanceStatus: _balancing ? 0xFFFF : 0,
      logCount: 49,
      cycles: 0,
      sleepSeconds: 86400,
      batteryType: '铁锂',
      buzzerOn: false,
      alarm: false,
      alarmDesc: '',
    );
  }

  double get _current {
    final slow = sin(_elapsed * 0.12);
    if (slow > 0.85) {
      _charging = true;
      _discharging = false;
      return _rnd(1.5, 5);
    } else if (slow < -0.85) {
      _discharging = true;
      _charging = false;
      return -_rnd(1.5, 5);
    }
    _charging = false;
    _discharging = false;
    return _rnd(-0.2, 0.2);
  }

  @override
  Stream<BmsData> get dataStream => _controller.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<List<BmsDevice>> scan(
      {Duration timeout = const Duration(seconds: 6)}) async {
    await Future.delayed(const Duration(milliseconds: 800));
    return List.of(_devices);
  }

  @override
  Future<bool> connect(String deviceId) async {
    await Future.delayed(const Duration(milliseconds: 400));
    _connected = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += 1;
      _controller.add(_makeData());
    });
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<bool> writeRegister(int reg, int value) async => true;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}
