$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$project = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $project 'scripts\test-session.ps1'
if (-not (Test-Path -LiteralPath $installerPath)) { $installerPath = Join-Path $project 'site\downloads\test-session.ps1' }
$source = [IO.File]::ReadAllText($installerPath)
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw ($errors | Out-String) }
$functions = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)
# 只载入本项目的函数定义，不运行脚本末尾的实际安装入口。
. ([scriptblock]::Create(($functions | ForEach-Object { $_.Extent.Text }) -join "`n"))
$workRoot = Join-Path $project 'work'
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
$testRoot = Join-Path $workRoot ('installer-qa-' + [guid]::NewGuid().ToString('N'))
$desktop = Join-Path $testRoot 'desktop with spaces'
$fixture = Join-Path $testRoot 'fixture'
New-Item -ItemType Directory -Path $desktop,$fixture | Out-Null
$cmd = @'
@echo off
cd /d "%~dp0"
start "" /wait "powershell.exe" -NoProfile -Command "$PID | Set-Content -LiteralPath 'child.pid'; Start-Sleep -Seconds 120"
'@
[IO.File]::WriteAllText((Join-Path $fixture 'Start-NetworkValidation.cmd'), $cmd, [Text.Encoding]::ASCII)
$script:archive = Join-Path $testRoot 'fixture.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($fixture, $script:archive)
$script:release = [pscustomobject]@{ id='test-fixture'; installName='fixture'; title='Harmless test fixture'; file='../fixture.zip'; bytes=(Get-Item -LiteralPath $script:archive).Length; sha256=(Get-FileHash -LiteralPath $script:archive).Hash; launcher='Start-NetworkValidation.cmd' }
$script:answer = 'No'
$script:childId = 0
$script:downloadCount = 0
$script:capturedPaths = @()
function Invoke-RestMethod { param($Uri, $TimeoutSec) return $script:release }
function Invoke-WebRequest { param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec) $script:downloadCount++; Copy-Item -LiteralPath $script:archive -Destination $OutFile }
function Read-Host {
    param($Prompt)
    if ($Prompt -like 'Download*') { return $script:answer }
    $started = [Diagnostics.Stopwatch]::StartNew()
    while ($started.Elapsed.TotalSeconds -lt 10) {
        $folders = @(Get-ChildItem -LiteralPath $desktop -Directory)
        foreach ($folder in $folders) {
            $childFile = Join-Path $folder.FullName 'game\child.pid'
            if (Test-Path -LiteralPath $childFile) {
                $script:childId = [int](Get-Content -LiteralPath $childFile -Raw)
                Get-Process -Id $script:childId -ErrorAction Stop | Out-Null
                $script:capturedPaths += $folder.FullName
                return 'Delete'
            }
        }
        Start-Sleep -Milliseconds 100
    }
    throw 'The harmless child process did not start.'
}
function Assert-True { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw $Message } }
$uri = [uri]'https://fixture.invalid/releases/test-fixture.json'
try {
    Invoke-WebShareSession $uri $desktop
    Assert-True ($script:downloadCount -eq 0) 'No must not download.'
    Assert-True (@(Get-ChildItem -LiteralPath $desktop -Force).Count -eq 0) 'No must not create files.'
    $script:answer = 'Yes'
    Invoke-WebShareSession $uri $desktop
    Assert-True ($script:childId -gt 0) 'Child process was not observed.'
    Assert-True ($null -eq (Get-Process -Id $script:childId -ErrorAction SilentlyContinue)) 'Child process survived cleanup.'
    Assert-True (@(Get-ChildItem -LiteralPath $desktop -Force).Count -eq 0) 'Installation survived Delete.'
    $validHash = $script:release.sha256
    $script:release.sha256 = '0' * 64
    $rejected = $false
    try { Invoke-WebShareSession $uri $desktop } catch { $rejected = $_.Exception.Message -match 'SHA-256' }
    Assert-True $rejected 'Bad hash was not rejected.'
    Assert-True (@(Get-ChildItem -LiteralPath $desktop -Force).Count -eq 0) 'Failed download verification left files.'
    $script:release.sha256 = $validHash
    $badArchive = Join-Path $testRoot 'traversal.zip'
    $zip = [IO.Compression.ZipFile]::Open($badArchive, [IO.Compression.ZipArchiveMode]::Create)
    try { $entry = $zip.CreateEntry('../escape.txt'); $writer = [IO.StreamWriter]::new($entry.Open()); $writer.Write('must not escape'); $writer.Dispose() } finally { $zip.Dispose() }
    $rejected = $false
    try { Expand-WebShareArchive $badArchive (Join-Path $testRoot 'extract') } catch { $rejected = $_.Exception.Message -match 'outside' }
    Assert-True $rejected 'Zip traversal was not rejected.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $testRoot 'escape.txt'))) 'Zip entry escaped.'
    $rejected = $false
    try { Remove-WebShareSession $fixture $desktop ('a' * 32) } catch { $rejected = $true }
    Assert-True $rejected 'Unowned directory was not rejected.'
    Assert-True (Test-Path -LiteralPath $fixture) 'Unowned directory was removed.'
    Write-Output 'PASS: No creates no files; Yes verifies, extracts and starts launcher; Delete stops launcher descendants and removes all session files; bad hashes, traversal and unrelated cleanup are rejected.'
}
finally {
    # 清理测试自身生成的临时目录，先验证绝对路径归属且没有重解析点。
    $resolvedTest = [IO.Path]::GetFullPath($testRoot)
    $resolvedWork = [IO.Path]::GetFullPath($workRoot).TrimEnd('\') + '\'
    if (-not $resolvedTest.StartsWith($resolvedWork, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid test cleanup path.' }
    if (Test-Path -LiteralPath $resolvedTest) {
        $links = @(Get-ChildItem -LiteralPath $resolvedTest -Recurse -Force | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
        if ($links.Count -gt 0) { throw 'Unexpected test links.' }
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
}
