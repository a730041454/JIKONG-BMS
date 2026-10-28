import 'package:flutter_test/flutter_test.dart';
import 'package:jikong_bms_app/models/inverter_data.dart';
import 'package:jikong_bms_app/services/gateway/crc16.dart';
import 'package:jikong_bms_app/services/gateway/egp.dart';
import 'package:jikong_bms_app/services/inverter/inverter_params.dart';
import 'package:jikong_bms_app/services/inverter/inverter_protocol.dart';

/// Modbus 03 应答构帧（供离线回归用）。
List<int> modbusReply(int slave, List<int> regs) {
  final body = <int>[slave, 0x03, regs.length * 2];
  for (final r in regs) {
    body.add((r >> 8) & 0xFF);
    body.add(r & 0xFF);
  }
  final crc = Crc16.modbus(body);
  return [...body, crc & 0xFF, (crc >> 8) & 0xFF];
}

/// ASCII 应答帧：`( … )\r`。
List<int> ascii(String text) => [0x28, ...text.codeUnits, 0x0D];

void main() {
  group('EGP 网关协议', () {
    test('CRC-16/XMODEM 标准校验值', () {
      expect(Crc16.xmodem('123456789'.codeUnits), 0x31C3);
    });

    test('编解码往返 + 任意分片', () {
      final codec = EgDecoder();
      final f1 = EgCodec.encode(EgPort.bms, [0xAA, 0x55, 0x90, 0xEB, 0x01]);
      final f2 = EgCodec.encode(
          EgPort.ctrl, '{"id":1,"cmd":"status"}'.codeUnits);
      final f3 = EgCodec.encode(EgPort.inv, List.generate(256, (i) => i & 0xFF));
      final stream = [...f1, ...f2, ...f3];

      final got = <EgFrame>[];
      // 按 7 字节一块喂入，模拟 BLE 分包
      for (var i = 0; i < stream.length; i += 7) {
        got.addAll(codec.feed(stream.sublist(
            i, i + 7 > stream.length ? stream.length : i + 7)));
      }
      expect(got.length, 3);
      expect(got[0].port, EgPort.bms);
      expect(got[0].payload, [0xAA, 0x55, 0x90, 0xEB, 0x01]);
      expect(got[1].text, '{"id":1,"cmd":"status"}');
      expect(got[2].payload.length, 256);
    });

    test('CRC 损坏后能重新同步下一个帧头', () {
      final codec = EgDecoder();
      final good = EgCodec.encode(EgPort.bms, [1, 2, 3]);
      final bad = EgCodec.encode(EgPort.inv, [9, 8, 7]);
      bad[bad.length - 1] ^= 0xFF; // 破坏 CRC 低字节
      final out = codec.feed([...bad, ...good]);
      expect(out.length, 1);
      expect(out.single.port, EgPort.bms);
      expect(out.single.payload, [1, 2, 3]);
    });

    test('帧头前的噪声字节被跳过', () {
      final codec = EgDecoder();
      final out = codec.feed([0x00, 0x5A, 0xA5, ...EgCodec.encode(EgPort.ctrl, [7])]);
      expect(out.single.payload, [7]);
    });
  });

  group('逆变器 Modbus RTU', () {
    final p = InvModbusProtocol();

    test('轮询队列为 4 个读取块，帧尾 CRC 低字节在前', () {
      final q = p.pollQueue;
      expect(q.map((e) => e.tag).toList(), ['batt', 'out', 'line', 'stat']);
      for (final r in q) {
        expect(r.bytes[0], InvModbusProtocol.defaultSlave);
        expect(r.bytes[1], 0x03);
        final crc = Crc16.modbus(r.bytes.sublist(0, r.bytes.length - 2));
        expect(r.bytes[r.bytes.length - 2], crc & 0xFF);
        expect(r.bytes[r.bytes.length - 1], (crc >> 8) & 0xFF);
      }
    });

    test('电池块解析：电压/电流符号/SOC/PV', () {
      final regs = List<int>.filled(24, 0);
      regs[0] = 532; // 7530 53.2V
      regs[1] = 0xFF9C; // 7531 -100 → -10.0A（负=充电）
      regs[2] = 88; // SOC
      regs[3] = 1200; // 充电功率 W
      regs[11] = 4253; // PV1 425.3V
      regs[13] = 850; // PV1 850W
      final buf = modbusReply(1, regs);
      final frame = p.tryTakeFrame(buf);
      expect(frame, isNotNull);
      expect(buf, isEmpty);
      final d = p.parse('batt', frame!, InverterData.empty);
      expect(d.batteryVoltage, closeTo(53.2, 0.001));
      expect(d.batteryCurrent, closeTo(-10.0, 0.001));
      expect(d.batterySoc, 88);
      expect(d.batteryChargePower, 1200);
      expect(d.pv1Voltage, closeTo(425.3, 0.001));
      expect(d.pv1Power, 850);
    });

    test('状态块解析：启动+输出状态合成模式文字', () {
      final regs = List<int>.filled(25, 0);
      regs[0] = 3; // 7594 逆变运行
      regs[1] = 2; // 7595 输出=逆变
      final frame = p.tryTakeFrame(modbusReply(1, regs));
      final d = p.parse('stat', frame!, InverterData.empty);
      expect(d.modeText, '逆变');
      expect(d.fault, isFalse);
      regs[17] = 0x0004; // 75A5 告警字
      final f2 = p.tryTakeFrame(modbusReply(1, regs));
      expect(p.parse('stat', f2!, InverterData.empty).fault, isTrue);
    });

    test('串流里的半个帧与异常应答', () {
      final regs = [1, 2, 3];
      final bytes = modbusReply(1, regs);
      final buf = <int>[];
      expect(p.tryTakeFrame(buf..addAll(bytes.sublist(0, 4))), isNull);
      expect(p.tryTakeFrame(buf..addAll(bytes.sublist(4))), isNotNull);
      // 异常应答：功能码 |0x80，长度 5
      final err = <int>[1, 0x83, 0x02];
      final c = Crc16.modbus(err);
      expect(p.isFailure('batt', p.tryTakeFrame([...err, c & 0xFF, (c >> 8) & 0xFF])!), isTrue);
    });

    test('写参数构帧：06 功能码 + 高字节在前 + CRC 低字节在前', () {
      final req = p.writeRequest('inv_out_volt', 230)!;
      expect(req.bytes.take(6).toList(), [1, 0x06, 0xA0, 0x29, 0x08, 0xFC]);
      final crc = Crc16.modbus(req.bytes.sublist(0, 6));
      expect(req.bytes[6], crc & 0xFF);
      expect(req.bytes[7], (crc >> 8) & 0xFF);
      expect(req.bytes.length, 8);
    });
  });

  group('逆变器 RS232 ASCII', () {
    final p = InvAsciiProtocol();

    test('查询应答以 ( 开头、\\r 结尾，可按空格切字段', () {
      final buf = <int>[0x28]; // 半截帧头
      expect(p.tryTakeFrame(buf), isNull);
      buf
        ..add(0x32)
        ..addAll('35.0 50.02 65.0 50.00 55.0 60.0 +1250)'.codeUnits)
        ..add(0x0D);
      final f = p.tryTakeFrame(buf);
      expect(f, isNotNull);
      final d = p.parse('HGRID', f!, InverterData.empty);
      expect(d.gridVoltage, closeTo(235.0, 0.001));
      expect(d.gridFrequency, closeTo(50.02, 0.001));
      expect(d.gridPower, closeTo(1250.0, 0.001)); // '+' = 从市电取电
    });

    test('输出侧与电池侧字段映射', () {
      final hop = p.tryTakeFrame(ascii('230.0 50.00 1500 1200 45 0.0 40.0 5.20)'));
      var d = p.parse('HOP', hop!, InverterData.empty);
      expect(d.outputVoltage, closeTo(230.0, 0.001));
      expect(d.outputPower, 1200);
      expect(d.outputVa, 1500);
      expect(d.loadPercent, 45);
      expect(d.outputCurrent, closeTo(5.2, 0.001));

      final hbat = p.tryTakeFrame(ascii('16 53.2 88 25.0 0.5 540 0000)'));
      d = p.parse('HBAT', hbat!, d);
      expect(d.batteryVoltage, closeTo(53.2, 0.001));
      expect(d.batterySoc, 88);
      expect(d.batteryCurrent, closeTo(-24.5, 0.001)); // 放电 0.5 - 充电 25
      expect(d.batteryChargePower, closeTo(53.2 * 25.0, 0.01));
    });

    test('写指令带 2 字节 XMODEM CRC（高字节在前）再回车', () {
      final req = p.writeRequest('inv_work_mode', 1)!;
      expect(String.fromCharCodes(req.bytes.take(5)), 'POP01');
      final crc = Crc16.xmodem('POP01'.codeUnits);
      expect(req.bytes[5], (crc >> 8) & 0xFF);
      expect(req.bytes[6], crc & 0xFF);
      expect(req.bytes.last, 0x0D);
    });

    test('NAK 应答里 CRC 字节含 0x0D 时不会截断', () {
      final body = '(NAK'.codeUnits;
      final crc = Crc16.xmodem('SON'.codeUnits); // 高字节可能等于 0x0D
      final tail = [(crc >> 8) & 0xFF, crc & 0xFF, 0x0D];
      final buf = [...body, ...tail];
      final f = p.tryTakeFrame(buf);
      expect(f, isNotNull);
      expect(f!.length, body.length + tail.length);
      expect(p.isFailure('ctl:SON', f), isTrue);
    });

    test('HPV 被 NAK 后自动改用 GBUS', () {
      final nak = p.tryTakeFrame(ascii('NAK 7209)'));
      expect(p.isFailure('HPV', nak!), isTrue);
      expect(p.pollQueue.map((e) => e.tag).toList(), contains('GBUS'));
    });

    test('HEEP1 设置概览：字段数不足时整体后移', () {
      // 非紧凑写法：第 4 段只有 7 位，输出电压单独占一段，其后所有字段下标 +1
      final f = p.tryTakeFrame(ascii(
          '1 60 50 0100010 230 000 0 0 0 0 1 010 030 090 040 56.4 54.0 46.0)'));
      final s = p.parseSettings('HEEP1', f!);
      expect(s, isNotNull);
      expect(s!['inv_work_mode'], 1);
      expect(s['inv_max_chg_curr'], 60);
      expect(s['inv_out_volt'], closeTo(230, 0.001));
      expect(s['inv_out_freq'], 50);
      expect(s['inv_bms_set'], 1);
      expect(s['inv_cv_volt'], closeTo(56.4, 0.001));
      expect(s['inv_float_volt'], closeTo(54.0, 0.001));
      expect(s['inv_eod_volt'], closeTo(46.0, 0.001));
    });
  });

  group('逆变器参数表', () {
    test('每个参数都有 Modbus 地址与 ASCII 写法', () {
      for (final p in kInvParams) {
        expect(p.addr, isNotNull, reason: p.key);
        expect(p.commandText(p.min + (p.max - p.min) / 2), isNotNull,
            reason: p.key);
      }
    });

    test('换算：物理值 ↔ 原始值', () {
      expect(invParamByKey('inv_out_volt')!.toRaw(230), 2300);
      expect(invParamByKey('inv_out_volt')!.toPhysical(2300), closeTo(230, 0.001));
      expect(invParamByKey('inv_out_freq')!.commandText(60), 'F60');
      expect(invParamByKey('inv_max_chg_curr')!.commandText(60), 'MNCHGC060');
      expect(invParamByKey('inv_cv_volt')!.commandText(56.4), 'PCVV56.4');
      expect(invParamByKey('inv_work_mode')!.commandText(2), 'POP02');
    });
  });
}
