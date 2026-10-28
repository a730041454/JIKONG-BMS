# 储能监控 APP · ESP32 网关版（APK）

贵州帝一无人化装备有限公司出品。手机不再直连保护板，而是连 **ESP32 网关**，由网关转发保护板（极空 JK02）与逆变器（QA6248）的串口数据。三页导航：**BMS管理 / 首页 / 参数设置**。

## 一、通讯方式

| 方式 | 说明 |
|---|---|
| 蓝牙 | 手机连网关 BLE（广播名前缀 `GNZK-`），GATT 服务 `0000fde0`，写 `fde1`、通知 `fde2`，MTU 247 |
| 局域网 | 网关连上路由器后监听 TCP `8266`；手机与网关同网段，UDP `8266` 发 `EGP_DISCOVER` 自动发现 |
| 热点 | 网关未配网时自建 SoftAP（默认 `GNZK-HOTSPOT` / `12345678`），手机连热点后直连 `192.168.4.1:8266` |

三种承载共用同一套 **EGP 帧**（`A5 5A | ver | port | len(BE) | payload | CRC16/XMODEM`，端口 0x01 BMS、0x02 INV、0x03 CTRL-JSON）。协议定义见 `../ESP32网关/PROTOCOL.md`，编解码在 `lib/services/gateway/`。

配网入口：**连接网关** 页（首页左上角、断网提示卡、设置 → ESP32 网关 三处都可进入）→ 蓝牙或局域网连上网关 → 「扫描 Wi-Fi」→ 选 SSID 输入密码 → 下发 `wifi_connect`，成功后可切到局域网 IP 继续通讯。

## 二、逆变器（两种接口都支持）

参数设置 → **逆变器设置** 里切换链路：

- **RS485 Modbus RTU**：9600 8N1，从机 1，功能码 03/06/10，读 `0x7530/0x7548/0x756A/0x7594` 四块，写设置区 `0xA028…0xA0B2`。
- **RS232 ASCII**：2400 8N1，查询 `HGRID/HOP/HBAT/HPV(GBUS)/HPVB/HTEMP/HSTS2`，写指令文本后附 2 字节 XMODEM CRC（高字节在前）再 `\r`，读设置用 `HEEP1`。

同一张参数表 `lib/services/inverter/inverter_params.dart` 驱动两种链路，界面只认 key。控制类指令（SON / FAULTC / BLIACT01）仅 ASCII 链路可用。

## 三、页面

- **BMS管理**：总压/电流/功率、SOC 能量条、单体电压网格（最高蓝 / 最低红）、温度、均衡线电阻、循环与寿命。
- **首页**：能量环表盘 + 放电/充电/均衡开关 + **逆变器电气数据卡**（市电/输出/电池/PV/温度散热，可展开）。
- **参数设置**：逆变器设置、BMS设置 两个分组均可折叠；进入需授权（默认密码 123456），点数值直接改、右侧保存写入并回读。
- 右上角设置：语言、主题、网关密码、ESP32 网关（配网/改名）、微信联系、设备二维码、检查更新、关于。

## 四、构建

```bash
# 注意：Dart/Flutter 不能在含中文的路径下构建，需先复制到 ASCII 目录
flutter pub get
JAVA_HOME=<jdk17> ANDROID_HOME=<sdk> flutter build apk --release
# 产物 build/app/outputs/flutter-apk/app-release.apk → dist/BMS_<version>.apk
```

版本号在 `pubspec.yaml` 与 `android/app/build.gradle`（`flutterVersionCode` / `flutterVersionName`）两处，需同步；签名用 `android/app/keystore.jks`，保证可覆盖安装。

`lib/main.dart` 的 `kUseMock` 可切模拟数据（无网关、无真板时预览界面）。

## 五、更新渠道

App 启动后静默读取 Gitee 仓库 `gnzk/sample_repository` 的 Releases：Tag 命名 `v<版本>`，附件名 `BMS_<版本>.apk`。**只匹配主版本号为 2 的 Release**（在 `lib/services/update_service.dart` 的 `kUpdateMajor` 配置），1.x 的 Release 不会推给 V2 用户，反之亦然。

### 与 1.x 的关系（重要）

V2.0 是一条独立数据线，网关版的数据包与 1.x 直连版**不兼容**：

- 包名保持 `com.diyi.jikong_bms_app`、签名证书不变，所以 V2 与 1.x 在同一台机器上只能存在一个，且互相覆盖安装不会被签名/包名拦住。
- `versionCode` 从 **38** 开始（1.x 用到 37），V2 线内 2.1→39、2.2→40 递增。取高于 1.x 是为了能直接覆盖开发机上残留的 1.x——Android 12+ 之后 `adb install -d` 对非 debuggable 的 release 包已经不起作用，低于 1.x 的 versionCode 会把自己也拦在门外。
- 副作用：系统不再阻止 1.x 被 V2 覆盖安装，两条线之间只剩更新渠道这一层隔离（`kUpdateMajor = 2`，V2 只认 v2.x 的 Release）。
- **仍未解决的方向**：已发出去的 1.x App 读的是 `/releases/latest`，若 v2.x 成为该仓库最新 Release，1.x 用户依旧会被提示升级到 V2 并且装得上。要彻底隔开，需要给 V2 换一个独立仓库或独立 version.json 直链（`kUpdateManifestUrl`）。

版本号在 `pubspec.yaml`（`2.0.0+38`）与 `android/app/build.gradle`（`flutterVersionCode` / `flutterVersionName`）两处，需同步。


## 六、ESP32 网关固件

源码 `../ESP32网关/esp32_gateway/`，接线见 `pins.h`（UART1=保护板、UART2=逆变器，RS485 自动方向模块时 DE 填 -1）。编译：

```bash
arduino-cli compile --fqbn esp32:esp32:esp32 esp32_gateway
```

固件职责：EGP 封帧双向搬运（不解析业务协议）、BLE GATT、TCP:8266、UDP 发现、SoftAP、NVS 持久化配置、`set_uart/set_poll/set_name/set_ap/wifi_*` 控制命令、无手机连接 60 秒后关 WiFi 省电（蓝牙常开）。USB 串口支持 `W <ssid> <pass>`、`A`、`N`、`S`、`R` 单字母命令，配网不必依赖手机。

BLE+WiFi 体积超过默认分区，必须用 `huge_app`：

```bash
arduino-cli compile --fqbn "esp32:esp32:esp32:PartitionScheme=huge_app" --build-path build esp32_gateway
# 1.67 MB / 3 MB，实测占用 53%；RAM 全局变量 68 KB
```

## 七、版本记录

- **2.0**：V2 数据线首个版本，内容承接 1.14 网关版（通讯改为 ESP32 网关、BMS管理页、首页逆变器电气数据卡、双链路逆变器参数），更新渠道改为只收 v2.x；关于页只保留 V2 线的更新记录。
- **1.14**：重大更新——通讯改为 ESP32 网关（蓝牙/局域网/热点），新增网关连接与配网页；实时状态页改名 BMS管理；首页新增逆变器电气数据卡；参数设置拆为可折叠的「逆变器设置」「BMS设置」两组，逆变器支持 Modbus RTU 与 RS232 ASCII 双链路。
- **1.5**：新增已保存设备列表、未连接时隐藏全部数据。
- **1.3**：修复 MIUI 下「打开微信」被拦截，改走 `weixin://` + `setPackage`。
- **1.2**：微信二维码可保存相册、一键拉起微信。
- **1.1**：界面去品牌化；参数页强制授权门禁；首页三开关。
