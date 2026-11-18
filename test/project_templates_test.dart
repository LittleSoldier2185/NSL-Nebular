import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/state/project_templates.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';

/// จุดเริ่มต้นสำเร็จรูปของโปรเจกต์ใหม่ (Phase 2)
void main() {
  late WorkspaceController w;
  setUp(() => w = WorkspaceController());
  tearDown(() => w.dispose());

  List<DocType?> types() => [for (final d in w.documents) d.type];

  test('blank / database: มี ER อันเดียว', () {
    createProjectFromTemplate(w, ProjectTemplate.blank);
    expect(types(), [DocType.er]);
    createProjectFromTemplate(w, ProjectTemplate.database);
    expect(types(), [DocType.er]);
    expect(w.activeDocument.type, DocType.er);
  });

  test('analysis: ER + DFD + Flowchart ; เปิด Flowchart (เอกสารแรกตามลำดับเปิด)', () {
    final open = createProjectFromTemplate(w, ProjectTemplate.analysis);
    expect(types(), [DocType.er, DocType.dfd, DocType.flowchart]);
    expect(open.type, DocType.flowchart);
    expect(w.activeId, open.id);
  });

  test('appDesign: ER + Wireframe + Screen Flow ; full: ครบ 5 ชนิด ลำดับคงที่', () {
    createProjectFromTemplate(w, ProjectTemplate.appDesign);
    expect(types(), [DocType.er, DocType.wireframe, DocType.screenflow]);
    createProjectFromTemplate(w, ProjectTemplate.full);
    expect(types(), [DocType.er, DocType.dfd, DocType.flowchart, DocType.wireframe, DocType.screenflow]);
  });

  test('createProject: ลำดับ docs ที่ส่งมาไม่มีผล ; ER ใน docs ถูกเมิน ; ชื่อโปรเจกต์ตั้งได้ ; ชื่อว่างไม่เปลี่ยน', () {
    createProject(w, docs: [DocType.screenflow, DocType.er, DocType.dfd], name: '  ร้านค้า  ');
    expect(types(), [DocType.er, DocType.dfd, DocType.screenflow]);
    expect(w.workspace.name, 'ร้านค้า');
    expect(w.mainEr.project.name, 'ร้านค้า');
    createProject(w, name: '   ');
    expect(w.workspace.name, isNot('   '));
  });

  test('สร้างใหม่: ออกจากหน้า Start ; ไม่มีไฟล์ ; ว่างไม่ dirty แต่มีเอกสารเพิ่ม = dirty (ปิดแอปต้องถามบันทึก)', () {
    w.showStart();
    expect(w.startView, true);
    createProjectFromTemplate(w, ProjectTemplate.blank);
    expect(w.startView, false);
    expect(w.filePath, isNull);
    expect(w.dirty, false);
    createProjectFromTemplate(w, ProjectTemplate.full);
    expect(w.filePath, isNull);
    expect(w.dirty, true);
  });

  test('ทุกเทมเพลตมีเอกสารเสริมไม่ซ้ำและไม่รวม ER', () {
    for (final t in ProjectTemplate.values) {
      expect(t.extraDocs.toSet().length, t.extraDocs.length, reason: t.name);
      expect(t.extraDocs.contains(DocType.er), false, reason: t.name);
    }
  });
}
