import 'dart:convert';
import 'dart:io';

import 'package:nsl_nebular/cli/nebular_cli.dart';

/// `nebular` — CLI ของ NSL Nebular : `dart run bin/nebular.dart <คำสั่ง> <ไฟล์โปรเจกต์> …`
/// (สร้าง exe: `dart build cli -t bin/nebular.dart -o build/cli/nebular` หรือ `tool/build_cli.ps1`)
Future<void> main(List<String> args) async {
  stdout.encoding = utf8; // ภาษาไทยต้องออกเป็น UTF-8 เสมอ (Windows ปกติใช้ code page ของเครื่อง)
  stderr.encoding = utf8;
  exitCode = await runCli(args, out: stdout, err: stderr);
}
