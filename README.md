# FoldBar

一个面向刘海屏 Mac 的轻量菜单栏收纳原型。点击菜单栏里的网格按钮，会像 Windows 的托盘溢出一样弹出 5 列图标面板。

## 当前功能

- 把分隔符左侧的真实菜单栏图标收纳到浮动网格面板。
- 悬浮面板顶部提供“展开”按钮，可直接恢复左侧真实图标并保持菜单栏展开；点击菜单栏里的 FoldBar 图标可再次收起。
- “设置”可在当前兼容材质、暗色模式和高透明 Liquid Glass 之间切换；原生 Liquid Glass 需要 macOS 26，较低系统自动回退到兼容材质。
- 点击面板中的代理图标，临时还原真实图标并把点击转发过去。
- 把面板图标拖到上方的“保持可见”区域，应用会用 macOS 原生的 ⌘-拖动语义把它移回菜单栏可见侧，并在确认真实图标已经移动后再重新折叠。系统拒绝自动拖动时，菜单栏会保持展开以便手动调整。
- 在折叠前预先采集图标并保存在内存中；打开面板不再先闪现横向菜单栏。
- 保留图标原始宽高比；文字、温度和电量等宽图标会自动占 2–3 格。
- 自动保存有效的 `NSStatusItem Preferred Position`，降低 macOS 26 把图标永久停在屏幕外的风险。
- 退出前总会展开分隔符，避免应用退出后仍把其他图标留在屏幕外。
- 可选择登录时启动。

## 为什么收纳时仍需要 ⌘-拖动

macOS 没有公开 API 可以把另一个应用的 `NSStatusItem` 直接放进自定义面板，也没有公开 API 可以改跨应用图标顺序。面板里显示的是实时截图代理，真实图标仍由 macOS 管理。因此：

- 从面板拖回菜单栏可以由本应用模拟一次经过安全边界检查的 ⌘-拖动；
- 从菜单栏收进面板，最可靠的方式仍是展开后由用户按住 ⌘，把真实图标拖过分隔符。

这不是把图标“复制”进面板，而是一个尽量接近 Windows 交互、同时不依赖 Ice 私有 CGS API 的实现。

## 权限

- **屏幕录制**：只截取每个菜单栏小窗口，用于画网格图标；图片仅保存在内存中。
- **辅助功能**：只在你点击代理图标或拖动到“保持可见”区域时发送对应的鼠标事件。

FoldBar 会用一次说明操作请求两项权限。macOS 仍会分别显示两个系统级确认——系统不提供合并隐私授权的 API——但 FoldBar 不会在每次点击时重复触发请求。

首次授予屏幕录制权限后，macOS 要求重新启动应用。Debug 与正式签名之间切换也可能导致系统重新询问权限。

## 构建

要求 macOS 14+、Xcode 16+、XcodeGen。

```bash
cd FoldBar
xcodegen
xcodebuild -project FoldBar.xcodeproj \
  -scheme FoldBar \
  -configuration Debug build
```

测试：

```bash
xcodebuild -project FoldBar.xcodeproj \
  -scheme FoldBar \
  -destination 'platform=macOS' test
```

工程已绑定当前开发团队，普通 Xcode 构建会使用同一 Apple Development 身份，避免因临时签名变化而反复丢失本机权限。公开分发仍需 Developer ID 签名和 Apple 公证。

## 技术与许可证边界

本项目使用公开的 AppKit、CoreGraphics、ScreenCaptureKit、Accessibility 和 ServiceManagement API。

实现参考并改编了 MIT 许可的 [MenubarHide](https://github.com/junior-rj/menubar-hide)，并保留其许可证。只研究了 Ice 的产品思路和公开问题；**没有复制 Ice 的 GPL-3.0 源码**。

详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
