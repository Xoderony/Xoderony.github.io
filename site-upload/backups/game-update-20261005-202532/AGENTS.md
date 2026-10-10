# WebShare 接手说明

本目录是当前网站的完整项目及部署目录。先阅读 README.md，其中包含启动、公网访问、共享表单接入、构建检查和测试包安装说明。以下状态记录于 2026-10-02；修改前核实实际运行状态。

## 入口与目录

- start-site.bat：启动现有 app/WebShare.dll，默认仅监听 http://127.0.0.1:8080/。停止使用运行窗口中的 Ctrl+C。
- src/：ASP.NET Core .NET 10 源码；app/：发布文件；NuGet.Config：构建配置。
- site/：唯一公开目录；site/index.html：首页模板，由后端替换 page-navigation 标记生成导航；site/steam-multiplayer/index.html：Steam 测试操作表。
- site/shared/sync.js：共享表单客户端；pages.json：页面及字段定义；data/：正式共享数据。
- site/codex-rules/：Codex 规则工坊，使用版本快照和浏览器本地草稿，不接入共享同步。scripts/publish-codex-rules.mjs 显式导出个人规则及技能，发布流程见 README.md；不覆盖旧快照，不自动发布整个 .codex 目录。
- scripts/test-session.ps1：测试包安装器源码；site/downloads/test-session.txt：公开脚本，必须与源码保持一致。
- site/downloads/：下载页、已复制的游戏 ZIP；releases/ 子目录保存版本元数据。
- tests/：客户端、后端和安装器行为检查；backups/：此前修改的备份。

公网入口为 https://www.h6968de49.nyat.app:13628/，依赖这台电脑运行网站及 Sakura Frp 客户端。隧道指向本机 127.0.0.1:8080。Sakura Frp 的安装、账号和隧道配置由外部客户端管理，不包含在本目录。运行环境 .NET、测试工具 Node.js 和游戏所需 Steam 也需外部安装。

## 修改约束

- 保留正式 data/，不要用示例数据或测试输出覆盖；备份正式数据前先停止服务。
- 只公开 site/ 中的文件，不将源码、数据、备份、密钥或目录联接放入其中。
- 现有表单是所有访问者共享一份状态，无账号或房间；pages.json 集中配置 title、path、description、order 和 fields，省略 fields 的页面仅参与导航。新页面接入步骤见 README.md。
- 静态页面修改后刷新浏览器即可；pages.json 或后端修改后需要重启。更新 app/ 前先停止已确认属于本项目的进程，不结束不明进程。
- 安装器先等待 Yes/No，Yes 后下载校验并启动，等待 Delete 后结束本次派生进程并删除本次目录。保持所有权、路径和 ZIP 检查，不按游戏进程名批量结束进程。
- 安装器源码及公开 txt 保持无 BOM ASCII，以兼容 Windows PowerShell 5.1；新增版本使用新包名、元数据及校验值，不原地替换已有版本。现有默认版本为 steam-validation-20261002-fix3。
- 原始指南和 ZIP 来自 E:\Stride Projects\Expriverse，但本目录已经保存所需发布副本，网站运行不依赖原目录。更新指南时保留共享标记、同步脚本和下载导航。
- https://vertex-skgu.upma.site/ 是旧的独立静态站点。本目录的共享功能需要后端，不能直接作为纯静态站点发布。

## 验证与交付

构建与测试命令见 README.md；按改动范围运行必要检查。tests/installer.ps1 使用模拟桌面及无害进程，不应替换成自动确认真实安装。测试不得修改正式共享状态。

`dotnet app/WebShare.dll --check` 只读检查配置和已保存状态；`/api/health` 提供启动就绪状态，`/api/pages` 提供导航元数据。tests/integration.mjs 可通过 WEBSHARE_APP 指定待发布 DLL，使用隔离数据验证后再更新 app。

已有本地行为检查及公网 HTTP/SSE 检查通过。真实浏览器的显示、剪贴板、打印、跨网络双端编辑，以及真实游戏的 Steam 登录与联机尚未验证，不能将它们描述为通过。

本目录是后续维护的权威版本。早期对话导出的 WebShare-upload.zip 和 WebShare-local.zip 不是当前完整版本；迁移时应停止网站后复制当前整个 WebShare 目录，并在目标电脑配置运行环境及隧道。
