# iOS 打包与极光推送

## GitHub Secrets

在 **Settings → Secrets → Actions** 添加：

| Secret | 说明 |
|--------|------|
| `IOS_P12_BASE64` | `dis_cer.p12` 的 base64 |
| `IOS_P12_PASSWORD` | p12 密码 |
| `IOS_PROFILE_BASE64` | `CharacterApp.mobileprovision` 的 base64 |
| `IOS_KEYCHAIN_PASSWORD` | 任意临时口令，如 `ci-temp-pass` |
| `PGYER_API_KEY` | 蒲公英 API Key（打 IPA 后自动上传，Summary 里出安装链接） |

本机生成 base64（私有 monorepo 脚本，输出到 `%USERPROFILE%\ios-github-secrets\`）：

```powershell
# 在 G:\ai虚拟角色 仓库根目录
.\scripts\prepare_ios_github_secrets.ps1
```

## 打 IPA

1. 配置上述 Secrets
2. **Actions → iOS Build → Run workflow**
3. 勾选 **build_signed_ipa**
4. 下载 Artifact `ios-ipa`

若已配置 `PGYER_API_KEY`，同一 run 的 **Summary** 里会出现蒲公英安装链接；也可在蒲公英后台查看二维码。

`ios/ExportOptions.plist` 已配置 Ad Hoc：`teamID=3B5Z385689`，profile `CharacterApp`。

## 推送（客户端）

- 依赖 `jpush_flutter`；Android 还需 `android/jpush.properties`（见 `jpush.properties.example`）
- 设置 → **主动关怀推送** → **发送测试推送**
- iOS 需在 Apple Developer 为 App ID 开启 **Push Notifications** 并更新描述文件

后端与极光控制台配置见私有仓库 `docs/iOS打包与推送.md`。
