/// 逆变器（QA6248 / HVPINV08）实时数据。
///
/// 字段全部可空：null 表示「该协议没有这个测点」或「尚未取到数据」，
/// 0 表示真实读数为 0。界面据此区分「没有该测点」和「值为零」。
class InverterData {
  // ---- 电网侧 ----
  final double? gridVoltage; // 电网电压 V
  final double? gridFrequency; // 电网频率 Hz
  final double? gridPower; // 电网侧功率 W（微逆并网功率）

  // ---- 输出侧 ----
  final double? outputVoltage; // 输出电压 V
  final double? outputCurrent; // 输出电流 A
  final double? outputFrequency; // 输出频率 Hz
  final double? outputPower; // 输出有功功率 W
  final double? outputVa; // 输出视在功率 VA
  final double? loadPercent; // 负载率 %

  // ---- 电池侧 ----
  final double? batteryVoltage; // 电池电压 V
  final double? batterySoc; // 电池 SOC %
  final double? batteryCurrent; // 电池电流 A（正=放电）
  final double? batteryChargePower; // 电池充电功率 W
  final double? lineChargeCurrent; // 电网充电电流 A
  final double? pvChargeCurrent; // 光伏充电电流 A

  // ---- 光伏 ----
  final double? pv1Voltage; // V
  final double? pv1Current; // A
  final double? pv1Power; // W
  final double? pv2Voltage;
  final double? pv2Current;
  final double? pv2Power;

  // ---- 温度与散热 ----
  final double? temperature; // 逆变器温度 ℃
  final double? fanDuty; // 风扇占空比 %

  // ---- 状态 ----
  final int? workMode; // 工作模式码
  final String? modeText; // 工作模式文字
  final bool fault; // 是否有故障
  final String? faultText; // 故障描述
  final int? statusBits; // 原始状态位

  /// 数据时间戳（毫秒）。
  final int stamp;

  const InverterData({
    this.gridVoltage,
    this.gridFrequency,
    this.gridPower,
    this.outputVoltage,
    this.outputCurrent,
    this.outputFrequency,
    this.outputPower,
    this.outputVa,
    this.loadPercent,
    this.batteryVoltage,
    this.batterySoc,
    this.batteryCurrent,
    this.batteryChargePower,
    this.lineChargeCurrent,
    this.pvChargeCurrent,
    this.pv1Voltage,
    this.pv1Current,
    this.pv1Power,
    this.pv2Voltage,
    this.pv2Current,
    this.pv2Power,
    this.temperature,
    this.fanDuty,
    this.workMode,
    this.modeText,
    this.fault = false,
    this.faultText,
    this.statusBits,
    this.stamp = 0,
  });

  static const empty = InverterData();

  /// 是否已经取到任何有效数据。
  bool get hasData =>
      batteryVoltage != null ||
      outputVoltage != null ||
      gridVoltage != null ||
      pv1Power != null ||
      temperature != null;

  /// 逆变器输出功率（带符号：正=放电到负载，负=充电）。
  double? get signedOutputPower => outputPower;

  InverterData copyWith({
    double? gridVoltage,
    double? gridFrequency,
    double? gridPower,
    double? outputVoltage,
    double? outputCurrent,
    double? outputFrequency,
    double? outputPower,
    double? outputVa,
    double? loadPercent,
    double? batteryVoltage,
    double? batterySoc,
    double? batteryCurrent,
    double? batteryChargePower,
    double? lineChargeCurrent,
    double? pvChargeCurrent,
    double? pv1Voltage,
    double? pv1Current,
    double? pv1Power,
    double? pv2Voltage,
    double? pv2Current,
    double? pv2Power,
    double? temperature,
    double? fanDuty,
    int? workMode,
    String? modeText,
    bool? fault,
    String? faultText,
    int? statusBits,
    int? stamp,
  }) {
    return InverterData(
      gridVoltage: gridVoltage ?? this.gridVoltage,
      gridFrequency: gridFrequency ?? this.gridFrequency,
      gridPower: gridPower ?? this.gridPower,
      outputVoltage: outputVoltage ?? this.outputVoltage,
      outputCurrent: outputCurrent ?? this.outputCurrent,
      outputFrequency: outputFrequency ?? this.outputFrequency,
      outputPower: outputPower ?? this.outputPower,
      outputVa: outputVa ?? this.outputVa,
      loadPercent: loadPercent ?? this.loadPercent,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      batterySoc: batterySoc ?? this.batterySoc,
      batteryCurrent: batteryCurrent ?? this.batteryCurrent,
      batteryChargePower: batteryChargePower ?? this.batteryChargePower,
      lineChargeCurrent: lineChargeCurrent ?? this.lineChargeCurrent,
      pvChargeCurrent: pvChargeCurrent ?? this.pvChargeCurrent,
      pv1Voltage: pv1Voltage ?? this.pv1Voltage,
      pv1Current: pv1Current ?? this.pv1Current,
      pv1Power: pv1Power ?? this.pv1Power,
      pv2Voltage: pv2Voltage ?? this.pv2Voltage,
      pv2Current: pv2Current ?? this.pv2Current,
      pv2Power: pv2Power ?? this.pv2Power,
      temperature: temperature ?? this.temperature,
      fanDuty: fanDuty ?? this.fanDuty,
      workMode: workMode ?? this.workMode,
      modeText: modeText ?? this.modeText,
      fault: fault ?? this.fault,
      faultText: faultText ?? this.faultText,
      statusBits: statusBits ?? this.statusBits,
      stamp: stamp ?? this.stamp,
    );
  }

  /// 按测点名取值（界面表格用）。
  double? value(String key) {
    switch (key) {
      case 'grid_v':
        return gridVoltage;
      case 'grid_f':
        return gridFrequency;
      case 'grid_p':
        return gridPower;
      case 'out_v':
        return outputVoltage;
      case 'out_a':
        return outputCurrent;
      case 'out_f':
        return outputFrequency;
      case 'out_w':
        return outputPower;
      case 'out_va':
        return outputVa;
      case 'load':
        return loadPercent;
      case 'batt_v':
        return batteryVoltage;
      case 'batt_soc':
        return batterySoc;
      case 'batt_a':
        return batteryCurrent;
      case 'batt_w':
        return batteryChargePower;
      case 'line_a':
        return lineChargeCurrent;
      case 'pv_a':
        return pvChargeCurrent;
      case 'pv1_v':
        return pv1Voltage;
      case 'pv1_a':
        return pv1Current;
      case 'pv1_w':
        return pv1Power;
      case 'pv2_v':
        return pv2Voltage;
      case 'pv2_a':
        return pv2Current;
      case 'pv2_w':
        return pv2Power;
      case 'temp':
        return temperature;
      case 'fan':
        return fanDuty;
      default:
        return null;
    }
  }
}
