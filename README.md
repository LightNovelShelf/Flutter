# 轻书架

轻书架官方 Flutter 客户端。当前面向 Android，代码保持平台无关，便于后续补齐 iOS / macOS / Windows / Linux。

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

联调本地服务端（默认走线上）：

```bash
flutter run --dart-define=API_ORIGIN=http://10.0.2.2:5199
```

开发期可注入刷新令牌免去反复登录：

```bash
flutter run --dart-define=REFRESH_TOKEN=<refresh token>
```

## 检查

```bash
flutter analyze
flutter test
dart run tool/smoke_api.dart <refresh token>   # 数据层打真实服务端的冒烟测试
```
