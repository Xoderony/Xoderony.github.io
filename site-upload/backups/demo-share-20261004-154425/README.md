# Xoderony：项目、页面与工具

网站名称为 Xoderony；WebShare 保留为程序和部署目录名称。Expriverse 是站内项目名称。

## 启动和停止

双击 `E:\WebShare\start-site.bat`，浏览器访问 http://127.0.0.1:8080/ 。
网站运行期间保留窗口。按 Ctrl+C 停止，然后按任意键关闭窗口。没有安装系统服务或开机自启。
当前电脑已安装所需的 .NET 10；在其他电脑上运行需要 ASP.NET Core Runtime 10。
如端口已被占用，网站会明确报错；不要结束不明进程。可在启动前设置 WEBSHARE_PORT 为其他端口，并同步修改隧道目标。

## 两人共同测试

双方打开同一个公网网站中的 Steam 操作表。六个标识和 37 个勾选项共享；进度和命令根据共享状态自动更新。复制、打印仍分别在各自电脑上完成。
输入暂停约 350 毫秒后提交；勾选立即提交。状态栏显示连接和保存状态，显示待同步时不要关闭页面。
连接断开时表单暂停编辑，阅读和打印仍可用。恢复连接后读取服务端状态；未确认保存的修改不会离线排队重放，请核对并重新填写。初次加载完成前也不可编辑。
不同字段分别更新；同一字段以服务端最后收到并保存的修改为准。这里不是长文档协作编辑器。
所有访问者都能查看和修改共享表单，无账号、口令或房间。不要填写需要保密的数据。

## Sakura Frp 目标

- 客户端在同一台电脑：本地 IP 127.0.0.1，本地端口 8080，本地协议 HTTP。
- 建议 TCP 隧道，远程端口可由平台分配；自动 HTTPS 选择自动或启用。
- 公网首页：https://www.h6968de49.nyat.app:13628/ 。远程端口 13628。已验证 HTTPS 证书，无需忽略证书错误；节点规则以实际节点说明为准。
- 网站使用同域 HTTP API 和 Server-Sent Events（SSE）推送；网页和同步共用一条隧道，无需额外端口。
- 需要在手机流量等独立网络检查可信 HTTPS、双端实时更新及断线恢复。不能仅凭首页能打开认定推送正常。
- 本地只监听回环地址，没有添加防火墙规则；其他局域网设备无法直接用你的局域网 IP 访问这个服务。

官方参考：https://doc.natfrp.com/frpc/auto-https.html

## 目录用途

- `site/`：唯一公开目录。放 HTML、CSS、JavaScript、图片等普通文件，不放日志、备份或链接/目录联接。
- `site/shared/sync.js`：可复用的共享表单脚本。
- `pages.json`：统一的页面清单，包含导航标题、路径、说明、排序及共享字段，不公开原始配置。
- `data/`：每页一份 JSON 状态，首次修改后创建，不公开。备份时先停止网站，再复制此目录。
- `src/`：ASP.NET Core 源代码。
- `app/`：已编译的运行文件。
- `backups/`：本次替换前的静态版本，不公开。
- `tests/`：本地行为检查。集成测试使用 18081 端口和 work 下的独立测试数据，不修改正式数据。

指南原件 `E:\Stride Projects\Expriverse\docs\Steam-Multiplayer-Test-Guide.html` 未修改；发布副本加入了共享字段和脚本。因此以后更新指南时需要保留这些接入标记，不能再直接用原件覆盖。
Upma 上原网站 https://vertex-skgu.upma.site/ 未改动，仍是静态版本。不要将这一版直接上传到 Upma 静态托管，缺少同步后端时表单会保持不可编辑。

## 后续网页如何接入

1. 将新网页及资源放进 `site` 内独立目录。在 `pages.json` 注册页面，首页自动生成导航，不需要另外修改首页链接。纯静态页面只填写 title、path、description、order，省略 fields 即可。
2. 为网页选一个固定 ID，例如 `checklist`，在 HTML 根元素写 `data-sync-page="checklist"`。
3. 为参与共享的输入框、文本区域或单选下拉框添加 `data-sync="字段名"`。勾选框使用布尔类型，文本、数字输入和下拉框使用文本类型。每个字段标识唯一；暂不支持文件、多选列表和富文本协同。
4. 在页面的 fields 中注册共享字段，例如：`"checklist": { "title": "检查表", "path": "/checklist/", "description": "共同记录检查进度", "order": 30, "fields": { "title": "text", "done": "boolean" } }`。path 使用站内目录（以 / 结尾）或 HTML 路径，目标文件必须存在；导航按 order 升序排列，同序按配置顺序。文本最多 1024 字符，长数字按字符串保存。
5. 添加 `<p data-sync-status role="status" aria-live="polite"></p>`，在页面逻辑之后引入 `<script src="/shared/sync.js"></script>`。共享表单初始应带 `disabled`，连接成功后脚本启用。
6. 本地交互可监听标准 input/change 事件，远程状态应用时脚本也会触发这些事件；不要在这些处理器内另行向服务器写回。
7. 修改页面定义或程序后停止并重新启动；只修改 HTML/CSS/JS 则刷新浏览器。

同一页面 ID 始终对应一份状态；无需创建测试房间。完成一次性测试后可停止服务，移除该页面定义、网页文件和对应数据文件，导航随配置更新。增添字段可直接补定义；修改或删除已有字段前应先处理旧数据，服务不会静默丢弃不匹配的数据。此次配置结构升级不改变 data 中的状态格式及页面 ID。

## 配置检查和服务状态

执行 `dotnet app/WebShare.dll --check` 可检查页面路径、字段类型、公开目录链接以及已有共享数据，不监听端口、不写共享数据。失败会返回非零退出码；字段错误包含页面或状态文件及字段名称。指定其他根目录时使用 WEBSHARE_ROOT。

- `/api/health`：返回 ready、页面数和共享页面数，表示服务已启动且配置及已有状态加载成功；不代表公网隧道或后续磁盘写入一定正常。
- `/api/pages`：返回按导航顺序排列的页面 ID、标题、路径、说明和是否共享，可供后续页面复用导航。
- 首页由后端将 `site/index.html` 中的 `<!-- page-navigation -->` 标记替换为导航。保留该标记，直接打开 HTML 文件不会生成导航。
- 静态文件使用 no-cache，浏览器可保存副本，每次使用前向服务器校验，未改动时返回 304；首页及 API 使用 no-store，避免复用共享状态。修改静态文件仍然刷新即可。

## Codex 规则工坊

入口 `/codex-rules/`。2026-10-03 按最新本地内容重置初版为 `2026-10-03-v1`，包含 14 条全局规则和 12 个个人 Skills；移除已删除的 `constraint-guided-coding`，加入 `interactive-discussion` 及其 Python 脚本、HTML 模板。此次按用户要求移除此前快照；旧版浏览器草稿不迁移，也不再提供旧版入口。系统技能及插件缓存不在分享范围内。

- 全局规则逐条勾选、编辑，支持整组选择和恢复原文；Skills 按完整技能选择，正文可编辑，元数据与附带文件完整保留。
- 相对路径引用的跨技能依赖自动包含，缺失技能或文件会阻止导出。依赖正文也可编辑；新增其他形式的外部依赖需在安装时由 Agent 检查。
- 使用 localStorage 按快照版本保存选择与正文，草稿不发送服务器，不调用共享表单 API。存储失败有明确提示；不同来源（例如本机 HTTP 与公网 HTTPS）有各自独立的草稿。
- 复制安装提示词或下载 UTF-8 txt 安装材料，二者包含相同的完整内容，包括访客修改和附带文件，不依赖远程草稿链接。
- 安装提示词要求 Agent 检查目标环境，逐项提出重复、合并、冲突和新增建议，展示逐文件 diff，用户确认后才备份、写入并验证。页面本身不安装规则；提示词不能代替目标 Agent 的实际行为验证。

手动发布新快照：

```powershell
node scripts/publish-codex-rules.mjs 新版本ID
node tests/codex-rules.mjs
```

发布脚本读取 CODEX_HOME（未设置时使用用户目录下的 .codex），也可在版本参数后传入明确的源目录。它只读取 AGENTS.md 和脚本内显式列出的个人 Skills；保留附带的 UTF-8 文本文件，遇到其他格式停止并要求检查。全局规则按二级标题和单行列表项提取，不支持的布局会报错。

脚本仅生成新的 `site/codex-rules/releases/<版本>.json`，拒绝覆盖已存在的版本。人工检查内容和附带文件适合分享后，再把版本加入 `site/codex-rules/catalog.json` 的 versions，并修改 current；随后运行 `node tests/codex-rules.mjs` 验证已发布版本。网页刷新后生效，无需重启；常规发布保留旧快照，已有草稿可通过版本选择器返回旧版。用户明确要求重置初版时，使用新的版本 ID 隔离旧草稿，将清单改为仅含新初版并移除旧快照。单独运行脚本生成未登记的新快照后，应先检查该文件；测试脚本只覆盖 catalog.json 中登记的版本。

首次新增导航需要重启加载 pages.json。后续仅更新快照、样式和页面脚本时不需要重启。

2026-10-02 首版验证：规则导出逻辑检查、网站隔离集成测试通过；真实浏览器验证了编辑、刷新恢复、自动包含依赖、实际剪贴板内容、清空取消与确认，并检查了窄屏无横向溢出。公网页面和版本清单在正常证书验证下返回 200。浏览器下载事件的自动化等待超时，未确认下载落盘；尚未在另一台电脑执行 Agent 安装。

## 重新构建与检查

在 WebShare 目录执行（需要 .NET 10 SDK）：

```powershell
dotnet restore src/WebShare.csproj --configfile NuGet.Config
dotnet publish src/WebShare.csproj -c Release -o app --no-restore
node tests/client.mjs
node tests/integration.mjs
```

更新 app 前先停止运行中的网站。没有第三方 NuGet 包依赖。

集成测试还覆盖自动导航及顺序、纯静态页面、配置错误诊断、健康接口和条件缓存。可设置 WEBSHARE_APP 为待发布 DLL 的绝对路径，在更新 app 前测试；测试完成后删除本次隔离目录。客户端脚本无需真实浏览器即可检查同步行为，浏览器显示和真实跨网络编辑仍需另外验证。

## 已验证与待验证

2026-10-02：发布构建成功，0 警告、0 错误。实际本地 HTTP/SSE 检查通过：首页、指南和脚本接入、43 个字段、双客户端推送、不同字段并发修改、页面隔离、无效提交拒绝、保存失败不污染状态、重启恢复、重连快照及非公开文件不可访问。
同步脚本的模拟表单检查通过：初始禁用、接收更新、输入草稿保护、发送修改、断线禁用和重连恢复。
公网只读检查已通过：可信 HTTPS，首页、操作表和状态接口均返回 200，43 个共享字段可读取；SSE 初始快照及连续两次约 10 秒间隔的心跳正常。未修改正式共享数据。真实浏览器的显示、剪贴板、打印以及不同网络的双端修改同步尚未验证。

## fix3 测试包下载与临时安装

下载页：https://www.h6968de49.nyat.app:13628/downloads/

在 64 位 Windows PowerShell 或 PowerShell 中执行：

```powershell
irm https://www.h6968de49.nyat.app:13628/downloads/test-session.txt | iex
```

1. 先打开 Steam 并登录自己的账号。脚本不需要管理员权限，不改变执行策略、不配置系统服务或自启。
2. 脚本显示下载大小和桌面目标目录，等待输入 Yes 或 No。No 取消，不创建安装文件。
3. Yes 下载 fix3 包，验证文件长度和 SHA-256，解压到桌面独立的 WebShare-Test-expriverse-fix3-随机标识\game 目录，运行根目录 Start-NetworkValidation.cmd。下载的 ZIP 随即删除。
4. 终端保持等待；测试结束先收集需要反馈的日志，然后输入 Delete。
5. Delete 结束本次启动器和它派生的游戏进程，并删除本次测试目录，包括日志。不会按进程名结束其他游戏或预先运行的 Steam。

正常 Delete 流程及可处理的错误会清理安装目录。强制关闭终端、关机、断电、外部程序锁定文件或进程被其他程序重新启动时，不能保证完整清理；清理失败会明确报告剩余目录，不伪报成功。Windows、Steam、杀毒软件或桌面云同步系统自身的缓存、历史记录不属于清理范围。

发布包：site/downloads/SteamValidation-20261002-fix3.zip，107715110 字节（约 102.7 MiB），解压约 301.4 MiB。
SHA-256：9ACFC3DB4A4A707FBBFC2D9C5636E3E8A561F278330DD5548CB5A8344DB42060
原始包：E:\Stride Projects\Expriverse\artifacts\SteamValidation-20261002-fix3.zip，保持不变。

安装器源文件：scripts/test-session.ps1。公开入口：site/downloads/test-session.txt。两者内容相同，使用无 BOM 的 ASCII 文本以兼容 Windows PowerShell 5.1 的网页文本解码；txt 后缀仅用于提供脚本文本，实际由 PowerShell 执行。
版本元数据：site/downloads/releases/steam-validation-20261002-fix3.json。已发布版本的包和校验值不要原地替换；新增版本应使用新文件名和元数据。
安装器支持 Package 参数；复用到新版本时应显式指定对应的版本 ID，保留当前默认 fix3 供既有命令使用。例如：

```powershell
& ([scriptblock]::Create((irm https://www.h6968de49.nyat.app:13628/downloads/test-session.txt))) -Package '新版本ID'
```

版本 ID 只能包含小写字母、数字和短横线。当前安装器面向同类游戏测试包，要求根目录入口为 Start-NetworkValidation.cmd。其他软件的入口或依赖不同，应先适配脚本再发布。
后续更新源脚本后，应同步公开 txt，并测试 Windows PowerShell 5.1；测试脚本为 tests/installer.ps1，使用模拟桌面和无害进程，不安装真实游戏。

2026-10-02 验证：Yes/No、下载校验、与实际启动器同样的 start /wait 进程创建、Delete 后子进程与全部安装文件清理、错误哈希拒绝及清理、ZIP 路径越界拒绝、不属于本次安装的目录拒绝删除均通过。公网脚本与本地验证源一致，PowerShell 5.1 解析及实际 No 分支通过；下载页和版本元数据正常，ZIP Range 请求返回 206 和正确文件头。没有运行真实游戏，也没有验证其 Steam 登录或联机。更新不需要重启网站，共享状态未改动。
