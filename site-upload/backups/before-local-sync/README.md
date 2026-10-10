# WebShare 使用说明

## 文件位置

- 发布目录：E:\WebShare\site
- 导航首页：site\index.html
- Steam 操作表：site\steam-multiplayer\index.html
- 原始网页：E:\Stride Projects\Expriverse\docs\Steam-Multiplayer-Test-Guide.html

原始网页未修改。发布副本与原件独立，不会自动同步。

## 发布与更新

已上传至 Upma 免费套餐。公网首页：https://vertex-skgu.upma.site/；指南直达：https://vertex-skgu.upma.site/steam-multiplayer/index.html 。
只上传 site 文件夹，或将 site 文件夹内的全部内容压缩后上传；压缩包顶层应直接是 index.html 和 steam-multiplayer 文件夹。不要上传整个 WebShare。
首次发布后保存平台提供的网址，使用手机流量检查首页、操作表、标识输入、命令复制和步骤勾选。
后续在原项目中修改指南后，将原 HTML 重新复制为 site\steam-multiplayer\index.html，在同一个托管项目中更新整个 site，确认原网址仍能访问新版。
新增网页时在 site 中为其创建独立文件夹，保留配套资源的相对位置，然后在导航首页添加链接。

## 当前状态

已准备：导航首页、原网页副本；原网页约 45 KB，未发现外部资源或后端请求。
2026-10-02 已通过本机网络 HTTP 请求验证：HTTPS 首页和指南均返回 200，首页包含正确指南链接，指南包含 37 步内容，不存在路径返回 404。未绕过证书验证。
待验证：真实浏览器显示与交互、手机流量等独立大陆网络访问、更新后网址保持不变。外部网页读取工具无法访问，不据此判断网站故障。
操作表的填写和勾选按原逻辑仅保留在当前页面，刷新会清空；不同访客之间不共享进度。

## 免费额度

2026-10-02 查询的 Upma 免费版：2 个项目，单次上传 10 MB，总存储 100 MB，每月流量 1 GB，并显示平台标识。以发布时控制台为准。
允许以后更换平台和网址；保留本地完整副本，避免依赖平台专有功能。
