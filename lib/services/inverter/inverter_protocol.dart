import 'dart:convert';

import '../../models/inverter_data.dart';
import '../gateway/crc16.dart';
import 'inverter_params.dart';

/// 一条下发给逆变器的原始请求。
class InvRequest {
  final String tag; // 应答归属标识，解析时用它选择字段表
  final List<int> bytes;
  const InvRequest(this.tag, this.bytes);
}

/// 逆变器侧串口协议。
///
/// ESP32 网关只做字节中继，不理解逆变器协议；成帧、解析、换算全部在这里完成。
/// 两种承载由现场接线决定：RS485 走 Modbus RTU（9600 8N1），RS232 走 ASCII（2400 8N1）。
abstract class InverterProtocol {
  /// 界面上的协议名。
  String get label;

  /// 该协议要求的串口波特率（切换协议时下发给网关 set_uart）。
  int get baud;

  /// 一轮轮询要依次下发的请求（发完一条等其应答，再发下一条）。
  List<InvRequest> get pollQueue;

  /// 从累积缓冲取出一个完整应答帧；数据不足返回 null 且不消费缓冲。
  /// 帧头前的杂字节会被丢弃。
  List<int>? tryTakeFrame(List<int> buf);

  /// 解析 [tag] 请求对应的应答，返回叠加到 [base] 之后的新数据。
  InverterData parse(String tag, List<int> frame, InverterData base);

  /// 写一个设置参数；该协议不支持此参数时返回 null。
  InvRequest? writeRequest(String key, double value) => null;

  /// 打开参数页时按需下发的设置区读请求。
  List<InvRequest> settingsReadQueue() => const [];

  /// 从应答里解析设置参数（键 → 物理值）；与该应答无关时返回 null。
  Map<String, double>? parseSettings(String tag, List<int> frame) => null;

  /// 应答是否表示失败（NAK / 异常码）。
  bool isFailure(String tag, List<int> frame) => false;

  static List<int> utf8Bytes(String s) => utf8.encode(s);
}

/// 十进制文本 → 数值；空串或非法返回 null（区别于真实的 0）。
double? _numText(String? s) {
  if (s == null || s.isEmpty) return null;
  final t = s.trim();
  if (t.isEmpty) return null;
  return double.tryParse(t.replaceAll(',', '.'));
}

/// u16 → 有符号 i16。
int _s16(int v) => v > 0x7FFF ? v - 0x10000 : v;

// ============================================================ Modbus RTU

/// QA6248 离并网储能逆变器 Modbus 点表里的一个连续读块。
///
/// 协议规定一次读写不超过 32 个寄存器，因此按功能区拆块。
/// 寄存器地址按文档原值下发（不做 40001 偏移换算），32 位量的低字在低地址。
class InvMbBlock {
  final String tag;
  final int addr;
  final int count;
  const InvMbBlock(this.tag, this.addr, this.count);

  List<int> request(int slave) {
    final p = [slave, 0x03, (addr >> 8) & 0xFF, addr & 0xFF, (count >> 8) & 0xFF, count & 0xFF];
    final crc = Crc16.modbus(p);
    return [...p, crc & 0xFF, (crc >> 8) & 0xFF];
  }
}

/// RS485 Modbus RTU 主站实现（9600 8N1，从机地址 1，功能码 03/06）。
class InvModbusProtocol extends InverterProtocol {
  static const int defaultSlave = 1;

  /// 读块：电池与PV、输出、市电与温度、状态与告警。
  static const List<InvMbBlock> blocks = [
    InvMbBlock('batt', 0x7530, 24), // 7530-7547
    InvMbBlock('out', 0x7548, 31), // 7548-7566
    InvMbBlock('line', 0x756A, 21), // 756A-757E
    InvMbBlock('stat', 0x7594, 25), // 7594-75AC
  ];

  final int slave;
  InvModbusProtocol({this.slave = defaultSlave});

  @override
  String get label => 'RS485 Modbus';

  @override
  int get baud => 9600;

  @override
  List<InvRequest> get pollQueue =>
      [for (final b in blocks) InvRequest(b.tag, b.request(slave))];

  @override
  List<int>? tryTakeFrame(List<int> buf) {
    while (true) {
      final h = buf.indexOf(slave);
      if (h < 0) {
        buf.clear();
        return null;
      }
      if (h > 0) buf.removeRange(0, h);
      if (buf.length < 3) return null;
      final func = buf[1];
      // 各功能码的应答长度：03 = 头3 + 数据(2*寄存器数) + CRC2；06 = 8；0x10 = 7
      final int total;
      if (func == 0x03) {
        total = 5 + buf[2];
      } else if (func == 0x06) {
        total = 8;
      } else if (func == 0x10) {
        total = 7;
      } else if (func == 0x83 || func == 0x86 || func == 0x90) {
        total = 5; // 异常响应：从机 功能码|0x80 异常码 CRC2
      } else {
        buf.removeRange(0, 1);
        continue;
      }
      if (buf.length < total) return null;
      final frame = List.of(buf.sublist(0, total));
      final crc = Crc16.modbus(frame.sublist(0, total - 2));
      if ((crc & 0xFF) == frame[total - 2] &&
          ((crc >> 8) & 0xFF) == frame[total - 1]) {
        buf.removeRange(0, total);
        return frame;
      }
      // CRC 不符：说明这个 0x01 只是数据里的巧合字节，丢 1 字节重新找帧头
      buf.removeRange(0, 1);
    }
  }

  @override
  bool isFailure(String tag, List<int> frame) =>
      frame.length >= 3 && frame[1] & 0x80 != 0;

  @override
  InverterData parse(String tag, List<int> frame, InverterData base) {
    if (frame.length < 4 || frame[1] != 0x03) return base;
    final n = frame[2];
    if (frame.length < 3 + n) return base;
    final r = <int>[];
    for (var i = 0; i < n ~/ 2; i++) {
      r.add((frame[3 + i * 2] << 8) | frame[4 + i * 2]);
    }
    // 块内偏移 → 值；越界（个别机型寄存器数不同）返回 null
    int? at(int off) => off >= 0 && off < r.length ? r[off] : null;
    double? sc(int off, double k, {bool signed = false}) {
      final v = at(off);
      if (v == null) return null;
      return (signed ? _s16(v) : v) / k;
    }

    switch (tag) {
      case 'batt': // 7530 起
        return base.copyWith(
          batteryVoltage: sc(0, 10),
          batteryCurrent: sc(1, 10, signed: true), // 正=放电 负=充电
          batterySoc: sc(2, 1),
          batteryChargePower: sc(3, 1),
          lineChargeCurrent: sc(4, 10, signed: true),
          pvChargeCurrent: sc(5, 10, signed: true),
          pv1Voltage: sc(11, 10),
          pv1Current: sc(12, 10),
          pv1Power: sc(13, 1),
          pv2Voltage: sc(14, 10),
          pv2Current: sc(15, 10),
          pv2Power: sc(16, 1),
        );
      case 'out': // 7548 起
        return base.copyWith(
          outputVoltage: sc(0, 10),
          outputCurrent: sc(1, 10, signed: true),
          outputFrequency: sc(2, 100),
          outputPower: sc(4, 1, signed: true),
          outputVa: sc(5, 1, signed: true),
          loadPercent: sc(6, 1),
        );
      case 'line': // 756A 起：市电A相电压/电流/频率…7574 市电A相有功、7579 温度1、757E 风扇
        return base.copyWith(
          gridVoltage: sc(0, 10),
          gridFrequency: sc(2, 100),
          gridPower: sc(10, 1, signed: true), // LinePowerW_A
          temperature: sc(15, 10, signed: true), // Temper1
          fanDuty: sc(20, 1),
        );
      case 'stat': // 7594 起
        final startup = at(0);
        final out = at(1);
        final alarm = <int>[];
        for (var i = 17; i < 25 && i < r.length; i++) {
          alarm.add(r[i]);
        }
        final hasAlarm = alarm.any((w) => w != 0);
        return base.copyWith(
          workMode: startup == null || out == null ? null : startup * 10 + out,
          modeText: _modeText(startup, out),
          fault: hasAlarm,
          faultText: hasAlarm ? 'inv_alarm' : '',
          statusBits: startup == null ? null : (startup << 16) | (out ?? 0),
        );
      default:
        return base;
    }
  }

  static String? _modeText(int? startup, int? out) {
    if (startup == null) return null;
    final s = switch (startup) {
      1 => '待机',
      2 => '市电',
      3 => '逆变',
      0 => '初始化',
      _ => '状态$startup',
    };
    if (startup >= 2) return s;
    return switch (out) {
      1 => '市电输出',
      2 => '逆变输出',
      3 => '市电过载',
      4 => '逆变过载',
      _ => s,
    };
  }

  /// P04 用户设置区的读块（每块 ≤32 寄存器）。
  static const List<InvMbBlock> settingBlocks = [
    InvMbBlock('set', 0xA028, 16), // A028-A037 模式/电压/频率/充电电流
    InvMbBlock('set', 0xA08C, 12), // A08C-A097 电池类型/强充/浮充/EOD
    InvMbBlock('set', 0xA099, 1), // A099 BMS 通信
    InvMbBlock('set', 0xA0B2, 1), // A0B2 放电限流
  ];

  @override
  List<InvRequest> settingsReadQueue() => [
        for (final b in settingBlocks)
          InvRequest('set:${b.addr}:${b.count}', b.request(slave)),
      ];

  @override
  Map<String, double>? parseSettings(String tag, List<int> frame) {
    if (!tag.startsWith('set:')) return null;
    final parts = tag.split(':');
    if (parts.length < 3) return null;
    final base = int.parse(parts[1]);
    final count = int.parse(parts[2]);
    if (frame.length < 4 || frame[1] != 0x03) return null;
    final n = frame[2];
    if (n != count * 2 || frame.length < 3 + n) return null;
    final out = <String, double>{};
    for (final p in kInvParams) {
      final a = p.addr;
      if (a == null || a < base || a >= base + count) continue;
      final i = (a - base) * 2;
      final raw = (frame[3 + i] << 8) | frame[4 + i];
      out[p.key] = p.toPhysical(raw);
    }
    return out;
  }

  @override
  InvRequest? writeRequest(String key, double value) {
    final p = invParamByKey(key);
    final addr = p?.addr;
    if (p == null || addr == null) return null;
    final raw = p.toRaw(value);
    final body = [
      slave,
      0x06,
      (addr >> 8) & 0xFF,
      addr & 0xFF,
      (raw >> 8) & 0xFF,
      raw & 0xFF,
    ];
    final crc = Crc16.modbus(body);
    return InvRequest('set:$key', [...body, crc & 0xFF, (crc >> 8) & 0xFF]);
  }
}

// ============================================================ RS232 ASCII

/// RS232C ASCII 协议（2400 8N1，无从机地址）。
///
/// 实测规则（见《sscom调试指令》与《写指令校验帧表》）：
///   - 查询指令 = 指令文本 + `\r`，**不带** CRC
///   - 写指令 = 指令文本 + 2 字节 CRC-16/XMODEM（高字节在前，只覆盖指令文本）+ `\r`
///   - 应答以 `(` 开头、`\r` 结尾；查询应答字段以空格分隔、以 `)` 结束，无 CRC
///   - 写应答为 `(ACK`/`(NAK` 后再跟 2 字节 CRC，CRC 里可能混入 0x0D
class InvAsciiProtocol extends InverterProtocol {
  static const List<String> baseQueries = [
    'HGRID',
    'HOP',
    'HBAT',
    'HPV',
    'HPVB',
    'HTEMP',
    'HSTS2',
  ];

  /// 部分固件把 PV 查询实现为 GBUS（文档章节标题 HPV、示例却发 GBUS）。
  String pvCmd = 'HPV';

  /// NAK 过的查询名，本轮起改用备用写法。
  final Set<String> _naked = {};

  @override
  String get label => 'RS232 ASCII';

  @override
  int get baud => 2400;

  @override
  List<InvRequest> get pollQueue {
    final out = <InvRequest>[];
    for (final q in baseQueries) {
      if (_naked.contains(q)) continue;
      final cmd = q == 'HPV' ? pvCmd : q;
      out.add(InvRequest(cmd, InverterProtocol.utf8Bytes('$cmd\r')));
    }
    return out;
  }

  @override
  List<int>? tryTakeFrame(List<int> buf) {
    while (true) {
      final h = buf.indexOf(0x28); // '('
      if (h < 0) {
        buf.clear();
        return null;
      }
      if (h > 0) buf.removeRange(0, h);
      final ackLike = buf.length >= 4 &&
          (String.fromCharCodes(buf, 1, 4) == 'ACK' ||
              String.fromCharCodes(buf, 1, 4) == 'NAK');
      if (ackLike) {
        // 写应答 = (ACK/(NAK + 2 字节二进制 CRC + \r，CRC 里可能混入 0x0D，
        // 所以结束符只从下标 6 之后开始找。
        final e = buf.indexOf(0x0D, 6);
        if (e < 0) return null;
        final f = List.of(buf.sublist(0, e + 1));
        buf.removeRange(0, e + 1);
        return f;
      }
      final e = buf.indexOf(0x0D, 1);
      if (e < 0) return null;
      final f = List.of(buf.sublist(0, e + 1));
      buf.removeRange(0, e + 1);
      return f;
    }
  }

  /// 应答正文按空格切分（去掉首尾的 `(`、`)`、`\r`）。
  static List<String> _tokens(List<int> frame) {
    var s = utf8.decode(frame, allowMalformed: true).trim();
    while (s.startsWith('(')) {
      s = s.substring(1);
    }
    if (s.endsWith(')')) s = s.substring(0, s.length - 1);
    return s.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  }

  static String _t(List<String> tk, int i) => i < tk.length ? tk[i] : '';

  @override
  bool isFailure(String tag, List<int> frame) {
    final s = utf8.decode(frame, allowMalformed: true);
    if (!s.contains('NAK')) return false;
    // PV 查询有两种写法，NAK 后换另一种继续轮询，不能整条丢掉
    if (tag == 'HPV') {
      pvCmd = pvCmd == 'HPV' ? 'GBUS' : 'HPV';
      return true;
    }
    _naked.add(tag);
    return true;
  }

  @override
  InverterData parse(String tag, List<int> frame, InverterData base) {
    final tk = _tokens(frame);
    String? at(int i) => i < tk.length ? tk[i] : null;
    double? v(int i, {int? sign}) {
      final raw = at(i);
      if (raw == null) return null;
      if (sign != null) {
        // HGRID 的市电功率把方向写在数值前面：'+' 从市电流入，'-' 逆变器馈网
        if (raw.startsWith('+') || raw.startsWith('-')) {
          final n = _numText(raw.substring(1));
          return n == null ? null : (raw.startsWith('-') ? -n : n);
        }
      }
      return _numText(raw);
    }

    switch (tag) {
      case 'HGRID': // 市电电压 频率 丢失高 丢失低 频率高 频率低 流向+功率
        return base.copyWith(
          gridVoltage: v(0),
          gridFrequency: v(1),
          gridPower: v(6, sign: 1),
        );
      case 'HOP': // 输出电压 频率 视在 有功 负载率 直流分量 内部 电感电流
        return base.copyWith(
          outputVoltage: v(0),
          outputFrequency: v(1),
          outputVa: v(2),
          outputPower: v(3),
          loadPercent: v(4),
          outputCurrent: v(7),
        );
      case 'HBAT': // 节数 电压 SOC 充电电流 放电电流 BUS电压 开关标志
        return base.copyWith(
          batteryVoltage: v(1),
          batterySoc: v(2),
          batteryCurrent: _netBattCurrent(at(3), at(4)),
          batteryChargePower: _chgPower(at(1), at(3)),
          lineChargeCurrent: v(3),
        );
      case 'HPV':
      case 'GBUS': // PV电压 电流 功率
        return base.copyWith(
          pv1Voltage: v(0),
          pv1Current: v(1),
          pv1Power: v(2),
          pvChargeCurrent: v(1),
        );
      case 'HPVB':
        return base.copyWith(pv2Voltage: v(0), pv2Current: v(1), pv2Power: v(2));
      case 'HTEMP': // PV 逆变 升压 内部 最高 风扇1 风扇2
        return base.copyWith(temperature: v(1), fanDuty: v(5));
      case 'HSTS2': // 故障码 模式+7标志 [组2] [并机数+组3]
        final code = tk.isEmpty ? null : _numText(tk[0]);
        final m = tk.length > 1 ? tk[1] : '';
        final mode = m.isEmpty ? null : _modeCode(m[0]);
        final fault = code != null && code != 0;
        return base.copyWith(
          workMode: mode,
          modeText: _modeCharText(mode),
          fault: fault,
          faultText: fault ? 'inv_alarm' : '',
          statusBits: code == null ? null : code.round(),
        );
      default:
        return base;
    }
  }

  /// HBAT 的充/放电电流分两列给出，电池电流按「正=放电」合成。
  static double? _netBattCurrent(String? chg, String? dis) {
    final c = _numText(chg ?? '');
    final d = _numText(dis ?? '');
    if (c == null || d == null) return d;
    return d - c;
  }

  static double? _chgPower(String? volt, String? chg) {
    final u = _numText(volt ?? '');
    final c = _numText(chg ?? '');
    if (u == null || c == null) return null;
    return u * c;
  }

  static int? _modeCode(String ch) => const {
        'P': 0,
        'S': 1,
        'L': 2,
        'B': 3,
        'F': 4,
        'D': 5,
        'X': 6,
      }[ch];

  static String? _modeCharText(int? code) => code == null
      ? null
      : const ['初始上电', '待机', '市电', '电池', '故障', '关机', '测试'][code];

  @override
  List<InvRequest> settingsReadQueue() =>
      [InvRequest('HEEP1', InverterProtocol.utf8Bytes('HEEP1\r'))];

  /// HEEP1 概览里能读到的设置项。
  ///
  /// 该应答的字段个数随机型不同：第 4 段（索引 3）若长 enough（≥11 字符）
  /// 则输出电压写在其尾部，否则输出电压单独占一段，后续字段整体后移一位。
  @override
  Map<String, double>? parseSettings(String tag, List<int> frame) {
    if (tag != 'HEEP1') return null;
    final tk = _tokens(frame);
    if (tk.length < 8) return null;
    final s3 = tk[3].padRight(9, '0');
    final packed = tk[3].length >= 11;
    final shift = packed ? 0 : 1;
    String? g(int i) {
      final j = i + shift;
      return j < tk.length ? tk[j] : null;
    }

    // 输出电压紧跟第 4 段，不参与后移；频率及其后字段才整体 +1
    final kkk = packed ? tk[3].substring(8, 11) : tk[4];
    final out = <String, double>{};
    void put(String key, double? v) {
      if (v != null) out[key] = v;
    }

    double? digit(String? s) =>
        (s == null || s.isEmpty) ? null : double.tryParse(s[0]);
    put('inv_work_mode', digit(tk[0]));
    put('inv_max_chg_curr', _numText(tk[1]));
    put('inv_line_chg_curr', _numText(tk[2]));
    put('inv_line_range', digit(s3[0]));
    put('inv_bat_type', digit(s3[2]));
    put('inv_out_volt', _numText(kkk));
    put('inv_bms_set', digit(g(9)));
    put('inv_cv_volt', _numText(g(14)));
    put('inv_float_volt', _numText(g(15)));
    put('inv_eod_volt', _numText(g(16)));
    final f = g(4);
    if (f != null && f.isNotEmpty) out['inv_out_freq'] = f[0] == '0' ? 50 : 60;
    return out.isEmpty ? null : out;
  }

  @override
  InvRequest? writeRequest(String key, double value) {
    final text = invParamByKey(key)?.commandText(value);
    if (text == null) return null;
    return _writeFrame(key, text);
  }

  /// 控制类指令（SON / FAULTC / BLIACT01）。
  InvRequest controlRequest(String commandText) =>
      _writeFrame('ctl:$commandText', commandText);

  static InvRequest _writeFrame(String tag, String text) {
    final body = InverterProtocol.utf8Bytes(text);
    final crc = Crc16.xmodem(body);
    return InvRequest(
      tag,
      [...body, (crc >> 8) & 0xFF, crc & 0xFF, 0x0D],
    );
  }
}
