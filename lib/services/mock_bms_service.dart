import 'dart:async';
import 'dart:math';

import '../models/bms_data.dart';
import 'bms_data_service.dart';

/// 模拟数据服务（无网关/真板时用于预览 / 自测）。
/// 真机走 [GatewayBmsService]，两者对界面完全同构。
class MockBmsService extends BmsDataService {
  final _controller = StreamController<BmsData>.broadcast();
  final _random = Random();

  @override
  String? get lastError => null;

  int _cells = 16;
  double _nominal = 100;
  double _soc = 88;
  bool _connected = false;
  bool _chgOn = true;
  bool _disOn = true;
  bool _balancing = true;
  double _temp = 25.7;
  Timer? _timer;
  int _elapsed = 0;

  double get nominal => _nominal;
  set nominal(double v) => _nominal = v;
  int get cells => _cells;
  set cells(int v) => _cells = v;

  void setCharge(bool on) {
    _chgOn = on;
    _emit();
  }

  void setDischarge(bool on) {
    _disOn = on;
    _emit();
  }

  void setBalance(bool on) {
    _balancing = on;
    _emit();
  }

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
      balanceCurrent: _balancing ? 0.639 : 0,
      chargeMos: _chgOn,
      dischargeMos: _disOn,
      prechargeMos: false,
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
      return _rnd(1.5, 5);
    } else if (slow < -0.85) {
      return -_rnd(1.5, 5);
    }
    return _rnd(-0.2, 0.2);
  }

  @override
  Stream<BmsData> get dataStream => _controller.stream;

  @override
  bool get isConnected => _connected;

  /// 开始推流（界面无需连接流程，构造后即调用）。
  void start() {
    _connected = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed += 1;
      _emit();
    });
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_makeData());
  }

  @override
  Future<bool> writeRegister(int reg, int value) async => true;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}
