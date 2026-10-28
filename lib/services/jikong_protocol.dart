/// 极空保护板（JK BMS）蓝牙 JK02（55AA）协议实现。
///
/// 实测（真机抓包，JK02_32S 布局）：
///   1. 连接 BLE 后，板子在 FFE1 特征持续发 `AT\r\n` 保活帧，可能单独到达，
///      也可能粘在数据帧前面；只能剥掉该前缀，不能整包丢弃
///   2. 建立推流：先发 0x97，再发 0x96（间隔 400ms）。只发 0x96 不会推流；
///      建流后板子持续被动推 0x02 帧（约 250ms/帧），不要周期性重发读指令
///   3. 设置参数帧（type 0x01）随 0x96 一起返回，写寄存器后可用 0x96 回读校验
///
/// JK02 命令（20 字节）：
///   AA 55 90 EB <寄存器/地址> <长度> <数据4B> <0x00*9> <CRC1B>
///     读：0x96 实时数据/设置参数、0x97 设备信息，长度 0x00
///     写：长度 = 数据字节数；CRC = 前 19 字节之和低字节
///
/// 回复帧：55 AA EB 90 <类型> <数据...> <CRC@299>（固定 300 字节，不足补 0）
///     类型 0x01 = 设置参数，0x02 = 实时数据，0x03 = 设备信息
library;

/// JK02 协议常量与命令构造。
class JkProtocol {
  JkProtocol._();

  static const int addrSettings = 0x96; // 设置参数（随实时数据一起返回 type 0x01）
  static const int addrCell = 0x96; // 实时数据
  static const int addrDevice = 0x97; // 设备信息

  static const int typeSettings = 0x01;
  static const int typeCell = 0x02;
  static const int typeDevice = 0x03;

  static const int frameLen = 300; // 回复帧固定长度（CRC 在 299）

  /// 构造 JK02 读命令帧（20 字节）。
  static List<int> _buildRead(int addr) {
    final f = List<int>.filled(20, 0);
    f[0] = 0xAA;
    f[1] = 0x55;
    f[2] = 0x90;
    f[3] = 0xEB;
    f[4] = addr;
    f[5] = 0x00; // 长度 0 = 读
    var crc = 0;
    for (var i = 0; i < 19; i++) {
      crc = (crc + f[i]) & 0xFF;
    }
    f[19] = crc;
    return f;
  }

  /// 读实时数据命令。
  static List<int> buildReadCell() => _buildRead(addrCell);

  /// 读设备信息命令。
  static List<int> buildReadDevice() => _buildRead(addrDevice);

  /// 读设置参数命令。
  static List<int> buildReadSettings() => _buildRead(addrSettings);

  /// 构造 JK02 写寄存器命令帧（20 字节）。
  ///
  /// 格式：AA 55 90 EB <寄存器> <数据长度> <数据前4B> <0x00*9> <CRC1B>
  /// 极空 BLE 版写寄存器与读命令共用帧格式，长度>0 即写。
  static List<int> buildWriteRegister(int reg, List<int> data) {
    final f = List<int>.filled(20, 0);
    f[0] = 0xAA;
    f[1] = 0x55;
    f[2] = 0x90;
    f[3] = 0xEB;
    f[4] = reg & 0xFF;
    f[5] = data.length > 4 ? 4 : data.length; // 数据长度（最多 4B）
    for (var i = 0; i < data.length && i < 4; i++) {
      f[6 + i] = data[i] & 0xFF;
    }
    var crc = 0;
    for (var i = 0; i < 19; i++) {
      crc = (crc + f[i]) & 0xFF;
    }
    f[19] = crc;
    return f;
  }

  /// u32 小端 4 字节。
  static List<int> u32le(int v) => [
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ];

  /// 充电 MOS 写寄存器（0x1D）：1 开 / 0 关。
  static List<int> buildChargeMos(bool on) =>
      buildWriteRegister(0x1D, [on ? 1 : 0, 0, 0, 0]);

  /// 放电 MOS 写寄存器（0x1E）：1 开 / 0 关。
  static List<int> buildDischargeMos(bool on) =>
      buildWriteRegister(0x1E, [on ? 1 : 0, 0, 0, 0]);

  /// 均衡开关写寄存器（0x1F）：1 开 / 0 关。
  static List<int> buildBalanceMos(bool on) =>
      buildWriteRegister(0x1F, [on ? 1 : 0, 0, 0, 0]);

  /// 电池串数设置写入（settings 帧偏移 114，寄存器 0x1C，u32 LE）。
  static List<int> buildWriteCellCount(int cells) =>
      buildWriteRegister(0x1C, u32le(cells));

  /// 标称容量设置写入（settings 帧偏移 130，寄存器 0x20，u32 LE，单位 mAh）。
  static List<int> buildWriteCapacity(double ah) =>
      buildWriteRegister(0x20, u32le((ah * 1000).round()));

  /// 按参数定义写入物理值（自动换算系数、按定义选择 len=1/4）。
  static List<int> buildWriteParam(JkParamDef p, double value) {
    final raw = (value * p.scale).round();
    if (p.len == 1) return buildWriteRegister(p.reg, [raw & 0xFF]);
    return buildWriteRegister(p.reg, u32le(raw));
  }

  static bool _match(List<int> buf, int h, List<int> pat) {
    for (var i = 0; i < pat.length; i++) {
      if (h + i >= buf.length || buf[h + i] != pat[i]) return false;
    }
    return true;
  }

  /// 从累积缓冲中取出一帧（固定 300 字节，CRC@299 校验）。
  /// 返回完整帧并消费；不足或校验失败则返回 null。
  /// 校验失败时丢弃帧头前 1 字节继续寻找，避免数据流中的杂字节（AT 等）误切帧。
  static List<int>? tryTakeFrame(List<int> buf) {
    while (true) {
      final h = buf.indexOf(0x55);
      if (h < 0) return null;
      if (!_match(buf, h, const [0x55, 0xAA, 0xEB, 0x90]) &&
          !_match(buf, h, const [0xAA, 0x55, 0xEB, 0x90])) {
        // 不是帧头，丢弃到下一个 0x55
        buf.removeRange(0, h + 1);
        continue;
      }
      if (h + frameLen > buf.length) return null; // 等待更多数据
      final frame = List.of(buf.sublist(h, h + frameLen));
      // CRC 校验：@299 = 前 299 字节和低字节
      var crc = 0;
      for (var i = 0; i < 299; i++) {
        crc = (crc + frame[i]) & 0xFF;
      }
      if (crc == frame[299]) {
        buf.removeRange(0, h + frameLen);
        return frame;
      }
      // 校验失败：丢弃 1 字节继续找（可能是数据流中的巧合序列）
      buf.removeRange(0, h + 1);
    }
  }

  static int _u16(List<int> d, int i) =>
      (d[i] & 0xFF) | ((d[i + 1] & 0xFF) << 8);
  static int _u32(List<int> d, int i) =>
      (d[i] & 0xFF) |
      ((d[i + 1] & 0xFF) << 8) |
      ((d[i + 2] & 0xFF) << 16) |
      ((d[i + 3] & 0xFF) << 24);
  static int _i32(List<int> d, int i) {
    final v = _u32(d, i);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }
  static int _i16(List<int> d, int i) {
    final v = _u16(d, i);
    return v >= 0x8000 ? v - 0x10000 : v;
  }
  static String _ascii(List<int> d, int i, int len) {
    final b = d.sublist(i, i + len);
    final s = String.fromCharCodes(b).replaceAll('\x00', '').trim();
    return s;
  }
}

/// 设置参数定义：settings 帧读偏移 + 写寄存器 + 换算系数。
class JkParamDef {
  final String key; // 界面 key（同时作为 AppState 取值键）
  final int reg; // 写寄存器
  final int offset; // settings 帧读偏移
  final double scale; // 物理值 = 原始值 / scale
  final int decimals;
  final bool signed; // 帧内为 i32
  final int len; // 写入长度（1 或 4）
  const JkParamDef(
    this.key,
    this.reg,
    this.offset, {
    this.scale = 1,
    this.decimals = 0,
    this.signed = false,
    this.len = 4,
  });
}

/// 已核对的设置参数表（偏移/寄存器见《极空BMS协议手册-JK02_32S》第 3、5 节）。
const List<JkParamDef> kJkParams = [
  JkParamDef('core_cells', 0x1C, 114),
  JkParamDef('core_cap', 0x20, 130, scale: 1000, decimals: 1),
  JkParamDef('bal_dv', 0x06, 26, scale: 1000, decimals: 3),
  JkParamDef('bal_sv', 0x22, 138, scale: 1000, decimals: 3),
  JkParamDef('bal_cur', 0x13, 78, scale: 1000, decimals: 1),
  JkParamDef('vp_ocv', 0x04, 18, scale: 1000, decimals: 3),
  JkParamDef('vp_recv', 0x09, 38, scale: 1000, decimals: 3),
  JkParamDef('vp_s100', 0x07, 30, scale: 1000, decimals: 3),
  JkParamDef('vp_or', 0x05, 22, scale: 1000, decimals: 3),
  JkParamDef('vp_ur', 0x03, 14, scale: 1000, decimals: 3),
  JkParamDef('vp_s0', 0x08, 34, scale: 1000, decimals: 3),
  JkParamDef('vp_uv', 0x02, 10, scale: 1000, decimals: 3),
  JkParamDef('vp_off', 0x0B, 46, scale: 1000, decimals: 3),
  JkParamDef('cp_cc', 0x0C, 50, scale: 1000, decimals: 1),
  JkParamDef('cp_cd', 0x0D, 54),
  JkParamDef('cp_cdr', 0x0E, 58),
  JkParamDef('cp_dc', 0x0F, 62, scale: 1000, decimals: 1),
  JkParamDef('cp_dd', 0x10, 66),
  JkParamDef('cp_ddr', 0x11, 70),
  JkParamDef('tp_cot', 0x14, 82, scale: 10, decimals: 1),
  JkParamDef('tp_cotr', 0x15, 86, scale: 10, decimals: 1),
  JkParamDef('tp_clt', 0x19, 102, scale: 10, decimals: 1, signed: true),
  JkParamDef('tp_cltp', 0x18, 98, scale: 10, decimals: 1, signed: true),
  JkParamDef('tp_dot', 0x16, 90, scale: 10, decimals: 1),
  JkParamDef('tp_dotr', 0x17, 94, scale: 10, decimals: 1),
  JkParamDef('tp_mos', 0x1A, 106, scale: 10, decimals: 1),
  JkParamDef('tp_mosr', 0x1B, 110, scale: 10, decimals: 1),
  JkParamDef('sc_d', 0x21, 134),
  JkParamDef('sc_r', 0x12, 74),
  JkParamDef('ss_v', 0x01, 6, scale: 1000, decimals: 3),
];

/// 按 key 查参数定义。
JkParamDef? jkParamDef(String key) {
  for (final p in kJkParams) {
    if (p.key == key) return p;
  }
  return null;
}

/// settings 帧（type=0x01）解析结果。
class JkSettings {
  final Map<String, double> values; // key → 物理值
  final int cellCount;
  final double capacityAh;
  final bool chargeEnabled;
  final bool dischargeEnabled;
  final bool balanceEnabled;

  const JkSettings({
    required this.values,
    required this.cellCount,
    required this.capacityAh,
    required this.chargeEnabled,
    required this.dischargeEnabled,
    required this.balanceEnabled,
  });
}

/// 实时数据解析结果。
class JkCellInfo {
  final double totalVoltage; // V
  final double current; // A（+充电 / -放电）
  final double soc; // %
  final double remainingAh;
  final double nominalAh;
  final int cycles;
  final List<double> cellVoltages; // V
  final List<double> cellResistances; // Ω（均衡线电阻）
  final double avgCellV; // V
  final double deltaV; // V
  final int maxCellIdx; // 最高单体序号（0 起，与帧内 @78 一致）
  final int minCellIdx; // 最低单体序号（0 起，与帧内 @79 一致）
  final List<double> temperatures; // ℃
  final double balanceCurrent; // A
  final bool chargeMos;
  final bool dischargeMos;
  final bool precharge;
  final bool balancingActive;

  const JkCellInfo({
    required this.totalVoltage,
    required this.current,
    required this.soc,
    required this.remainingAh,
    required this.nominalAh,
    required this.cycles,
    required this.cellVoltages,
    required this.cellResistances,
    required this.avgCellV,
    required this.deltaV,
    required this.maxCellIdx,
    required this.minCellIdx,
    required this.temperatures,
    required this.balanceCurrent,
    required this.chargeMos,
    required this.dischargeMos,
    required this.precharge,
    required this.balancingActive,
  });
}

/// 设备信息解析结果。
class JkDeviceInfo {
  final String model; // 型号，如 JK-BD6A20S10PD
  final String hwRev;
  final String swRev; // 固件版本，如 20.28
  final int uptime; // 秒
  final String mfgDate;
  final String bluetoothPassword; // 蓝牙密码（device 帧 @118，6 位 ASCII）
  const JkDeviceInfo({
    required this.model,
    required this.hwRev,
    required this.swRev,
    required this.uptime,
    required this.mfgDate,
    required this.bluetoothPassword,
  });
}

class JkParser {
  /// 解析实时数据帧（type=0x02），布局按真板抓包校验（JK02_32S）：
  ///
  ///   单体电压 2B×32 @6   | 使能位图 @70 | 平均 @74 | 压差 @76
  ///   最高序号 @78（0起） | 最低序号 @79 | 均衡线电阻 2B×32 @80
  ///   MOS 温 @144 | 总压 u32 @150 | 功率 @154 | 电流 i32 @158
  ///   T1 @162 | T2 @164 | 错误码 @166 | 均衡电流 i16 @170
  ///   均衡动作 @172 | SOC @173 | 剩余 u32 @174 | 标称 u32 @178
  ///   循环次数 u32 @182 | 累计循环量 @186 | SOH @190
  ///   充电 MOS @198 | 放电 MOS @199 | 预充 @200 | 均衡工作 @201
  ///   加热 @215 | T5 @254 | T4 @256 | T3 @258
  ///
  /// 电压/电流 0.001 精度，温度 i16 精度 0.1℃，容量 0.001Ah。
  static JkCellInfo parseCell(List<int> f) {
    final u16 = JkProtocol._u16;
    final u32 = JkProtocol._u32;
    final cells = <double>[];
    for (var i = 0; i < 32; i++) {
      cells.add(u16(f, 6 + i * 2) / 1000.0);
    }
    double? tempAt(int off) {
      if (off + 1 >= f.length) return null;
      final raw = u16(f, off);
      if (raw == 0 || raw >= 0xFF00) return null;
      final v = JkProtocol._i16(f, off) / 10.0;
      return (v > -40 && v < 150) ? v : null;
    }

    // UI 温度位：T1 保护板 / T2 电池 / T3~T5 预留探头（MOS 温单独，不混入）
    final temps = <double>[
      ...[162, 164, 258, 256, 254]
          .map(tempAt)
          .whereType<double>(),
    ];
    final res = <double>[];
    for (var i = 0; i < 32; i++) {
      res.add(u16(f, 80 + i * 2) / 1000.0);
    }
    final nominal = u32(f, 178) / 1000.0;
    final remaining = u32(f, 174) / 1000.0;
    final socRaw = f.length > 173 ? f[173] : 0;
    final soc = (socRaw <= 100 && (socRaw > 0 || remaining <= 0))
        ? socRaw.toDouble()
        : (nominal > 0 ? (remaining / nominal * 100).clamp(0.0, 100.0) : 0.0);
    final balancing =
        (f.length > 201 && f[201] != 0) || (f.length > 172 && f[172] != 0);
    return JkCellInfo(
      totalVoltage: u32(f, 150) / 1000.0,
      current: JkProtocol._i32(f, 158) / 1000.0,
      soc: soc,
      remainingAh: remaining,
      nominalAh: nominal,
      cycles: u32(f, 182),
      cellVoltages: cells,
      cellResistances: res,
      avgCellV: u16(f, 74) / 1000.0,
      deltaV: u16(f, 76) / 1000.0,
      maxCellIdx: f.length > 78 ? f[78] : 0,
      minCellIdx: f.length > 79 ? f[79] : 0,
      temperatures: temps,
      balanceCurrent: JkProtocol._i16(f, 170) / 1000.0,
      chargeMos: f.length > 198 && f[198] != 0,
      dischargeMos: f.length > 199 && f[199] != 0,
      precharge: f.length > 200 && f[200] != 0,
      balancingActive: balancing,
    );
  }

  /// 解析设置参数帧（type=0x01）。
  ///
  /// 开关使能位：@118 充电 / @122 放电 / @126 均衡（u32，0/1）。
  /// 运行时 MOS 位（cell 帧 @198/@199/@201）只代表当前通断/均衡动作，
  /// 不能当作用户开关状态回显。
  static JkSettings parseSettings(List<int> f) {
    final u32 = JkProtocol._u32;
    final values = <String, double>{};
    for (final p in kJkParams) {
      if (p.offset + 4 > f.length) continue;
      final raw = p.signed ? JkProtocol._i32(f, p.offset) : u32(f, p.offset);
      values[p.key] = raw / p.scale;
    }
    bool sw(int off) => off + 4 <= f.length && u32(f, off) != 0;
    return JkSettings(
      values: values,
      cellCount: u32(f, 114),
      capacityAh: u32(f, 130) / 1000.0,
      chargeEnabled: sw(118),
      dischargeEnabled: sw(122),
      balanceEnabled: sw(126),
    );
  }

  /// 解析设备信息帧（type=0x03）。
  ///
  /// 两种固件的密码位置不同：
  ///   新固件（如 19.09，JK_PB2A16S20P）：蓝牙密码 @62（6 位数字 ASCII）
  ///   旧固件（如 20.28，JK-BD6A20S10PD）：蓝牙密码 @118
  /// 布局：型号@6、硬件@22、固件@30、设备名@46、生产日期@78、设备号@86
  static JkDeviceInfo parseDevice(List<int> f) {
    String pwd = '';
    // 优先 @62（新固件），取到纯数字才采用；否则回退 @118（旧固件）
    final s62 = f.length > 62 ? JkProtocol._ascii(f, 62, 6) : '';
    final s118 = f.length > 118 ? JkProtocol._ascii(f, 118, 6) : '';
    if (s62.isNotEmpty && RegExp(r'^[0-9]{4,6}$').hasMatch(s62)) {
      pwd = s62;
    } else if (s118.isNotEmpty && RegExp(r'^[0-9]{4,6}$').hasMatch(s118)) {
      pwd = s118;
    }
    return JkDeviceInfo(
      model: JkProtocol._ascii(f, 6, 16),
      hwRev: JkProtocol._ascii(f, 22, 8),
      swRev: JkProtocol._ascii(f, 30, 8),
      uptime: JkProtocol._u32(f, 38),
      mfgDate: JkProtocol._ascii(f, 78, 8),
      bluetoothPassword: pwd,
    );
  }
}
