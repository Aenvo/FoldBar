<p align="center">
  <img src="docs/assets/foldbar-icon.png" alt="FoldBar 应用图标：深色背景上的白色向下折角" width="112" height="112">
</p>

<h1 align="center">FoldBar</h1>

<p align="center">给拥挤的 Mac 菜单栏，留一点空间。</p>

<p align="center">
  <a href="README.md">简体中文</a> · <a href="README.en.md">English</a>
</p>

FoldBar 是一个原生 macOS 菜单栏收纳工具，面向菜单栏空间不足、尤其是使用刘海屏 Mac 的用户。把暂时不用的图标收进浮动面板，需要时点击菜单栏中的 FoldBar 箭头即可访问。

**v0.2.0 开发预览 · macOS 14+ · Apple Silicon / Intel · MIT**

[下载 ZIP](dist/FoldBar-0.2.0-macOS.zip) · [SHA-256 校验和](dist/SHA256SUMS.txt) · [构建清单](dist/release-manifest.json) · [版本说明](dist/RELEASE_NOTES.md)

当前构建包使用 Apple Development 签名，未进行 Developer ID 签名、Apple 公证或装订，本机 Gatekeeper 评估未通过。它是供验证使用的开发预览，尚未完成干净 Mac 安装验收；需要自行签名时可从[源码构建](#构建与开发)。

## 主要功能

- **收进面板，按需访问**：五列图标面板保留菜单栏顺序；点击截图代理时重新定位真实图标并转发操作。
- **拖入收纳，拖出常驻**：面板打开时可按住 ⌘ 拖入菜单栏图标；拖到“保持可见”区域可让图标返回菜单栏。
- **保留图标原貌**：使用真实菜单栏图标截图，保持宽高比，文字、电量等宽图标可占多格。
- **中英文即时切换**：跟随系统、简体中文或 English，覆盖设置、菜单、权限说明和旧版系统操作提示。
- **按喜好调整**：浅色、暗色与 Liquid Glass 外观；可选免 ⌘ 直接拖动和登录时启动。
- **减少闲时工作**：macOS 27 收纳列表为空时停止后台扫描；截图失败会逐级延长重试间隔。

## 快速开始

1. 下载 `FoldBar-0.2.0-macOS.zip` 和同一交付中的 `SHA256SUMS.txt`，在下载目录校验：

   ```bash
   shasum -a 256 FoldBar-0.2.0-macOS.zip
   ```

   将结果与 `SHA256SUMS.txt` 中同名文件的摘要比较。
2. 解压，退出旧版 FoldBar，把 `FoldBar.app` 拖入“应用程序”，作为 `/Applications/FoldBar.app` 打开。包内附有中英文 `INSTALL.txt` 与许可证。此开发签名包可能被系统阻止，说明见 Apple 的[安全打开应用指南](https://support.apple.com/en-us/102445)。
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

## 兼容性与限制

部署目标为 macOS 14.0，最近的 Release 构建包含 `arm64` 和 `x86_64`。当前版本在 macOS 27 上完成了构建与短时运行检查；macOS 14–26 的最新实机交互验收仍待完成。

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

两项权限由 macOS 分别管理。完成首次请求后，后续权限操作会引导至系统设置；如果图标截图仍不可用，请检查授权并重新启动 FoldBar。更换构建或签名身份可能导致系统重新请求授权。

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
