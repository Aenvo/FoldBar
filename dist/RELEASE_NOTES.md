# FoldBar v0.2.1

## 简体中文

版本 **0.2.1（build 3）**，目标系统 macOS 14+，包含 Apple Silicon 与 Intel 两种架构。

### 本次修复

- 首次权限引导选择“稍后”后，不再在后续启动时自动提醒。
- 保留从右键菜单“权限设置…”主动申请两项权限的入口。
- 已申请过权限的用户继续进入系统设置；延迟展示前会重新检查授权及用户选择。

### 安装前须知

- 包使用 **Apple Development 开发签名**，尚未经过 Developer ID 签名、Apple 公证或装订。本机 Gatekeeper 评估未通过，首次打开可能被阻止。
- 确认来源可信且校验和一致后，先尝试打开一次，再检查“系统设置 → 隐私与安全性”是否提供“仍要打开”，按系统提示确认。受管理设备可能不允许运行。请遵循 [Apple 的操作说明](https://support.apple.com/en-us/102445)，不要关闭系统整体安全保护。
- 屏幕录制和辅助功能需要分别授权；首次授权后可能需要重启 FoldBar。截图仅保存在内存中。
- 150 项测试、15 个套件和双架构构建通过；干净 Mac、macOS 14–26、Intel、多显示器及完整点击/拖动验收仍待完成。macOS 13 及以下不支持。
- macOS 27 使用私有接口，可能随系统更新变化；同一应用的菜单栏项一起收纳或移出。

下载附件中的 `FoldBar-0.2.1-macOS.zip`、`SHA256SUMS.txt`、`release-manifest.json`。核对摘要、解压并退出旧版，再把 `FoldBar.app` 拖入“应用程序”。详细说明见包内中英双语 `INSTALL.txt` 和仓库 README。

ZIP：**1,992,459 字节**；SHA-256：

```text
f249dd56da66345961187bd53aea7e0a5701b74044e1e5962a04c6b83c251318
```

## English

Version **0.2.1 (build 3)** targets macOS 14+, with Apple Silicon and Intel architectures included.

### Fixes

- Choosing Later in permission onboarding stops automatic reminders on later launches.
- Permission Settings in the right-click menu still lets you initiate the first request for both grants.
- Existing request history continues to route to System Settings. Delayed presentation rechecks current grants and your decision.

### Before you install

- The package is **Apple Development signed**, without Developer ID signing, Apple notarization, or stapling. It did not pass the local Gatekeeper assessment; macOS may block its first launch.
- Only after trusting the source and verifying the checksum, try opening it once, then check System Settings → Privacy & Security for Open Anyway and follow the system prompts. Managed devices may prohibit running it. Follow [Apple's instructions](https://support.apple.com/en-us/102445); do not disable system-wide security protections.
- Grant Screen Recording and Accessibility separately. A restart may be needed after the first grant. Screenshots stay in memory.
- All 150 tests in 15 suites and the universal build passed. Clean-Mac, macOS 14–26, Intel, multi-display and complete click/drag acceptance remain pending. macOS 13 and earlier are unsupported.
- macOS 27 uses private interfaces that may change with system updates; menu extras from one application move together.

Download the attached `FoldBar-0.2.1-macOS.zip`, `SHA256SUMS.txt` and `release-manifest.json`. Verify the digest, extract the archive, quit the old version and drag `FoldBar.app` to Applications. See the bilingual `INSTALL.txt` and repository README for details.

ZIP: **1,992,459 bytes**; SHA-256:

```text
f249dd56da66345961187bd53aea7e0a5701b74044e1e5962a04c6b83c251318
```
