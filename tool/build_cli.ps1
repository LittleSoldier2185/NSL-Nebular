<#
.SYNOPSIS
  สร้าง CLI และ MCP server ของ NSL Nebular เป็นไฟล์ exe (build\cli\nebular\bundle\bin\nebular.exe และ build\cli\nebular-mcp\bundle\bin\nebular_mcp.exe)

.DESCRIPTION
  ใช้ `dart build cli` (ไม่ใช่ `dart compile exe` เพราะแพ็กเกจของโปรเจกต์มี build hooks)
  exe เริ่มทำงานเร็วกว่า `dart run` มาก (~0.4 วินาที เทียบกับ ~2 วินาที) จึงเหมาะกับ MCP server ที่ Claude Code เปิดทุกครั้งที่ใช้
  ต้องรันจากเครื่องที่ติดตั้ง Dart/Flutter SDK

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\build_cli.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

foreach ($t in @(@{ Src = 'bin/nebular.dart'; Out = 'build/cli/nebular' }, @{ Src = 'bin/nebular_mcp.dart'; Out = 'build/cli/nebular-mcp' })) {
  if (Test-Path $t.Out) { Remove-Item -Recurse -Force $t.Out }
  dart build cli -t $t.Src -o $t.Out
  if ($LASTEXITCODE -ne 0) { throw "dart build cli ล้มเหลว: $($t.Src)" }
}

Write-Host ''
Write-Host 'สร้างเสร็จ:'
Write-Host "  $root\build\cli\nebular\bundle\bin\nebular.exe"
Write-Host "  $root\build\cli\nebular-mcp\bundle\bin\nebular_mcp.exe"
Write-Host ''
Write-Host 'ตั้งค่า Claude Code (.mcp.json ในโฟลเดอร์โปรเจกต์ของคุณ):'
Write-Host '  { "mcpServers": { "nebular": { "command": "<path ของ nebular_mcp.exe ข้างบน>" } } }'
