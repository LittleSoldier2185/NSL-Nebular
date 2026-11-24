<#
.SYNOPSIS
  ผูกไฟล์ .nsln (และ .erd รุ่นเก่า) กับ NSL Nebular ใน Windows — ดับเบิลคลิกแล้วเปิดในแอป

.DESCRIPTION
  ลงทะเบียนเฉพาะผู้ใช้ปัจจุบัน (HKCU\Software\Classes) ไม่ต้องใช้สิทธิ์ผู้ดูแลระบบ
  ไม่แตะไฟล์ของผู้ใช้ และถอนออกได้ด้วย -Unregister

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\register_file_association.ps1
  powershell -ExecutionPolicy Bypass -File tool\register_file_association.ps1 -ExePath "C:\Apps\NSL\nsl_nebular.exe"
  powershell -ExecutionPolicy Bypass -File tool\register_file_association.ps1 -Unregister
#>
param(
  [string]$ExePath,
  [switch]$Unregister,
  [switch]$IncludeLegacyErd
)

$ErrorActionPreference = 'Stop'
$progId = 'NSLNebular.Project'
$classes = 'HKCU:\Software\Classes'

function Notify-Shell {
  Add-Type -Namespace Win32 -Name Shell -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(int eventId, uint flags, System.IntPtr item1, System.IntPtr item2);
'@
  # SHCNE_ASSOCCHANGED = 0x08000000, SHCNF_IDLIST = 0
  [Win32.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
}

$extensions = @('.nsln')
if ($IncludeLegacyErd) { $extensions += '.erd' }

if ($Unregister) {
  foreach ($ext in @('.nsln', '.nslm', '.erd')) {
    $key = Join-Path $classes $ext
    if (Test-Path $key) {
      $cur = (Get-Item $key).GetValue('')
      # ลบเฉพาะที่เราเป็นคนลงไว้
      if ($cur -eq $progId) { Remove-Item $key -Recurse -Force }
    }
  }
  $progKey = Join-Path $classes $progId
  if (Test-Path $progKey) { Remove-Item $progKey -Recurse -Force }
  Notify-Shell
  Write-Host 'ถอนการผูกไฟล์ .nsln / .erd แล้ว'
  return
}

if (-not $ExePath) {
  $root = Split-Path -Parent $PSScriptRoot
  $candidates = @(
    'build\windows\x64\runner\Release\nsl_nebular.exe',
    'build\windows\x64\runner\Debug\nsl_nebular.exe'
  ) | ForEach-Object { Join-Path $root $_ }
  $ExePath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $ExePath) {
    $sibling = Join-Path $PSScriptRoot 'nsl_nebular.exe'
    if (Test-Path $sibling) { $ExePath = $sibling }
  }
}
if (-not $ExePath -or -not (Test-Path $ExePath)) {
  throw 'ไม่พบ nsl_nebular.exe — build ก่อน (flutter build windows) หรือระบุ -ExePath'
}
$ExePath = (Resolve-Path $ExePath).Path

$progKey = Join-Path $classes $progId
New-Item -Path $progKey -Force | Out-Null
Set-ItemProperty -Path $progKey -Name '(default)' -Value 'NSL Nebular Project'
# ไอคอนไฟล์โปรเจกต์: ใช้ nsln_file_icon.ico ข้าง exe (ตัวติดตั้งวางไว้) หรือในซอร์ส ; ไม่พบ = ใช้ไอคอนของ exe
$iconValue = "`"$ExePath`",0"
$iconCandidates = @(
  (Join-Path (Split-Path -Parent $ExePath) 'nsln_file_icon.ico'),
  (Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\runner\resources\nsln_file_icon.ico')
)
$iconFile = $iconCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($iconFile) { $iconValue = (Resolve-Path $iconFile).Path }
New-Item -Path "$progKey\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "$progKey\DefaultIcon" -Name '(default)' -Value $iconValue
New-Item -Path "$progKey\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$progKey\shell\open\command" -Name '(default)' -Value "`"$ExePath`" `"%1`""

foreach ($ext in $extensions) {
  $key = Join-Path $classes $ext
  New-Item -Path $key -Force | Out-Null
  Set-ItemProperty -Path $key -Name '(default)' -Value $progId
}

Notify-Shell
Write-Host "ผูก $($extensions -join ', ') กับ $ExePath แล้ว"
if (-not $IncludeLegacyErd) {
  Write-Host '(.erd รุ่นเก่าไม่ได้ผูก เพราะสกุลนี้อาจชนกับโปรแกรมอื่น — เพิ่ม -IncludeLegacyErd ถ้าต้องการ)'
}
