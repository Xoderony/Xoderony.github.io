param(
    [string]$InstallerPath = (Join-Path $PSScriptRoot '..\downloads\expriverse-installer.txt'),
    [switch]$CheckPublicHttps
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitProcess) { throw 'Run this suite in 64-bit Windows PowerShell 5.1 or PowerShell 7.' }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$InstallerPath = [IO.Path]::GetFullPath($InstallerPath)
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($InstallerPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
# Import only function definitions. Never invoke the installer top-level or downloaded code.
$definitions = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)
$script:OriginalFunctions = @{}
foreach ($definition in $definitions) {
    Invoke-Expression $definition.Extent.Text
    $script:OriginalFunctions[$definition.Name] = (Get-Item ('Function:\' + $definition.Name)).ScriptBlock
}
$script:Passed = 0
$script:Failed = [Collections.Generic.List[string]]::new()
$script:SuiteRoot = Join-Path ([IO.Path]::GetTempPath()) ('expriverse-safe-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($script:SuiteRoot) | Out-Null

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Assert-Throws {
    param([scriptblock]$Body, [string]$Message)
    $thrown = $false
    try { & $Body | Out-Null } catch { $thrown = $true }
    Assert-True $thrown $Message
}
function Reset-Functions {
    foreach ($name in $script:OriginalFunctions.Keys) { Set-Item -Path ('Function:\script:' + $name) -Value $script:OriginalFunctions[$name] }
    if (Test-Path Function:\script:Copy-Item) { Remove-Item Function:\script:Copy-Item }
    # Even an accidental opt-in must fail before any game or child process is launched.
    Set-Item Function:\script:Start-Process -Value { throw 'A test attempted to launch a process.' }
}
function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    Reset-Functions
    try { & $Body; $script:Passed++; Write-Host ('PASS: ' + $Name) -ForegroundColor Green }
    catch { $script:Failed.Add($Name + ': ' + $_.Exception.Message); Write-Host ('FAIL: ' + $Name + ': ' + $_.Exception.Message) -ForegroundColor Red }
}
function New-TestPath { param([string]$Label) return (Join-Path $script:SuiteRoot ($Label + '-' + [guid]::NewGuid().ToString('N'))) }
function New-TestZip {
    param([string]$Path, [object[]]$Entries)
    $file = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
    $zip = [IO.Compression.ZipArchive]::new($file, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($spec in $Entries) {
            $entry = $zip.CreateEntry([string]$spec.Name)
            if ($spec.ContainsKey('Attributes')) { $entry.ExternalAttributes = [int]$spec.Attributes }
            $stream = $entry.Open()
            try { $data = [Text.Encoding]::UTF8.GetBytes([string]$spec.Text); $stream.Write($data, 0, $data.Length) }
            finally { $stream.Dispose() }
        }
    } finally { $zip.Dispose(); $file.Dispose() }
}
function New-ReleaseFixture {
    $script:FixtureArchive = New-TestPath 'fixture.zip'
    $content = 'FAKE EXE. NEVER EXECUTE.'
    New-TestZip $script:FixtureArchive @(@{ Name = 'Expriverse.Windows.exe'; Text = $content })
    $script:ActiveRelease = [pscustomobject]@{
        schemaVersion = 2; id = 'expriverse-demo-fixture-v2'; title = 'Safe fixture';
        file = 'https://github.com/Xoderony/Xoderony.github.io/releases/download/demo-v0.1.0/Expriverse-win-x64.zip';
        bytes = (Get-Item -LiteralPath $script:FixtureArchive).Length;
        expandedBytes = [Text.Encoding]::UTF8.GetByteCount($content);
        sha256 = (Get-FileHash -LiteralPath $script:FixtureArchive -Algorithm SHA256).Hash;
        launcher = 'Start-Expriverse.cmd'; layout = 'flat'; executable = 'Expriverse.Windows.exe'
    }
}
function Use-OfflineFixture {
    New-ReleaseFixture
    $script:DownloadCount = 0
    $script:AcceptInstall = $true
    Set-Item Function:\script:Read-Release -Value {
        param([uri]$Uri, [bool]$AllowHttp)
        return @{ Metadata = ($script:ActiveRelease | ConvertTo-Json | ConvertFrom-Json); ArchiveUri = [uri]$script:ActiveRelease.file }
    }
    Set-Item Function:\script:Save-Archive -Value {
        param([uri]$Uri, [string]$Destination, [long]$ExpectedBytes, [bool]$AllowHttp)
        $script:DownloadCount++
        [IO.File]::Copy($script:FixtureArchive, $Destination, $false)
    }
    Set-Item Function:\script:Read-Choice -Value { param([string]$Prompt) return $script:AcceptInstall }
}
function Invoke-FixtureInstall {
    param([string]$Root)
    Install-Expriverse ([uri]'https://xoderony.github.io/downloads/releases/expriverse-demo-latest.json') $Root $true $true $false
}
function New-LegacyInstall {
    param([string]$Root)
    $game = Join-Path $Root 'game'
    [IO.Directory]::CreateDirectory($game) | Out-Null
    [IO.File]::WriteAllText((Join-Path $game 'Expriverse.Windows.exe'), 'OLD FAKE EXE. NEVER EXECUTE.')
    [IO.File]::WriteAllText((Join-Path $game 'Start-Expriverse.cmd'), '@echo old')
    $marker = @{ installFormat = 2; id = 'expriverse-demo-legacy-v1'; sha256 = ('1' * 64); bytes = 1; expandedBytes = 1; launcher = 'Start-Expriverse.cmd' }
    [IO.File]::WriteAllText((Join-Path $game '.expriverse-release.json'), ($marker | ConvertTo-Json))
    foreach ($name in @('local', 'roaming', 'Logs', 'cache')) {
        $state = Join-Path $game $name
        [IO.Directory]::CreateDirectory($state) | Out-Null
        [IO.File]::WriteAllText((Join-Path $state 'sentinel.txt'), ('preserve ' + $name))
    }
    return $game
}
function Use-ManifestMemory {
    Set-Item Function:\script:Open-Download -Value {
        param([uri]$Uri, [string]$Kind, [bool]$AllowHttp)
        $bytes = [Text.Encoding]::UTF8.GetBytes($script:ManifestJson)
        return [pscustomobject]@{ Stream = [IO.MemoryStream]::new($bytes, $false); Response = [IO.MemoryStream]::new(); Client = [IO.MemoryStream]::new(); ContentLength = $bytes.Length }
    }
}

try {
    Test-Case 'All entry points parse; no policy/certificate bypass' {
        $source = [IO.File]::ReadAllText($InstallerPath)
        Assert-True (-not ($source -match 'Set-ExecutionPolicy|SecurityProtocol\s*=|ServerCertificateValidationCallback|ServerCertificateCustomValidationCallback')) 'Unexpected global security change.'
        $bootstrap = Join-Path ([IO.Path]::GetDirectoryName($InstallerPath)) 'install-expriverse.txt'
        $errors = $null; $t = $null
        [void][Management.Automation.Language.Parser]::ParseFile($bootstrap, [ref]$t, [ref]$errors)
        Assert-True ($errors.Count -eq 0) ($errors | Out-String)
        $cmd = [IO.File]::ReadAllText((Join-Path ([IO.Path]::GetDirectoryName($InstallerPath)) 'Install-Expriverse.cmd.txt'))
        $line = @($cmd -split '\r?\n' | Where-Object { $_ -match ' -Command ' })[0]
        $command = $line.Substring($line.IndexOf(' -Command "') + 11).TrimEnd('"')
        [void][Management.Automation.Language.Parser]::ParseInput($command, [ref]$t, [ref]$errors)
        Assert-True ($errors.Count -eq 0) ($errors | Out-String)
        Assert-True ($cmd.Contains('setlocal DisableDelayedExpansion')) 'Delayed expansion must be disabled.'
        Assert-True ($cmd.Contains('"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"')) 'PowerShell must use its system path.'
    }
    Test-Case 'URI allowlist accepts only pinned asset, manifest, and redirect CDN' {
        $manifest = [uri]'https://xoderony.github.io/downloads/releases/expriverse-demo-latest.json'
        $asset = [uri]'https://github.com/Xoderony/Xoderony.github.io/releases/download/demo-v0.1.0/Expriverse-win-x64.zip'
        Assert-DownloadUri $manifest 'Manifest' $false
        Assert-DownloadUri $asset 'Archive' $false
        Assert-DownloadUri ([uri]'https://release-assets.githubusercontent.com/github-production-release-asset/123/asset?sig=x') 'Archive' $false $true
        foreach ($bad in @('http://github.com/Xoderony/Xoderony.github.io/releases/download/demo-v0.1.0/Expriverse-win-x64.zip', 'https://github.com/Other/Repo/releases/download/demo-v0.1.0/Expriverse-win-x64.zip', 'https://github.com.evil.test/Xoderony/Xoderony.github.io/releases/download/demo-v0.1.0/Expriverse-win-x64.zip', 'https://user:pass@github.com/Xoderony/Xoderony.github.io/releases/download/demo-v0.1.0/Expriverse-win-x64.zip', 'https://github.com:444/Xoderony/Xoderony.github.io/releases/download/demo-v0.1.0/Expriverse-win-x64.zip', 'https://release-assets.githubusercontent.com/other-path')) {
            Assert-Throws { Assert-DownloadUri ([uri]$bad) 'Archive' $false $true } ('Accepted bad URI: ' + $bad)
        }
        Assert-Throws { Assert-DownloadUri $manifest 'Manifest' $false $true } 'Manifest redirects must fail.'
        Assert-Throws { Assert-DownloadUri ([uri]'https://release-assets.githubusercontent.com/github-production-release-asset/123/a') 'Archive' $false } 'Initial CDN URI must fail.'
        Assert-Throws { Assert-DownloadUri ([uri]'http://127.0.0.1:9876/a') 'Archive' $false } 'Loopback must be opt-in.'
        Assert-DownloadUri ([uri]'http://127.0.0.1:9876/a') 'Archive' $true
        Assert-Throws { Assert-DownloadUri ([uri]'http://127.0.0.1:9876/a') 'Archive' $true $true } 'Loopback redirects must fail.'
    }
    Test-Case 'Manifest schema and HTTP isolation' {
        New-ReleaseFixture; Use-ManifestMemory
        $script:ManifestJson = $script:ActiveRelease | ConvertTo-Json
        $uri = [uri]'https://xoderony.github.io/downloads/releases/expriverse-demo-latest.json'
        $parsed = Read-Release $uri $false
        Assert-True ($parsed.Metadata.layout -ceq 'flat') 'Valid schema rejected.'
        $script:ActiveRelease.file = 'http://127.0.0.1:9876/package.zip'
        $script:ManifestJson = $script:ActiveRelease | ConvertTo-Json
        Assert-Throws { Read-Release $uri $true } 'HTTPS manifest must never downgrade to HTTP.'
        $script:ActiveRelease.file = 'http://127.0.0.1:9877/package.zip'
        $script:ManifestJson = $script:ActiveRelease | ConvertTo-Json
        Assert-Throws { Read-Release ([uri]'http://127.0.0.1:9876/release.json') $true } 'Loopback origins must match.'
        $script:ManifestJson = 'x' * 65537
        Assert-Throws { Read-Release $uri $false } 'Oversized manifest must fail.'
    }
    Test-Case 'Download stream enforces exact bytes and Content-Length' {
        $script:MemoryBody = [Text.Encoding]::ASCII.GetBytes('abc')
        $script:MemoryLength = $null
        Set-Item Function:\script:Open-Download -Value {
            param([uri]$Uri, [string]$Kind, [bool]$AllowHttp)
            return [pscustomobject]@{ Stream = [IO.MemoryStream]::new($script:MemoryBody, $false); Response = [IO.MemoryStream]::new(); Client = [IO.MemoryStream]::new(); ContentLength = $script:MemoryLength }
        }
        $uri = [uri]'https://github.com/Xoderony/Xoderony.github.io/releases/download/demo-v0.1.0/Expriverse-win-x64.zip'
        $exact = New-TestPath 'exact-download'; Save-Archive $uri $exact 3
        Assert-True ([IO.File]::ReadAllText($exact) -ceq 'abc') 'Exact streamed download failed.'
        $short = New-TestPath 'short-download'
        Assert-Throws { Save-Archive $uri $short 4 } 'Short chunked response was accepted.'
        $long = New-TestPath 'long-download'
        Assert-Throws { Save-Archive $uri $long 2 } 'Oversized chunked response was accepted.'
        $script:MemoryLength = 4
        $mismatch = New-TestPath 'mismatched-length'
        Assert-Throws { Save-Archive $uri $mismatch 3 } 'Mismatched Content-Length was accepted.'
        Assert-True (-not (Test-Path -LiteralPath $mismatch)) 'Content-Length mismatch wrote a destination.'
        $script:MemoryLength = 3
        Save-Archive $uri (New-TestPath 'exact-length-download') 3
    }
    Test-Case 'ZIP traversal, duplicate paths, links, special files, prefix conflicts' {
        $cases = @(
            @(@{ Name = '../escape.txt'; Text = 'x' }),
            @(@{ Name = 'C:/escape.txt'; Text = 'x' }),
            @(@{ Name = 'file:stream'; Text = 'x' }),
            @(@{ Name = 'NUL.txt'; Text = 'x' }),
            @(@{ Name = 'trailing. /a'; Text = 'x' }),
            @(@{ Name = 'file'; Text = 'x' }, @{ Name = 'FILE'; Text = 'y' }),
            @(@{ Name = 'a'; Text = 'x' }, @{ Name = 'a/b'; Text = 'y' }),
            @(@{ Name = 'a/b'; Text = 'x' }, @{ Name = 'a'; Text = 'y' }),
            @(@{ Name = 'directory/'; Text = 'x' }),
            @(@{ Name = 'symlink'; Text = 'x'; Attributes = [int](-1610612736) }),
            @(@{ Name = 'junction'; Text = 'x'; Attributes = 1024 }),
            @(@{ Name = 'fifo'; Text = 'x'; Attributes = 268435456 })
        )
        foreach ($entries in $cases) {
            $zip = New-TestPath 'unsafe.zip'; New-TestZip $zip $entries
            [long]$bytes = 0; foreach ($entry in $entries) { $bytes += [Text.Encoding]::UTF8.GetByteCount($entry.Text) }
            $destination = New-TestPath 'unsafe-out'
            Assert-Throws { Expand-SafeArchive $zip $destination $bytes } 'Unsafe ZIP was accepted.'
            Assert-True (-not (Test-Path -LiteralPath $destination)) 'Unsafe ZIP wrote files before complete preflight.'
        }
    }
    Test-Case 'ZIP actual output is bounded even with forged declared length' {
        $zip = New-TestPath 'underreported.zip'; New-TestZip $zip @(@{ Name = 'a'; Text = ('A' * 8192) })
        $bytes = [IO.File]::ReadAllBytes($zip)
        for ($i = 0; $i -le $bytes.Length - 30; $i++) {
            $signature = [BitConverter]::ToUInt32($bytes, $i)
            if ($signature -eq 0x04034b50) { [BitConverter]::GetBytes([uint32]1).CopyTo($bytes, $i + 22) }
            if ($signature -eq 0x02014b50) { [BitConverter]::GetBytes([uint32]1).CopyTo($bytes, $i + 24) }
        }
        [IO.File]::WriteAllBytes($zip, $bytes)
        Assert-Throws { Expand-SafeArchive $zip (New-TestPath 'forged-out') 1 } 'Actual expansion exceeded trusted size.'
    }
    Test-Case 'New install, Unicode/metacharacter root, cache creation, same-version no-download' {
        Use-OfflineFixture
        $root = New-TestPath "Chinese 中文 O'Brien & %TEMP% ! (demo)"
        Invoke-FixtureInstall $root
        $game = Join-Path $root 'game'; Assert-InstalledFiles $game
        foreach ($name in @('local', 'roaming', 'Logs', 'cache')) { Assert-True (Test-Path -LiteralPath (Join-Path $game $name) -PathType Container) ('Missing state directory: ' + $name) }
        $before = (Get-Item -LiteralPath (Join-Path $game 'Expriverse.Windows.exe')).LastWriteTimeUtc
        Invoke-FixtureInstall $root
        Assert-True ($script:DownloadCount -eq 1) 'Same version downloaded again.'
        Assert-True ((Get-Item -LiteralPath (Join-Path $game 'Expriverse.Windows.exe')).LastWriteTimeUtc -eq $before) 'Same version rewrote the game.'
    }
    Test-Case 'Cancel and unmanaged directory refusal leave user files intact' {
        Use-OfflineFixture; $script:AcceptInstall = $false
        $root = New-TestPath 'cancel'; Invoke-FixtureInstall $root
        Assert-True (-not (Test-Path -LiteralPath $root)) 'Cancel created installation files.'
        $script:AcceptInstall = $true
        $root = New-TestPath 'unmanaged'; $game = Join-Path $root 'game'; [IO.Directory]::CreateDirectory($game) | Out-Null
        [IO.File]::WriteAllText((Join-Path $game 'mine.txt'), 'mine')
        Assert-Throws { Invoke-FixtureInstall $root } 'Unmanaged directory was replaced.'
        Assert-True ([IO.File]::ReadAllText((Join-Path $game 'mine.txt')) -ceq 'mine') 'Unmanaged file changed.'
    }
    Test-Case 'Legacy format-2 upgrade preserves state and recreates cache' {
        Use-OfflineFixture; $root = New-TestPath 'legacy'; $game = New-LegacyInstall $root
        Invoke-FixtureInstall $root
        foreach ($name in @('local', 'roaming', 'Logs')) { Assert-True ([IO.File]::ReadAllText((Join-Path $game ($name + '\sentinel.txt'))) -ceq ('preserve ' + $name)) ('Lost state: ' + $name) }
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $game 'cache\sentinel.txt'))) 'Old cache was retained.'
        Assert-True ((Read-InstalledRelease $game).id -ceq $script:ActiveRelease.id) 'Upgrade marker was not committed.'
        Assert-True (@(Get-ChildItem -LiteralPath $root -Directory -Filter '.expriverse-install-*').Count -eq 0) 'Successful update left work directories.'
    }
    Test-Case 'Same-id changed hash and missing wrapper/exe are refused' {
        Use-OfflineFixture; $root = New-TestPath 'same-id'; Invoke-FixtureInstall $root
        $hash = $script:ActiveRelease.sha256; $script:ActiveRelease.sha256 = '0' * 64
        Assert-Throws { Invoke-FixtureInstall $root } 'Same-id changed hash was ignored.'
        $script:ActiveRelease.sha256 = $hash
        $game = Join-Path $root 'game'; $wrapper = Join-Path $game 'Start-Expriverse.cmd'
        [IO.File]::Delete($wrapper)
        Assert-Throws { Invoke-FixtureInstall $root } 'Missing wrapper was ignored.'
        [IO.File]::WriteAllText($wrapper, '@echo altered wrapper')
        Assert-Throws { Invoke-FixtureInstall $root } 'Altered wrapper was ignored.'
        [IO.File]::WriteAllText($wrapper, (Get-GameWrappers)['Start-Expriverse.cmd'], [Text.Encoding]::ASCII)
        [IO.File]::Delete((Join-Path $game 'Expriverse.Windows.exe'))
        Assert-Throws { Invoke-FixtureInstall $root } 'Missing executable was ignored.'
        Assert-True ($script:DownloadCount -eq 1) 'Refused same-version flow downloaded a package.'
    }
    Test-Case 'Wrong SHA256 cannot replace existing game' {
        Use-OfflineFixture; $root = New-TestPath 'hash'; $game = New-LegacyInstall $root
        $script:ActiveRelease.sha256 = '0' * 64
        Assert-Throws { Invoke-FixtureInstall $root } 'Wrong hash was accepted.'
        Assert-True ([IO.File]::ReadAllText((Join-Path $game 'Expriverse.Windows.exe')).StartsWith('OLD FAKE')) 'Hash failure changed the old game.'
    }
    Test-Case 'Second install cannot acquire target lock' {
        Use-OfflineFixture; $root = New-TestPath 'locked'; [IO.Directory]::CreateDirectory($root) | Out-Null
        $handle = [IO.File]::Open((Join-Path $root '.expriverse-update.lock'), [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try { Assert-Throws { Invoke-FixtureInstall $root } 'Concurrent target lock was bypassed.' }
        finally { $handle.Dispose() }
        Assert-True ($script:DownloadCount -eq 0) 'Locked install downloaded a package.'
    }
    Test-Case 'Failed commit rename restores full old install' {
        Use-OfflineFixture; $root = New-TestPath 'rollback'; $game = New-LegacyInstall $root; $script:MoveCount = 0
        Set-Item Function:\script:Move-GameDirectory -Value { param([string]$Source, [string]$Destination) $script:MoveCount++; if ($script:MoveCount -eq 2) { throw 'Injected rename failure' }; [IO.Directory]::Move($Source, $Destination) }
        Assert-Throws { Invoke-FixtureInstall $root } 'Injected rename failure did not fail.'
        Assert-True ([IO.File]::ReadAllText((Join-Path $game 'Expriverse.Windows.exe')).StartsWith('OLD FAKE')) 'Rollback failed to restore old executable.'
        Assert-True (Test-Path -LiteralPath (Join-Path $game 'local\sentinel.txt')) 'Rollback lost state.'
        Assert-True ($script:MoveCount -eq 3) 'Rollback rename was not attempted.'
    }
    Test-Case 'Failed state copy restores full old install' {
        Use-OfflineFixture; $root = New-TestPath 'copy-failure'; $game = New-LegacyInstall $root
        Set-Item Function:\script:Copy-Item -Value { param($LiteralPath, $Destination, [switch]$Recurse, [switch]$Force) throw 'Injected state copy failure' }
        Assert-Throws { Invoke-FixtureInstall $root } 'Injected state copy failure did not fail.'
        Assert-True ([IO.File]::ReadAllText((Join-Path $game 'local\sentinel.txt')) -ceq 'preserve local') 'Copy failure lost original state.'
        Assert-True ((Read-InstalledRelease $game).id -ceq 'expriverse-demo-legacy-v1') 'Copy failure replaced marker.'
    }
    Test-Case 'Failed rollback preserves backup and blocks later update' {
        Use-OfflineFixture; $root = New-TestPath 'preserve-backup'; [void](New-LegacyInstall $root); $script:MoveCount = 0
        Set-Item Function:\script:Move-GameDirectory -Value { param([string]$Source, [string]$Destination) $script:MoveCount++; if ($script:MoveCount -in @(2, 3)) { throw 'Injected rename and rollback failure' }; [IO.Directory]::Move($Source, $Destination) }
        Assert-Throws { Invoke-FixtureInstall $root } 'Rollback failure did not fail.'
        $pending = @(Get-ChildItem -LiteralPath $root -Directory -Filter '.expriverse-install-*')
        Assert-True ($pending.Count -eq 1) 'Rollback failure discarded its work directory.'
        $backup = Join-Path $pending[0].FullName 'previous'
        Assert-True ([IO.File]::ReadAllText((Join-Path $backup 'Expriverse.Windows.exe')).StartsWith('OLD FAKE')) 'Rollback failure lost old executable.'
        Assert-True (Test-Path -LiteralPath (Join-Path $backup 'roaming\sentinel.txt')) 'Rollback failure lost state.'
        Assert-Throws { Invoke-FixtureInstall $root } 'Pending preserved backup did not block a later install.'
    }
    Test-Case 'Owned cleanup refuses bad token or marker' {
        $root = New-TestPath 'ownership'; [IO.Directory]::CreateDirectory($root) | Out-Null
        $token = [guid]::NewGuid().ToString('N'); $work = Join-Path $root ('.expriverse-install-' + $token)
        [IO.Directory]::CreateDirectory($work) | Out-Null
        [IO.File]::WriteAllText((Join-Path $work '.expriverse-owner'), 'wrong')
        Assert-Throws { Remove-OwnedWorkDirectory $work $root $token } 'Bad ownership marker was ignored.'
        Assert-True (Test-Path -LiteralPath $work) 'Bad ownership cleanup removed a directory.'
    }
    Test-Case 'Directory junctions are refused without touching their target' {
        $root = New-TestPath 'junctions'; [IO.Directory]::CreateDirectory($root) | Out-Null
        $target = Join-Path $root 'user-target'; [IO.Directory]::CreateDirectory($target) | Out-Null
        [IO.File]::WriteAllText((Join-Path $target 'keep.txt'), 'untouched')
        $token = [guid]::NewGuid().ToString('N'); $work = Join-Path $root ('.expriverse-install-' + $token)
        [IO.Directory]::CreateDirectory($work) | Out-Null
        [IO.File]::WriteAllText((Join-Path $work '.expriverse-owner'), $token)
        $junction = Join-Path $work 'linked-state'
        try {
            [void](New-Item -ItemType Junction -Path $junction -Target $target)
            Assert-Throws { Assert-NoDirectoryLinks $junction } 'Junction in install path was accepted.'
            Assert-Throws { Assert-SafeTree $work } 'Junction in managed tree was accepted.'
            Assert-Throws { Remove-OwnedWorkDirectory $work $root $token } 'Owned cleanup followed a junction.'
            Assert-True ([IO.File]::ReadAllText((Join-Path $target 'keep.txt')) -ceq 'untouched') 'Junction target was modified.'
        } finally {
            # Non-recursive .NET removal deletes the junction itself, never its target.
            if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction) }
        }
        Assert-True ([IO.File]::ReadAllText((Join-Path $target 'keep.txt')) -ceq 'untouched') 'Junction removal touched its target.'
    }
    Test-Case 'Updater root survives CMD metacharacters without source interpolation' {
        $root = New-TestPath "中文 O'Brien & %TEMP% ! (update)"; $game = Join-Path $root 'game'; [IO.Directory]::CreateDirectory($game) | Out-Null
        $wrapper = (Get-GameWrappers)['Update-Expriverse.cmd']
        $lines = $wrapper -split '\r?\n'; $original = @($lines | Where-Object { $_ -match ' -Command ' })[0]
        $probe = '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -Command "[IO.File]::WriteAllText($env:EXPRIVERSE_TEST_OUTPUT,[IO.Path]::GetFullPath($env:EXPRIVERSE_INSTALL_ROOT))"'
        $wrapper = $wrapper.Replace($original, $probe).Replace('    pause', '    rem pause').Replace("`r`npause", "`r`nrem pause")
        $path = Join-Path $game 'Probe-Update.cmd'; [IO.File]::WriteAllText($path, $wrapper, [Text.Encoding]::ASCII)
        $env:EXPRIVERSE_TEST_OUTPUT = New-TestPath 'root-probe.txt'
        # This is our harmless replacement probe, not the updater/downloaded code or fake game.
        & $env:ComSpec /d /c ('""' + $path + '""')
        Assert-True ($LASTEXITCODE -eq 0) 'CMD probe failed.'
        Assert-True ([IO.File]::ReadAllText($env:EXPRIVERSE_TEST_OUTPUT).TrimEnd('\') -ceq $root.TrimEnd('\')) 'CMD changed the selected root.'
        Remove-Item Env:\EXPRIVERSE_TEST_OUTPUT
    }
    if ($CheckPublicHttps) {
        Test-Case 'Initial one-line HTTPS fetch works without global TLS changes' {
            # Fetch static HTML only; never execute the response.
            $before = [Net.ServicePointManager]::SecurityProtocol
            $html = Invoke-RestMethod 'https://xoderony.github.io/downloads/' -MaximumRedirection 0 -TimeoutSec 30
            Assert-True ($null -ne $html) 'Public HTTPS fetch returned no content.'
            Assert-True ([Net.ServicePointManager]::SecurityProtocol -eq $before) 'Initial fetch changed TLS policy.'
        }
    }
} finally {
    Reset-Functions
    if (Test-Path -LiteralPath $script:SuiteRoot) { Remove-Item -LiteralPath $script:SuiteRoot -Recurse -Force }
}
Write-Host ('Passed: ' + $script:Passed + '; Failed: ' + $script:Failed.Count)
foreach ($failure in $script:Failed) { Write-Host $failure -ForegroundColor Red }
if ($script:Failed.Count -gt 0) { exit 1 }
