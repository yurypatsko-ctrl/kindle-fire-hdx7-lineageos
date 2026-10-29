#Requires -RunAsAdministrator
# Writes the vulnerable aboot and TWRP to a Fire HDX 7 (thor) that is in bulk mode
# (after "fastboot -i 0x1949 erase aboot" + reboot). Replaces the manual dd.exe step.
# The tablet's eMMC is identified by exact size and partition layout, so a PC disk is never touched.
$ErrorActionPreference = 'Stop'

$tools = Split-Path -Parent $MyInvocation.MyCommand.Path
$aboot = (Get-ChildItem "$tools\aboot-13-thor\*.mbn" | Select-Object -First 1).FullName
$twrp  = Join-Path (Split-Path $tools) 'thor-twrp-3.1.1-0.img'

# Layout read from this tablet over adb before erasing aboot
$diskBytes     = 15388672L * 1024    # /proc/partitions: mmcblk0
$abootBytes    = 4096L * 512         # mmcblk0p6  = aboot
$recoveryBytes = 20480L * 512        # mmcblk0p18 = recovery
$userdataBytes = 12255215L * 1024    # mmcblk0p23 = userdata (/proc/partitions rounds to 1 KiB)

$hashes = @{
    $aboot = '12E536CD88887012'      # first 16 hex of SHA256, checked when the zip was unpacked
    $twrp  = '6aae6362bedf1fb0741f9946ae3982ba'  # MD5 published on AndroidFileHost
}
if ((Get-FileHash $aboot -Algorithm SHA256).Hash.Substring(0,16) -ne $hashes[$aboot]) { throw "aboot file changed: $aboot" }
if ((Get-FileHash $twrp -Algorithm MD5).Hash.ToLower() -ne $hashes[$twrp]) { throw "TWRP file changed: $twrp" }

Write-Host "Looking for the tablet among disks..." -ForegroundColor Cyan
try { Update-HostStorageCache } catch {}
$candidates = foreach ($d in Get-Disk) {
    if ($d.IsBoot -or $d.IsSystem -or $d.Size -ne $diskBytes) { continue }
    $parts = @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue)
    $p6  = $parts | Where-Object PartitionNumber -eq 6
    $p18 = $parts | Where-Object PartitionNumber -eq 18
    $p23 = $parts | Where-Object PartitionNumber -eq 23
    if ($parts.Count -eq 23 -and $p6.Size -eq $abootBytes -and $p18.Size -eq $recoveryBytes -and [math]::Abs($p23.Size - $userdataBytes) -lt 1024) {
        [pscustomobject]@{ Disk = $d; Aboot = $p6; Recovery = $p18 }
    }
}
Get-Disk | Format-Table Number, FriendlyName, BusType, Size, IsBoot, IsSystem -AutoSize

if (@($candidates).Count -ne 1) {
    Write-Host "Tablet not found (or more than one match). Nothing was written." -ForegroundColor Red
    Write-Host "Make sure the tablet is in bulk mode (black screen, Windows shows many new drives)."
    return
}
$t = $candidates
Write-Host ("Tablet found: disk {0} ({1}, {2:N0} bytes)" -f $t.Disk.Number, $t.Disk.FriendlyName, $t.Disk.Size) -ForegroundColor Green
Write-Host ("  Partition 6  (aboot)    offset {0}, size {1}" -f $t.Aboot.Offset, $t.Aboot.Size)
Write-Host ("  Partition 18 (recovery) offset {0}, size {1}" -f $t.Recovery.Offset, $t.Recovery.Size)
if ($t.Disk.IsOffline) { Set-Disk -Number $t.Disk.Number -IsOffline $false }
if ($t.Disk.IsReadOnly) { Set-Disk -Number $t.Disk.Number -IsReadOnly $false }

if ((Read-Host "Type YES to write aboot and TWRP to disk $($t.Disk.Number)") -cne 'YES') {
    Write-Host "Cancelled. Nothing was written."; return
}

function Test-PartitionHead([int]$disk, [int]$partNum, [scriptblock]$check, [string]$what) {
    $fs = [IO.FileStream]::new("\\.\Harddisk${disk}Partition$partNum", 'Open', 'Read', 'ReadWrite', 512)
    try { $head = New-Object byte[] 512; if ($fs.Read($head, 0, 512) -ne 512) { throw "Cannot read partition $partNum" } }
    finally { $fs.Dispose() }
    if (-not (& $check $head)) { throw "Partition $partNum does not look like $what. Nothing was written." }
    Write-Host "  Partition $partNum looks like $what" -ForegroundColor Green
}

function Write-Partition([int]$disk, [int]$partNum, [long]$size, [string]$file) {
    $data = [IO.File]::ReadAllBytes($file)
    if ($data.Length -gt $size) { throw "$file does not fit into the partition" }
    $buf = New-Object byte[] ([math]::Ceiling($data.Length / 512) * 512)
    [Array]::Copy($data, $buf, $data.Length)
    # Open the partition itself (like dd's \\?\Device\HarddiskX\PartitionN), so a write cannot leave it.
    # Write in 512-byte blocks without write-through: the Qualcomm bulk-mode USB device rejects FUA/large writes.
    $fs = [IO.FileStream]::new("\\.\Harddisk${disk}Partition$partNum", 'Open', 'ReadWrite', 'ReadWrite', 512)
    try {
        [void]$fs.Seek(0, 'Begin')
        for ($pos = 0; $pos -lt $buf.Length; $pos += 512) { $fs.Write($buf, $pos, 512) }
        $fs.Flush()
        [void]$fs.Seek(0, 'Begin')
        $back = New-Object byte[] $buf.Length
        for ($pos = 0; $pos -lt $back.Length; $pos += 512) {
            $n = $fs.Read($back, $pos, 512); if ($n -ne 512) { throw "Short read at $pos of $file" }
        }
    } finally { $fs.Dispose() }
    for ($i = 0; $i -lt $buf.Length; $i++) { if ($buf[$i] -ne $back[$i]) { throw "Verification failed at byte $i of $file" } }
    Write-Host ("  OK: {0} written and verified ({1:N0} bytes)" -f (Split-Path $file -Leaf), $data.Length) -ForegroundColor Green
}

Test-PartitionHead $t.Disk.Number 18 { param($h) [Text.Encoding]::ASCII.GetString($h, 0, 8) -eq 'ANDROID!' } 'the stock recovery (ANDROID! header)'
Test-PartitionHead $t.Disk.Number 6 { param($h) -not ($h | Where-Object { $_ -ne 0 -and $_ -ne 255 }) } 'the erased aboot'
Write-Partition $t.Disk.Number 6 $t.Aboot.Size $aboot
Write-Partition $t.Disk.Number 18 $t.Recovery.Size $twrp
Write-Host "`nDone. Do NOT format anything Windows offers. Hold Power to reboot into fastboot." -ForegroundColor Cyan
