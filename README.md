# 轻书架

轻书架官方 Flutter 客户端。目前面向 Android 与 iOS 平台进行测试，macOS / Windows / Linux 需要自行编译测试。

- Dart 包名：`lightnovel`
- 应用标识：`app.lightnovel.shelf`

## 目录结构

```
lib/
  app/      路由、主题、底部标签外壳
  core/     SignalR 客户端、限流调度、错误分类、凭据与键值存储
  data/     接口模型与解码、会话状态机、设置持久化、仓库
  shared/   跨功能复用的组件与布局参数
  features/ auth · discover · shelf · history · community · book · search · reader · settings
```

## 开发

```bash
flutter pub get
flutter run -d <device>
```

注入刷新令牌：

```bash
flutter run --dart-define=REFRESH_TOKEN=<refresh token>
```

## iOS

部署目标 iOS 15.0。首次准备：

```bash
brew install cocoapods
xcodebuild -downloadPlatform iOS   # 模拟器运行时
flutter run -d <udid>
```

## 检查

```bash
flutter analyze
flutter test
```

## 致谢

基于 https://github.com/celia-sh/Novella 的 Flutter 版本重新开发得来

感谢 https://github.com/Kanscape 提供的 UI 布局交互思路，如果你需要体验 iOS 上的原生组件，不妨试试上述第三方客户端
