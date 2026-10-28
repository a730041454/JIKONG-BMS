import 'package:flutter/services.dart';

/// 客服微信二维码图片；替换 assets 中同名文件即可换成自己的二维码。
const String kWechatQrAsset = 'assets/wechat_qr.png';

/// 客服微信 wxid（微信内部 ID，不是手机号/昵称）。
/// 填上后点「打开微信」会直接进入该联系人的聊天，留空则只打开微信。
const String kWechatContactId = '';

/// 可选的联系人链接，仅在 [kWechatContactId] 为空时尝试。
/// 注意：微信不接管 `https://u.wechat.com/...` 这类二维码域名，
/// 填普通网页链接才会交给微信内置浏览器打开。
const String kWechatContactLink = '';

enum WeChatOpenResult { contact, home, none }

class WeChatService {
  static const MethodChannel _channel = MethodChannel('bms/contact');

  /// 把客服二维码写入系统相册，返回保存位置；失败抛 PlatformException。
  static Future<String?> saveQr() async {
    final data = await rootBundle.load(kWechatQrAsset);
    return _channel.invokeMethod<String>('saveImage', {
      'bytes': data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      'name': 'bms_wechat_qr',
    });
  }

  /// 打开微信：配置了客服 ID 就直达其聊天，否则打开微信主界面。
  static Future<WeChatOpenResult> openWeChat() async {
    final r = await _channel.invokeMethod<String>('openWeChat', {
      'id': kWechatContactId,
      'link': kWechatContactLink,
    });
    return switch (r) {
      'contact' => WeChatOpenResult.contact,
      'home' => WeChatOpenResult.home,
      _ => WeChatOpenResult.none,
    };
  }
}
