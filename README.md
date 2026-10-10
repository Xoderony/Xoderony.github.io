# Xoderony · 项目、页面与工具

公开网站：https://xoderony.github.io/

这是 GitHub Pages 上的纯静态站点。发布文件直接位于 `main` 根目录，`.nojekyll` 禁用 Jekyll 处理；不需要 .NET、数据库、本机服务器或公网隧道。

## 页面

- `/`：项目与工具导航
- `/codex-rules/`：Codex 规则工坊，可选规则、编辑 Skills、保存当前浏览器草稿、复制或下载完整安装材料
- `/downloads/`：Expriverse 项目介绍与 Windows x64 Demo 下载，当前接入 GitHub Release `demo-v0.1.0`
- `/404.html`：静态错误页

规则工坊的当前快照为 `2026-10-09-v1`，保留两个旧版快照与按版本隔离的草稿。规则及技能是待审阅的分享内容，不是访问网站或安装时的自动授权。附带脚本只作为文本展示与导出，不在本站执行。

## 维护

GitHub Pages 沿用 `main` 分支根目录的发布方式。提交后在仓库 Actions 中检查该提交的 Pages 构建与部署，再验证线上页面。所有运行时资源均同站点提供，不依赖第三方字体或脚本 CDN；不同地区的实际访问情况仍受 GitHub Pages 网络可达性影响。

本地预览可在仓库目录运行 `python -m http.server 8080`，然后访问 `http://localhost:8080/`。规则工坊使用 ES Modules 和 JSON 请求，请勿直接双击 HTML。

新增规则版本时，先审阅内容与附带文件，检查敏感信息和目标环境路径；写入新的 `codex-rules/releases/YYYY-MM-DD-vN.json`，验证后再更新 `catalog.json`。已有快照不要原地改写，以免影响版本对应的草稿。

当前游戏包通过 GitHub Releases 托管：`Expriverse-win-x64.zip`，139,827,035 字节，GitHub 资产元数据中的 SHA-256 为 `a4e963126c7b00f7f8f99b4fee0d00e2908b68941d054123860a20000cacec05`。发布页：https://github.com/Xoderony/Xoderony.github.io/releases/tag/demo-v0.1.0 。

发布新 Demo 时，应先验证实际包的文件名、大小、SHA-256 与下载地址，再更新下载页中的版本信息。网站托管安装脚本与 `downloads/releases/expriverse-demo-latest.json`，游戏 ZIP 托管在 GitHub Releases。安装器支持 Windows PowerShell 5.1（.NET Framework 4.7.2+）与 PowerShell 7；可选安装父目录、SHA-256/长度校验、安全解压、可选桌面快捷方式、可选首次启动，以及同目录更新和失败回滚。游戏和包内脚本不在网站执行。

当前 ZIP 已实测核对大小、SHA-256 与所有条目 CRC：根目录直接包含 `Expriverse.Windows.exe`，共 435 个条目，解压文件共 358,979,548 字节。包内没有启动/更新 CMD，由经过审阅的安装器生成。安装器仅替换带管理标记的 `game` 目录，保留其中 `local`、`roaming`、`Logs`；重要存档仍应自行备份。手动解压目录不会被接管。为避免 Windows CMD 展开路径，实际安装目录名不能含 `%`；交互输入中的 `%LOCALAPPDATA%` 等环境变量会先展开。

发布新版本时，先创建新的不可变版本清单，再更新 latest、安装器允许的 Release 资产路径和页面版本信息，重新运行安全样例测试。不要仅改 latest 指向未经检查的包。安装器只接受本站清单和已限定的 HTTPS GitHub 资产重定向，不需要修改系统执行策略、关闭证书校验、保存令牌或管理员权限。

## 迁移范围

从 `site-import` 的 `site-upload/site/` 提取所需静态页面。主页导航已静态化；未发布服务器 DLL/EXE、源码、共享数据、日志、备份、原始旧安装器及指向缺失 ZIP 的发布清单；随后接回了适配 GitHub Releases 的安装器。

旧博客和导入分支的 Git 历史保留。清理 `main` 的发布内容不会删除其他分支或历史中的文件；不要将密钥、私人数据或不应公开的文件提交到本仓库。
