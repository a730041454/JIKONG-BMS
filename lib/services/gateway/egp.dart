import 'crc16.dart';

/// ESP 网关端口号（EGP 帧里的 port 字段）。
class EgPort {
  EgPort._();

  /// 保护板（极空 JK02）字节流，双向透明中继。
  static const int bms = 0x01;

  /// 逆变器字节流，双向透明中继（Modbus RTU 或 RS232-ASCII 由 APP 侧决定）。
  static const int inv = 0x02;

  /// 控制通道，载荷为 UTF-8 JSON 文本（配网、状态、参数设置）。
  static const int ctrl = 0x03;
}

/// 一个已解码的网关帧。
class EgFrame {
  final int port;
  final List<int> payload;
  const EgFrame(this.port, this.payload);

  /// 控制通道的载荷按 UTF-8 JSON 解析。
  String get text {
    try {
      return String.fromCharCodes(payload);
    } catch (_) {
      return '';
    }
  }
}

/// ESP 网关协议（EGP）编解码。
///
/// 帧格式（小端端口、大端长度）：
///
///   偏移  长度  说明
///   0     2    帧头 0xA5 0x5A
///   2     1    协议版本，当前 0x01
///   3     1    端口号：0x01=保护板 0x02=逆变器 0x03=控制(JSON)
///   4     2    载荷长度（BE，最大 1024）
///   6     N    载荷
///   6+N   2    CRC16/XMODEM（高字节在前），计算范围 = [ver .. 载荷末尾]
///
/// BLE 与 TCP 两种承载共用本格式：BLE 按 MTU 切块写入，对端按流式重组。
class EgCodec {
  EgCodec._();

  static const int magicHi = 0xA5;
  static const int magicLo = 0x5A;
  static const int version = 0x01;

  /// 帧头+版本+端口+长度
  static const int headerLen = 6;
  static const int crcLen = 2;
  static const int maxPayload = 1024;

  /// 编码一帧。
  static List<int> encode(int port, List<int> payload) {
    if (payload.length > maxPayload) {
      throw ArgumentError('payload too long: ${payload.length}');
    }
    final out = <int>[
      magicHi,
      magicLo,
      version,
      port & 0xFF,
      (payload.length >> 8) & 0xFF,
      payload.length & 0xFF,
      ...payload,
    ];
    final crc = Crc16.xmodem(out.sublist(2));
    out.add((crc >> 8) & 0xFF);
    out.add(crc & 0xFF);
    return out;
  }
}

/// 流式解码器：接收任意切分的字节流，吐出完整帧。
///
/// 容错：帧头错位时向前扫描下一个 0xA5 0x5A；CRC 不符时丢弃一个字节重找帧头。
class EgDecoder {
  final List<int> _buf = [];

  /// 喂入一段字节，返回本次解出的完整帧。
  List<EgFrame> feed(List<int> chunk) {
    _buf.addAll(chunk);
    final out = <EgFrame>[];
    while (true) {
      final start = _findHeader();
      if (start < 0) {
        // 没有帧头：只保留最后一个字节（可能是半个帧头）
        if (_buf.length > 1) _buf.removeRange(0, _buf.length - 1);
        break;
      }
      if (start > 0) _buf.removeRange(0, start);
      if (_buf.length < EgCodec.headerLen) break;
      final ver = _buf[2];
      final port = _buf[3];
      final len = (_buf[4] << 8) | _buf[5];
      if (ver != EgCodec.version || len > EgCodec.maxPayload) {
        _buf.removeAt(0);
        continue;
      }
      final total = EgCodec.headerLen + len + EgCodec.crcLen;
      if (_buf.length < total) break;
      final body = _buf.sublist(2, EgCodec.headerLen + len);
      final got = (_buf[EgCodec.headerLen + len] << 8) | _buf[EgCodec.headerLen + len + 1];
      if (Crc16.xmodem(body) != got) {
        _buf.removeAt(0);
        continue;
      }
      out.add(EgFrame(port, _buf.sublist(EgCodec.headerLen, EgCodec.headerLen + len)));
      _buf.removeRange(0, total);
    }
    return out;
  }

  /// 丢弃残留字节（换连接时用）。
  void reset() => _buf.clear();

  int _findHeader() {
    for (var i = 0; i + 1 < _buf.length; i++) {
      if (_buf[i] == EgCodec.magicHi && _buf[i + 1] == EgCodec.magicLo) return i;
    }
    return -1;
  }
}
