import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/requirement.dart';
import 'package:nsl_nebular/core/models/screenflow_model.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/storage/project_codec.dart';
import 'package:nsl_nebular/core/storage/project_subset.dart';

Workspace build() {
  final sf = ScreenFlowDiagram();
  sf.nodes.add(SfNode(id: 'n1', kind: SfKind.screen, wireframeId: 'w1'));
  sf.nodes.add(SfNode(id: 'n2', kind: SfKind.screen, wireframeId: 'w2'));
  final r = Requirement(id: 'q1', code: 'REQ-01', text: 'ล็อกอิน');
  r.cell(DocType.wireframe).links
    ..add(const TraceLink('w1'))
    ..add(const TraceLink('w2'));
  return Workspace(
    name: 'demo',
    folders: [
      DocFolder(id: 'fa', name: 'A'),
      DocFolder(id: 'fb', name: 'B', parentId: 'fa'),
      DocFolder(id: 'fc', name: 'C'),
    ],
    documents: [
      ProjectDocument.er(id: 'er', name: 'ER', content: Project(name: 'demo')),
      ProjectDocument.wireframe(id: 'w1', name: 'Home', content: WireframeDiagram(), folderId: 'fb'),
      ProjectDocument.wireframe(id: 'w2', name: 'Cart', content: WireframeDiagram(), folderId: 'fc'),
      ProjectDocument.screenflow(id: 's1', name: 'Nav', content: sf, folderId: 'fa'),
      ProjectDocument(id: 'x1', typeName: 'future', name: 'Future', content: RawDocContent({'k': 1})),
    ],
    requirements: [r],
  );
}

void main() {
  test('เลือกเอกสารเดียว: เหลือเอกสารนั้น + โฟลเดอร์แม่ทุกชั้น', () {
    final r = extractSubset(build(), docIds: {'w1'})!;
    expect(r.documentCount, 1);
    expect(r.workspace.documents.map((d) => d.id), ['w1']);
    expect(r.workspace.folders.map((f) => f.id).toSet(), {'fa', 'fb'});
    expect(r.workspace.folderById('fb')!.parentId, 'fa');
  });

  test('เลือกโฟลเดอร์: รวมเอกสารในโฟลเดอร์ย่อย', () {
    final r = extractSubset(build(), folderIds: {'fa'})!;
    expect(r.workspace.documents.map((d) => d.id).toSet(), {'w1', 's1'});
    expect(r.workspace.folders.map((f) => f.id).toSet(), {'fa', 'fb'});
  });

  test('ไม่แก้โปรเจกต์ต้นฉบับ', () {
    final w = build();
    extractSubset(w, docIds: {'w1'});
    expect(w.documents.length, 5);
    expect(w.folders.length, 3);
    expect(w.requirements.single.cell(DocType.wireframe).links.length, 2);
  });

  test('นับอ้างอิงที่ชี้ออกนอกชุด และตัดลิงก์ไล่ตามที่ชี้นอกชุด', () {
    final r = extractSubset(build(), docIds: {'s1', 'w1'})!;
    expect(r.brokenRefs, 1); // s1.n2 -> w2
    expect(r.droppedTraceLinks, 1); // REQ-01 -> w2
    final links = r.workspace.requirements.single.cell(DocType.wireframe).links;
    expect(links.map((l) => l.docId), ['w1']);
    expect(r.workspace.requirements.single.text, 'ล็อกอิน');
  });

  test('เอกสารชนิดที่ไม่รู้จักถูกเก็บและเขียนกลับครบ', () {
    final r = extractSubset(build(), docIds: {'x1'})!;
    final back = decodeProjectMap(encodeProjectMap(r.workspace));
    expect(back.documents.single.typeName, 'future');
    expect((back.documents.single.content as RawDocContent).value, {'k': 1});
  });

  test('ไม่มีอะไรเลือก = null ; ผลลัพธ์เขียน/อ่านกลับได้', () {
    expect(extractSubset(build()), isNull);
    expect(extractSubset(build(), docIds: {'nope'}), isNull);
    final r = extractSubset(build(), docIds: {'er', 'w2'})!;
    final back = decodeProjectMap(encodeProjectMap(r.workspace));
    expect(back.documents.map((d) => d.id), ['er', 'w2']);
    expect(back.name, 'demo');
  });
}
