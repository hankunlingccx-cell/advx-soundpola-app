# SoundPola

产品：`first.md` · 视觉：`designstyle.md`

## 当前实现

Android **Jetpack Compose** MVP（`first.md` 目标 Flutter/RN，后续迁移）。

### 主流程

权限 → Record → 录音 → 结果 → Drafts → Press → Collection → Memory

### 设计规范

- 背景 `#FAFCFB`、主色 `#63E0CB`
- 录音中深色沉浸 `#0D1514`
- 组件见 `app/.../ui/theme/` 与 `DesignComponents.kt`

## 运行

Android Studio 打开项目 → Sync → 选设备 → Run **app**

```powershell
$env:JAVA_HOME = "D:\software installation\Androiddev\jbr"
.\gradlew.bat :app:assembleDebug
```

## 结构

```
app/src/main/java/com/soundpola/app/
├── data/SoundRepository.kt
├── ui/
│   ├── components/DesignComponents.kt
│   ├── record/
│   ├── drafts/
│   ├── collection/
│   ├── press/
│   └── navigation/SoundpolaApp.kt
```
