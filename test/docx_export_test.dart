import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/export/docx_export.dart';

void main() {
  const md = '# หัวเรื่อง\n\n- รายการ `a_b`\n\n| ก | ข |\n|---|---|\n| **x** | y\\|z<br>w |\n';

  test('markdownToDocx: ข้อความ ตาราง และการ escape ถูกต้อง', () {
    final bytes = markdownToDocx(md, title: 't');
    expect(bytes.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]); // ZIP แบบ stored → XML อ่านได้ตรง ๆ
    final xml = utf8.decode(bytes, allowMalformed: true);
    expect(xml, contains('หัวเรื่อง'));
    expect(xml, contains('w:val="Heading1"'));
    expect(xml, contains('<w:tbl>'));
    expect(xml, contains('y|z'));
    expect(xml, contains('<w:br/>'));
    expect(RegExp('<w:tc>').allMatches(xml).length, 4); // 2 คอลัมน์ × 2 แถว (ไม่แตกคอลัมน์ที่ \| )
  });

  test('markdownToDocx: ZIP เปิดได้จริง (ตรวจด้วย .NET บน Windows)', () async {
    final dir = await Directory.systemTemp.createTemp('docx');
    final f = File('${dir.path}/t.docx')..writeAsBytesSync(markdownToDocx(md));
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "Add-Type -A System.IO.Compression.FileSystem; \$z=[IO.Compression.ZipFile]::OpenRead('${f.path}'); "
          "(\$z.Entries | % { \$_.FullName }) -join ','; \$z.Dispose()"
    ]);
    expect(r.stdout.toString(), contains('word/document.xml'));
    await dir.delete(recursive: true);
  }, skip: !Platform.isWindows);

  test('markdownToDocx: ฝังภาพใต้หัวข้อที่ระบุ + ไฟล์ media + ความสัมพันธ์', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
    final bytes = markdownToDocx('# P\n\n## ER: a\n\n- x\n',
        imagesAfter: {'ER: a': [DocxImage(png, 800, 400)]});
    final s = latin1.decode(bytes);
    expect(s, contains('word/media/image1.png'));
    expect(s, contains('r:embed="rIdImg1"'));
    expect(s, contains('Target="media/image1.png"'));
    expect(s, contains('image/png'));
    expect(s.indexOf('<w:drawing>') > s.indexOf('ER: a'), isTrue);
  });
}
