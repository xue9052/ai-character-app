# AI 虚拟角色 · Flutter 客户端

公开仓库，仅含 Android / iOS / Web 客户端。后端 API 在私有仓库维护。

- 私聊 UI：`flutter_ai_ui_kit`
- 角色广场 / 记忆 / 语音通话（ZEGO）
- 默认 API：`https://905299378.xyz`（可在 App 设置页修改）

## 本机开发

```bash
flutter pub get
flutter run
```

Android 侧载包：

```bash
flutter build apk --debug
```

## CI

| Workflow | 触发 | 说明 |
|----------|------|------|
| **Android APK** | push / 手动 | Linux runner，产出 debug apk |
| **iOS Build** | push / 手动 | macOS runner；签名 ipa 需配置 Secrets |

iOS 签名 Secrets：`IOS_P12_BASE64`、`IOS_P12_PASSWORD`、`IOS_PROFILE_BASE64`（可选 `IOS_KEYCHAIN_PASSWORD`）。  
导出配置见 `ios/ExportOptions.plist`（需填 Team ID 与描述文件名称）。

## 后端

本仓库不包含 Python API 服务。联调时在设置页填写你的后端地址，或使用公网默认域名。
