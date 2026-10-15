/// 极空保护板（JK BMS / JBD）通信协议实现。
///
/// 采用社区广泛逆向使用的 JK 帧协议：
///  - 主机命令帧头：`0x4E 0x57`（即 ASCII "NW"）
///  - 设备遥测帧头：`0x55 0xAA`
///  - 校验：对帧头起至校验位前的所有字节做 XOR，取 16 位小端（双字节）
///  - 命令采用寄存器模型：功能码 0x03 读保持寄存器、0x06 写单寄存器
///
/// ⚠️ 真实接入前，请用你的板子固件核对（不同型号/固件寄存器地址有差异）：
///   1. BLE 服务/特征 UUID（见 BleBmsService，默认 ffe0/ffe1）
///   2. 寄存器映射（见 JkRegisterMap 注释，字段偏移与缩放系数）
///   3. 是否需先发送"使能"帧才推送遥测（部分固件）
///
/// 本文件不依赖 Flutter，可独立单测。
library;

/// 小端字节读取。
class ByteReader {
  final List<int> _data;
  int _pos = 0;
  ByteReader(List<int> data) : _data = List.unmodifiable(data);
  int get remaining => _data.length - _pos;
  bool get hasMore => _pos < _data.length;

  int readU8() => _data[_pos++];
  int readU16() {
    final v = _data[_pos] | (_data[_pos + 1] << 8);
    _pos += 2;
    return v;
  }

  int readU32() {
    final v = _data[_pos] |
        (_data[_pos + 1] << 8) |
        (_data[_pos + 2] << 16) |
        (_data[_pos + 3] << 24);
    _pos += 4;
    return v;
  }

  /// 有符号电流（补码）。
  int readI16() {
    final v = readU16();
    return v >= 0x8000 ? v - 0x10000 : v;
  }
}

/// 极空协议帧工具（帧头 / 校验 / 命令构造 / 遥测解析）。
class JkProtocol {
  JkProtocol._();

  static const int hostHeader0 = 0x4E; // 'N'
  static const int hostHeader1 = 0x57; // 'W'
  static const int teleHeader0 = 0x55;
  static const int teleHeader1 = 0xAA;

  static const int funcRead = 0x03; // 读保持寄存器
  static const int funcWrite = 0x06; // 写单寄存器

  /// 16 位 XOR 校验（字节流逐字节异或，取低 16 位）。
  static int xor16(List<int> bytes) {
    var cs = 0;
    for (final b in bytes) {
      cs ^= b;
    }
    return cs & 0xFFFF;
  }

  /// 构造"读寄存器"命令帧（主机 → 设备）。
  /// 布局：4E 57 <len:16le> 03 <reg:16le> <count:16le> <cs:16le>
  static List<int> buildReadCommand({int reg = 0x00, int count = 0x60}) {
    final data = <int>[
      funcRead,
      reg & 0xFF,
      (reg >> 8) & 0xFF,
      count & 0xFF,
      (count >> 8) & 0xFF,
    ];
    final frame = <int>[
      hostHeader0,
      hostHeader1,
      data.length & 0xFF,
      (data.length >> 8) & 0xFF,
      ...data,
    ];
    final cs = xor16(frame);
    frame.add(cs & 0xFF);
    frame.add((cs >> 8) & 0xFF);
    return frame;
  }

  /// 构造"写单寄存器"命令帧（主机 → 设备）。
  /// 布局：4E 57 <len:16le> 06 <reg:16le> <val:16le> <cs:16le>
  static List<int> buildWriteRegister(int reg, int value) {
    final data = <int>[
      funcWrite,
      reg & 0xFF,
      (reg >> 8) & 0xFF,
      value & 0xFF,
      (value >> 8) & 0xFF,
    ];
    final frame = <int>[
      hostHeader0,
      hostHeader1,
      data.length & 0xFF,
      (data.length >> 8) & 0xFF,
      ...data,
    ];
    final cs = xor16(frame);
    frame.add(cs & 0xFF);
    frame.add((cs >> 8) & 0xFF);
    return frame;
  }

  static bool isTelemetry(List<int> data) {
    return data.length >= 6 && data[0] == teleHeader0 && data[1] == teleHeader1;
  }

  /// 从遥测帧中剥离校验，返回 [regPayload]（功能码 + 寄存器数据）。
  /// 校验失败返回 null。布局：55 AA <len:16le> <func> <regs...> <cs:16le>
  static List<int>? parseTelemetry(List<int> data) {
    if (!isTelemetry(data)) return null;
    final len = data[2] | (data[3] << 8);
    if (data.length < 4 + len + 2) return null;
    final body = data.sublist(0, 4 + len);
    final csRaw = data[4 + len] | (data[4 + len + 1] << 8);
    if (xor16(body) != csRaw) return null;
    return body.sublist(4); // 去掉 55 AA len，保留 func + regs
  }
}

/// 极空寄存器映射（典型 JK 布局，地址以"字"为单位）。
///
/// ⚠️ 字段偏移与缩放系数请以你的板子固件为准。默认按社区通用版本给出：
///   - 0x00..        单体电压（0.001 V）
///   - 温度区         12 路温度（0.1 ℃，有符号，偏移见注释）
///   - 总电压区        总电压（0.001 V）
///   - 总电流区        电流（0.001 A，有符号）
///   - 容量区          剩余/标称容量（mAh）、SOC（0.1%）
///   - 状态区          均衡位图、循环次数等
class JkRegisterMap {
  JkRegisterMap._();

  // ---- 缩放系数 ----
  static const double cellVScale = 0.001;
  static const double currentScale = 0.001;
  static const double tempScale = 0.1;
  static const double mAhToAh = 1 / 1000.0;

  // ---- 地址（字偏移，相对遥测寄存器数据起始）----
  // 单体电压区（0x00 起，每串 1 个字）
  // 温度区
  static const int tempStart = 0x20; // 12 路
  // 总量区
  static const int totalVoltReg = 0x2C;
  static const int totalCurReg = 0x2D;
  // 容量区
  static const int remCapReg = 0x2E; // 4 字节 mAh
  static const int nomCapReg = 0x30; // 4 字节 mAh
  static const int cycleReg = 0x32; // 2 字节
  static const int socReg = 0x34; // 2 字节，0.1%
  // 均衡区
  static const int balanceReg = 0x36; // 4 字节位图
}

/// 从"遥测负载"（func + 寄存器数据）解析出 [JkParsedStatus]。
/// [cellCount] 由用户设置的串数决定；偏移可按 [JkRegisterMap] 调整。
class JkStatusParser {
  final int cellCount;

  JkStatusParser({this.cellCount = 16});

  JkParsedStatus parse(List<int> payload) {
    final r = ByteReader(payload);
    // 跳过功能码
    if (r.hasMore) r.readU8();

    // ---- 单体电压区 ----
    final cells = <double>[];
    for (var i = 0; i < cellCount && r.remaining >= 2; i++) {
      cells.add(r.readU16() * JkRegisterMap.cellVScale);
    }

    // ---- 温度区（最多 12 路）----
    final temps = <double>[];
    while (r.remaining >= 2 && temps.length < 12) {
      final raw = r.readU16();
      // 0x4000 位表示负温（部分固件用 2000 偏移）
      final v = (raw & 0x4000) != 0 ? (raw & 0x3FFF) - 0x4000 : raw.toDouble();
      temps.add(v * JkRegisterMap.tempScale);
    }

    // ---- 总量区 ----
    final totalV = r.hasMore ? r.readU16() * JkRegisterMap.cellVScale : 0;
    final current = r.hasMore ? r.readI16() * JkRegisterMap.currentScale : 0;

    // ---- 容量区 ----
    final remMah = r.remaining >= 4 ? r.readU32() : 0;
    final nomMah = r.remaining >= 4 ? r.readU32() : 0;
    final cycles = r.remaining >= 2 ? r.readU16() : 0;
    final soc = r.remaining >= 2 ? r.readU16() * 0.1 : 0;

    // ---- 均衡区（位图）----
    final balance = r.remaining >= 2 ? r.readU16() : 0;

    return JkParsedStatus(
      totalVoltage: totalV,
      current: current,
      power: totalV * current,
      soc: soc.clamp(0, 100).toDouble(),
      remainingCapacity: remMah * JkRegisterMap.mAhToAh,
      nominalCapacity: nomMah * JkRegisterMap.mAhToAh,
      cellVoltages: cells,
      temperatures: temps,
      balanceStatus: balance,
      cycles: cycles,
    );
  }
}

/// 解析结果（协议层独立于 UI 的数据载体）。
class JkParsedStatus {
  final double totalVoltage;
  final double current;
  final double power;
  final double soc;
  final double remainingCapacity;
  final double nominalCapacity;
  final List<double> cellVoltages;
  final List<double> temperatures;
  final int balanceStatus;
  final int cycles;

  const JkParsedStatus({
    required this.totalVoltage,
    required this.current,
    required this.power,
    required this.soc,
    required this.remainingCapacity,
    required this.nominalCapacity,
    required this.cellVoltages,
    required this.temperatures,
    required this.balanceStatus,
    required this.cycles,
  });

  double get maxCellV => cellVoltages.isEmpty
      ? 0
      : cellVoltages.reduce((a, b) => a > b ? a : b);
  double get minCellV => cellVoltages.isEmpty
      ? 0
      : cellVoltages.reduce((a, b) => a < b ? a : b);
}
