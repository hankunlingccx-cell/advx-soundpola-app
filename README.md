# SoundPola

产品：`first.md` · 视觉：`designstyle.md`

## 工程

**Flutter 跨平台主工程：** `mobile/`（Android + iOS）

### 主流程

权限 → Record → 录音 → 结果 → Drafts → Press → Collection → Memory

## 运行

```powershell
cd mobile
flutter pub get
flutter run
```

**硬件能力：** 真实麦克风录音 + NFC 写入（需 NFC 已开启、NDEF 空白声片）。上链为本地模拟。

**Android：** 开启 NFC；首次录音允许麦克风权限；需安装 NDK 28.2（Android Studio → SDK Tools）。

**iOS：** Xcode 开启 **Near Field Communication Tag Reading** capability。

Flutter SDK 示例：`D:\downloads\flutter_windows_3.44.7-stable\flutter`

国内镜像：

- `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
- `PUB_HOSTED_URL=https://pub.flutter-io.cn`

## 设计规范

- 背景 `#FAFCFB`、主色 `#63E0CB`、录音沉浸 `#0D1514`
- Token 与组件：`mobile/lib/theme/`、`mobile/lib/widgets/`
