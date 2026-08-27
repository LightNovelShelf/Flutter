# 轻书架

轻书架官方 Flutter 客户端。目前面向 Android 与 iOS 平台进行测试，macOS / Windows / Linux 需要自行编译测试。

目前已知 macOS 平台，没有签名的应用无法访问钥匙串，会导致登陆信息写入失败

- Dart 包名：`lightnovel`
- 应用标识：`app.lightnovel.shelf`

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

## 赞助本站

<a href="https://www.ifdian.net/a/wuyu8512">赞助</a>本站可以帮助我购买更多的 Token，来使网站变得更好

<img src=".github/afdian.jpeg" height="300">

## 致谢

基于 https://github.com/celia-sh/Novella 的 Flutter 版本重新开发得来

感谢 https://github.com/Kanscape 提供的 UI 布局交互思路，如果你需要体验 iOS 上的原生组件，不妨试试上述第三方客户端
