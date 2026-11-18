import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/export/html_doc_export.dart';
import 'package:nsl_nebular/core/export/markdown_export.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/review_note.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';

/// Phase 5d: โน้ตและงานค้างในเอกสารส่งออก (Markdown / HTML)
void main() {
  late WorkspaceController w;
  setUp(() {
    w = WorkspaceController();
    w.mainEr.project.tables.add(TableModel(id: 't1', name: 'orders'));
  });
  tearDown(() => w.dispose());

  test('ไม่มีโน้ต: ไม่มีส่วนโน้ต (ผลส่งออกเดิมไม่เปลี่ยน)', () {
    w.addDocument(DocType.flowchart, name: 'F');
    expect(exportWorkspaceDictionary(w.workspace), isNot(contains('โน้ตและงานค้าง')));
    expect(exportHtmlDocument(w.workspace, includeDiagrams: false), isNot(contains('review-notes')));
  });

  test('Markdown: จัดกลุ่มตามเอกสาร ช่องติ๊กตามสถานะ บันทึกไม่มีช่องติ๊ก มีเลขหมุดและวัตถุที่ผูก', () {
    final f = w.addDocument(DocType.flowchart, name: 'ขั้นตอน\nชำระเงิน')!;
    w.mainEr.doc.reviewNotes = [
      ReviewNote(id: 'a', text: 'เพิ่ม status', anchorId: 't1', x: 1, y: 1),
      ReviewNote(id: 'b', text: 'ถามเรื่อง\nภาษี', kind: NoteKind.question, done: true),
    ];
    f.reviewNotes = [ReviewNote(id: 'c', text: 'ตกลงแล้ว', kind: NoteKind.memo)];
    final md = exportWorkspaceDictionary(w.workspace);
    expect(md, contains('## โน้ตและงานค้าง'));
    expect(md, contains('- ค้างอยู่ 1 รายการ'));
    expect(md, contains('### ER: ER'));
    expect(md, contains('- [ ] เพิ่ม status _(ต้องทำ · หมุด 1 · orders)_'));
    expect(md, contains('- [x] ถามเรื่อง ภาษี _(คำถาม)_'));
    expect(md, contains('### Flowchart: ขั้นตอน ชำระเงิน'));
    expect(md, contains('- ตกลงแล้ว _(บันทึก)_'));
    // ส่วนโน้ตอยู่ท้ายสุด
    expect(md.indexOf('## โน้ตและงานค้าง'), greaterThan(md.indexOf('## Flowchart:')));
  });

  test('โปรเจกต์ ER เดียว: ยังมีส่วนโน้ตต่อท้าย', () {
    w.mainEr.doc.reviewNotes = [ReviewNote(id: 'a', text: 'งานเดียว')];
    expect(exportWorkspaceDictionary(w.workspace), contains('- [ ] งานเดียว'));
  });

  test('HTML: ส่วนโน้ตก่อน footer, escape ข้อความ, งานที่เสร็จขีดฆ่า', () {
    w.mainEr.doc.reviewNotes = [
      ReviewNote(id: 'a', text: 'ใช้ <b> & "x"'),
      ReviewNote(id: 'b', text: 'เสร็จแล้ว', done: true),
    ];
    final html = exportHtmlDocument(w.workspace, includeDiagrams: false);
    expect(html, contains('id="review-notes"'));
    expect(html, contains('ใช้ &lt;b&gt; &amp; &quot;x&quot;'));
    expect(html, contains('<s>☑ เสร็จแล้ว</s>'));
    expect(html.indexOf('review-notes'), lessThan(html.indexOf('<footer>')));
  });

  test('ภาษาอังกฤษ: หัวข้อและชนิดแปลครบ', () {
    currentLang = Lang.en;
    addTearDown(() => currentLang = Lang.th);
    w.mainEr.doc.reviewNotes = [ReviewNote(id: 'a', text: 'Add index', x: 0, y: 0)];
    final md = exportWorkspaceDictionary(w.workspace);
    expect(md, contains('## Notes & to-dos'));
    expect(md, contains('- [ ] Add index _(To-do · pin 1)_'));
    expect(md, contains('- Open items: 1'));
  });
}
