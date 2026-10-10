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
        $shortcutPath = Join-Path $DesktopDirectory ('Expriverse - ' + $Version + '.lnk')
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

    function Install-Expriverse {
        param([uri]$Uri, [string]$RequestedRoot, [bool]$SkipLaunch, [bool]$SkipShortcut, [bool]$AllowHttp)
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) { throw '请在 64 位 Windows 的 Windows PowerShell 或 PowerShell 中运行。' }
        Write-Host ''
        Write-Host 'Expriverse 多人 Demo 安装' -ForegroundColor Cyan
        Write-Host '正在读取版本信息……'
        $download = Read-Release $Uri $AllowHttp
        $release = $download.Metadata
        Write-Host ('版本：' + $release.title + ' (' + $release.id + ')')
        Write-Host ('下载 {0:N1} MiB，游戏文件 {1:N1} MiB；安装期间需同时容纳压缩包和游戏文件。' -f ([long]$release.bytes / 1MB), ([long]$release.expandedBytes / 1MB))
        while ($true) {
            $parent = Get-InstallRoot $RequestedRoot
            $directory = Join-Path $parent $release.id
            if (-not (Test-Path -LiteralPath $directory)) { break }
            Assert-NoDirectoryLinks $directory
            Write-Host ('此版本目录已存在，保留原内容：' + $directory) -ForegroundColor Yellow
            if (Read-Choice '使用已安装版本？') { Show-InstalledGame $directory $release.id $SkipLaunch $SkipShortcut; return }
            if (-not (Read-Choice '改选另一个安装父目录？')) { Write-Host '已取消，未修改安装文件。'; return }
            $RequestedRoot = $null
        }
        Write-Host ('将安装到：' + $directory)
        Write-Host '每个版本使用独立目录；不会覆盖旧版本，不需要管理员权限。'
        if (-not (Read-Choice '确认下载并安装？')) { Write-Host '已取消，未创建安装文件。'; return }

        $token = [guid]::NewGuid().ToString('N')
        $work = Join-Path $parent ('.expriverse-install-' + $token)
        $created = $false
        try {
            Assert-NoDirectoryLinks $parent
            if (Test-Path -LiteralPath $directory) { throw '目标版本目录已存在，已停止以免覆盖。' }
            if (Test-Path -LiteralPath $work) { throw '临时目录已存在，请重新运行安装器。' }
            [IO.Directory]::CreateDirectory($work) | Out-Null
            $created = $true
            [IO.File]::WriteAllText((Join-Path $work '.expriverse-owner'), $token, [Text.Encoding]::ASCII)
            $archivePath = Join-Path $work 'package.zip'
            Save-Archive $download.ArchiveUri $archivePath ([long]$release.bytes)
            Write-Host '下载完成，正在校验 SHA-256……'
            if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ine $release.sha256) { throw 'SHA-256 校验失败，安装包未解压、未运行。' }
            Write-Host '校验通过，正在解压……'
            $payload = Join-Path $work 'game'
            Expand-SafeArchive $archivePath $payload ([long]$release.expandedBytes)
            if (-not (Test-Path -LiteralPath (Join-Path $payload $release.launcher) -PathType Leaf)) { throw '安装包缺少启动器，未完成安装。' }
            [IO.File]::WriteAllText((Join-Path $payload '.expriverse-release.json'), ($release | ConvertTo-Json), [Text.UTF8Encoding]::new($true))
            Assert-NoDirectoryLinks $parent
            [IO.Directory]::Move($payload, $directory)
            Write-Host '安装完成。' -ForegroundColor Green
        }
        finally {
            if ($created) {
                try { Remove-OwnedWorkDirectory $work $parent $token }
                catch { Write-Warning ('临时文件未完全清理，请检查 ' + $work + '。' + $_.Exception.Message) }
            }
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
