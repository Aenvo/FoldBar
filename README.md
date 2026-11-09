<p align="center">
  <img src="docs/assets/foldbar-icon.png" alt="FoldBar 应用图标：深色背景上的白色向下折角" width="112" height="112">
</p>

<h1 align="center">FoldBar</h1>

<p align="center">给拥挤的 Mac 菜单栏，留一点空间。</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.en.md">English</a>
</p>

FoldBar 是一个原生 macOS 菜单栏收纳工具，面向菜单栏空间不足、尤其是使用刘海屏 Mac 的用户。把暂时不用的图标收进浮动面板，需要时点击菜单栏中的 FoldBar 箭头即可访问。

**v0.2.1 · macOS 14+ · Apple Silicon / Intel · MIT**

[下载 v0.2.1](https://github.com/Aenvo/FoldBar/releases/tag/v0.2.1) · [SHA-256 校验和](https://github.com/Aenvo/FoldBar/releases/download/v0.2.1/SHA256SUMS.txt) · [构建清单](https://github.com/Aenvo/FoldBar/releases/download/v0.2.1/release-manifest.json) · [版本说明](dist/RELEASE_NOTES.md)

> **安装前须知**
>
> - 安装包使用 Apple Development 开发签名，尚未经过 Developer ID 签名、Apple 公证或装订。本机 Gatekeeper 评估未通过；首次打开可能被系统阻止，需要按[首次打开说明](#首次打开被系统阻止时)手动确认。受管理设备可能不允许这样做。
> - 系统要求为 macOS 14+，包含 Apple Silicon 与 Intel 两种架构。当前只完成了 macOS 27.2 本机升级与短时启动检查；干净 Mac、macOS 14–26 和 Intel 的完整安装及交互验收仍待完成。
> - 正常使用需要分别授予**屏幕录制**与**辅助功能**权限。菜单栏截图只保存在内存中；详见[权限与数据](#权限与数据)。

请先确认能够接受上述安装步骤和验证范围，再下载安装。需要自行签名时可从[源码构建](#构建与开发)。

## 主要功能

- **收进面板，按需访问**：五列图标面板保留菜单栏顺序；点击截图代理时重新定位真实图标并转发操作。
- **拖入收纳，拖出常驻**：面板打开时可按住 ⌘ 拖入菜单栏图标；拖到“保持可见”区域可让图标返回菜单栏。
- **保留图标原貌**：使用真实菜单栏图标截图，保持宽高比，文字、电量等宽图标可占多格。
- **中英文即时切换**：跟随系统、简体中文或 English，覆盖设置、菜单、权限说明和旧版系统操作提示。
- **按喜好调整**：浅色、暗色与 Liquid Glass 外观；可选免 ⌘ 直接拖动和登录时启动。
- **减少闲时工作**：macOS 27 收纳列表为空时停止后台扫描；截图失败会逐级延长重试间隔。

## 快速开始

1. 在[发布页](https://github.com/Aenvo/FoldBar/releases/tag/v0.2.1)的 **Assets（附件）** 中下载 `FoldBar-0.2.1-macOS.zip` 和 `SHA256SUMS.txt`。

   打开 Mac 的“终端”，输入 `shasum -a 256` 后按一次空格，把下载的 ZIP 从访达拖进终端窗口，再按回车。打开 `SHA256SUMS.txt`，找到 ZIP 对应的那一行。两处开头的 64 个字符一致即可继续。
2. 在访达中双击 ZIP 解压，将 `FoldBar.app` 拖入“应用程序”，再从“应用程序”双击打开。如果 macOS 拦截，请查看[首次打开说明](#首次打开被系统阻止时)。包内附有中英文 `INSTALL.txt` 和许可证。
3. 根据应用说明，分别授予**屏幕录制**与**辅助功能**权限。首次授予屏幕录制权限后，可能需要重新启动 FoldBar。
4. 点击菜单栏中的 FoldBar 箭头打开面板，按住 ⌘ 将可见菜单栏图标拖入虚线区域。
5. 点击面板中的图标访问对应应用；想让图标常驻菜单栏时，将其拖到“保持可见”区域。

| 操作 | 方法 |
| --- | --- |
| 打开或关闭面板 | 点击 FoldBar 箭头；Escape 或点击面板外也可关闭 |
| 收纳图标 | 打开面板，按住 ⌘ 从菜单栏拖入虚线区域 |
| 保持图标可见 | 将面板图标拖到“保持可见”区域 |
| 设置外观或拖动方式 | 点击面板齿轮，或右键点击 FoldBar 箭头进入“设置” |
| 切换界面语言 | 设置 › 语言；保存后立即生效，无需重启 |
| 登录时启动 | 右键点击 FoldBar 箭头，切换“登录时启动” |

“直接拖动菜单栏图标”默认关闭，启用后可在面板打开期间免按 ⌘ 拖动。macOS 27 首次打开面板时会先刷新菜单栏清单，完成后才能导入图标。

### 首次打开被系统阻止时

1. 确认 ZIP 来自本仓库的发布页，并按[快速开始](#快速开始)核对校验和。然后从“应用程序”尝试打开一次 FoldBar。
2. 如果 macOS 提示无法验证开发者，或无法检查 FoldBar 是否包含恶意软件，先关闭提示。打开“系统设置 → 隐私与安全性”，向下滚动到“安全性”。
3. 如果系统为 FoldBar 提供“仍要打开”按钮，点按该按钮，再在弹窗中选择“打开”。这次确认只针对 FoldBar。
4. FoldBar 打开后，按应用提示分别授予“屏幕录制”和“辅助功能”权限。首次授予屏幕录制权限后，可能需要重启 FoldBar。

如果找不到“仍要打开”，当前版本可能无法在这台 Mac 上启动。公司或学校管理的 Mac 可能限制这项操作。反馈时请附上系统提示原文和 macOS 版本。当前发布包的首次打开流程尚未在全新 Mac 上实测。[Apple 官方操作说明](https://support.apple.com/zh-cn/102445)

### 从旧版升级

如果你已经安装了 FoldBar，请先退出正在运行的旧版，再用解压得到的 `FoldBar.app` 替换“应用程序”中的旧版，然后打开新版。

## 兼容性与限制

macOS 13 及以下不支持。部署目标为 macOS 14.0，最近的 Release 构建包含 `arm64` 和 `x86_64`。当前版本在 macOS 27 上完成了构建与短时运行检查；macOS 14–26 的最新实机交互验收仍待完成。

| 系统 | 收纳方式 | 外观 |
| --- | --- | --- |
| macOS 14–25 | FoldBar 分隔符与经过坐标检查的 ⌘-拖动 | 浅色、暗色；Liquid Glass 回退为浅色 |
| macOS 26 | 沿用分隔符路径 | 浅色、暗色、Liquid Glass |
| macOS 27+ | FoldBar 自己的应用收纳列表与私有可见性断言 | 浅色、暗色、Liquid Glass |

- **macOS 27 按应用收纳**：同一应用的多个菜单栏项会一起收纳或移出，无法单独管理。系统 `«` 独立于 FoldBar，FoldBar 不会点击它或将它作为收纳边界。
- **面板显示截图代理**：第三方真实菜单栏项仍由 macOS 管理，面板不承载其他应用的原生视图。
- **无法确认目标时保留真实图标**：身份、截图或私有服务验证失败时，不隐藏新收纳的应用；正常退出会恢复真实菜单栏项。
- **私有接口有兼容性风险**：macOS 27 路径动态调用 MenuBarClientCore 的 `MBAssessmentModeAssertion`，可能随系统更新失效，不适合 Mac App Store 分发。
- **长期稳定性仍需验证**：系统截图 API 仍有少量泄漏报告，多显示器与真实点击、拖动也需要持续实机验证。

## 权限与数据

| 项目 | 用途 |
| --- | --- |
| 屏幕录制 | 获取单个菜单栏图标窗口或经验证区域的截图，供面板和拖动预览使用；图片保存在内存中 |
| 辅助功能 | 识别菜单栏项、读取原生提示和实时位置，并处理用户发起的点击与拖动 |
| 本地偏好 | 保存界面语言、外观、拖动选项、应用收纳列表及有效的菜单栏位置备份 |

两项权限由 macOS 分别管理。首次引导选择“稍后”后，启动时不再自动提醒；仍可从 FoldBar 右键菜单的“权限设置…”主动请求。完成首次请求后，后续权限操作会引导至系统设置；如果图标截图仍不可用，请检查授权并重新启动 FoldBar。更换构建或签名身份可能导致系统重新请求授权。

FoldBar 自己的界面遵循所选语言；系统权限弹窗仍使用系统语言，第三方图标名称和原生提示保留原文。

## 构建与开发

需要 **Xcode 26+** 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。当前源码引用 macOS 26 SDK 的 Liquid Glass API；验证 macOS 27 路径时使用 **Xcode 27 / macOS 27 SDK**。

```bash
git clone https://github.com/Aenvo/FoldBar.git
cd FoldBar
```

`project.yml` 是工程配置来源。签名默认指向维护者的开发团队；外部贡献者需要先在本地配置中选择自己的可用开发团队，再生成工程。

```bash
xcodegen generate
open FoldBar.xcodeproj
```

在 Xcode 中选择 `FoldBar` scheme 和本机 Mac。命令行测试与 Release 构建可共用一个独立临时 DerivedData 目录：

```bash
foldbar_derived="$(mktemp -d /private/tmp/foldbar-derived.XXXXXX)"

xcodebuild \
  -project FoldBar.xcodeproj \
  -scheme FoldBar \
  -destination 'platform=macOS' \
  -derivedDataPath "$foldbar_derived" \
  test

xcodebuild \
  -project FoldBar.xcodeproj \
  -scheme FoldBar \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$foldbar_derived" \
  build
```

Release 应用位于 `$foldbar_derived/Build/Products/Release/FoldBar.app`。安装前退出旧版本，日常运行只保留一份已安装应用；不要把 Debug 测试宿主作为安装版本使用。验证结束后，先退出测试宿主并取消临时应用的 Launch Services 注册，再移除自己创建的临时目录。

已有的构建与实机观察记录见 [BUILD_REPORT.md](BUILD_REPORT.md)。构建成功和单元测试通过不能替代真实菜单栏上的点击、拖动与权限验收。

## 许可证与致谢

FoldBar 使用 [MIT 许可证](LICENSE)。部分实现改编自 MIT 许可的 [MenubarHide](https://github.com/junior-rj/menubar-hide)，并保留其版权声明。

Hidden Bar 作为分隔符方案的参考；Ice 仅用于了解产品行为与公开问题，未复制其 GPL-3.0 源码。完整来源与许可边界见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
