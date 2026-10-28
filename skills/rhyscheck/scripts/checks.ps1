<#
.SYNOPSIS
    RhysCheck diagnostics - read-only Windows fault checks.

.DESCRIPTION
    Collects diagnostic information for one or more categories and prints it
    as plain text. Makes no changes to the system. Works in Windows
    PowerShell 5.1 and PowerShell 7+.

.EXAMPLE
    .\checks.ps1 -Category baseline,display
    .\checks.ps1 -Category crash -Days 30
#>
[CmdletBinding()]
param(
    [ValidateSet('baseline','display','performance','crash','network','audio','storage','usb','boot','all')]
    [string[]]$Category = @('baseline'),

    [ValidateRange(1,90)]
    [int]$Days = 7
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$since     = (Get-Date).AddDays(-$Days)
$sinceLong = (Get-Date).AddDays(-([Math]::Max($Days, 30)))

if ($Category -contains 'all') {
    $Category = @('baseline','display','performance','crash','network','audio','storage','usb','boot')
}

# ---------- helpers ----------

function Section([string]$Title) { ""; "=== $($Title.ToUpper()) ===" }

function Run([string]$Label, [scriptblock]$Block) {
    "-- $Label"
    try {
        $out = & $Block | Out-String -Width 220
        if ([string]::IsNullOrWhiteSpace($out)) { "   (none found)" } else { $out.TrimEnd() }
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'No events were found') { "   (none found)" }
        elseif ($msg -match 'denied|privilege|unauthori|elevat|CIM resource was not available') { "   needs admin" }
        else { "   error: $msg" }
    }
}

function FirstLine($Text) { if ($Text) { (($Text -split "`r?`n")[0]).Trim() } else { '(no message text)' } }

function Short-Location($Loc) {
    $Loc -replace '^HKU\\S-1-5-21-[\d-]+\\', 'HKCU\' -replace '^HKU\\(S-1-5-18|\.DEFAULT)\\', 'HKU-System\' -replace '\\Microsoft\\Windows\\CurrentVersion\\Run$', '\Run'
}

function Get-Events([hashtable]$Filter, [int]$Max = 20) {
    Get-WinEvent -FilterHashtable $Filter -MaxEvents $Max -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, ProviderName, LevelDisplayName,
            @{n='Message'; e={ FirstLine $_.Message }}
}

function Decode-WmiString($Codes) { -join ($Codes | Where-Object { $_ } | ForEach-Object { [char]$_ }) }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

"RhysCheck diagnostics | $env:COMPUTERNAME | $(Get-Date -Format 'yyyy-MM-dd HH:mm') | Admin: $isAdmin | Window: last $Days days"

# ---------- categories ----------

foreach ($cat in $Category) {
switch ($cat) {

'baseline' {
    Section 'Baseline'
    Run 'System' {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        [pscustomobject]@{
            OS        = "$($os.Caption) ($($os.Version))"
            Model     = "$($cs.Manufacturer) $($cs.Model)"
            LastBoot  = $os.LastBootUpTime
            UptimeHrs = [int]((Get-Date) - $os.LastBootUpTime).TotalHours
            RAM_GB    = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            FreeRAM_GB= [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        } | Format-List
    }
    Run 'CPU' { Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, LoadPercentage | Format-Table -AutoSize }
    Run 'GPU' {
        Get-CimInstance Win32_VideoController |
            Select-Object Name, DriverVersion, DriverDate, CurrentRefreshRate,
                @{n='Resolution'; e={ "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)" }}, Status |
            Format-Table -AutoSize
    }
    Run 'Drives' {
        Get-Volume | Where-Object DriveLetter |
            Select-Object DriveLetter, FileSystemLabel,
                @{n='FreeGB'; e={ [math]::Round($_.SizeRemaining / 1GB, 1) }},
                @{n='SizeGB'; e={ [math]::Round($_.Size / 1GB, 1) }},
                @{n='Free%';  e={ if ($_.Size) { [int](100 * $_.SizeRemaining / $_.Size) } }}, HealthStatus |
            Format-Table -AutoSize
    }
    Run 'Devices with problems' {
        Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -notin 'OK','Unknown' } |
            Select-Object Class, FriendlyName, Status | Format-Table -AutoSize
    }
    Run 'Recent updates' { Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 5 HotFixID, Description, InstalledOn | Format-Table -AutoSize }
    Run 'Pending reboot' {
        $keys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        )
        if ($keys | Where-Object { Test-Path $_ }) { 'Yes - a restart is pending' } else { 'No' }
    }
}

'display' {
    Section 'Display'
    Run 'Display drivers' {
        Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY'" |
            Select-Object DeviceName, DriverVersion, DriverDate, Manufacturer | Format-Table -AutoSize
    }
    Run 'Monitors' {
        $names = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)
        $conns = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction SilentlyContinue)
        $map = @{ '0'='VGA'; '4'='DVI'; '5'='HDMI'; '10'='DisplayPort'; '11'='DisplayPort (internal)'; '15'='Miracast'; '2147483648'='Internal panel' }
        foreach ($m in $names) {
            $c = $conns | Where-Object { $_.InstanceName -eq $m.InstanceName } | Select-Object -First 1
            $tech = if ($c) { [int64]$c.VideoOutputTechnology } else { $null }
            [pscustomobject]@{
                Monitor    = Decode-WmiString $m.UserFriendlyName
                Maker      = Decode-WmiString $m.ManufacturerName
                Year       = $m.YearOfManufacture
                Connection = if ($null -ne $tech -and $map.ContainsKey("$tech")) { $map["$tech"] } elseif ($null -ne $tech) { "Other ($tech)" } else { '?' }
                Active     = $m.Active
            }
        }
    }
    Run 'Connected monitor devices' {
        Get-PnpDevice -Class Monitor -PresentOnly -ErrorAction SilentlyContinue | Select-Object FriendlyName, Status | Format-Table -AutoSize
    }
    Run "GPU / display driver events (last $Days days)" {
        Get-WinEvent -FilterHashtable @{ LogName='System'; Level=1,2,3; StartTime=$since } -MaxEvents 5000 -ErrorAction SilentlyContinue |
            Where-Object { $_.ProviderName -match 'nvlddmkm|amdkmdag|amdwddmg|igfx|^Display$|DxgKrnl|dxgkrnl' -or $_.Id -eq 4101 } |
            Select-Object -First 25 TimeCreated, Id, ProviderName, @{n='Message'; e={ FirstLine $_.Message }} | Format-Table -AutoSize -Wrap
    }
    Run 'Multiplane overlay (MPO)' {
        $v = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' -Name OverlayTestMode -ErrorAction SilentlyContinue).OverlayTestMode
        if ($v -eq 5) { 'Disabled (OverlayTestMode=5)' } else { 'Default (enabled)' }
    }
    Run 'Overlay / RGB / capture apps running' {
        Get-Process | Where-Object { $_.Name -match 'overlay|RTSS|Afterburner|GameBar|Discord|NVIDIA Share|obs|iCUE|Armoury|LightingService|SignalRgb|Wallpaper|f\.lux|DisplayFusion|Steam' } |
            Select-Object -Unique Name | Format-Table -AutoSize
    }
}

'performance' {
    Section 'Performance'
    Run 'Top 10 by CPU time' {
        Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name,
            @{n='CPU_s'; e={ [int]$_.CPU }}, @{n='RAM_MB'; e={ [int]($_.WS / 1MB) }} | Format-Table -AutoSize
    }
    Run 'Top 10 by RAM' {
        Get-Process | Sort-Object WS -Descending | Select-Object -First 10 Name,
            @{n='RAM_MB'; e={ [int]($_.WS / 1MB) }} | Format-Table -AutoSize
    }
    Run 'Startup programs' { Get-CimInstance Win32_StartupCommand | Select-Object Name, @{n='Location'; e={ Short-Location $_.Location }} | Sort-Object Name -Unique | Format-Table -AutoSize }
    Run 'Power plan' { powercfg /getactivescheme }
    Run 'Thermal zones' {
        Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop |
            Select-Object InstanceName, @{n='TempC'; e={ [math]::Round($_.CurrentTemperature / 10 - 273.15, 1) }} | Format-Table -AutoSize
    }
}

'crash' {
    Section 'Crashes and restarts'
    Run 'Unexpected shutdowns / BSODs (last 30+ days)' {
        Get-Events @{ LogName='System'; Id=41,1001,6008; StartTime=$sinceLong } 20 | Format-Table -AutoSize -Wrap
    }
    Run 'Hardware errors (WHEA)' {
        Get-Events @{ LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$sinceLong } 15 | Format-Table -AutoSize -Wrap
    }
    Run 'Minidumps' {
        if (-not (Test-Path C:\Windows\Minidump)) { 'No Minidump folder' }
        else {
            Get-ChildItem C:\Windows\Minidump -ErrorAction Stop | Sort-Object LastWriteTime -Descending |
                Select-Object -First 5 Name, LastWriteTime | Format-Table -AutoSize
        }
    }
    Run "App crashes and hangs (last $Days days)" {
        Get-WinEvent -FilterHashtable @{ LogName='Application'; ProviderName='Application Error','Application Hang'; StartTime=$since } -MaxEvents 200 -ErrorAction SilentlyContinue |
            Group-Object { "$($_.Properties[0].Value) ($(if ($_.Id -eq 1002) { 'hang' } else { 'crash' }))" } |
            Sort-Object Count -Descending | Select-Object -First 10 Count, Name | Format-Table -AutoSize
    }
}

'network' {
    Section 'Network'
    Run 'Adapters' { Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, LinkSpeed | Format-Table -AutoSize }
    Run 'IP configuration' {
        Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' } |
            Select-Object InterfaceAlias, @{n='IPv4'; e={ $_.IPv4Address.IPAddress }},
                @{n='Gateway'; e={ $_.IPv4DefaultGateway.NextHop }}, @{n='DNS'; e={ $_.DNSServer.ServerAddresses -join ', ' }} | Format-Table -AutoSize
    }
    Run 'Wi-Fi' { netsh wlan show interfaces | Select-String 'Name|State|SSID|Signal|Radio type|Receive rate|Transmit rate' | ForEach-Object { $_.Line.Trim() } }
    Run 'Internet reachability' {
        $p = Test-Connection 1.1.1.1 -Count 4 -ErrorAction SilentlyContinue
        if ($p) {
            $t = $p | ForEach-Object { if ($_.PSObject.Properties['ResponseTime']) { $_.ResponseTime } else { $_.Latency } }
            "Ping 1.1.1.1: $(@($p).Count)/4 replies, avg $([int]($t | Measure-Object -Average).Average) ms"
        } else { 'Ping 1.1.1.1: no replies' }
        $d = Resolve-DnsName google.com -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($d) { 'DNS: OK' } else { 'DNS: FAILED to resolve google.com' }
    }
    Run "Network events (last $Days days)" {
        Get-WinEvent -FilterHashtable @{ LogName='System'; Level=1,2,3; StartTime=$since } -MaxEvents 3000 -ErrorAction SilentlyContinue |
            Where-Object { $_.ProviderName -match 'WLAN|Netwtw|e1d|e2f|rt640|Tcpip|Dhcp|NDIS|NetBT' } |
            Select-Object -First 15 TimeCreated, Id, ProviderName, @{n='Message'; e={ FirstLine $_.Message }} | Format-Table -AutoSize -Wrap
    }
}

'audio' {
    Section 'Audio'
    Run 'Audio devices (connected)' {
        $all = @(Get-PnpDevice -Class AudioEndpoint, MEDIA -ErrorAction SilentlyContinue)
        $all | Where-Object { $_.Status -ne 'Unknown' } | Select-Object Class, FriendlyName, Status | Sort-Object Class, FriendlyName | Format-Table -AutoSize
        "Not currently connected: $(@($all | Where-Object Status -eq 'Unknown').Count) device(s)"
    }
    Run 'Audio services' { Get-Service Audiosrv, AudioEndpointBuilder | Select-Object Name, Status, StartType | Format-Table -AutoSize }
}

'storage' {
    Section 'Storage'
    Run 'Physical disks' {
        Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus,
            @{n='SizeGB'; e={ [int]($_.Size / 1GB) }} | Format-Table -AutoSize
    }
    Run 'Disk reliability counters' {
        Get-PhysicalDisk | Get-StorageReliabilityCounter -ErrorAction Stop |
            Select-Object DeviceId, Temperature, Wear, ReadErrorsTotal, WriteErrorsTotal, PowerOnHours | Format-Table -AutoSize
    }
    Run "Disk / file system errors (last $([Math]::Max($Days,14)) days)" {
        Get-Events @{ LogName='System'; ProviderName='disk','Ntfs','stornvme','storahci','volmgr'; Level=1,2,3; StartTime=(Get-Date).AddDays(-([Math]::Max($Days,14))) } 15 |
            Format-Table -AutoSize -Wrap
    }
}

'usb' {
    Section 'USB and peripherals'
    $generic = 'Generic|Service|Profile|Enumerator|HID-compliant|HID Keyboard|USB Input|Root Hub|Composite|Avrcp|RFCOMM|GATT|Host Controller|Information|Identification|Discovery|PS/2|HID Button|Event Filter|Synthetic|Input Configuration|Portable Device|I2C HID|Bluetooth HID|XINPUT'
    Run 'Peripherals with problems' {
        Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.Class -match 'USB|HIDClass|Keyboard|Mouse|Image|Camera|Bluetooth' -and $_.Status -ne 'OK' } |
            Select-Object Class, FriendlyName, Status | Format-Table -AutoSize
    }
    Run 'Connected peripherals' {
        Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.Class -match 'USB|HIDClass|Keyboard|Mouse|Image|Camera|Bluetooth' -and $_.FriendlyName -notmatch $generic } |
            Sort-Object FriendlyName -Unique | Select-Object Class, FriendlyName, Status | Sort-Object Class | Format-Table -AutoSize
    }
    Run "Device connect / disconnect events (last $Days days)" {
        Get-Events @{ LogName='System'; ProviderName='Microsoft-Windows-Kernel-PnP'; StartTime=$since } 20 | Format-Table -AutoSize -Wrap
    }
}

'boot' {
    Section 'Boot and login'
    Run 'Recent boot times' {
        Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-Diagnostics-Performance/Operational'; Id=100 } -MaxEvents 5 -ErrorAction Stop |
            ForEach-Object {
                $x = [xml]$_.ToXml()
                $bt = ($x.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' }).'#text'
                [pscustomobject]@{ Date = $_.TimeCreated; BootSeconds = [math]::Round([int]$bt / 1000, 1) }
            } | Format-Table -AutoSize
    }
    Run 'Startup programs' { Get-CimInstance Win32_StartupCommand | Select-Object Name, @{n='Location'; e={ Short-Location $_.Location }} | Sort-Object Name -Unique | Format-Table -AutoSize }
    Run 'Fast Startup' {
        $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
        if ($v -eq 1) { 'Enabled' } elseif ($v -eq 0) { 'Disabled' } else { 'Unknown' }
    }
}

} # switch
} # foreach

""
"=== END ==="
