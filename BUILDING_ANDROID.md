# Android debug 构建

## 已验证环境

- Windows 11 25H2
- Flutter 3.44.9（stable）
- Dart 3.12.2
- Android SDK 36.0.0
- JDK 17.0.20（通过 `flutter config --jdk-dir` 配置）
- Gradle 8.12.1
- Android Gradle Plugin 8.7.0
- Kotlin 2.1.0
- NDK 28.2.13676358

## 构建命令

在仓库根目录执行：

```powershell
pwsh -File .\tool\build_android_debug.ps1
```

APK 输出：`build\app\outputs\flutter-apk\app-debug.apk`。

Windows 的 Android Gradle Plugin、Kotlin 和 CMake 对包含非 ASCII 字符的项目路径支持不稳定。脚本检测到此类路径时，会把同一仓库临时映射到 `R:` 后构建，并在结束时删除映射；不会复制仓库。若 `R:` 已占用，可执行：

```powershell
pwsh -File .\tool\build_android_debug.ps1 -DriveLetter S
```

`android/local.properties` 继续保存每台机器自己的 Android SDK 和 Flutter SDK 路径，不应提交。JDK 使用 Flutter 的全局配置，不在仓库内写机器绝对路径。

## 当前限制

- 当前跨盘符依赖场景关闭了 Kotlin 增量编译，以避免 Pub Cache 与项目位于不同盘符时的缓存相对路径异常。
- Flutter 已提示后续需升级到 Gradle 8.14+、AGP 8.11.1+、Kotlin 2.2.20+；应作为单独升级任务验证，不与业务开发混合。
- `flutter pub get` 显示 40 个依赖存在不兼容当前约束的更新版本；本基线不做批量升级。
