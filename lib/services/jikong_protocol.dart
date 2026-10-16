/// 极空保护板（JK BMS）蓝牙 JK02（55AA）协议实现。
///
/// 实测（真机 JK-BD6A20S10PD，固件 20.28）：
///   1. 连接 BLE 后，板子在 FFE1 特征持续发 `AT\r\n`（只是状态提示，
///      固件不做认证，可忽略）
///   2. 直接向 FFE1 写 JK02 读命令（55AA 帧），板子即以 55AA 帧回数据
///
/// JK02 读命令（20 字节）：
///   AA 55 90 EB <地址> <长度> <数据4B> <0x00*9> <CRC1B>
///     地址 0x96 = 实时数据（单体电压等），0x97 = 设备信息
///     长度 0x00 表示读；CRC = 前 19 字节之和低字节
///
/// 回复帧：55 AA EB 90 <类型> <数据...> <CRC@299>（固定 300 字节，不足补 0）
///     类型 0x01 = 设置参数，0x02 = 实时数据，0x03 = 设备信息
library;

/// JK02 协议常量与命令构造。
class JkProtocol {
  JkProtocol._();

  static const int addrSettings = 0x95; // 设置参数
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

  static bool _match(List<int> buf, int h, List<int> pat) {
    for (var i = 0; i < pat.length; i++) {
      if (h + i >= buf.length || buf[h + i] != pat[i]) return false;
    }
    return true;
  }

  /// 从累积缓冲中取出一帧（固定 300 字节）。返回完整帧并消费；不足则返回 null。
  static List<int>? tryTakeFrame(List<int> buf) {
    final h = buf.indexOf(0x55);
    if (h < 0) return null;
    if (!_match(buf, h, const [0x55, 0xAA, 0xEB, 0x90]) &&
        !_match(buf, h, const [0xAA, 0x55, 0xEB, 0x90])) {
      // 不是帧头，丢弃到下一个 0x55
      buf.removeRange(0, h + 1);
      return tryTakeFrame(buf);
    }
    if (h + frameLen > buf.length) return null; // 等待更多数据
    final frame = List.of(buf.sublist(h, h + frameLen));
    buf.removeRange(0, h + frameLen);
    return frame;
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
  static String _ascii(List<int> d, int i, int len) {
    final b = d.sublist(i, i + len);
    final s = String.fromCharCodes(b).replaceAll('\x00', '').trim();
    return s;
  }
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
  final int maxCellIdx; // 1 起
  final int minCellIdx; // 1 起
  final List<double> temperatures; // ℃
  final double balanceCurrent; // A
  final bool chargeMos;
  final bool dischargeMos;
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
  /// 解析实时数据帧（type=0x02）。
  ///
  /// 实测（真机固件 20.28，16 串）cell 帧布局（区别于 syssi 24S/32S 标准）：
  ///   6..36  单体电压 1..16（2B，0.001V），17..24 为 0
  ///   76     单体平均（2B，0.001V）
  ///   78     最大压差（2B，0.001V）
  ///   80     最高单体序号，81 最低单体序号
  ///   82..110 均衡线电阻 1..16（2B，0.001Ω）
  ///   150    总电压（4B，0.001V）
  ///   174    剩余容量（4B，0.001Ah），178 标称容量（4B，0.001Ah）
  ///   214/240/254 温度（2B，0.1℃）
  static JkCellInfo parseCell(List<int> f) {
    final u16 = JkProtocol._u16;
    final u32 = JkProtocol._u32;
    final cells = <double>[];
    for (var i = 0; i < 24; i++) {
      cells.add(u16(f, 6 + i * 2) / 1000.0);
    }
    final temps = <double>[];
    final t1 = u16(f, 214), t2 = u16(f, 240), tm = u16(f, 254);
    if (t1 > 0 && t1 < 65500) temps.add(t1 / 10.0);
    if (t2 > 0 && t2 < 65500) temps.add(t2 / 10.0);
    if (tm > 0 && tm < 65500) temps.add(tm / 10.0);
    // 均衡线电阻 2B×16 @82..110（0.001Ω）
    final res = <double>[];
    for (var i = 0; i < 16; i++) {
      res.add(u16(f, 82 + i * 2) / 1000.0);
    }
    final nominal = u32(f, 178) / 1000.0;
    final remaining = u32(f, 174) / 1000.0;
    final soc = nominal > 0 ? (remaining / nominal * 100.0).clamp(0.0, 100.0) : 0.0;
    return JkCellInfo(
      totalVoltage: u32(f, 150) / 1000.0,
      current: JkProtocol._i32(f, 158) / 1000.0,
      soc: soc,
      remainingAh: remaining,
      nominalAh: nominal,
      cycles: 0,
      cellVoltages: cells,
      cellResistances: res,
      avgCellV: u16(f, 76) / 1000.0,
      deltaV: u16(f, 78) / 1000.0,
      maxCellIdx: f.length > 80 ? f[80] : 0,
      minCellIdx: f.length > 81 ? f[81] : 0,
      temperatures: temps,
      balanceCurrent: 0.0,
      chargeMos: f.length > 166 && (f[166] & 0xFF) != 0,
      dischargeMos: f.length > 167 && (f[167] & 0xFF) != 0,
      balancingActive: f.length > 140 && (f[140] & 0xFF) != 0,
    );
  }

  /// 解析设备信息帧（type=0x03）。
  ///
  /// 实测布局：型号@6、硬件@22、固件@30、设备号@86、串口密码@62、
  /// 蓝牙密码@118（6 位 ASCII）、生产日期@78。
  static JkDeviceInfo parseDevice(List<int> f) {
    return JkDeviceInfo(
      model: JkProtocol._ascii(f, 6, 16),
      hwRev: JkProtocol._ascii(f, 22, 8),
      swRev: JkProtocol._ascii(f, 30, 8),
      uptime: JkProtocol._u32(f, 38),
      mfgDate: JkProtocol._ascii(f, 78, 8),
      bluetoothPassword: f.length > 118
          ? JkProtocol._ascii(f, 118, 6)
          : '',
    );
  }
}
