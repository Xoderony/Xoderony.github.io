param(
    [uri]$ReleaseUri = 'https://www.h6968de49.nyat.app:13628/downloads/releases/expriverse-demo-latest.json',
    [string]$InstallRoot,
    [switch]$NoLaunch,
    [switch]$NoShortcut,
    [switch]$AllowLoopbackHttp
)

# Keep functions and state local even when this script is invoked through irm | iex.
& {
    param($ReleaseUri, $InstallRoot, $NoLaunch, $NoShortcut, $AllowLoopbackHttp)
    $ErrorActionPreference = 'Stop'
    Set-StrictMode -Version Latest

    function Read-Choice {
        param([string]$Prompt)
        do {
            $answer = (Read-Host ($Prompt + ' [Y/N，回车为 N]')).Trim()
        } while ($answer -notmatch '^(?i:y|yes|n|no|是|否)?$')
        return $answer -match '^(?i:y|yes|是)$'
    }

    function Assert-NoDirectoryLinks {
        param([string]$Path)
        $current = [IO.Path]::GetFullPath($Path)
        while (-not [string]::IsNullOrEmpty($current)) {
            if (Test-Path -LiteralPath $current) {
                $item = Get-Item -LiteralPath $current -Force
                if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw ('安装路径包含文件、链接或目录联接，请选择普通本地文件夹：' + $current)
                }
            }
            $current = [IO.Path]::GetDirectoryName($current.TrimEnd('\'))
        }
    }

    function Get-InstallRoot {
        param([string]$Requested)
        $defaultRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Expriverse'
        if ([string]::IsNullOrWhiteSpace($Requested)) {
            $Requested = Read-Host ('安装到哪个父目录？直接回车使用 ' + $defaultRoot)
            if ([string]::IsNullOrWhiteSpace($Requested)) { $Requested = $defaultRoot }
        }
        $Requested = [Environment]::ExpandEnvironmentVariables($Requested.Trim().Trim('"'))
        if ($Requested -notmatch '^[A-Za-z]:[\\/]') { throw '请输入完整的本地目录，例如 D:\游戏\Expriverse。' }
        $full = [IO.Path]::GetFullPath($Requested).TrimEnd('\')
        if ($full -match '^[A-Za-z]:$') { $full += '\' }
        Assert-NoDirectoryLinks $full
        return $full
    }

    function Open-Download {
        param([uri]$Uri)
        $request = [Net.HttpWebRequest]::CreateHttp($Uri)
        $request.AllowAutoRedirect = $false
        $request.Timeout = 30000
        $request.ReadWriteTimeout = 120000
        $request.UserAgent = 'Expriverse-Installer/1'
        $response = $request.GetResponse()
        if ([int]$response.StatusCode -ne 200) {
            $response.Dispose()
            throw '下载地址没有直接返回文件，请稍后重试或联系分享者。'
        }
        return $response
    }

    function Read-Release {
        param([uri]$Uri, [bool]$AllowHttp)
        $trustedHttps = $Uri.Scheme -eq 'https' -and $Uri.Authority -ieq 'www.h6968de49.nyat.app:13628'
        $testHttp = $AllowHttp -and $Uri.Scheme -eq 'http' -and $Uri.IsLoopback
        if ((-not $trustedHttps -and -not $testHttp) -or -not [string]::IsNullOrEmpty($Uri.UserInfo)) {
            throw '版本信息必须来自分享网站的 HTTPS 地址；HTTP 仅供显式启用的本机隔离测试。'
        }
        $response = Open-Download $Uri
        try {
            $reader = [IO.StreamReader]::new($response.GetResponseStream(), [Text.Encoding]::UTF8, $true)
            try { $release = $reader.ReadToEnd() | ConvertFrom-Json }
            finally { $reader.Dispose() }
        }
        finally { $response.Dispose() }
        foreach ($name in @('id', 'title', 'file', 'bytes', 'expandedBytes', 'sha256', 'launcher')) {
            if ($null -eq $release.PSObject.Properties[$name]) { throw ('版本信息缺少字段：' + $name) }
        }
        if ($release.id -notmatch '^expriverse-demo-[a-z0-9-]{1,48}$' -or
            [string]::IsNullOrWhiteSpace($release.title) -or
            $release.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
            [string]$release.bytes -notmatch '^[1-9][0-9]*$' -or
            [string]$release.expandedBytes -notmatch '^[1-9][0-9]*$' -or
            $release.launcher -cne 'Start-Expriverse.cmd') { throw '版本信息格式无效，未开始安装。' }
        [void][long]$release.bytes
        [void][long]$release.expandedBytes
        $archiveUri = [uri]::new($Uri, [string]$release.file)
        if ($archiveUri.Scheme -ne $Uri.Scheme -or $archiveUri.Authority -ine $Uri.Authority -or
            -not [string]::IsNullOrEmpty($archiveUri.UserInfo) -or $archiveUri.AbsolutePath -notmatch '^/downloads/[^/]+\.zip$') {
            throw '安装包必须来自同一分享网站的 downloads 目录。'
        }
        return @{ Metadata = $release; ArchiveUri = $archiveUri }
    }

    function Save-Archive {
        param([uri]$Uri, [string]$Destination, [long]$ExpectedBytes)
        $response = Open-Download $Uri
        try {
            if ($response.ContentLength -ge 0 -and $response.ContentLength -ne $ExpectedBytes) { throw '服务器返回的安装包大小与版本信息不符。' }
            $inputStream = $response.GetResponseStream()
            $outputStream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try {
                $buffer = New-Object byte[] 131072
                [long]$received = 0
                $lastProgress = [DateTime]::MinValue
                while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $received += $read
                    if ($received -gt $ExpectedBytes) { throw '下载内容超过预期大小，已停止。' }
                    $outputStream.Write($buffer, 0, $read)
                    if (([DateTime]::UtcNow - $lastProgress).TotalMilliseconds -ge 250) {
                        Write-Progress -Activity '正在下载 Expriverse' -Status ('{0:N1} / {1:N1} MiB' -f ($received / 1MB), ($ExpectedBytes / 1MB)) -PercentComplete ([int](100 * $received / $ExpectedBytes))
                        $lastProgress = [DateTime]::UtcNow
                    }
                }
                if ($received -ne $ExpectedBytes) { throw '安装包下载不完整，请重试。' }
            }
            finally { $outputStream.Dispose(); $inputStream.Dispose(); Write-Progress -Activity '正在下载 Expriverse' -Completed }
        }
        finally { $response.Dispose() }
    }

    function Expand-SafeArchive {
        param([string]$ArchivePath, [string]$Destination, [long]$ExpectedExpandedBytes)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
        $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
        try {
            $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            [long]$total = 0
            foreach ($entry in $archive.Entries) {
                $name = $entry.FullName.Replace('/', '\')
                if ([string]::IsNullOrEmpty($name) -or [IO.Path]::IsPathRooted($name) -or $name.Contains(':')) { throw '安装包包含无效或绝对路径。' }
                foreach ($part in $name.TrimEnd('\').Split('\')) {
                    if ([string]::IsNullOrEmpty($part) -or $part -in @('.', '..') -or
                        $part.EndsWith('.') -or $part.EndsWith(' ') -or $part.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
                        $part -match '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)') { throw '安装包包含不安全的文件路径。' }
                }
                $target = [IO.Path]::GetFullPath([IO.Path]::Combine($root, $name))
                if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or -not $names.Add($target.TrimEnd('\'))) { throw '安装包包含越界或重复路径。' }
                if ((($entry.ExternalAttributes -shr 16) -band 0xf000) -eq 0xa000 -or ($entry.ExternalAttributes -band 0x400) -ne 0) { throw '安装包不得包含链接或目录联接。' }
                if ($entry.Length -gt ($ExpectedExpandedBytes - $total)) { throw '解压后大小超过版本信息，已停止。' }
                $total += $entry.Length
            }
            if ($total -ne $ExpectedExpandedBytes) { throw '解压后大小与版本信息不符。' }
            # Validate the entire archive before any entry is extracted.
            [IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $Destination)
        }
        finally { $archive.Dispose() }
    }

    function Remove-OwnedWorkDirectory {
        param([string]$Path, [string]$Parent, [string]$Token)
        $expected = [IO.Path]::GetFullPath((Join-Path $Parent ('.expriverse-install-' + $Token)))
        if ($Token -notmatch '^[a-f0-9]{32}$' -or -not [string]::Equals([IO.Path]::GetFullPath($Path), $expected, [StringComparison]::OrdinalIgnoreCase)) { throw '临时目录所有权不匹配，拒绝清理。' }
        if (-not (Test-Path -LiteralPath $Path)) { return }
        Assert-NoDirectoryLinks $Path
        $marker = Join-Path $Path '.expriverse-owner'
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or
            ((Get-Item -LiteralPath $marker -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            [IO.File]::ReadAllText($marker) -cne $Token) { throw '临时目录所有权标记不匹配，拒绝清理。' }
        $pending = [Collections.Generic.Stack[string]]::new()
        $pending.Push($Path)
        while ($pending.Count -gt 0) {
            foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '临时目录包含链接，拒绝清理。' }
                if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            }
        }
        Remove-Item -LiteralPath $expected -Recurse -Force
    }

    function Test-GamePrerequisites {
        $systemDirectory = [Environment]::GetFolderPath('System')
        foreach ($library in @('VCRUNTIME140.dll', 'MSVCP140.dll', 'VCRUNTIME140_1.dll')) {
            if (-not (Test-Path -LiteralPath (Join-Path $systemDirectory $library) -PathType Leaf)) {
                Write-Host '游戏已安装，但还缺少 Microsoft Visual C++ x64 运行库。' -ForegroundColor Yellow
                Write-Host '请先下载并安装微软运行库，然后使用游戏启动器；本次跳过自动启动。'
                Write-Host 'https://aka.ms/vc14/vc_redist.x64.exe'
                return $false
            }
        }
        return $true
    }

    function New-GameShortcut {
        param([string]$Directory, [string]$Version, [string]$DesktopDirectory)
        $shortcutPath = Join-Path $DesktopDirectory 'Expriverse.lnk'
        if (Test-Path -LiteralPath $shortcutPath) { Write-Host ('快捷方式已存在，未覆盖：' + $shortcutPath); return }
        $shell = New-Object -ComObject WScript.Shell
        try {
            $shortcut = $shell.CreateShortcut($shortcutPath)
            try {
                $shortcut.TargetPath = Join-Path $Directory 'Start-Expriverse.cmd'
                $shortcut.WorkingDirectory = $Directory
                $shortcut.Description = 'Expriverse 多人 Demo'
                $shortcut.Save()
            }
            finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
        }
        finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
        Write-Host '已创建桌面快捷方式。'
    }
    function Show-InstalledGame {
        param([string]$Directory, [string]$Version, [bool]$SkipLaunch, [bool]$SkipShortcut)
        $launcher = Join-Path $Directory 'Start-Expriverse.cmd'
        if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw '已有目录缺少 Start-Expriverse.cmd，请换一个安装父目录。' }
        Write-Host ''
        Write-Host ('游戏目录：' + $Directory) -ForegroundColor Green
        Write-Host '文件会保留；以后双击 Start-Expriverse.cmd 即可运行，不需要保持安装终端打开。'
        $prerequisitesReady = Test-GamePrerequisites
        if (-not $SkipShortcut -and (Read-Choice '创建桌面快捷方式？')) {
            try {
                New-GameShortcut $Directory $Version ([Environment]::GetFolderPath('DesktopDirectory'))
            }
            catch { Write-Warning ('游戏已保留，但快捷方式未创建：' + $_.Exception.Message) }
        }
        if ($prerequisitesReady -and -not $SkipLaunch -and (Read-Choice '请先打开 Steam 并登录。现在启动游戏？')) {
            try { Start-Process -FilePath $launcher -WorkingDirectory $Directory | Out-Null }
            catch { Write-Warning ('自动启动失败，请在游戏目录双击启动器：' + $_.Exception.Message) }
        }
    }

    function Assert-SafeTree {
        param([string]$Path)
        Assert-NoDirectoryLinks $Path
        $pending = [Collections.Generic.Stack[string]]::new()
        $pending.Push($Path)
        while ($pending.Count -gt 0) {
            foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '游戏目录包含链接，不能更新。' }
                if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            }
        }
    }

    function Read-InstalledRelease {
        param([string]$Directory)
        if (-not (Test-Path -LiteralPath $Directory)) { return $null }
        Assert-SafeTree $Directory
        $marker = Join-Path $Directory '.expriverse-release.json'
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { throw '目标目录不是新版安装器管理的游戏，拒绝替换。请选择空的安装位置。' }
        $installed = [IO.File]::ReadAllText($marker) | ConvertFrom-Json
        if ($null -eq $installed.PSObject.Properties['installFormat'] -or $installed.installFormat -ne 2 -or
            $null -eq $installed.PSObject.Properties['id'] -or $installed.id -notmatch '^expriverse-demo-[a-z0-9-]{1,48}$') {
            throw '目标目录不是新版安装器管理的游戏，拒绝替换。'
        }
        return $installed
    }

    function Assert-GameStopped {
        param([string]$Directory)
        $executable = Join-Path $Directory 'Expriverse.Windows.exe'
        foreach ($process in Get-Process -Name 'Expriverse.Windows' -ErrorAction SilentlyContinue) {
            if ([string]::IsNullOrEmpty($process.Path)) { throw '无法核实正在运行的游戏位置，请退出游戏后重试。' }
            if ([string]::Equals($process.Path, $executable, [StringComparison]::OrdinalIgnoreCase)) { throw '请先退出此目录中的游戏，再运行更新。' }
        }
        if (Test-Path -LiteralPath $executable -PathType Leaf) {
            try {
                $handle = [IO.File]::Open($executable, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
                $handle.Dispose()
            } catch { throw '游戏文件正在使用，请退出游戏后重试。' }
        }
    }

    function Move-GameDirectory {
        param([string]$Source, [string]$Destination)
        [IO.Directory]::Move($Source, $Destination)
    }

    function Install-Expriverse {
        param([uri]$Uri, [string]$RequestedRoot, [bool]$SkipLaunch, [bool]$SkipShortcut, [bool]$AllowHttp)
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) { throw '请在 64 位 Windows 的 Windows PowerShell 或 PowerShell 中运行。' }
        Write-Host 'Expriverse 安装 / 更新' -ForegroundColor Cyan
        $download = Read-Release $Uri $AllowHttp
        $release = $download.Metadata
        $parent = Get-InstallRoot $RequestedRoot
        $directory = Join-Path $parent 'game'
        $installed = Read-InstalledRelease $directory
        if ($null -ne $installed -and $installed.id -ceq $release.id) {
            Write-Host ('已是最新版本：' + $release.id) -ForegroundColor Green
            Show-InstalledGame $directory $release.id $SkipLaunch $SkipShortcut
            return
        }
        if ($null -ne $installed) { Assert-GameStopped $directory }
        Write-Host ('目标版本：' + $release.id + '；游戏目录：' + $directory)
        Write-Host ('下载 {0:N1} MiB，解压 {1:N1} MiB；更新时还需保留旧版和设置的空间。' -f ([long]$release.bytes / 1MB), ([long]$release.expandedBytes / 1MB))
        Write-Host '更新会替换程序，保留 local、roaming 和 Logs；缓存重新生成。请保持游戏关闭。'
        if (-not (Read-Choice '确认下载并安装？')) { Write-Host '已取消，未修改安装文件。'; return }

        $token = [guid]::NewGuid().ToString('N')
        $work = Join-Path $parent ('.expriverse-install-' + $token)
        $backup = Join-Path $work 'previous'
        $created = $false
        $preserveWork = $false
        $committed = $false
        $lock = $null
        try {
            Assert-NoDirectoryLinks $parent
            [IO.Directory]::CreateDirectory($parent) | Out-Null
            $lockPath = Join-Path $parent '.expriverse-update.lock'
            if ((Test-Path -LiteralPath $lockPath) -and ((Get-Item -LiteralPath $lockPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '更新锁不能是链接。' }
            try { $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
            catch { throw '另一个安装或更新正在使用此目录，请等待它结束。' }
            foreach ($pending in Get-ChildItem -LiteralPath $parent -Directory -Filter '.expriverse-install-*' -Force) {
                if (Test-Path -LiteralPath (Join-Path $pending.FullName 'previous')) { throw ('发现上次中断保留的旧版，请先检查并恢复：' + $pending.FullName) }
            }
            $current = Read-InstalledRelease $directory
            if (($null -eq $installed) -ne ($null -eq $current) -or ($null -ne $current -and $current.id -cne $installed.id)) { throw '安装状态已改变，请重新运行。' }
            if (Test-Path -LiteralPath $work) { throw '临时目录已存在，请重新运行。' }
            [IO.Directory]::CreateDirectory($work) | Out-Null
            $created = $true
            [IO.File]::WriteAllText((Join-Path $work '.expriverse-owner'), $token, [Text.Encoding]::ASCII)
            $archivePath = Join-Path $work 'package.zip'
            Save-Archive $download.ArchiveUri $archivePath ([long]$release.bytes)
            if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ine $release.sha256) { throw 'SHA-256 校验失败，未替换游戏。' }
            $payload = Join-Path $work 'game'
            Expand-SafeArchive $archivePath $payload ([long]$release.expandedBytes)
            foreach ($name in @($release.launcher, 'Expriverse.Windows.exe', 'Update-Expriverse.cmd')) {
                if (-not (Test-Path -LiteralPath (Join-Path $payload $name) -PathType Leaf)) { throw ('安装包缺少：' + $name) }
            }
            foreach ($name in @('local', 'roaming', 'Logs', 'cache')) {
                if (Test-Path -LiteralPath (Join-Path $payload $name)) { throw '安装包不应包含用户状态或缓存。' }
            }
            $release | Add-Member -NotePropertyName installFormat -NotePropertyValue 2 -Force
            [IO.File]::WriteAllText((Join-Path $payload '.expriverse-release.json'), ($release | ConvertTo-Json), [Text.UTF8Encoding]::new($true))
            Assert-NoDirectoryLinks $parent
            if ($null -ne $installed) {
                Assert-SafeTree $directory
                Assert-GameStopped $directory
                Move-GameDirectory $directory $backup
            }
            try {
                if ($null -ne $installed) {
                    foreach ($name in @('local', 'roaming', 'Logs')) {
                        $state = Join-Path $backup $name
                        if (Test-Path -LiteralPath $state) { Copy-Item -LiteralPath $state -Destination (Join-Path $payload $name) -Recurse -Force }
                    }
                }
                Move-GameDirectory $payload $directory
                $committed = $true
            } catch {
                if (Test-Path -LiteralPath $backup) {
                    try { Move-GameDirectory $backup $directory }
                    catch { $preserveWork = $true; throw ('恢复旧版失败，完整旧版保留在 ' + $backup + '。请勿删除此目录。原因：' + $_.Exception.Message) }
                }
                throw
            }
            Write-Host ('安装 / 更新完成：' + $release.id) -ForegroundColor Green
        } finally {
            if (-not $committed -and (Test-Path -LiteralPath $backup)) {
                $preserveWork = $true
                Write-Warning ('更新中断，完整旧版保留在：' + $backup)
            }
            if ($created -and -not $preserveWork) {
                try { Remove-OwnedWorkDirectory $work $parent $token }
                catch { Write-Warning ('临时目录未完全清理：' + $work + '；' + $_.Exception.Message) }
            }
            if ($null -ne $lock) { $lock.Dispose() }
        }
        Show-InstalledGame $directory $release.id $SkipLaunch $SkipShortcut
    }


    $previousTls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $previousTls -bor [Net.SecurityProtocolType]::Tls12
        Install-Expriverse $ReleaseUri $InstallRoot ([bool]$NoLaunch) ([bool]$NoShortcut) ([bool]$AllowLoopbackHttp)
    }
    catch { Write-Host ('安装未完成：' + $_.Exception.Message) -ForegroundColor Red; throw }
    finally { [Net.ServicePointManager]::SecurityProtocol = $previousTls }
} $ReleaseUri $InstallRoot $NoLaunch $NoShortcut $AllowLoopbackHttp
