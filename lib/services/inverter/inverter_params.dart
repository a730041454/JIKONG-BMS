/// 逆变器设置参数表。
///
/// 同一份参数列表服务两种串口协议：Modbus RTU 写 0xA0xx 用户设置区，
/// RS232-ASCII 写对应的指令文本（`V230`、`MNCHGC060`、`PCVV56.4` 等）。
/// 界面只按 [InvParamDef.key] 取名，切换协议不影响表单结构。
enum InvAsciiKind {
  /// 该参数没有 ASCII 写法（只用 Modbus 下发）。
  none,

  /// 前缀 + 整数，如 `V230`。
  int_,

  /// 前缀 + 补零整数，如 `MNCHGC060`（pad 位宽度）。
  padded,

  /// 前缀 + 一位小数，如 `PCVV56.4`。
  volt,

  /// 输出频率：只接受 50/60，如 `F50`。
  freq,
}

class InvParamDef {
  /// 参数键，同时作为 i18n 键与界面取值键。
  final String key;

  /// 中文兜底名（i18n 缺词条时显示）。
  final String title;

  /// 物理值 = 原始寄存器值 / scale。
  final double scale;

  final int decimals;
  final double min;
  final double max;

  /// Modbus 保持寄存器地址（P04 用户设置区），null 表示该协议不可写。
  final int? addr;

  /// 枚举参数：原始值 → 选项文案；null 表示数值输入。
  final Map<int, String>? options;

  final String asciiPrefix;
  final InvAsciiKind asciiKind;

  /// `padded` 时的最小位数。
  final int asciiPad;

  /// ASCII 用的换算系数（默认与 Modbus 相同；电流类 ASCII 用整安培）。
  final double asciiScale;

  const InvParamDef({
    required this.key,
    required this.title,
    this.addr,
    this.scale = 1,
    this.decimals = 0,
    this.min = 0,
    this.max = 65535,
    this.options,
    this.asciiPrefix = '',
    this.asciiKind = InvAsciiKind.none,
    this.asciiPad = 0,
    this.asciiScale = 0,
  });

  bool get isEnum => options != null;

  double get effAsciiScale => asciiScale == 0 ? scale : asciiScale;

  double toPhysical(int raw) => raw / scale;

  int toRaw(double value) => (value * scale).round();

  /// 生成 RS232-ASCII 写指令文本（不含 CRC 与回车）；无对应写法时返回 null。
  String? commandText(double value) {
    switch (asciiKind) {
      case InvAsciiKind.none:
        return null;
      case InvAsciiKind.int_:
        return '$asciiPrefix${(value / effAsciiScale).round()}';
      case InvAsciiKind.padded:
        final n = (value / effAsciiScale).round().clamp(0, 999);
        return '$asciiPrefix${n.toString().padLeft(asciiPad, '0')}';
      case InvAsciiKind.volt:
        return '$asciiPrefix${value.toStringAsFixed(1)}';
      case InvAsciiKind.freq:
        return '$asciiPrefix${value.round() == 60 ? 60 : 50}';
    }
  }
}

/// 逆变器可写设置项。
/// Modbus 地址取自《离并网储能逆变器Modbus协议 V2.6.2》P04 用户设置参数；
/// ASCII 写法取自实测《写指令校验帧表》。
const List<InvParamDef> kInvParams = [
  InvParamDef(
    key: 'inv_work_mode',
    title: '工作模式',
    addr: 0xA028,
    options: {0: 'SUB 市电优先', 1: 'SBU 电池优先', 2: 'SUF 混合', 3: 'PEC'},
    asciiPrefix: 'POP',
    asciiKind: InvAsciiKind.padded,
    asciiPad: 2,
  ),
  InvParamDef(
    key: 'inv_out_volt',
    title: '输出电压',
    addr: 0xA029,
    scale: 10,
    min: 200,
    max: 250,
    asciiPrefix: 'V',
    asciiKind: InvAsciiKind.int_,
    asciiScale: 1,
  ),
  InvParamDef(
    key: 'inv_out_freq',
    title: '输出频率',
    addr: 0xA02A,
    scale: 100,
    decimals: 2,
    options: {50: '50 Hz', 60: '60 Hz'},
    asciiKind: InvAsciiKind.freq,
    asciiPrefix: 'F',
    asciiScale: 1,
  ),
  InvParamDef(
    key: 'inv_line_range',
    title: '市电输入范围',
    addr: 0xA02B,
    options: {0: 'APL 宽范围', 1: 'UPS 窄范围'},
    asciiPrefix: 'PGR',
    asciiKind: InvAsciiKind.padded,
    asciiPad: 2,
  ),
  InvParamDef(
    key: 'inv_max_chg_curr',
    title: '最大充电电流',
    addr: 0xA02F,
    scale: 10,
    decimals: 1,
    min: 1,
    max: 80,
    asciiPrefix: 'MNCHGC',
    asciiKind: InvAsciiKind.padded,
    asciiPad: 3,
    asciiScale: 1,
  ),
  InvParamDef(
    key: 'inv_line_chg_curr',
    title: '市电充电电流',
    addr: 0xA031,
    scale: 10,
    decimals: 1,
    min: 1,
    max: 60,
    asciiPrefix: 'MUCHGC',
    asciiKind: InvAsciiKind.padded,
    asciiPad: 3,
    asciiScale: 1,
  ),
  InvParamDef(
    key: 'inv_bat_type',
    title: '电池类型',
    addr: 0xA08C,
    options: {0: '铅酸 AGM', 1: '注水 FLD', 2: '自定义 USE', 4: '锂电 04', 7: '锂电 LIB'},
    asciiPrefix: 'PBT',
    asciiKind: InvAsciiKind.padded,
    asciiPad: 2,
  ),
  InvParamDef(
    key: 'inv_cv_volt',
    title: '恒压充电电压',
    addr: 0xA08D,
    scale: 10,
    decimals: 1,
    min: 40,
    max: 70,
    asciiPrefix: 'PCVV',
    asciiKind: InvAsciiKind.volt,
    asciiScale: 1,
  ),
  InvParamDef(
    key: 'inv_float_volt',
    title: '浮充电压',
    addr: 0xA08E,
    scale: 10,
    decimals: 1,
    min: 40,
    max: 70,
    asciiPrefix: 'PBFT',
    asciiKind: InvAsciiKind.volt,
    asciiScale: 1,
  ),
  InvParamDef(
    key: 'inv_eod_volt',
    title: '欠压关机电压',
    addr: 0xA096,
    scale: 10,
    decimals: 1,
    min: 40,
    max: 70,
    asciiPrefix: 'PSDV',
    asciiKind: InvAsciiKind.volt,
    asciiScale: 1,
  ),
  InvParamDef(
    key: 'inv_bms_set',
    title: 'BMS 通信',
    addr: 0xA099,
    options: {0: '关闭', 1: 'RS485', 2: 'CAN'},
    asciiPrefix: 'BMSC',
    asciiKind: InvAsciiKind.padded,
    asciiPad: 2,
  ),
  InvParamDef(
    key: 'inv_dischg_limit',
    title: '放电限流',
    addr: 0xA0B2,
    scale: 10,
    min: 1,
    max: 250,
    asciiPrefix: 'DISCC',
    asciiKind: InvAsciiKind.padded,
    asciiPad: 3,
    asciiScale: 1,
  ),
];

/// 控制类指令（非数值参数，界面按按钮下发；仅 RS232-ASCII 有对应写法）。
class InvControlDef {
  final String key;
  final String title;
  final String commandText;
  const InvControlDef(this.key, this.title, this.commandText);
}

const List<InvControlDef> kInvControls = [
  InvControlDef('inv_ctl_on', '开机', 'SON'),
  InvControlDef('inv_ctl_clear', '清除故障', 'FAULTC'),
  InvControlDef('inv_ctl_activate', '锂电激活', 'BLIACT01'),
];

InvParamDef? invParamByKey(String key) {
  for (final p in kInvParams) {
    if (p.key == key) return p;
  }
  return null;
}
