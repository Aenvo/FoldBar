# FoldBar v0.2.0

## 简体中文

FoldBar 0.2.0（build 2）面向 macOS 14.0 及以上，包含 Apple Silicon 与 Intel 两种架构。

- 原生菜单栏收纳面板，支持截图代理点击、拖入收纳与拖出保持可见。
- 简体中文、English 和跟随系统三种语言选项，切换后立即生效。
- 浅色、暗色与 Liquid Glass 外观，支持登录时启动和可选的免 Command 拖动。
- 减少后台菜单栏扫描与失败截图重试；macOS 27 空收纳列表停止后台扫描。

下载 `FoldBar-0.2.0-macOS.zip`、`SHA256SUMS.txt` 与 `release-manifest.json`。核对 ZIP 摘要后解压，退出旧版本，将 `FoldBar.app` 拖入“应用程序”。包内包含中英文安装说明、MIT 许可证和第三方声明；源码 ZIP 不是可运行的应用包。

ZIP：**1,991,023 字节**。SHA-256：

```text
12e0086afbaa32210118bde07bab2f1d3d71f4f447a61dea214cdd23e6121cee
```

### 验证与限制

- 142 项 Swift Testing 测试、14 个套件通过；双架构 Release 构建完成，无 Swift 源码警告。现有 AppIntents 元数据跳过警告仍存在。
- ZIP 完整性、解压后应用的严格签名验证通过。应用使用 **Apple Development 签名**，未经过 Developer ID 签名、公证或装订；本机 Gatekeeper 评估未通过，其他 Mac 的启动行为尚未验收。
- 构建时对工作区与所有可达 Git 历史的 Gitleaks 8.30.1 默认规则扫描均未发现凭据模式；这不是完整安全审计。
- 干净 Mac 安装、macOS 14–26 最新实机交互、多显示器及最终安装包的完整点击/拖动验收仍待完成。本轮构建没有替换本机正在运行的应用。
- macOS 27 使用私有可见性接口，可能随系统更新变化；同一应用的菜单栏项一起收纳或移出，不支持按单个菜单栏项控制，也不适用于 Mac App Store 分发。
- 系统截图 API 仍有少量泄漏报告，长期稳定性仍需验证。屏幕录制和辅助功能需要分别授权。

## English

FoldBar 0.2.0 (build 2) targets macOS 14.0 and later with Apple Silicon and Intel architectures.

- Native menu-bar collection panel with screenshot-proxy clicks, drag-to-collect, and drag-to-keep-visible interactions.
- Simplified Chinese, English, and system-following language choices that apply immediately.
- Light, dark, and Liquid Glass appearances, launch at login, and optional dragging without Command.
- Reduced background inventory scans and failed screenshot retries; an empty collection stops background scanning on macOS 27.

Download `FoldBar-0.2.0-macOS.zip`, `SHA256SUMS.txt`, and `release-manifest.json`. Verify the ZIP digest, extract it, quit the previous version, and drag `FoldBar.app` to Applications. The archive includes bilingual installation instructions, the MIT license, and third-party notices. A source-code ZIP is not a runnable application package.

ZIP: **1,991,023 bytes**. SHA-256:

```text
12e0086afbaa32210118bde07bab2f1d3d71f4f447a61dea214cdd23e6121cee
```

### Validation and limitations

- All 142 Swift Testing tests in 14 suites passed. The universal Release build completed without Swift source warnings; the existing skipped AppIntents metadata warning remains.
- ZIP integrity and strict signature verification after extraction passed. The app is **Apple Development signed**, without Developer ID signing, notarization, or stapling. The local Gatekeeper assessment rejected it; this does not establish that other Macs can open it directly.
- At build time, Gitleaks 8.30.1 default-rule scans of the working directory and all reachable Git history found no credential patterns. This is not a complete security audit.
- Clean-Mac installation, updated macOS 14–26 hands-on acceptance, multiple displays, and a complete click/drag acceptance pass on this final package remain pending. This build did not replace the running installed app.
- The macOS 27 path uses private visibility interfaces that may change with system updates. All menu extras from one application move together; per-extra control is unavailable. This path is unsuitable for Mac App Store distribution.
- Small leak reports remain in the system screenshot API, and long-term stability needs more verification. Screen Recording and Accessibility require separate grants.
