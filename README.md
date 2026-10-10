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

发布新 Demo 时，应先验证实际包的文件名、大小、SHA-256 与下载地址，再更新下载页中的版本信息。当前站点提供手动 ZIP 下载，不沿用原本依赖旧隧道的安装器或更新脚本。历史导入中的清单不代表包已经托管，不应直接启用。

## 迁移范围

从 `site-import` 的 `site-upload/site/` 提取所需静态页面。主页导航已静态化；未发布服务器 DLL/EXE、源码、共享数据、日志、备份、旧安装器及指向缺失 ZIP 的发布清单。

旧博客和导入分支的 Git 历史保留。清理 `main` 的发布内容不会删除其他分支或历史中的文件；不要将密钥、私人数据或不应公开的文件提交到本仓库。
