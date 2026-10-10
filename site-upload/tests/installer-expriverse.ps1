param([string]$InstallerPath = (Join-Path $PSScriptRoot '..\scripts\install-expriverse.ps1'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem, System.IO.Compression

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAILED: ' + $Message) }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern)
    try { & $Action }
    catch { Assert-True ($_.Exception.Message -match $Pattern) ('Unexpected error: ' + $_.Exception.Message); return }
    throw ('FAILED: expected error matching ' + $Pattern)
}

function Read-Host {
    param([string]$Prompt)
    if ($script:answers.Count -eq 0) { throw ('Unexpected prompt: ' + $Prompt) }
    return $script:answers.Dequeue()
}

function Start-Process {
    param([string]$FilePath, [string]$WorkingDirectory)
    $script:launches.Add(@{ FilePath = $FilePath; WorkingDirectory = $WorkingDirectory })
}

function Set-Answers {
    param([string[]]$Values)
    $script:answers = [Collections.Generic.Queue[string]]::new()
    foreach ($value in $Values) { $script:answers.Enqueue($value) }
}

function Write-Fixture {
    param([string]$EntryName = '中文资源/read me.txt', [switch]$WrongHash, [switch]$Link, [string]$Version = 'expriverse-demo-test')
    $zipPath = Join-Path $site 'downloads\fixture.zip'
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath }
    $archive = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    [long]$expanded = 0
    try {
        foreach ($entryData in @(
            @{ Name = 'Start-Expriverse.cmd'; Text = '@echo harmless-test-only' },
            @{ Name = 'Update-Expriverse.cmd'; Text = '@echo harmless-test-only' },
            @{ Name = 'Expriverse.Windows.exe'; Text = 'not executable - test only' },
            @{ Name = $EntryName; Text = '无害测试文件 Chinese path & spaces' }
        )) {
            $entry = $archive.CreateEntry($entryData.Name)
            if ($Link -and $entryData.Name -eq $EntryName) { $entry.ExternalAttributes = -1577123840 }
            $stream = $entry.Open()
            try {
                $bytes = [Text.Encoding]::UTF8.GetBytes($entryData.Text)
                $stream.Write($bytes, 0, $bytes.Length)
                $expanded += $bytes.Length
            }
            finally { $stream.Dispose() }
        }
    }
    finally { $archive.Dispose() }
    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    if ($WrongHash) { $hash = '0' * 64 }
    $metadata = @{
        id = $Version; title = '中文测试版本'; file = '../fixture.zip'
        bytes = (Get-Item -LiteralPath $zipPath).Length; expandedBytes = $expanded
        sha256 = $hash; launcher = 'Start-Expriverse.cmd'
    }
    [IO.File]::WriteAllText((Join-Path $site 'downloads\releases\latest.json'), ($metadata | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    return $metadata
}

$installer = [IO.Path]::GetFullPath($InstallerPath)
$sourceBytes = [IO.File]::ReadAllBytes($installer)
Assert-True ($sourceBytes[0] -eq 0xef -and $sourceBytes[1] -eq 0xbb -and $sourceBytes[2] -eq 0xbf) 'Source must have UTF-8 BOM.'
$publicPath = [IO.Path]::GetFullPath((Join-Path (Split-Path $installer -Parent) '..\site\downloads\expriverse-installer.txt'))
Assert-True ((Get-FileHash -LiteralPath $installer).Hash -eq (Get-FileHash -LiteralPath $publicPath).Hash) 'Public Chinese installer must match source.'
$bootstrapPath = Join-Path (Split-Path $publicPath -Parent) 'install-expriverse.txt'
Assert-True (@([IO.File]::ReadAllBytes($bootstrapPath) | Where-Object { $_ -gt 127 }).Count -eq 0) 'Bootstrap must be ASCII.'
$source = [IO.File]::ReadAllText($installer)
Assert-True ($source.Contains('确认下载并安装？') -and -not $source.Contains([char]0xfffd)) 'Chinese text decoded correctly.'
$parseErrors = $null
$parseTokens = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$parseTokens, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'PowerShell parser must accept installer.'
$functionText = ($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`n"
. ([scriptblock]::Create($functionText))
$runInstaller = [scriptblock]::Create($source)
$script:launches = [Collections.Generic.List[object]]::new()
$token = [guid]::NewGuid().ToString('N')
$testRoot = Join-Path $PSScriptRoot ('work-' + $token)
$site = Join-Path $testRoot 'site'
[IO.Directory]::CreateDirectory((Join-Path $site 'downloads\releases')) | Out-Null
$server = $null

try {
    if (-not ('ExpriverseInstallerFixtureServer' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
public sealed class ExpriverseInstallerFixtureServer : IDisposable
{
    private readonly string root;
    private readonly TcpListener listener;
    private readonly Thread thread;
    private volatile bool stopped;
    public int Port { get; private set; }
    public ExpriverseInstallerFixtureServer(string path)
    {
        root = Path.GetFullPath(path) + Path.DirectorySeparatorChar;
        listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        Port = ((IPEndPoint)listener.LocalEndpoint).Port;
        thread = new Thread(Serve);
        thread.IsBackground = true;
        thread.Start();
    }
    private void Serve()
    {
        while (!stopped)
        {
            try
            {
                using (var client = listener.AcceptTcpClient())
                using (var stream = client.GetStream())
                using (var reader = new StreamReader(stream, Encoding.ASCII, false, 1024, true))
                {
                    string first = reader.ReadLine();
                    while (!String.IsNullOrEmpty(reader.ReadLine())) { }
                    var relative = Uri.UnescapeDataString(first.Split(' ')[1].Split('?')[0]).TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
                    var path = Path.GetFullPath(Path.Combine(root, relative));
                    bool exists = path.StartsWith(root, StringComparison.OrdinalIgnoreCase) && File.Exists(path);
                    byte[] body = exists ? File.ReadAllBytes(path) : Encoding.UTF8.GetBytes("missing");
                    string status = exists ? "200 OK" : "404 Not Found";
                    var header = Encoding.ASCII.GetBytes("HTTP/1.1 " + status + "\r\nContent-Length: " + body.Length + "\r\nContent-Type: application/octet-stream\r\nConnection: close\r\n\r\n");
                    stream.Write(header, 0, header.Length);
                    stream.Write(body, 0, body.Length);
                    stream.Flush();
                }
            }
            catch (SocketException) { if (!stopped) throw; }
        }
    }
    public void Dispose()
    {
        stopped = true;
        listener.Stop();
        thread.Join(3000);
    }
}
"@
    }
    $server = [ExpriverseInstallerFixtureServer]::new($site)
    $port = $server.Port
    $uri = [uri]('http://127.0.0.1:' + $port + '/downloads/releases/latest.json')
    $metadata = Write-Fixture

    $cancelRoot = Join-Path $testRoot '取消 不写文件'
    Set-Answers @('')
    & $runInstaller -ReleaseUri $uri -AllowLoopbackHttp -InstallRoot $cancelRoot -NoLaunch -NoShortcut
    Assert-True (-not (Test-Path -LiteralPath $cancelRoot)) 'Cancel must not create parent or installation files.'
    Write-Host 'PASS: cancel creates no files'

    $successRoot = Join-Path $testRoot '中文 游戏 & 空格'
    Set-Answers @($successRoot, '是')
    & $runInstaller -ReleaseUri $uri -AllowLoopbackHttp -NoLaunch -NoShortcut
    $installed = Join-Path $successRoot 'game'
    Assert-True (Test-Path -LiteralPath (Join-Path $installed '中文资源\read me.txt')) 'Real HTTP download and safe ZIP extraction support Chinese/spaces.'
    Assert-True (@(Get-ChildItem -LiteralPath $successRoot -Force).Count -eq 2) 'Download work directory cleaned after commit.'
    Assert-True ($script:answers.Count -eq 0) 'Only intended prompts occurred.'
    Write-Host 'PASS: UTF-8 metadata, actual HTTP, Chinese path, successful persistent install'

    $sentinel = Join-Path $installed 'leave-this.txt'
    [IO.File]::WriteAllText($sentinel, 'unchanged')
    Set-Answers @()
    & $runInstaller -ReleaseUri $uri -AllowLoopbackHttp -InstallRoot $successRoot -NoLaunch -NoShortcut
    Assert-True ([IO.File]::ReadAllText($sentinel) -ceq 'unchanged') 'Existing version must not be overwritten.'
    Write-Host 'PASS: existing version preserved'

    if (Test-GamePrerequisites) {
        Set-Answers @('Y')
        & $runInstaller -ReleaseUri $uri -AllowLoopbackHttp -InstallRoot $successRoot -NoShortcut
        Assert-True ($script:launches.Count -eq 1 -and $script:launches[0].FilePath -ceq (Join-Path $installed 'Start-Expriverse.cmd') -and $script:launches[0].WorkingDirectory -ceq $installed) 'Launch uses explicit path and working directory; mock never executes it.'
        Write-Host 'PASS: optional launch uses literal path and working directory (mock process)'
    }

    $failureRoot = Join-Path $testRoot '失败 保留旁边文件'
    [IO.Directory]::CreateDirectory($failureRoot) | Out-Null
    $neighbor = Join-Path $failureRoot 'unrelated.txt'
    [IO.File]::WriteAllText($neighbor, 'keep')
    [void](Write-Fixture -WrongHash)
    Set-Answers @('Y')
    Assert-Throws { & $runInstaller -ReleaseUri $uri -AllowLoopbackHttp -InstallRoot $failureRoot -NoLaunch -NoShortcut } 'SHA-256'
    Assert-True (@(Get-ChildItem -LiteralPath $failureRoot -Force).Count -eq 2 -and (Test-Path -LiteralPath $neighbor)) 'Wrong hash cleans only own temporary directory.'
    Write-Host 'PASS: wrong SHA-256 rejects and cleans only owned files'

    $sizeMetadata = Write-Fixture
    $sizeMetadata.bytes += 1
    [IO.File]::WriteAllText((Join-Path $site 'downloads\releases\latest.json'), ($sizeMetadata | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Set-Answers @('Y')
    Assert-Throws { & $runInstaller -ReleaseUri $uri -AllowLoopbackHttp -InstallRoot $failureRoot -NoLaunch -NoShortcut } '大小'
    Assert-True (@(Get-ChildItem -LiteralPath $failureRoot -Force).Count -eq 2) 'Wrong download length cleans temporary files.'
    Write-Host 'PASS: incorrect download length rejected'
    [void](Write-Fixture -EntryName '../escape.txt')
    Set-Answers @('Y')
    Assert-Throws { & $runInstaller -ReleaseUri $uri -AllowLoopbackHttp -InstallRoot $failureRoot -NoLaunch -NoShortcut } '不安全|越界'
    Assert-True (@(Get-ChildItem -LiteralPath $failureRoot -Force).Count -eq 2 -and -not (Test-Path -LiteralPath (Join-Path $failureRoot 'escape.txt'))) 'ZIP traversal rejected before extraction.'
    Write-Host 'PASS: ZIP traversal rejects before extraction'

    [void](Write-Fixture -Link)
    Set-Answers @('Y')
    Assert-Throws { & $runInstaller -ReleaseUri $uri -AllowLoopbackHttp -InstallRoot $failureRoot -NoLaunch -NoShortcut } '链接'
    Write-Host 'PASS: ZIP links rejected'

    $ownedToken = [guid]::NewGuid().ToString('N')
    $owned = Join-Path $failureRoot ('.expriverse-install-' + $ownedToken)
    [IO.Directory]::CreateDirectory($owned) | Out-Null
    [IO.File]::WriteAllText((Join-Path $owned '.expriverse-owner'), 'wrong-token')
    Assert-Throws { Remove-OwnedWorkDirectory $owned $failureRoot $ownedToken } '所有权'
    Assert-True (Test-Path -LiteralPath $owned) 'Wrong ownership marker must prevent removal.'
    Assert-Throws { Remove-OwnedWorkDirectory $successRoot $failureRoot $ownedToken } '所有权'
    [IO.File]::WriteAllText((Join-Path $owned '.expriverse-owner'), $ownedToken)
    $junction = Join-Path $owned 'do-not-follow'
    New-Item -ItemType Junction -Path $junction -Target $installed | Out-Null
    Assert-Throws { Remove-OwnedWorkDirectory $owned $failureRoot $ownedToken } '链接'
    Assert-True (Test-Path -LiteralPath $sentinel) 'Refused junction cleanup preserves outside files.'
    [IO.Directory]::Delete($junction)
    Remove-OwnedWorkDirectory $owned $failureRoot $ownedToken
    Assert-True (-not (Test-Path -LiteralPath $owned)) 'Owned ordinary work directory is cleaned.'
    Write-Host 'PASS: ownership, parent boundary and reparse-point cleanup guards'

    Assert-Throws { Read-Release $uri $false } 'HTTPS'
    Assert-Throws { Read-Release ([uri]'https://example.com/downloads/releases/latest.json') $false } 'HTTPS'
    Write-Host 'PASS: non-published origin and implicit HTTP rejected'

    $mockDesktop = Join-Path $testRoot '模拟 桌面'
    [IO.Directory]::CreateDirectory($mockDesktop) | Out-Null
    New-GameShortcut $installed $metadata.id $mockDesktop
    $shortcutPath = Join-Path $mockDesktop 'Expriverse.lnk'
    $shortcutShell = New-Object -ComObject WScript.Shell
    try {
        $shortcut = $shortcutShell.CreateShortcut($shortcutPath)
        try {
            Assert-True ($shortcut.TargetPath -ceq (Join-Path $installed 'Start-Expriverse.cmd') -and $shortcut.WorkingDirectory -ceq $installed) 'Real shortcut preserves Chinese and space paths.'
        }
        finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
    }
    finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcutShell) }
    $shortcutHash = (Get-FileHash -LiteralPath $shortcutPath).Hash
    New-GameShortcut $failureRoot $metadata.id $mockDesktop
    Assert-True ((Get-FileHash -LiteralPath $shortcutPath).Hash -ceq $shortcutHash) 'Existing shortcut not overwritten.'
    Write-Host 'PASS: real shortcut in isolated mock desktop, including no-overwrite'
    # Exercise a full update using real download, extraction, state copy and directory replacement.
    foreach ($name in @('local', 'roaming', 'Logs', 'cache')) {
        [IO.Directory]::CreateDirectory((Join-Path $installed $name)) | Out-Null
        [IO.File]::WriteAllText((Join-Path $installed ($name + '\state.txt')), ('preserve-' + $name))
    }
    [void](Write-Fixture -Version 'expriverse-demo-update-1')
    Set-Answers @('N')
    & $runInstaller -ReleaseUri $uri -AllowLoopbackHttp -InstallRoot $successRoot -NoLaunch -NoShortcut
    Assert-True (Test-Path -LiteralPath $sentinel) 'Cancelled update preserves old files.'
    Set-Answers @('Y')
    & $runInstaller -ReleaseUri $uri -AllowLoopbackHttp -InstallRoot $successRoot -NoLaunch -NoShortcut
    Assert-True (-not (Test-Path -LiteralPath $sentinel)) 'Obsolete files removed by full directory replacement.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $installed 'cache'))) 'Cache removed.'
    foreach ($name in @('local', 'roaming', 'Logs')) {
        Assert-True ([IO.File]::ReadAllText((Join-Path $installed ($name + '\state.txt'))) -ceq ('preserve-' + $name)) 'User state survives update.'
    }
    Assert-True ((Read-InstalledRelease $installed).id -ceq 'expriverse-demo-update-1') 'Installed marker updated.'
    Write-Host 'PASS: update, cancel, stale-file removal, settings/log preservation and cache reset'

    [void](Write-Fixture -Version 'expriverse-demo-update-2' -WrongHash)
    Set-Answers @('Y')
    Assert-Throws { & $runInstaller -ReleaseUri $uri -AllowLoopbackHttp -InstallRoot $successRoot -NoLaunch -NoShortcut } 'SHA-256'
    Assert-True ((Read-InstalledRelease $installed).id -ceq 'expriverse-demo-update-1') 'Bad update preserves working version.'
    Write-Host 'PASS: corrupt update leaves old installation intact'

    [void](Write-Fixture -Version 'expriverse-demo-update-2')
    $lockedExe = [IO.File]::Open((Join-Path $installed 'Expriverse.Windows.exe'), [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        Set-Answers @()
        Assert-Throws { & $runInstaller -ReleaseUri $uri -AllowLoopbackHttp -InstallRoot $successRoot -NoLaunch -NoShortcut } '正在使用'
    } finally { $lockedExe.Dispose() }
    $updateLock = [IO.File]::Open((Join-Path $successRoot '.expriverse-update.lock'), [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        Set-Answers @('Y')
        Assert-Throws { & $runInstaller -ReleaseUri $uri -AllowLoopbackHttp -InstallRoot $successRoot -NoLaunch -NoShortcut } '另一个安装'
    } finally { $updateLock.Dispose() }
    Write-Host 'PASS: locked game and concurrent updater are refused'

    $unknownRoot = Join-Path $testRoot 'unmanaged'
    [IO.Directory]::CreateDirectory((Join-Path $unknownRoot 'game')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $unknownRoot 'game\keep.txt'), 'keep')
    Set-Answers @()
    Assert-Throws { & $runInstaller -ReleaseUri $uri -AllowLoopbackHttp -InstallRoot $unknownRoot -NoLaunch -NoShortcut } '不是新版'
    Assert-True (Test-Path -LiteralPath (Join-Path $unknownRoot 'game\keep.txt')) 'Unmanaged directory unchanged.'
    Write-Host 'PASS: unmanaged installation refused; no legacy migration'

    # Inject a filesystem commit failure into the extracted production functions.
    function Move-GameDirectory {
        param([string]$Source, [string]$Destination)
        if ($Source -match '\.expriverse-install-[a-f0-9]+\\game$') { throw 'simulated commit failure' }
        [IO.Directory]::Move($Source, $Destination)
    }
    Set-Answers @('Y')
    Assert-Throws { Install-Expriverse $uri $successRoot $true $true $true } 'simulated commit failure'
    Assert-True ((Read-InstalledRelease $installed).id -ceq 'expriverse-demo-update-1') 'Commit failure restores old version.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $installed 'local\state.txt')) -ceq 'preserve-local') 'Rollback preserves settings.'
    Write-Host 'PASS: failed replacement restores complete old installation'

    function Move-GameDirectory {
        param([string]$Source, [string]$Destination)
        if ($Source -match '\.expriverse-install-[a-f0-9]+\\(game|previous)$') { throw 'simulated commit and rollback failure' }
        [IO.Directory]::Move($Source, $Destination)
    }
    Set-Answers @('Y')
    Assert-Throws { Install-Expriverse $uri $successRoot $true $true $true } '完整旧版保留'
    $recovery = @(Get-ChildItem -LiteralPath $successRoot -Directory -Filter '.expriverse-install-*')
    Assert-True ($recovery.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $recovery[0].FullName 'previous\local\state.txt'))) 'Failed rollback must never clean old version.'
    Set-Answers @('Y')
    Assert-Throws { & $runInstaller -ReleaseUri $uri -AllowLoopbackHttp -InstallRoot $successRoot -NoLaunch -NoShortcut } '上次中断'
    [IO.Directory]::Move((Join-Path $recovery[0].FullName 'previous'), $installed)
    $recoveryToken = $recovery[0].Name.Substring('.expriverse-install-'.Length)
    Remove-OwnedWorkDirectory $recovery[0].FullName $successRoot $recoveryToken
    Write-Host 'PASS: failed rollback retains old game and blocks unsafe retry'

    function Test-GamePrerequisites { return $false }
    $script:launches.Clear()
    Set-Answers @()
    Show-InstalledGame $installed $metadata.id $false $true
    Assert-True ($script:launches.Count -eq 0) 'Missing CRT prevents auto launch.'
    Write-Host 'PASS: missing runtime prevents automatic launch'
    Write-Host ('ALL PASSED on PowerShell ' + $PSVersionTable.PSVersion)
}
finally {
    if ($null -ne $server) { $server.Dispose() }
    $expectedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('work-' + $token)))
    if ([string]::Equals([IO.Path]::GetFullPath($testRoot), $expectedRoot, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $testRoot)) {
        $links = @(Get-ChildItem -LiteralPath $testRoot -Recurse -Force | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
        if ($links.Count -eq 0) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
        else { Write-Warning ('Test files retained because of links: ' + $testRoot) }
    }
}
