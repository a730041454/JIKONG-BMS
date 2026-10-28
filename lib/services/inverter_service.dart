import 'dart:async';

import '../models/inverter_data.dart';
import '../services/gateway/egp.dart';
import '../services/gateway/gateway_manager.dart';
import '../services/inverter/inverter_params.dart';
import '../services/inverter/inverter_protocol.dart';

/// 逆变器接入方式。
enum InvLinkKind {
  /// RS485，Modbus RTU，9600 8N1。
  modbus,

  /// RS232C，ASCII 文本指令，2400 8N1。
  ascii,
}

/// 逆变器轮询服务。
///
/// 通过 [GatewayManager] 的 [EgPort.inv] 端口收发原始字节；ESP32 只是字节中继，
/// 成帧与解析由 [InverterProtocol] 负责。请求严格串行：发一条、等应答（或超时）、再发下一条。
class InverterService {
  InverterService(this.gateway);

  final GatewayManager gateway;

  final _controller = StreamController<InverterData>.broadcast();
  StreamSubscription<EgFrame>? _sub;
  Timer? _timer;

  final List<int> _rx = [];
  final List<InvRequest> _queue = [];
  InvRequest? _active;
  Completer<bool>? _writeDone;

  InvLinkKind _kind = InvLinkKind.modbus;
  InverterProtocol _protocol = InvModbusProtocol();

  InverterData _data = InverterData.empty;
  final Map<String, double> _settings = {};

  Duration _responseTimeout = const Duration(milliseconds: 700);

  static const Duration _cycleGap = Duration(milliseconds: 1200);
  static const Duration _stepGap = Duration(milliseconds: 80);

  Stream<InverterData> get stream => _controller.stream;
  InverterData get data => _data;
  Map<String, double> get settings => Map.unmodifiable(_settings);
  InvLinkKind get kind => _kind;
  String get protocolLabel => _protocol.label;
  bool get isAscii => _kind == InvLinkKind.ascii;

  bool _running = false;

  /// 最近一次取到有效应答的时间（毫秒），0 表示还没取到过。
  int get lastStamp => _data.stamp;

  void start() {
    if (_running) return;
    _running = true;
    _sub ??= gateway.framesFor(EgPort.inv).listen(_onFrame);
    _fill();
    _pump();
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _queue.clear();
    _active = null;
    _rx.clear();
  }

  /// 切换逆变器接入协议，并把网关 UART2 的波特率改到协议要求值。
  Future<void> setKind(InvLinkKind kind) async {
    if (_kind == kind) return;
    stop();
    _kind = kind;
    _protocol = switch (kind) {
      InvLinkKind.modbus => InvModbusProtocol(),
      InvLinkKind.ascii => InvAsciiProtocol(),
    };
    // 2400 波特下字符本身耗时较长，超时放宽
    _responseTimeout =
        kind == InvLinkKind.ascii ? const Duration(seconds: 1) : const Duration(milliseconds: 700);
    await gateway.setUartBaud(2, _protocol.baud);
    _data = InverterData.empty;
    _settings.clear();
    start();
  }

  void _fill() {
    _queue
      ..clear()
      ..addAll(_protocol.pollQueue);
  }

  void _pump() {
    if (!gateway.isConnected) {
      _timer = Timer(_cycleGap, _pump);
      return;
    }
    if (_writeDone != null) return;
    if (_active != null) return;
    if (_queue.isEmpty) {
      _timer?.cancel();
      _timer = Timer(_cycleGap, () {
        _fill();
        _pump();
      });
      return;
    }
    final req = _queue.removeAt(0);
    _active = req;
    unawaited(gateway.send(EgPort.inv, req.bytes).then((ok) {
      if (!ok && _active == req) _advance();
    }));
    _timer?.cancel();
    _timer = Timer(_responseTimeout, _advance);
  }

  /// 一条查询结束（应答或超时），推进下一条。
  void _advance() {
    _timer?.cancel();
    _timer = null;
    _active = null;
    if (!_running) return;
    // RS485 半双工换向需要一点空档
    _timer = Timer(_stepGap, _pump);
  }

  void _onFrame(EgFrame frame) {
    _rx.addAll(frame.payload);
    while (true) {
      final f = _protocol.tryTakeFrame(_rx);
      if (f == null) break;
      final a = _active;
      if (a == null) {
        _rx.clear();
        break;
      }
      final failed = _protocol.isFailure(a.tag, f);
      if (a.tag.startsWith('set:') || a.tag.startsWith('ctl:')) {
        _finishWrite(!failed);
        continue;
      }
      if (failed) {
        _advance();
        continue;
      }
      _data = _protocol
          .parse(a.tag, f, _data)
          .copyWith(stamp: DateTime.now().millisecondsSinceEpoch);
      final s = _protocol.parseSettings(a.tag, f);
      if (s != null) _settings.addAll(s);
      if (!_controller.isClosed) _controller.add(_data);
      _advance();
      return; // 本轮应答已消费，剩下的字节留到下一次回调
    }
  }

  /// 参数页打开时读一次设置区（ASCII 用 HEEP1，Modbus 读 0xA0xx 块）。
  void requestSettings() {
    if (!_running) return;
    final reqs = _protocol.settingsReadQueue();
    if (reqs.isEmpty) return;
    _queue.insertAll(0, reqs);
    if (_active == null) _pump();
  }

  /// 写一个设置参数，返回设备是否确认。
  Future<bool> writeParam(String key, double value) async {
    final req = _protocol.writeRequest(key, value);
    if (req == null) return false;
    return _transact(req);
  }

  /// 下发控制类指令（开机 / 清除故障 / 锂电激活），仅 ASCII 协议有对应写法。
  Future<bool> sendControl(String commandText) {
    final p = _protocol;
    if (p is! InvAsciiProtocol) return Future.value(false);
    return _transact(p.controlRequest(commandText));
  }

  /// 暂停轮询、发一条写请求并等应答。
  Future<bool> _transact(InvRequest req) async {
    if (!gateway.isConnected) return false;
    _timer?.cancel();
    _queue.clear();
    _rx.clear();
    _active = req;
    final c = Completer<bool>();
    _writeDone = c;
    final ok = await gateway.send(EgPort.inv, req.bytes);
    if (!ok) {
      _finishWrite(false);
      return c.future;
    }
    _timer = Timer(const Duration(seconds: 3), () {
      if (_writeDone != null) _finishWrite(false);
    });
    return c.future;
  }

  void _finishWrite(bool ok) {
    _timer?.cancel();
    _timer = null;
    _active = null;
    final w = _writeDone;
    _writeDone = null;
    if (w != null && !w.isCompleted) w.complete(ok);
    if (_running) {
      _fill();
      _timer = Timer(_stepGap, _pump);
    }
  }

  void dispose() {
    stop();
    _sub?.cancel();
    _sub = null;
    _controller.close();
  }
}

/// 界面用的接入方式描述。
String invLinkLabel(InvLinkKind k) =>
    k == InvLinkKind.modbus ? 'RS485 Modbus RTU · 9600' : 'RS232 ASCII · 2400';

List<InvParamDef> get invParamDefs => kInvParams;
List<InvControlDef> get invControlDefs => kInvControls;
