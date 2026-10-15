# BMS 监控 · 极空协议 APK 版（云构建）

贵州帝一无人化装备有限公司出品。仿极空保护板 App 的 BMS 监控客户端，**数据通过蓝牙按极空（JK/JBD）协议解析**，支持实时状态 / 首页 / 参数设置三页导航、能量环表盘、中英切换、亮暗主题、密码保护、扫描/扫码添加设备。

界面设计对齐网页预览版（`jikong-bms-preview/极空BMS预览.html`）。

---

## 一、云上构建 APK（推荐，无需本机装 Flutter）

本工程已内置 `.github/workflows/build_apk.yml`，用 GitHub Actions 在线编译：

1. 在 GitHub 新建一个私有仓库（例如 `jikong-bms`）。
2. 把本目录全部文件上传/推送到仓库 `main` 分支（包含 `.github/` 目录）。
3. 仓库 **Actions** 页 → 选择 **Build APK** 工作流 → **Run workflow**（或直接 push 触发）。
4. 构建约 3–6 分钟，完成后在 Actions 运行记录里可下载产物 **`jikong-bms-apk`**（`app-release.apk`），安装到手机即可测试。

> 首次构建 Gradle/Android 依赖下载较慢属正常。若你的网络对 gradle 依赖有限制，可在仓库 Settings→Secrets 里配置镜像，或本地构建。

## 二、本地构建（装有 Flutter 时）

```bash
flutter pub get
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

`release` 使用 debug 签名，方便直接安装测试；正式发布请配置正式签名（`android/app/build.gradle` 的 `signingConfig`）。

## 三、真机蓝牙权限

Android 首次扫描设备时，系统会弹窗请求**蓝牙**与**位置/附近设备**权限，需允许。已配置：

- `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT`（Android 12+）
- `BLUETOOTH` / `BLUETOOTH_ADMIN`（Android 11-）
- `ACCESS_FINE_LOCATION`

## 四、数据源：模拟 vs 真实 BLE

- 默认 **真实 BLE**（`lib/main.dart` 中 `kUseMock=false`）：通过 `BleBmsService` 连接极空保护板，解析协议遥测帧。
- 预览/自测可切 `kUseMock=true`，使用 `MockBmsService` 输出模拟数据。

## 五、极空协议说明（务必核对你的板子）

协议层见 `lib/services/jikong_protocol.dart`，按社区通用 JK 帧协议实现：

| 项目 | 约定 |
|---|---|
| 主机命令帧头 | `0x4E 0x57`（"NW"） |
| 设备遥测帧头 | `0x55 0xAA` |
| 校验 | 帧头起逐字节 XOR，低 16 位小端 |
| 命令模型 | 0x03 读寄存器、0x06 写寄存器 |
| BLE 服务/特征 | 默认 `0000ffe0-…` / `0000ffe1-…`（见 `BleBmsService`） |

**真板接入前请用你的板子固件核对以下两点**（不同型号/固件有差异）：
1. BLE 服务/特征 UUID（部分板用 `ffe5/ffe9`）→ 改 `BleBmsService` 的 `serviceUuid`/`charUuid`。
2. 寄存器映射与缩放系数 → 核对 `lib/services/jikong_protocol.dart` 中 `JkRegisterMap`（单体电压/温度/总电压电流/容量/SOC/均衡位图的地址与 scale），据实调整 `JkStatusParser`。

## 六、功能清单

- 三页导航：实时状态（实时数据+单体电压[最高蓝/最低红]+均衡线电阻）、首页（能量环渐变表盘+充电/放电/均衡开关+状态徽标）、参数设置（受密码保护）。
- 左上角 **+** 添加设备：搜索 / 扫描 / 扫码连接；连接后记住设备，下次启动自动重连。
- 右上角设置：语言（中/英）、主题（亮/暗）、密码保护（默认 123456）、联系方式、关于版本（公司 logo + 名称）。
- 状态栏、顶栏、连接指示灯、toast 提示。

## 七、目录结构

```
lib/
  main.dart / app.dart           # 入口（kUseMock 切换数据源）
  i18n/strings.dart              # 中英双语
  theme/app_theme.dart           # 亮暗主题
  state/app_state.dart           # Provider 全局状态
  models/bms_data.dart           # 数据模型
  services/
    jikong_protocol.dart         # 极空协议（帧/校验/寄存器解析）
    bms_data_service.dart        # 服务抽象
    ble_bms_service.dart         # 真实 BLE
    mock_bms_service.dart        # 模拟数据
  screens/                       # 首页/实时状态/参数设置/添加设备/应用设置/关于
  widgets/soc_gauge.dart         # 能量环表盘
android/                         # Android 平台（BLE 权限已配）
.github/workflows/build_apk.yml  # 云构建
assets/logo.png                  # 公司 logo
```
