import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/cli/nebular_api.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/traceability.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/storage/project_file.dart';

/// โปรเจกต์ตัวอย่างขนาดเล็ก "ห้องสมุดเล็ก" (samples/mini_library.nsln — สร้างด้วย `dart run tool/gen_mini_sample.dart`)
/// ใช้ลองแอปด้วยมือทีละฟีเจอร์ : ต้องเปิดได้ ไม่มี error/warning และช่องว่างที่ตั้งใจเว้นไว้ยังอยู่
void main() {
  late Workspace w;

  setUp(() async {
    currentLang = Lang.th;
    w = await loadProject('samples/mini_library.nsln');
  });

  test('มีครบทุกชนิดเอกสาร ตรวจแล้วไม่มี error/warning (เหลือ info ตาราง categories ไว้ลอง "สร้าง CRUD")', () {
    expect({for (final d in w.documents) d.type}, DocType.values.toSet());
    expect(w.documents.length, 8);
    final r = validateReport(w);
    expect(r['errors'], 0);
    expect(r['warnings'], 0, reason: '${r['issues']}');
  });

  test('ไป-กลับไฟล์ไม่เสียข้อมูล', () {
    expect(ProjectFile.encode(ProjectFile.decode(ProjectFile.encode(w))), ProjectFile.encode(w));
  });

  test('ความต้องการ: REQ-01/02 ครบ ; REQ-03/04 เว้นช่องไว้ ; ลิงก์ไม่ขาด', () {
    bool covered(String code) => requirementCovered(w, w.requirements.firstWhere((r) => r.code == code));
    expect([for (final code in ['REQ-01', 'REQ-02', 'REQ-03', 'REQ-04']) covered(code)], [true, true, false, false]);
    for (final r in w.requirements) {
      for (final t in kTraceColumns) {
        expect(validLinks(w, r, t).length, r.cells[t]?.links.length ?? 0, reason: '${r.code}/${t.name}');
      }
    }
  });
}
