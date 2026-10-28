/// 两种 CRC-16，逆变器两套协议与网关协议各用其一。
class Crc16 {
  Crc16._();

  /// CRC-16/XMODEM：初值 0x0000、多项式 0x1021、不反转、不异或。
  /// 用于：ESP 网关协议帧校验、逆变器 RS232-ASCII 写指令的校验字节。
  static int xmodem(List<int> data) {
    var crc = 0x0000;
    for (final b in data) {
      crc ^= (b & 0xFF) << 8;
      for (var i = 0; i < 8; i++) {
        if (crc & 0x8000 != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc & 0xFFFF;
  }

  /// CRC-16/MODBUS：初值 0xFFFF、多项式 0xA001（反转）、低字节在前。
  /// 用于：逆变器 Modbus RTU 帧。
  static int modbus(List<int> data) {
    var crc = 0xFFFF;
    for (final b in data) {
      crc ^= b & 0xFF;
      for (var i = 0; i < 8; i++) {
        if (crc & 1 != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc & 0xFFFF;
  }
}
