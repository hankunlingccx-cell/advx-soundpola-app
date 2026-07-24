# SoundPola

产品：`first.md` · 视觉：`designstyle.md`

## 工程结构

| 目录 | 技术 | 说明 |
|------|------|------|
| `mobile/` | **Flutter 3.44** | 跨平台主工程（Android + iOS） |
| `app/` | Jetpack Compose | Android 参考原型 |

### 主流程

权限 → Record → 录音 → 结果 → Drafts → Press → Collection → Memory

## 运行 Flutter（推荐）

```powershell
cd mobile
flutter pub get
flutter run
```

**硬件能力：** 麦克风录音 + NFC 写入（需 NFC 已开启、使用 NDEF 空白声片）。上链步骤为本地模拟。

**Android：** 在系统设置中开启 NFC；首次录音会弹出麦克风权限。

**iOS：** 需在 Xcode 为 Runner 开启 **Near Field Communication Tag Reading** capability。

Flutter SDK 路径示例：`D:\downloads\flutter_windows_3.44.7-stable\flutter`

国内镜像（已配置用户环境变量）：

- `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
- `PUB_HOSTED_URL=https://pub.flutter-io.cn`

## 运行 Android Compose 原型

```powershell
$env:JAVA_HOME = "D:\software installation\Androiddev\jbr"
.\gradlew.bat :app:assembleDebug
```

## 设计规范

- 背景 `#FAFCFB`、主色 `#63E0CB`、录音沉浸 `#0D1514`
- Flutter：`mobile/lib/theme/`、`mobile/lib/widgets/`
- Compose：`app/.../ui/theme/`、`DesignComponents.kt`
