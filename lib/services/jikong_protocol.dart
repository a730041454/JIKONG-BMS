/// 极空保护板（JK BMS）串口透传协议实现。
///
/// 极空板内置 BLE 串口透传模块，通信流程：
///   1. 手机连接 BLE 后，模块主动发 `AT\r\n`（握手）
///   2. 手机回复 `OK\r\n`，模块进入透传模式
///   3. 之后手机发送极空 0xDD 帧协议命令，板子以 0xDD 帧应答
///
/// 0xDD 帧结构（参考极空官方《软件板通用协议》）：
///   请求：DD <状态0xA5> <命令码> <长度> <数据> <校验2> 77
///   应答：DD <命令码> <状态> <长度> <数据> <校验2> 77
///   校验：0x10000 - (命令码 + 长度 + 数据字节和)，取 16 位，高位在前
library;

/// 极空 0xDD 串口协议。
class JkProtocol {
  JkProtocol._();

  static const int frameHeader = 0xDD; // 帧头
  static const int frameTail = 0x77; // 帧尾
  static const int modeRead = 0xA5; // 读取状态位

  static const int cmdBase = 0x03; // 读基本信息及状态
  static const int cmdCells = 0x04; // 读电池单体电压

  /// 计算请求校验：0x10000 - (cmd + len + data)，返回 [高字节, 低字节]。
  static List<int> _checksum(int cmd, List<int> data) {
    var s = cmd + data.length;
    for (final b in data) {
      s += b;
    }
    final cs = (0x10000 - s) & 0xFFFF;
    return [(cs >> 8) & 0xFF, cs & 0xFF];
  }

  /// 构造读命令帧：DD A5 <cmd> 00 <cs:16be> 77
  static List<int> buildRead(int cmd) {
    final cs = _checksum(cmd, const []);
    return [frameHeader, modeRead, cmd, 0, ...cs, frameTail];
  }

  /// 读基本信息及状态命令。
  static List<int> buildReadBase() => buildRead(cmdBase);

  /// 读单体电压命令。
  static List<int> buildReadCells() => buildRead(cmdCells);

  /// 从累积缓冲中取出完整的一帧（含 0xDD 头与 0x77 尾）。
  /// 帧长度由第 4 字节（长度字段）决定：总长 = 长度 + 7。
  /// 找不到合法帧头返回 null，且不消费缓冲。
  static List<int>? tryTakeFrame(List<int> buf) {
    // 找 0xDD 帧头
    var h = buf.indexOf(frameHeader);
    while (h >= 0 && h + 4 <= buf.length) {
      final len = buf[h + 3];
      final total = len + 7;
      if (h + total <= buf.length) {
        // 校验帧尾
        if (buf[h + total - 1] == frameTail) {
          final frame = List.of(buf.sublist(h, h + total));
          buf.removeRange(0, h + total);
          return frame;
        }
      }
      // 该位置不是合法帧，继续找下一个 0xDD
      h = buf.indexOf(frameHeader, h + 1);
    }
    return null;
  }

  /// 从完整帧中提取数据段（去掉 头/命令/状态/长度/校验/尾）。
  /// 返回帧头后的字节（含命令码、状态位、长度、数据）。
  static List<int> frameBody(List<int> frame) {
    return frame.sublist(1, frame.length - 3); // 去掉 DD 与 cs2 + 77
  }
}

/// 极空基本状态帧解析结果。
class JkBaseInfo {
  final double totalVoltage; // V
  final double current; // A（+充电 / -放电）
  final double remainingAh;
  final double nominalAh;
  final int cycles;
  final double soc; // %
  final int cellCount;
  final List<double> temperatures; // ℃
  final int balanceStatus; // 均衡位图
  final bool chargeMos;
  final bool dischargeMos;

  const JkBaseInfo({
    required this.totalVoltage,
    required this.current,
    required this.remainingAh,
    required this.nominalAh,
    required this.cycles,
    required this.soc,
    required this.cellCount,
    required this.temperatures,
    required this.balanceStatus,
    required this.chargeMos,
    required this.dischargeMos,
  });
}

/// 极空单体电压帧解析结果。
class JkCellsInfo {
  final List<double> cellVoltages; // V
  const JkCellsInfo({required this.cellVoltages});
}

class JkParser {
  /// 解析基本信息应答帧数据段（命令码之后、校验之前）。
  /// 数据结构（参考极空通用协议）：
  ///   总压 2B(10mV) | 总流 2B(10mA,有符号) | 剩余 2B(10mAh) | 标称 2B(10mAh)
  ///   | 循环 2B | 日期 2B | 均衡 2B | 均衡高 2B | 保护 2B | 保留 1B
  ///   | SOC 1B(%) | FET 1B | 串数 1B | NTC数 1B | NTC 2*N (0.1K, 2731偏移)
  static JkBaseInfo parseBase(List<int> d) {
    int u16(int i) => (d[i] << 8) | d[i + 1];
    final totalV = u16(0) * 0.01;
    final cur = (u16(2) >= 0x8000 ? u16(2) - 0x10000 : u16(2)) * 0.01;
    final remAh = u16(4) * 0.01;
    final nomAh = u16(6) * 0.01;
    final cycles = u16(8);
    // d[10..11] 生产日期
    final balance = u16(12);
    // d[14..15] 均衡高
    // d[16..17] 保护状态
    // d[18] 保留
    final soc = d.length > 19 ? d[19].toDouble() : 0;
    final fet = d.length > 20 ? d[20] : 0;
    final cellCount = d.length > 21 ? d[21] : 0;
    final ntcCount = d.length > 22 ? d[22] : 0;
    final temps = <double>[];
    for (var i = 0; i < ntcCount && 23 + i * 2 + 1 < d.length; i++) {
      final raw = u16(23 + i * 2);
      temps.add((raw - 2731) / 10.0);
    }
    return JkBaseInfo(
      totalVoltage: totalV,
      current: cur,
      remainingAh: remAh,
      nominalAh: nomAh,
      cycles: cycles,
      soc: soc.clamp(0, 100),
      cellCount: cellCount,
      temperatures: temps,
      balanceStatus: balance,
      chargeMos: (fet & 0x01) != 0,
      dischargeMos: (fet & 0x02) != 0,
    );
  }

  /// 解析单体电压应答帧数据段：每串 2B(mV，高位在前)。
  static JkCellsInfo parseCells(List<int> d) {
    final cells = <double>[];
    for (var i = 0; i + 1 < d.length; i += 2) {
      cells.add(((d[i] << 8) | d[i + 1]) / 1000.0);
    }
    return JkCellsInfo(cellVoltages: cells);
  }
}
