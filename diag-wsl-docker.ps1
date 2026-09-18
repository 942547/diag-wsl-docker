<#
=======================================================================
 diag-wsl-docker.ps1
=======================================================================
 Read-only diagnostic for machines where WSL2 / Docker Desktop /
 OpenCode CLI won't install or run (common on Windows 10 domain PCs).

 What it does:
   - Collects system / virtualization / optional-feature / WSL /
     Docker Desktop / toolchain / network facts.
   - Emits a full report with RAW command output (no truncation)
     to: diag-report.txt  (same folder as this script)
   - Appends a short list of HYPOTHESES as hints. These are hints,
     not verdicts - confirm each against the RAW data before acting.

 What it does NOT do:
   - It makes NO changes to the system. Read-only.
   - Run as Administrator so the optional-features section works:
       powershell -ExecutionPolicy Bypass -File .\diag-wsl-docker.ps1
=======================================================================
#>

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:WSL_UTF8 = '1'

$ReportPath = Join-Path $PSScriptRoot 'diag-report.txt'
$sb = New-Object System.Text.StringBuilder

function Add-Line {
    param([string]$Text = '')
    [void]$sb.AppendLine($Text)
}

function Add-Raw {
    param([string]$Title, [object]$Data)
    Add-Line ("=== " + $Title + " ===")
    Add-Line ([string]$Data)
    Add-Line
}

function Invoke-Diag {
    param([string]$Title, [scriptblock]$Block)
    Add-Line ("=== " + $Title + " ===")
    try {
        $res = & $Block 2>&1 | Out-String -Width 500
        Add-Line $res.TrimEnd()
    } catch {
        Add-Line ("ERROR: " + $_.Exception.Message)
    }
    Add-Line
}

function Read-TextFileSmart {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        return $strictUtf8.GetString($bytes)
    } catch {
        return [System.Text.Encoding]::Default.GetString($bytes)
    }
}

function Test-Tool {
    param([string]$Name)
    Add-Line ("=== tool: " + $Name + " ===")
    $gc = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gc) {
        Add-Line ("Path   : " + $gc.Source)
        Add-Line ("Version: " + $gc.Version)
        try {
            Add-Line ("--version output--")
            Add-Line ((& $Name --version 2>&1 | Out-String).TrimEnd())
        } catch {
            Add-Line ("--version failed: " + $_.Exception.Message)
        }
    } else {
        Add-Line "NOT FOUND"
    }
    Add-Line
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$build = [int]($os.BuildNumber)
$sysinfo = systeminfo 2>&1 | Out-String -Width 500

# ---------------------------------------------------------------------
Add-Line "======================================================================"
Add-Line "DIAGNOSTIC REPORT: WSL2 + Docker Desktop + OpenCode CLI"
Add-Line ("Machine    : " + $env:COMPUTERNAME)
Add-Line ("User       : " + $env:USERNAME + " @ " + $env:USERDOMAIN)
Add-Line ("OS         : " + $os.Caption + "  build " + $os.BuildNumber)
Add-Line ("Admin run  : " + $isAdmin)
Add-Line ("Date       : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
Add-Line ("Report: paste the FULL content of this file into OpenCode/LLM")
Add-Line "======================================================================"
Add-Line

# ---------------------------------------------------------------------
Add-Line "## 1. SYSTEM"
Add-Raw "Win32_OperatingSystem" ($os | Select-Object Caption,Version,BuildNumber,OSArchitecture,InstallDate,Manufacturer | Format-List | Out-String -Width 500)
Add-Raw "Win32_ComputerSystem" ($cs | Select-Object Manufacturer,Model,Domain,PartOfDomain,HypervisorPresent,TotalPhysicalMemory | Format-List | Out-String -Width 500)
$ureg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
Add-Raw "Registry CurrentVersion (ProductName/DisplayVersion/UBR)" ($ureg | Select-Object ProductName,DisplayVersion,CurrentBuildNumber,CurrentBuild,UBR | Format-List | Out-String -Width 500)
Add-Raw "systeminfo (FULL)" $sysinfo

# ---------------------------------------------------------------------
Add-Line "## 2. VIRTUALIZATION"
Invoke-Diag "Win32_Processor virtualization flags" {
    $cpu | Select-Object Name,Manufacturer,NumberOfCores,VirtualizationFirmwareEnabled,VMMonitorModeExtensions,SecondLevelAddressTranslationExtensions | Format-List | Out-String -Width 500
}
Invoke-Diag "systeminfo - Hyper-V requirements (from captured sysinfo)" {
    ($sysinfo -split "`r?`n") | Where-Object { $_ -match 'Hyper-V|virtualization|VM Monitor|Second Level|Data Execution|listed below' } | ForEach-Object { Add-Line $_ }
}

# ---------------------------------------------------------------------
Add-Line "## 3. OPTIONAL FEATURES (admin required)"
if ($isAdmin) {
    Invoke-Diag "Get-WindowsOptionalFeature - WSL / VM Platform / Hyper-V" {
        $featNames = 'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform', 'HypervisorPlatform', 'Microsoft-Hyper-V-All'
        foreach ($fn in $featNames) {
            Get-WindowsOptionalFeature -Online -FeatureName $fn |
                Select-Object FeatureName, State
        }
    }
} else {
    Add-Line "NOT ADMIN -> cannot query optional features. Re-run elevated for this section."
    Add-Line
}

# ---------------------------------------------------------------------
Add-Line "## 4. WSL"
Invoke-Diag "wsl --status" { wsl.exe --status }
Invoke-Diag "wsl -l -v (distros + VERSION 1/2)" { wsl.exe -l -v }
Invoke-Diag "wsl --list --running" { wsl.exe --list --running }
Invoke-Diag "wsl --list --online (available distros)" { wsl.exe --list --online }
Invoke-Diag "wsl --version (new WSL shell only)" { wsl.exe --version }
Add-Line "=== wsl.exe location & file version ==="
$wslCmd = Get-Command wsl.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($wslCmd) {
    Add-Line ("Path   : " + $wslCmd.Source)
    $wver = Get-Item $wslCmd.Source
    if ($wver) { Add-Raw "wsl.exe FileVersion" ($wver.VersionInfo | Select-Object FileVersion,ProductVersion | Format-List | Out-String -Width 500) }
} else {
    Add-Line "wsl.exe NOT FOUND"
}
Add-Line
Add-Line "=== .wslconfig ==="
$wslcfg = Join-Path $env:USERPROFILE '.wslconfig'
if (Test-Path $wslcfg) { Add-Line (Read-TextFileSmart $wslcfg) } else { Add-Line "(no .wslconfig)" }
Add-Line
Add-Line "=== Registry: Lxss (default WSL config) ==="
Add-Raw "HKCU Lxss" ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' | Select-Object DefaultVersion,DefaultDistribution) | Format-List | Out-String -Width 500)
Invoke-Diag "WSL-related services (LxssManager / WslService)" {
    Get-Service LxssManager,WslService -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType | Format-Table -AutoSize | Out-String -Width 500
}

# ---------------------------------------------------------------------
Add-Line "## 5. DOCKER DESKTOP"
$ddExe = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
Add-Line "=== Docker Desktop install ==="
if (Test-Path $ddExe) {
    Add-Line ("Exists: " + $ddExe)
    $vi = (Get-Item $ddExe).VersionInfo
    Add-Line ("Version: " + $vi.FileVersion + "  ProductVersion: " + $vi.ProductVersion)
} else {
    Add-Line "NOT INSTALLED at default path"
}
Add-Line
Invoke-Diag "docker CLI availability" { Get-Command docker -ErrorAction SilentlyContinue | Select-Object Source,Version | Format-List | Out-String -Width 500 }
Invoke-Diag "docker version" { docker version 2>&1 | Out-String -Width 500 }
Invoke-Diag "docker context ls" { docker context ls 2>&1 | Out-String -Width 500 }
Invoke-Diag "docker info" { docker info 2>&1 | Out-String -Width 500 }
Invoke-Diag "com.docker.service" { Get-Service com.docker.service -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType | Format-Table -AutoSize | Out-String -Width 500 }
Invoke-Diag "Docker/Dockerd processes" {
    Get-Process 'Docker Desktop','com.docker.backend','com.docker.service','dockerd','vpnkit','wsl-relay' -ErrorAction SilentlyContinue |
        Select-Object Name,Id | Format-Table -AutoSize | Out-String -Width 500
}
Add-Line "=== Docker settings files ==="
foreach ($f in @("$env:AppData\Docker\settings-store.json", "$env:AppData\Docker\settings.json", "$env:AppData\Docker\settings-data.json")) {
    Add-Line ("--- " + $f + " ---")
    if (Test-Path $f) { Add-Line (Read-TextFileSmart $f) } else { Add-Line "(not found)" }
    Add-Line
}
Add-Line "=== Docker log files (newest 5, filtered, last 40 lines each) ==="
Add-Line "(filtered: GET /time pings, backend ipc S<-C/S->C, extension settings polls)"
$logDir = Join-Path $env:LocalAppData 'Docker\log'
if (Test-Path $logDir) {
    $logs = Get-ChildItem $logDir -Recurse -Filter *.log -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 5
    foreach ($l in $logs) {
        Add-Line ("--- " + $l.FullName + "  (" + $l.LastWriteTime.ToString('yyyy-MM-dd HH:mm') + ") ---")
        $logText = Read-TextFileSmart $l.FullName
        if ($null -ne $logText) {
            $logText -split "`r?`n" |
                Where-Object { $_ -notmatch 'GET /time|S<-C |S->C |/app/settings/flat|gvisor/forwarder' } |
                Select-Object -Last 40 | ForEach-Object { Add-Line $_ }
        }
        Add-Line
    }
} else {
    Add-Line "(no Docker log directory)"
}

# ---------------------------------------------------------------------
Add-Line "## 6. OPENCODE CLI RUNTIMES / TOOLING"
foreach ($t in 'node', 'npm', 'npx', 'bun', 'pnpm', 'yarn', 'winget', 'opencode') { Test-Tool $t }
Add-Line "=== PowerShell environment ==="
Add-Raw "PSVersion" $PSVersionTable.PSVersion.ToString()
Add-Raw "ExecutionPolicy -List" ((Get-ExecutionPolicy -List) | Out-String -Width 500)
Add-Raw "PATH" $env:Path

# ---------------------------------------------------------------------
Add-Line "## 7. DOMAIN / POLICY / NETWORK"
Invoke-Diag "whoami /fqdn" { whoami.exe /fqdn }
Add-Line "=== Proxy settings ==="
$ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
Add-Raw "HKCU Internet Settings (proxy)" ($ie | Select-Object ProxyEnable,ProxyServer,ProxyOverride,AutoConfigURL | Format-List | Out-String -Width 500)
Invoke-Diag "netsh winhttp show proxy" { netsh.exe winhttp show proxy }
Add-Raw "Environment proxy vars" (("HTTP_PROXY=" + $env:HTTP_PROXY) + "`r`n" + ("HTTPS_PROXY=" + $env:HTTPS_PROXY) + "`r`n" + ("NO_PROXY=" + $env:NO_PROXY))

function Test-Port {
    param([string]$HostName, [int]$Port = 443, [int]$TimeoutMs = 5000)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $res = $client.BeginConnect($HostName, $Port, $null, $null)
        if ($res.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            try { $client.EndConnect($res); return ("OPEN     " + $HostName) }
            catch { return ("CLOSED   " + $HostName + "  " + $_.Exception.Message) }
        } else {
            return ("TIMEOUT  " + $HostName)
        }
    } catch {
        return ("FAIL     " + $HostName + "  " + $_.Exception.Message)
    } finally {
        $client.Close()
    }
}

$hostsToTest = @('github.com', 'raw.githubusercontent.com', 'api.github.com', 'registry.npmjs.org', 'www.npmjs.org', 'nodejs.org', 'opencode.ai', 'download.docker.com')
Add-Line "=== TCP 443 reachability (5s timeout each) ==="
foreach ($h in $hostsToTest) { Add-Line (Test-Port $h) }
Add-Line
Invoke-Diag "DNS resolution for hosts above" {
    foreach ($h in $hostsToTest) {
        try {
            $addrs = [System.Net.Dns]::GetHostAddresses($h) | ForEach-Object { $_.IPAddressToString }
            Add-Line ($h + " -> " + ($addrs -join ", "))
        } catch {
            Add-Line ($h + " -> DNS FAIL")
        }
    }
}

# ---------------------------------------------------------------------
Add-Line "## 8. HYPOTHESES (hints only - verify each against RAW above)"
$hyp = New-Object System.Collections.Generic.List[string]
Add-Line ("Running as Administrator: " + $isAdmin)
$vmModel = $cs.Model
$vmManuf = $cs.Manufacturer
if ($vmManuf -match 'VMware|VirtualBox|innotek|QEMU|Xen|Bochs' -or $vmModel -match 'VMware|VirtualBox|QEMU|KVM|Hyper-V|Virtual Machine') {
    $hyp.Add("Machine appears to be a VM (Manufacturer=$vmManuf, Model=$vmModel). WSL2 needs NESTED virtualization enabled on the host/VM.")
}
if ($build -lt 19041) {
    $hyp.Add("Windows build $build is below 19041 -> WSL2 is NOT supported on this build. Update Windows (2004+ / 22H2 recommended).")
}
if ($cpu.VirtualizationFirmwareEnabled -eq $false) {
    $hyp.Add("VirtualizationFirmwareEnabled=False -> VT-x/AMD-V is OFF in BIOS/UEFI (or absent in VM without nested virt). Enable it, otherwise WSL2 and the Docker engine cannot start.")
}
if ($cs.HypervisorPresent -eq $false -and $build -ge 19041) {
    $hyp.Add("HypervisorPresent=False -> the Windows hypervisor is not running. Usually caused by the VirtualMachinePlatform feature being disabled and/or missing reboot.")
}
if ($isAdmin) {
    $vmPlat = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
    if ($vmPlat -and $vmPlat.State -eq 'Disabled') {
        $hyp.Add("VirtualMachinePlatform feature is DISABLED -> WSL2 is impossible. Enable it (admin) and reboot: Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform")
    }
    $wslFeat = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
    if ($wslFeat -and $wslFeat.State -eq 'Disabled') {
        $hyp.Add("'Windows Subsystem for Linux' feature is DISABLED -> install/enable it and reboot.")
    }
}
$wslOut = & wsl.exe -l -v 2>&1 | Out-String
Add-Raw "wsl -l -v captured for hypothesis parsing" $wslOut
$wslRows = @(foreach ($_line in ($wslOut -split "`r?`n")) {
    if ($_line -match '^\s*\*?\s*(.+?)\s{2,}(Stopped|Running|Installed)\s+\(?(\d)\)?\s*$') {
        [PSCustomObject]@{ Name = $matches[1].Trim(); State = $matches[2]; WslVer = [int]$matches[3] }
    }
})
if ($wslRows.Count -gt 0) {
    Add-Raw "Parsed WSL distros" ($wslRows | Format-Table -AutoSize | Out-String -Width 500)
    foreach ($r in $wslRows) {
        if ($r.WslVer -eq 1) {
            $hyp.Add("WSL distro '$($r.Name)' runs WSL1 (VERSION=1) -> Docker Desktop (WSL2 backend) ignores it. Convert: wsl --set-version '$($r.Name)' 2")
        }
    }
    if (-not ($wslRows | Where-Object { $_.Name -like 'docker-desktop*' })) {
        $hyp.Add("No 'docker-desktop' WSL distro found in 'wsl -l -v'. If Docker Desktop is installed, its WSL2 integration did not initialize (often the same root cause as WSL2 being unavailable).")
    }
}
if (-not (Test-Path $ddExe)) {
    $hyp.Add("Docker Desktop not installed. Install it and enable 'Use the WSL 2 based engine'.")
}
$nodeFound = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
$bunFound = Get-Command bun -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $nodeFound -and -not $bunFound) {
    $hyp.Add("Neither Node.js nor Bun found -> OpenCode CLI cannot be installed via npm/bun. Use winget (winget search opencode) or a standalone binary from GitHub releases.")
}
if (-not $isAdmin) {
    $hyp.Add("Script was NOT run as Administrator -> optional-features status is unknown. Re-run elevated for the complete picture.")
}
Add-Line "---"
if ($hyp.Count -eq 0) {
    Add-Line "No obvious red flags detected. Provide the RAW data above to an LLM for deeper analysis."
} else {
    for ($i = 0; $i -lt $hyp.Count; $i++) {
        Add-Line ("H" + ($i + 1) + ". " + $hyp[$i])
    }
}

# ---------------------------------------------------------------------
Add-Line
Add-Line "======================================================================"
Add-Line "END OF REPORT."
Add-Line "To use: paste the full content of diag-report.txt into OpenCode and ask"
Add-Line "what to do next. This script changed NOTHING on the system."
Add-Line "======================================================================"

[System.IO.File]::WriteAllText($ReportPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
Write-Host ""
Write-Host ("Report written to: " + $ReportPath)
Write-Host ("Size: " + ((Get-Item $ReportPath).Length) + " bytes")