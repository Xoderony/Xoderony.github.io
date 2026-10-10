# Xoderony：项目、页面与工具

网站名称为 Xoderony；WebShare 保留为程序和部署目录名称。Expriverse 是站内项目名称。

## 启动和停止

双击 `E:\WebShare\start-site.bat`，浏览器访问 http://127.0.0.1:8080/ 。
网站运行期间保留窗口。按 Ctrl+C 停止，然后按任意键关闭窗口。没有安装系统服务或开机自启。
当前电脑已安装所需的 .NET 10；在其他电脑上运行需要 ASP.NET Core Runtime 10。
如端口已被占用，网站会明确报错；不要结束不明进程。可在启动前设置 WEBSHARE_PORT 为其他端口，并同步修改隧道目标。

## 共享表单状态

Steam 双端联调操作表已下线，当前页面均不接入共享同步。共享后端与通用客户端保留，后续页面可按下文接入；原正式数据保留在非公开的 data/ 中，不再加载。

## Sakura Frp 目标

- 客户端在同一台电脑：本地 IP 127.0.0.1，本地端口 8080，本地协议 HTTP。
- 建议 TCP 隧道，远程端口可由平台分配；自动 HTTPS 选择自动或启用。
- 公网首页：https://www.h6968de49.nyat.app:13628/ 。远程端口 13628。已验证 HTTPS 证书，无需忽略证书错误；节点规则以实际节点说明为准。
- 网站使用同域 HTTP API 和 Server-Sent Events（SSE）推送；网页和同步共用一条隧道，无需额外端口。
- 若后续接入共享表单，需要在手机流量等独立网络检查可信 HTTPS、双端实时更新及断线恢复。不能仅凭首页能打开认定推送正常。
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

入口 `/codex-rules/`。当前版 `2026-10-09-v1` 包含 15 条全局规则和 13 个个人 Skills，同步本地全局规则、新增的 `delegated-work`，以及 `interactive-discussion` 和 `modern-csharp-coding-standards` 的更新；不包含 Python 缓存。保留 `2026-10-05-v1`、初版 `2026-10-03-v1` 及其草稿入口。该初版曾按用户要求重置并移除更早快照。系统技能及插件缓存不在分享范围内。规则和技能原文中的本机绝对路径原样保留，安装到其他环境时需检查并按目标环境调整。

- 全局规则逐条勾选、编辑，支持整组选择和恢复原文；Skills 按完整技能选择，正文可编辑，元数据与附带文件完整保留。
- 相对路径引用的跨技能依赖自动包含，缺失技能或文件会阻止导出。依赖正文也可编辑；新增其他形式的外部依赖需在安装时由 Agent 检查。
- 使用 localStorage 按快照版本保存选择与正文，草稿不发送服务器，不调用共享表单 API。存储失败有明确提示；不同来源（例如本机 HTTP 与公网 HTTPS）有各自独立的草稿。
- 复制安装提示词或下载 UTF-8 txt 安装材料，二者包含相同的完整内容，包括访客修改和附带文件，不依赖远程草稿链接。
- 安装提示词要求 Agent 检查目标环境，逐项提出重复、合并、冲突和新增建议，展示逐文件 diff，用户确认后才备份、写入并验证。页面本身不安装规则；提示词不能代替目标 Agent 的实际行为验证。

一键更新：双击根目录 `update-codex-rules.bat`。窗口会保留成功、无变化或失败信息，按任意键关闭；可以从任意工作目录调用。命令行也可运行：

```powershell
node scripts/update-codex-rules.mjs
# 可选：显式指定源目录
node scripts/update-codex-rules.mjs C:\Users\用户名\.codex
```

读取 `CODEX_HOME`（未设置时为用户目录下 `.codex`）的 `AGENTS.md` 和 `scripts/publish-codex-rules.mjs` 内显式登记的个人 Skills。新增个人技能必须先检查是否适合公开，再登记白名单及展示信息；发现未登记目录或缺失白名单项会停止并列出原因，不会自动扩大分享范围。`.system` 和插件缓存不发布。保留技能附带的 UTF-8 文本文件，跳过 `__pycache__`；拒绝链接、目录联接和未支持的文件格式。全局规则按二级标题和单行列表项提取，不支持的布局会报错。技能附带脚本只作为文本导出，不会执行。

脚本先在网站目录之外的项目临时目录生成快照，并运行现有规则导出行为检查。与当前版内容相同则不生成版本；有变化时按本地日期生成 `YYYY-MM-DD-vN`，避开已存在的快照和清单版本，保留全部旧版本。校验成功后以禁止覆盖方式写入快照，最后原子切换 `catalog.json`。准备或校验失败不切换旧版，正常退出会清理本次临时文件及锁。只更新静态文件，刷新网页即可，无需重启；浏览器草稿仍按版本隔离。

并发更新由项目根目录 `.codex-rules-update.lock` 阻止。强制关闭窗口、进程崩溃或断电可能留下锁、临时目录或尚未登记的完整快照：确认没有更新进程后再清理残留锁；不要删除已登记版本。未登记快照会占用版本号，下次更新自动避开。BAT 优先使用 PATH 中的 Node.js，找不到时尝试当前用户 Codex bundled runtime；不会安装依赖或修改系统 PATH。

维护脚本后的定向检查：

```powershell
node tests/codex-rules.mjs
node tests/codex-rules-publish.mjs
```

发布测试使用项目内临时隔离目录和无害文本，完成后清理，不修改正式快照或源技能。覆盖无变化、成功发布、同日版本递增、旧版保留、未知或缺失技能、链接拒绝、校验失败以及并发锁；目录联接检查需要当前环境允许创建测试联接。

如需先人工审阅再发布，仍可运行 `node scripts/publish-codex-rules.mjs 新版本ID [源目录]`，它只生成不可覆盖的新快照，不切换清单。检查内容和附带文件后，将版本加入 `catalog.json` 的 versions 并修改 current，再执行 `node tests/codex-rules.mjs`。不要与一键更新同时修改清单。常规发布保留旧版；只有用户明确要求重置初版时，才改用新的版本 ID 隔离旧草稿并移除旧快照。

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

## 历史验证记录（操作表下线前）

2026-10-02：发布构建成功，0 警告、0 错误。实际本地 HTTP/SSE 检查通过：首页、指南和脚本接入、43 个字段、双客户端推送、不同字段并发修改、页面隔离、无效提交拒绝、保存失败不污染状态、重启恢复、重连快照及非公开文件不可访问。
同步脚本的模拟表单检查通过：初始禁用、接收更新、输入草稿保护、发送修改、断线禁用和重连恢复。
公网只读检查已通过：可信 HTTPS，首页、操作表和状态接口均返回 200，43 个共享字段可读取；SSE 初始快照及连续两次约 10 秒间隔的心跳正常。未修改正式共享数据。真实浏览器的显示、剪贴板、打印以及不同网络的双端修改同步尚未验证。

## 旧版 fix3 联调工具：下载与临时安装

旧版下载页：https://www.h6968de49.nyat.app:13628/downloads/steam-validation.html 。这一流程继续保留，面向原有网络联调工具；当前多人跑酷 Demo 的持久安装见下一节。

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

## 多人跑酷 Demo：中文引导与持久安装

当前下载页：https://www.h6968de49.nyat.app:13628/downloads/ 。新版用于分享完整的 Expriverse 多人跑酷 Demo，安装文件会保留，之后可以直接重复启动。旧版 fix3 包、校验信息和 `test-session.txt` 入口继续保留。

在 64 位 Windows PowerShell 5.1 或 PowerShell 中运行：

```powershell
irm https://www.h6968de49.nyat.app:13628/downloads/install-expriverse.txt | iex
```

也可以在下载页获取 `Install-Expriverse.cmd`，双击进入同一套中文安装引导。

运行前提：Windows 10 / 11 x64、已登录的 Steam，以及 Microsoft Visual C++ x64 Redistributable。Visual C++ 运行库已安装可跳过；未安装时使用[微软官方下载](https://aka.ms/vc14/vc_redist.x64.exe)，安装该运行库可能需要管理员权限。游戏包自带 .NET，无需另装 .NET；Visual C++ 运行库不包含在游戏包内。中文安装器检测到缺少该运行库时会提示补装，并暂不启动游戏。

1. 查看当前发布版本和下载大小，输入希望存放游戏的父目录。安装器在其下创建固定的 game 目录；可使用带空格或中文的路径。
2. 确认安装后，自动下载、校验长度与 SHA-256，再解压游戏。安装结束后可选择创建桌面快捷方式及立即启动。
3. 游戏文件持续保留；以后使用快捷方式或 game 目录内的 `Start-Expriverse.cmd` 启动。安装器不要求管理员权限，不改变系统执行策略，不安装服务或配置自启，游戏包自带 .NET 运行时。
4. 每位玩家分别打开 Steam 并登录自己的账号。在游戏主菜单进入 Demo，一人创建大厅，其他人输入大厅 ID 加入。建议所有参与者安装相同的当前版本。
5. 更新时先退出游戏，双击 game 目录中的 `Update-Expriverse.cmd`，确认后下载并替换程序。不再需要时删除安装目录与自己创建的快捷方式。

下载期间需要网站及公网隧道在线；下载完成后的本地游戏文件不依赖网站。游戏的 Steam 联机仍需要 Steam 客户端和网络。

### 入口、中文编码与发布文件

- `site/downloads/install-expriverse.txt`：短小的 ASCII 引导入口，以 UTF-8 显式解码中文主体，避免 Windows PowerShell 5.1 对网页文本编码的兼容性差异。
- `site/downloads/expriverse-installer.txt`：中文安装器主体。PowerShell 支持中文提示和中文目录；源码、网页响应及读取方式需要采用匹配的编码。
- `site/downloads/Install-Expriverse.cmd.txt`：可下载的双击入口，调用同一安装流程。使用 `.txt` 兼容网站默认静态文件类型；页面的 `download` 属性将下载文件名设为 `Install-Expriverse.cmd`。
- `site/downloads/releases/expriverse-demo-latest.json`：当前 Demo 发布清单，字段为 `id`、`title`、`file`、`bytes`、`expandedBytes`、`sha256`、`launcher`；`file` 相对于清单地址解析，`launcher` 为 `Start-Expriverse.cmd`。
- `site/downloads/index.html`：读取清单展示版本、下载大小、解压大小、校验值及手动 ZIP 下载链接。读取失败时显示错误和重试按钮，不展示过期的硬编码校验值。
- `site/downloads/steam-validation.html`：原 fix3 临时安装页的保留副本，继续使用原包和入口。

每次发布 Demo 使用新的版本 ID、ZIP 名称和固定版本清单；先核对文件长度与 SHA-256，再更新 `expriverse-demo-latest.json`。不要原地覆盖已经分享的版本包。下载页与安装器通过当前清单取得同一版本，客户端仅在玩家运行更新入口并确认后更新；旧版独立版本目录不迁移。

下载导航的标题和说明位于 `pages.json`，首次更新需重启网站使导航生效；后续仅更新静态页面、脚本、版本清单及包文件时刷新即可。本节描述安装与发布约定，实际下载、安装、Steam 登录和跨网络联机结果应按当次验证另行记录。

### 2026-10-04 发布验证

已发布 `expriverse-demo-20261004-01`：下载 107,345,269 字节，解压 311,735,412 字节，共 394 个文件。完整 Release/win-x64 自包含构建及 Stride 资源编译成功；SHA-256 为 `db47a40459caabdfe08008d2aa83d423957be34ecb1367319a8deeda6d161a50`。

`tests/installer-expriverse.ps1` 在 Windows PowerShell 5.1.26100.9444 和 PowerShell 7.6.5 各通过 12 组隔离检查，覆盖中文/空格目录、取消不安装、保留已有版本、下载长度与 SHA-256、ZIP 越界与链接拒绝、临时目录所有权清理、可选启动、模拟桌面上的真实快捷方式及缺少 VC++ 时跳过启动。测试没有启动真实游戏或修改真实桌面。

公网下载页、两个脚本入口、双击入口、版本清单和旧版页面均返回 HTTP 200；ZIP HEAD 长度正确，Range 返回 206 及正确 ZIP 文件头；公网中文脚本与已验证源码哈希一致。Windows PowerShell 5.1 实际执行公网命令的取消分支，中文提示正常且未创建安装文件。页面 HTML/JavaScript 已静态检查，浏览器自动化读取超时，未完成视觉验收。

网站已启动，原有共享数据哈希未变；被替换文件已备份到 `backups/demo-share-20261004-154425/`。本次后台网站进程的日志位于 `work/demo-share/`，未配置开机自启；以后仍可使用根目录 `start-site.bat` 启动。尚未验证真实游戏启动及两台电脑之间的 Steam 联机。

### 2026-10-05 固定目录更新发布

当前版本为 `expriverse-demo-20261005-02`，下载 104,365,520 字节（约 99.5 MiB），解压 310,635,286 字节。ZIP 的 SHA-256 为 `36cd6db012234cc788b7878bcdb3ace60bbd7961b7a5d0ee93f5d02b4b7aea24`。

新版安装固定使用所选父目录下的 `game`，桌面快捷方式为 `Expriverse.lnk`。退出游戏后双击 `Update-Expriverse.cmd`，确认后全量更新。相同版本不下载；不迁移旧版独立版本目录。手动 ZIP 请解压到独立父目录下名为 `game` 的文件夹。设置和日志保留，缓存重新生成。

当前游戏 Release/win-x64 自包含发布及 Stride 内容编译成功。安装器在 Windows PowerShell 5.1 和 PowerShell 7.6.5 各通过 18 组隔离行为检查，覆盖首次安装、取消、同版跳过、下载和 ZIP 校验、更新保留设置与日志、旧文件清理、文件占用、并发更新、拒绝非托管目录、失败回滚及恢复失败保留旧版。使用无害测试包及模拟启动，没有启动真实游戏。

公网 HTTPS 清单、下载页和安装器已核对，公开安装器与源码哈希一致，ZIP HEAD 返回 200 且长度正确，本机健康接口为 ready。未执行真实 Steam 多人联机或浏览器视觉验收。此次未修改共享数据、导航配置或后端，无需重启网站。
