import 'dart:convert';
import 'dart:io';

import 'gen_targets.dart';

/// ไฟล์บันทึกว่าโปรแกรมเขียนไฟล์ไหนไว้ด้วยเนื้อหาอะไร (ลายนิ้วมือ) — อยู่ในโฟลเดอร์ปลายทาง
const kGenManifest = '.nsl-generated.json';

/// ลายนิ้วมือของเนื้อหา (FNV-1a 2 × 32 บิต ; ไม่สนชนิดขึ้นบรรทัด — Git บน Windows แปลง LF ↔ CRLF ได้)
String contentHash(String s) {
  var h1 = 0x811c9dc5, h2 = 0x01000193;
  for (final u in utf8.encode(s.replaceAll('\r\n', '\n'))) {
    h1 = ((h1 ^ u) * 0x01000193) & 0xFFFFFFFF;
    h2 = ((h2 ^ u) * 0x85ebca6b + h1) & 0xFFFFFFFF;
  }
  return h1.toRadixString(16).padLeft(8, '0') + h2.toRadixString(16).padLeft(8, '0');
}

/// แผนการเขียน: สร้างใหม่ / เขียนทับได้ (เราสร้างไว้และไม่ถูกแก้) / ไม่เปลี่ยน / **ถูกแก้ด้วยมือ** (ต้องถามก่อน)
class GenPlan {
  GenPlan(this.dir);
  final Directory dir;
  final create = <GenFile>[];
  final overwrite = <GenFile>[];
  final unchanged = <GenFile>[];

  /// มีไฟล์อยู่แล้วแต่ไม่ใช่ที่เราสร้างไว้ หรือถูกแก้หลังจากเราสร้าง
  final edited = <GenFile>[];

  int get total => create.length + overwrite.length + unchanged.length + edited.length;
}

File _file(Directory dir, String path) => File('${dir.path}${Platform.pathSeparator}${path.replaceAll('/', Platform.pathSeparator)}');

Future<Map<String, String>> _readManifest(Directory dir) async {
  try {
    final f = _file(dir, kGenManifest);
    if (!await f.exists()) return {};
    final j = jsonDecode(await f.readAsString());
    final files = j is Map ? j['files'] : null;
    if (files is! Map) return {};
    return {for (final e in files.entries) if (e.key is String && e.value is String) e.key as String: e.value as String};
  } catch (_) {
    return {};
  }
}

/// ตรวจโฟลเดอร์ [dir] ก่อนเขียน [files]
Future<GenPlan> planWrite(Directory dir, List<GenFile> files) async {
  final plan = GenPlan(dir);
  final manifest = await _readManifest(dir);
  for (final g in files) {
    final f = _file(dir, g.path);
    if (!await f.exists()) {
      plan.create.add(g);
      continue;
    }
    final disk = await f.readAsString();
    if (disk.replaceAll('\r\n', '\n') == g.content.replaceAll('\r\n', '\n')) {
      plan.unchanged.add(g);
    } else if (manifest[g.path] == contentHash(disk)) {
      plan.overwrite.add(g);
    } else {
      plan.edited.add(g);
    }
  }
  return plan;
}

/// เขียนตาม [plan] — ไฟล์ที่ถูกแก้ด้วยมือเขียนทับเฉพาะเมื่อ [overwriteEdited] ; อัปเดตไฟล์ลายนิ้วมือ ; คืนจำนวนไฟล์ที่เขียน
Future<int> applyWrite(GenPlan plan, {bool overwriteEdited = false}) async {
  final manifest = await _readManifest(plan.dir);
  final write = [...plan.create, ...plan.overwrite, if (overwriteEdited) ...plan.edited];
  for (final g in write) {
    final f = _file(plan.dir, g.path);
    await f.parent.create(recursive: true);
    await f.writeAsString(g.content);
    manifest[g.path] = contentHash(g.content);
  }
  for (final g in plan.unchanged) {
    manifest[g.path] = contentHash(g.content);
  }
  await plan.dir.create(recursive: true);
  final sorted = Map.fromEntries(manifest.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  await _file(plan.dir, kGenManifest).writeAsString(const JsonEncoder.withIndent('  ').convert({'generator': 'NSL Nebular', 'files': sorted}));
  return write.length;
}
