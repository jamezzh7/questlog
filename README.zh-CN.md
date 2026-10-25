<p align="center"><img src="assets/AppIcon.png" width="112" alt="Questlog 图标"></p>

<h1 align="center">Questlog</h1>

<p align="center"><strong>在 Mac 桌面，安静地看见项目进展。</strong><br>把本地 Markdown 计划，变成随时可看的项目进度。</p>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-13%2B-333333?logo=apple&amp;logoColor=white" alt="macOS 13 及以上"></a>
  <a href="https://developer.apple.com/documentation/appkit"><img src="https://img.shields.io/badge/Swift-AppKit-F05138?logo=swift&amp;logoColor=white" alt="Swift 与 AppKit"></a>
  <a href="https://www.python.org/downloads/macos/"><img src="https://img.shields.io/badge/Python-3.9%2B-3776AB?logo=python&amp;logoColor=white" alt="Python 3.9 及以上"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-5874A3" alt="MIT 许可"></a>
</p>

<p align="center"><a href="README.md">English</a> · <strong>简体中文</strong> · <a href="README.fr.md">Français</a></p>
<p align="center"><a href="#开始使用">开始使用</a> · <a href="#功能">功能</a> · <a href="docs/privacy.md">隐私</a> · <a href="CONTRIBUTING.md">参与贡献</a></p>

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/widget-dark.png"><img src="docs/images/widget.png" width="420" alt="原生小窗显示虚构示例项目 Orbit 的 60% 进度"></picture></p>

Questlog 读取项目里已有的任务文档。平时只占一个 **300 × 120 pt** 的原生小窗，需要时展开详情，查看任务和项目资料。

无需账户、API Key、模型调用或第三方运行包。项目内容留在你的 Mac 上。

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/details-dark.jpg"><img src="docs/images/details.jpg" width="1000" alt="详情窗口按模块展示 Orbit 示例项目的任务及状态"></picture></p>

截图来自当前原生应用，使用虚构的 [Orbit 示例](examples/orbit/tasks.md)。下方预览随浅色或深色外观显示对应截图，不包含个人项目资料。

## 功能

- **菜单栏总览** — 点击 Questlog 图标查看所有已连接项目的进度，进入项目详情，或显示、隐藏小窗。
- **原生轻量小窗**：自由拖动、手动置顶，仅在当前桌面显示；按需展开详情。
- **兼容已有 Markdown**：复选清单、普通章节、阶段、关联模块计划、任务标题及 Task/Status 表格。
- **连接本机项目**：从 Codex、Claude Code 项目元数据发现目录，也支持手动连接。
- **明确的统计口径**：主清单每项只计一次，模块状态与阶段子项独立展示；没有清单时显示“—”。
- **可追溯的任务详情**：搜索、筛选、来源行号、项目文档原文和最近 Git 活动。
- **有依据的工时估算**：填写剩余工时范围及每日投入后，显示工作日区间。
- **按你的偏好显示**：在设置中选择跟随系统、浅色或深色，小窗、菜单栏总览与详情同步切换，重启后保留选择。
- **三种界面语言**：English、简体中文、Français，可跟随系统；项目内容保留原文。
- **按需运行**：小窗轻量检查文件元数据，展开详情才启动本机服务，收起时释放。

<details>
<summary>外观设置与菜单栏总览</summary>

<p align="center"><img src="docs/images/appearance.jpg" width="760" alt="Questlog 设置提供跟随系统、浅色和深色三档外观"></p>
<p align="center"><img src="docs/images/menu-bar.jpg" width="360" alt="原生菜单栏总览显示 Orbit 项目 60% 的进度"></p>

</details>

## 开始使用

### 环境要求

Mac App Store 沙盒版本正在准备首发，已内嵌运行环境，并通过 macOS 系统选择器请求目录只读访问。构建方式见 [Xcode 说明](docs/mac-app-store.md)。下方源码启动方式继续保留；目前还没有已发布的商店下载。

- macOS **13 及以上**。
- 可通过 `python3` 使用的 Python **3.9 及以上**。
- Apple **Command Line Tools**，包括 `swiftc` 和 `codesign`。
- 使用 Git 克隆源码。Node.js 仅用于开发检查，不是运行依赖。

### 构建与安装

目前采用**源码分发**，请在使用 Questlog 的 Mac 上构建。应用记录这台机器的 Python 路径，使用本机 ad hoc 签名；暂未提供可跨机器使用的公证安装包或 Homebrew 包。

```sh
git clone https://github.com/jamezzh7/questlog.git
cd questlog
python3 build_app.py
python3 install_app.py
open /Applications/Questlog.app
```

缺少 Command Line Tools 时，先运行 `xcode-select --install`。也可以安装到用户目录：

```sh
python3 install_app.py --destination ~/Applications/Questlog.app
open ~/Applications/Questlog.app
```

更新时先退出 Questlog，再拉取、构建和安装。安装器保留 `~/Library/Application Support/Questlog/projects.json` 中已有设置。换电脑或 Python 路径变化后需要重新构建。更多说明见[开发指南](docs/development.md)。

### 连接第一个项目

1. 从小窗打开详情，点击 **连接新项目**。
2. 选择 **Codex**、**Claude Code** 或 **手动输入**。
3. 连接含有 Markdown 计划的目录；通过 **选择任务清单** 更换来源。

可以手动连接仓库内的 `examples/orbit` 目录，体验[示例计划](examples/orbit/tasks.md)。普通清单也可以直接使用：

```md
# 我的项目
- [x] A1 搭建项目骨架
- [ ] A2 完成核心功能
- [ ] A3 测试与交付
```

上面的清单显示 **1/3，33%**。总验收和细分任务放在同一文件时，可用 `primaryIds` 指定主任务范围。详见[配置与支持的计划格式](docs/configuration.md)。

## 进度如何计算

主百分比是**已完成主任务数 ÷ 全部主任务数**，每项等权。它反映文档勾选状态，不代表工时或代码完成度。

模块任务保留“进行中”“已交付”“延后”“待验收”等原文状态，不自动勾选父验收。Git 提交只作为活动记录。全部剩余主任务填写工时后才会显示工作日估算，不把外部等待当作可推算的交付日期。

## 本地运行与隐私

Questlog 读取已连接的 Markdown；展开详情时，还会有界读取项目说明及最近 Git 元数据。可选的 Codex / Claude Code 发现功能只读取本机项目目录元数据，不读取聊天正文或调用模型。

应用只写入自己的连接、语言、外观、范围和估算设置，不修改被观察项目或工具注册表。详情服务只绑定 `127.0.0.1`，没有分析上报或远程后端。[隐私说明](docs/privacy.md)介绍具体范围。

## 快捷键

| 快捷键 | 操作 |
| --- | --- |
| `⌘1` | 所有项目进度 |
| `⌘D` | 打开详情 |
| `⌘0` | 返回小窗 |
| `⌘R` | 刷新 |
| `⌘Q` | 退出 |
| `Tab` / `Shift-Tab` | 切换控件焦点 |
| `Escape` | 关闭菜单或弹窗 |

右键小窗可切换项目。关闭详情窗口会返回小窗，小窗关闭按钮会隐藏小窗；Questlog 仍可从菜单栏打开。点击面板的电源按钮或按 `⌘Q` 退出。

## 开发与贡献

原生外壳使用 Swift/AppKit，数据层只用 Python 标准库，按需详情使用 WebKit 和原生 HTML/CSS/JavaScript，无需 npm 构建或安装 Python 包。

```sh
python3 -m unittest discover -s tests -v
node --test tests/*.cjs
node --check public/app.js
node --check public/i18n.js
```

欢迎问题反馈、文档改进、翻译和范围明确的 PR。参阅[贡献指南](CONTRIBUTING.md)、[架构说明](docs/architecture.md)、[开发指南](docs/development.md)及[更新记录](CHANGELOG.md)。安全问题请按 [SECURITY.md](SECURITY.md) 中的方式反馈。

## 许可证

[MIT](LICENSE) © 2026 jamezzh7。Apple 系统符号适用 Apple 的条款，详见[第三方声明](THIRD_PARTY_NOTICES.md)。
