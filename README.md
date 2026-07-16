# CPA Usage Menu Bar

一个轻量的原生 macOS 状态栏应用，用于查看单个 [CPA Usage Keeper](https://github.com/Willxup/cpa-usage-keeper) 实例的用量，无需一直保留浏览器标签页。

## 功能

- 状态栏显示今日 Token、费用、请求数或仅显示图标。
- 原生弹窗显示请求数、Token、费用和成功率。
- 支持今日、最近 24 小时、7 天和 30 天。
- 支持 Keeper 管理密钥和 CPA API Key 两种身份。
- URL、刷新周期、显示指标和开机启动均可配置。
- 密码或 API Key 仅存储在 macOS Keychain。
- Session 失效后自动重新认证一次。
- 保留最后一次成功数据，网络异常时不会清空状态栏。

## 系统要求

- macOS 13 或更高版本。
- Apple Silicon Mac（当前构建脚本在本机生成 `arm64` 应用）。
- 构建需要 Apple Command Line Tools 或 Xcode。

## 构建

```bash
swift test
./scripts/build-app.sh
```

生成的应用位于：

```text
dist/CPA Usage.app
```

可以将它拖到 `/Applications` 后运行。脚本会执行 Release 编译，并在本地进行 ad-hoc 签名。

## 首次配置

1. 启动 `CPA Usage.app`。
2. 点击状态栏图标，选择“开始设置”。
3. 填写 CPA Usage Keeper URL，例如 `http://keeper.local:8318`。
4. 选择认证类型：
   - “Keeper 管理密钥”使用 `/api/v1/auth/login`，对应 Keeper 的 `LOGIN_PASSWORD`，可查看整个实例。
   - “CPA API Key”使用 `/api/v1/auth/api-key-login`，只查看该 Key 的用量。
5. 输入凭据，选择刷新间隔和状态栏显示内容后保存。

修改非认证设置时，可以把凭据输入框留空，继续使用 Keychain 中的当前凭据。

## 安全说明

- 凭据只保存在 macOS Keychain，不写入偏好设置或日志。
- URL、认证类型和显示偏好保存在本地 `UserDefaults`。
- 应用不会记录 Cookie、登录请求体或完整 API 响应。
- 如果使用 `http://`，凭据在网络传输过程中不会被 TLS 加密。仅应在可信局域网中使用 HTTP；条件允许时建议启用 HTTPS。

## 开机启动

设置中的“登录时启动”使用 macOS `SMAppService`。建议先将应用移动到 `/Applications`，再启用该选项。

## 故障排查

- 状态栏出现感叹号：点击图标查看具体错误和最后更新时间。
- 认证失败：确认选择的是 Keeper 管理密钥还是 CPA API Key，这两种凭据使用不同接口。`CPA_MANAGEMENT_KEY` 是 Keeper 访问 CPA 后端时使用的配置，不能用于仪表盘登录。
- 服务不可用：确认当前 Mac 可以访问所配置的局域网 URL。
- 数据格式不兼容：升级应用或检查 CPA Usage Keeper 是否发生了 API 变更。

## 退出

点击状态栏图标，然后点击“退出”。若已启用登录时启动，请先在设置中关闭。
