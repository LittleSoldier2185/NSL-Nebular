import 'dart:convert';
import 'dart:io';

import 'package:nsl_nebular/cli/mcp_server.dart';

/// MCP server ของ NSL Nebular (stdio) — ตั้งค่าใน `.mcp.json` ของโปรเจกต์ที่ใช้ Claude Code :
///   { "mcpServers": { "nebular": { "command": "nebular-mcp" } } }
/// (สร้าง exe: `dart build cli -t bin/nebular_mcp.dart -o build/cli/nebular-mcp` หรือ `tool/build_cli.ps1`)
/// stdout ใช้กับโปรโตคอลเท่านั้น — บันทึกทั้งหมดไป stderr
Future<void> main() async {
  stdout.encoding = utf8; // ภาษาไทยต้องออกเป็น UTF-8 เสมอ (Windows ปกติใช้ code page ของเครื่อง)
  stderr.encoding = utf8;
  await runMcpStdio(stdin, stdout.writeln, log: (m) => stderr.writeln('[nebular-mcp] $m'));
  await stdout.flush();
}
