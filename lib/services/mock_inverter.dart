import 'dart:async';
import 'dart:math';

import '../models/inverter_data.dart';
import '../services/gateway/gateway_link.dart';
import '../services/inverter/inverter_params.dart';

/// 模拟逆变器数据（无硬件时预览首页逆变器面板与参数页）。
class MockInverterSource {
  final _controller = StreamController<InverterData>.broadcast();
  final _random = Random();

  InverterData _data = InverterData.empty;
  final Map<String, double> settings = {};

  bool ascii = false;
  int cells = 16;
  double nominal = 100;

  Timer? _timer;
  int _tick = 0;

  Stream<InverterData> get stream => _controller.stream;
  InverterData get data => _data;

  double _rnd(double a, double b) => a + _random.nextDouble() * (b - a);

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick++;
      _data = _make();
      if (!_controller.isClosed) _controller.add(_data);
    });
    settings
      ..addAll({
        for (final p in kInvParams)
          p.key: p.isEnum ? p.options!.keys.first.toDouble() : p.min,
      });
    _data = _make();
  }

  InverterData _make() {
    final wobble = sin(_tick * 0.15);
    final charging = wobble > 0.4;
    final pv = (wobble > -0.2) ? _rnd(180, 420) : _rnd(0, 40);
    return InverterData(
      gridVoltage: 229.5 + _rnd(-0.6, 0.6),
      gridFrequency: 50.01 + _rnd(-0.02, 0.02),
      gridPower: charging ? _rnd(1200, 2100) : _rnd(-300, 200),
      outputVoltage: 230.2 + _rnd(-0.4, 0.4),
      outputCurrent: _rnd(2.1, 9.4),
      outputFrequency: 50.0,
      outputPower: _rnd(500, 2600),
      outputVa: _rnd(600, 2900),
      loadPercent: _rnd(8, 46),
      batteryVoltage: 51.2 + _rnd(-0.3, 0.3),
      batterySoc: 78,
      batteryCurrent: charging ? -_rnd(8, 26) : _rnd(4, 18),
      batteryChargePower: charging ? _rnd(450, 1300) : 0,
      lineChargeCurrent: charging ? _rnd(8, 20) : 0,
      pvChargeCurrent: pv > 100 ? _rnd(4, 14) : 0,
      pv1Voltage: pv,
      pv1Current: pv > 100 ? _rnd(3, 12) : 0,
      pv1Power: pv > 100 ? pv * _rnd(0.04, 0.09) : 0,
      pv2Voltage: pv * 0.92,
      pv2Current: pv > 100 ? _rnd(2, 9) : 0,
      pv2Power: pv > 100 ? pv * _rnd(0.03, 0.07) : 0,
      temperature: 41.5 + _rnd(-2, 4),
      fanDuty: _rnd(0, 55),
      workMode: 3,
      modeText: '逆变',
      fault: false,
      faultText: '',
      stamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}

/// 预览模式下假扮网关的发现结果。
class MockGateways {
  MockGateways._();

  static List<GatewayDevice> get list => const [
        GatewayDevice(
            name: 'GNZK-ESP32-A1B2',
            id: '3C:61:05:12:34:56',
            rssi: -55,
            mode: LinkMode.ble),
        GatewayDevice(
            name: 'GNZK-ESP32-C3D4',
            id: '3C:61:05:98:76:54',
            rssi: -71,
            mode: LinkMode.ble),
      ];

  static List<GatewayDevice> get lan => const [
        GatewayDevice(
            name: 'GNZK-ESP32-A1B2',
            id: '192.168.1.88',
            rssi: -40,
            mode: LinkMode.lan,
            ip: '192.168.1.88'),
      ];
}
