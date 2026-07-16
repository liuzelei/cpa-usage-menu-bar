# CPA Usage Menu Bar

一个轻量的原生 macOS 状态栏应用，用来查看单个 [CPA Usage Keeper](https://github.com/Willxup/cpa-usage-keeper) 实例的用量。无需一直保留浏览器标签页，今日 Token 数可以直接显示在菜单栏中。

## 功能

- 状态栏显示今日 Token、费用、请求数，或仅显示图标。
- 原生弹窗展示请求数、Token、费用和成功率。
- 支持今日、最近 24 小时、7 天和 30 天。
- 支持 Keeper 管理密钥和 CPA API Key 两种认证方式。
- 支持配置 Keeper 地址、刷新周期、状态栏指标和登录时启动。
- 密码或 API Key 仅存储在 macOS Keychain。
- Keeper Session 失效后自动重新认证。
- 网络异常时保留最后一次成功数据。

## 系统要求

- macOS 13 或更高版本。
- Apple Silicon Mac。
- 构建时需要 Apple Command Line Tools 或 Xcode。

安装 Apple Command Line Tools：

```bash
xcode-select --install
```

## 获取源码

```bash
git clone https://github.com/liuzelei/cpa-usage-menu-bar.git
cd cpa-usage-menu-bar
```

## 构建

先编译测试目标：

```bash
swift test
```

再生成 Release 应用：

```bash
./scripts/build-app.sh
```

构建产物位于：

```text
dist/CPA Usage.app
```

构建脚本会：

1. 使用 Swift Package Manager 进行 Release 编译。
2. 组装标准 macOS `.app` 目录。
3. 使用本机 ad-hoc 签名，方便直接运行。

## 安装与启动

将应用复制到 `/Applications`：

```bash
cp -R "dist/CPA Usage.app" /Applications/
open "/Applications/CPA Usage.app"
```

应用是菜单栏程序，正常运行时不会显示在 Dock 中。首次启动会自动打开设置窗口。

如果 macOS 阻止首次运行，可以在 Finder 中右键应用并选择“打开”。

## 配置

### Keeper 服务地址

填写 CPA Usage Keeper 仪表盘的访问地址。

Keeper 官方文档中的默认 HTTP 监听端口是 `8080`，局域网部署示例：

```text
http://192.168.1.10:8080
```

如果部署时修改了 `APP_PORT`、配置了反向代理或使用了子路径，请填写浏览器中实际访问 Keeper 仪表盘的完整根地址。

### 认证方式

应用支持两种身份，二者使用不同的 Keeper 接口：

| 认证方式 | Keeper 登录接口 | 可查看的数据 |
| --- | --- | --- |
| Keeper 管理密钥 | `/api/v1/auth/login` | 整个 Keeper 实例的用量 |
| CPA API Key | `/api/v1/auth/api-key-login` | 该 CPA API Key 自己的用量 |

“Keeper 管理密钥”对应 Keeper 配置中的 `LOGIN_PASSWORD`。

`CPA_MANAGEMENT_KEY` 是 Keeper 服务端访问 CPA 管理接口时使用的配置，不能用来登录 Keeper 仪表盘。

### 其他设置

- 状态栏显示：今日 Token、今日费用、今日请求数或仅图标。
- 刷新间隔：30 秒、60 秒、5 分钟或 15 分钟。
- 登录时启动：使用 macOS `SMAppService`。建议先将应用放入 `/Applications`。

保存设置前，应用会先验证 URL 和凭据。验证失败时不会覆盖原来的有效配置。

## 使用

点击状态栏中的图标或数字打开摘要弹窗：

- 切换今日、24 小时、7 天或 30 天范围。
- 查看请求数、Token、费用和成功率。
- 点击刷新按钮立即更新数据。
- 点击“打开面板”在默认浏览器中打开完整 Keeper 仪表盘。
- 点击“设置…”修改连接或显示选项。
- 点击“退出”关闭应用。

状态栏出现感叹号时，点击它可以查看认证、网络或兼容性错误。发生暂时性网络错误时，应用仍会保留最后一次成功数据和更新时间。

## 安全说明

- Keeper 管理密钥或 CPA API Key 只存储在 macOS Keychain。
- URL、认证类型和显示偏好存储在本地 `UserDefaults`。
- 应用不会记录凭据、Cookie、登录请求体或完整 API 响应。
- 使用 `http://` 时，凭据在网络传输中不受 TLS 加密保护。HTTP 只适合可信局域网，条件允许时建议通过 HTTPS 或可信反向代理访问 Keeper。

## 故障排查

### 无法连接 Keeper

- 确认 Mac 可以在浏览器中打开相同 URL。
- 确认端口正确；Keeper 默认端口是 `8080`，但部署配置可能不同。
- 检查防火墙、VPN、反向代理和局域网路由。

### 认证失败

- 管理员应选择“Keeper 管理密钥”并填写 `LOGIN_PASSWORD`。
- 普通用户应选择“CPA API Key”。
- 不要把 `CPA_MANAGEMENT_KEY` 当成 Keeper 登录密码。

### 状态栏没有数据

- 点击状态栏图标查看具体错误。
- 手动刷新一次。
- 确认所选 CPA API Key 已经产生用量记录。

## 项目结构

```text
Sources/CPAUsageMenuBar/    应用源码
Tests/CPAUsageMenuBarTests/ 测试
Resources/Info.plist        macOS 应用配置
scripts/build-app.sh        Release 打包脚本
```

## License

本项目暂未附加开源许可证。在复用或分发代码前，请先联系仓库所有者。
