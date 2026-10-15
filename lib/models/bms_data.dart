/// 电池组实时状态数据（由极空协议遥测帧解析得到，或由模拟服务生成）。
class BmsData {
  final double totalVoltage; // V
  final double current; // A（放电为负）
  final double power; // W
  final double soc; // %
  final double remainingCapacity; // Ah
  final double nominalCapacity; // Ah
  final List<double> cellVoltages; // V
  final List<double> cellResistances; // Ω（均衡线电阻）
  final List<double> temperatures; // ℃
  final double maxCellV; // V
  final double minCellV; // V
  final bool balancing; // 是否均衡中
  final bool chargeMos; // 充电 MOS 状态（保护板为准）
  final bool dischargeMos; // 放电 MOS 状态（保护板为准）
  final int balanceStatus; // 均衡位图
  final int logCount; // 详细日志条数
  final int cycles; // 循环次数
  final int sleepSeconds; // 进入休眠倒计时
  final String batteryType; // 电池类型（铁锂/三元…）
  final bool buzzerOn; // LCD 蜂鸣器
  final bool alarm; // 告警
  final String alarmDesc; // 告警描述

  const BmsData({
    required this.totalVoltage,
    required this.current,
    required this.power,
    required this.soc,
    required this.remainingCapacity,
    required this.nominalCapacity,
    required this.cellVoltages,
    required this.cellResistances,
    required this.temperatures,
    required this.maxCellV,
    required this.minCellV,
    required this.balancing,
    required this.chargeMos,
    required this.dischargeMos,
    required this.balanceStatus,
    required this.logCount,
    required this.cycles,
    required this.sleepSeconds,
    required this.batteryType,
    required this.buzzerOn,
    required this.alarm,
    required this.alarmDesc,
  });

  double get maxTemp => temperatures.isEmpty
      ? 0
      : temperatures.reduce((a, b) => a > b ? a : b);

  BmsData copyWith({
    double? totalVoltage,
    double? current,
    double? power,
    double? soc,
    double? remainingCapacity,
    double? nominalCapacity,
    List<double>? cellVoltages,
    List<double>? cellResistances,
    List<double>? temperatures,
    double? maxCellV,
    double? minCellV,
    bool? balancing,
    bool? chargeMos,
    bool? dischargeMos,
    int? balanceStatus,
    int? logCount,
    int? cycles,
    int? sleepSeconds,
    String? batteryType,
    bool? buzzerOn,
    bool? alarm,
    String? alarmDesc,
  }) {
    return BmsData(
      totalVoltage: totalVoltage ?? this.totalVoltage,
      current: current ?? this.current,
      power: power ?? this.power,
      soc: soc ?? this.soc,
      remainingCapacity: remainingCapacity ?? this.remainingCapacity,
      nominalCapacity: nominalCapacity ?? this.nominalCapacity,
      cellVoltages: cellVoltages ?? this.cellVoltages,
      cellResistances: cellResistances ?? this.cellResistances,
      temperatures: temperatures ?? this.temperatures,
      maxCellV: maxCellV ?? this.maxCellV,
      minCellV: minCellV ?? this.minCellV,
      balancing: balancing ?? this.balancing,
      chargeMos: chargeMos ?? this.chargeMos,
      dischargeMos: dischargeMos ?? this.dischargeMos,
      balanceStatus: balanceStatus ?? this.balanceStatus,
      logCount: logCount ?? this.logCount,
      cycles: cycles ?? this.cycles,
      sleepSeconds: sleepSeconds ?? this.sleepSeconds,
      batteryType: batteryType ?? this.batteryType,
      buzzerOn: buzzerOn ?? this.buzzerOn,
      alarm: alarm ?? this.alarm,
      alarmDesc: alarmDesc ?? this.alarmDesc,
    );
  }
}
