import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/models/flowchart_model.dart';
import 'package:nsl_nebular/core/models/review_note.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/storage/project_codec.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';

/// Phase 5a: โมเดลโน้ตและงานค้าง — JSON, ไฟล์ .nsln, undo/redo ร่วมกับเนื้อหาเอกสาร
void main() {
  group('ReviewNote JSON', () {
    test('ไป-กลับครบทุกฟิลด์ และเก็บคีย์ที่ไม่รู้จักกลับ', () {
      final n = ReviewNote(
        id: 'n1',
        kind: NoteKind.question,
        text: 'ตาราง #orders ต้องมี status ไหม',
        done: true,
        x: 12.5,
        y: -40,
        anchorId: 't1',
        created: DateTime.utc(2026, 11, 18, 9, 30),
        extra: {'future': 1},
      );
      final back = ReviewNote.tryFromJson(jsonDecode(jsonEncode(n.toJson())))!;
      expect(back.id, 'n1');
      expect(back.kind, NoteKind.question);
      expect(back.text, n.text);
      expect(back.done, isTrue);
      expect((back.x, back.y), (12.5, -40.0));
      expect(back.anchorId, 't1');
      expect(back.created.toUtc(), DateTime.utc(2026, 11, 18, 9, 30));
      expect(back.extra, {'future': 1});
    });

    test('ไม่ปักหมุด = ไม่เขียน x/y ; ไม่เสร็จ = ไม่เขียน done', () {
      final j = ReviewNote(id: 'a', text: 'x').toJson();
      expect(j.containsKey('x'), isFalse);
      expect(j.containsKey('done'), isFalse);
    });

    test('ข้อมูลเสียถูกข้ามรายการเดียว ; id ซ้ำใช้ตัวแรก ; ชนิดที่ไม่รู้จัก = บันทึก', () {
      final list = decodeNotes([
        {'id': 'a', 'kind': 'todo', 'text': 'แรก'},
        'ขยะ',
        {'kind': 'todo'},
        {'id': 'a', 'text': 'ซ้ำ'},
        {'id': 'b', 'kind': 'idea', 'x': 'ผิด', 'y': 3},
      ]);
      expect(list.map((n) => n.id), ['a', 'b']);
      expect(list.first.text, 'แรก');
      expect(list.last.kind, NoteKind.memo);
      expect(list.last.pinned, isFalse);
      expect(decodeNotes('ไม่ใช่ list'), isEmpty);
    });

    test('open: ต้องทำ/คำถามที่ยังไม่เสร็จเท่านั้น', () {
      expect(ReviewNote(id: 'a', kind: NoteKind.todo).open, isTrue);
      expect(ReviewNote(id: 'a', kind: NoteKind.todo, done: true).open, isFalse);
      expect(ReviewNote(id: 'a', kind: NoteKind.memo).open, isFalse);
    });

    test('คำอ้างอิง # : ชื่ออังกฤษ/ไทย ไม่ซ้ำ ไม่รวมจุดท้ายประโยค และไม่จับ # กลางคำ', () {
      expect(noteRefs('ผูกกับ #orders และ #หน้าตะกร้า. ดู #orders อีกที'), ['orders', 'หน้าตะกร้า']);
      expect(noteRefs('สี C#5 และ a#b ไม่นับ'), isEmpty);
      expect(noteRefs('endpoint #api/orders-v2.'), ['api/orders-v2']);
    });
  });

  group('ไฟล์ .nsln', () {
    Workspace ws() {
      final w = WorkspaceController();
      final d = w.addDocument(DocType.flowchart, name: 'Flow')!;
      d.reviewNotes = [ReviewNote(id: 'n1', text: 'ต้องทำ', x: 10, y: 20)];
      return w.workspace;
    }

    test('โน้ตอยู่รอดการบันทึก-เปิดใหม่ ; เอกสารไม่มีโน้ตไม่เขียนคีย์ notes', () {
      final j = jsonDecode(jsonEncode(encodeProjectMap(ws()))) as Map<String, dynamic>;
      final docs = (j['documents'] as List).cast<Map<String, dynamic>>();
      expect(docs.where((d) => d.containsKey('notes')).length, 1);
      final back = decodeProjectMap(j);
      final flow = back.documents.firstWhere((d) => d.type == DocType.flowchart);
      expect(flow.reviewNotes.single.text, 'ต้องทำ');
      expect(flow.extra.containsKey('notes'), isFalse); // ไม่ซ้ำไปอยู่ใน extra
    });

    test('รุ่นเก่า (ไม่รู้จักคีย์ notes) เก็บไว้ใน extra แล้วเขียนกลับครบ — จำลองด้วยกลไก extra เดิม', () {
      final j = jsonDecode(jsonEncode(encodeProjectMap(ws()))) as Map<String, dynamic>;
      final flowJ = (j['documents'] as List).cast<Map<String, dynamic>>().firstWhere((d) => d['type'] == 'flowchart');
      // รุ่นก่อน Phase 5 อ่านคีย์ที่ไม่รู้จักของเอกสารเข้า extra แล้วกระจายกลับตอนเขียน
      final old = ProjectDocument(
        id: flowJ['id'] as String,
        typeName: 'flowchart',
        name: 'Flow',
        content: FlowchartDiagram.fromJson(flowJ['content']),
        extra: {'notes': flowJ['notes']},
      );
      final rewritten = jsonDecode(jsonEncode(encodeProjectMap(Workspace(documents: [old])))) as Map<String, dynamic>;
      final again = decodeProjectMap(rewritten).documents.single;
      expect(again.reviewNotes.single.id, 'n1');
      expect(again.reviewNotes.single.pinned, isTrue);
    });
  });

  group('controller: undo/redo', () {
    late WorkspaceController w;
    late String id;
    setUp(() {
      w = WorkspaceController();
      id = w.addDocument(DocType.flowchart, name: 'Flow')!.id;
      w.markSaved('test.nsln');
    });
    tearDown(() => w.dispose());

    test('ไม่มีโน้ต: snapshot ของประวัติเท่ากับเนื้อหาเดิมทุกตัวอักษร', () {
      final f = w.flowchartController(id)!;
      expect(f.historySnapshot(), jsonEncode(f.diagram.toJson()));
    });

    test('เพิ่มโน้ต = dirty ; undo เอาออก ; redo คืนมา', () {
      final c = w.controllerOf(id)!;
      expect(c.addReviewNote('   '), isNull);
      final n = c.addReviewNote('  ผูกปุ่มกับ #orders ', kind: NoteKind.todo, x: 5, y: 6)!;
      expect(n.text, 'ผูกปุ่มกับ #orders');
      expect(w.dirty, isTrue);
      c.undo();
      expect(c.reviewNotes, isEmpty);
      c.redo();
      expect(c.reviewNotes.single.id, n.id);
      expect(c.reviewNotes.single.pinned, isTrue);
    });

    test('แก้/สลับเสร็จ/ลบ แต่ละอย่าง undo ได้ ; แก้แล้วค่าเดิม = ไม่เข้าประวัติ', () {
      final c = w.controllerOf(id)!;
      final n = c.addReviewNote('a')!;
      expect(c.updateReviewNote(n.id, text: 'a'), isFalse);
      expect(c.updateReviewNote(n.id, text: 'b', kind: NoteKind.question), isTrue);
      expect(c.toggleReviewNoteDone(n.id), isTrue);
      expect(c.reviewNotes.single.done, isTrue);
      expect(c.deleteReviewNote(n.id), isTrue);
      expect(c.reviewNotes, isEmpty);
      c.undo();
      expect(c.reviewNotes.single.done, isTrue);
      c.undo();
      expect(c.reviewNotes.single.done, isFalse);
      c.undo();
      expect((c.reviewNotes.single.text, c.reviewNotes.single.kind), ('a', NoteKind.todo));
    });

    test('ลากหมุด = undo ขั้นเดียว', () {
      final c = w.controllerOf(id)!;
      final n = c.addReviewNote('a', x: 0, y: 0)!;
      c.beginGesture();
      for (var i = 1; i <= 5; i++) {
        c.moveReviewNote(n.id, i * 10.0, i * 5.0);
      }
      expect(c.endGesture(), isTrue);
      expect((c.reviewNotes.single.x, c.reviewNotes.single.y), (50.0, 25.0));
      c.undo();
      expect((c.reviewNotes.single.x, c.reviewNotes.single.y), (0.0, 0.0));
    });

    test('undo ของเนื้อหาไม่ทำโน้ตหาย และ undo ของโน้ตไม่แตะเนื้อหา', () {
      final f = w.flowchartController(id)!;
      final n = f.addReviewNote('โน้ต')!;
      f.addNode(FcShape.process, 100, 100);
      expect(f.diagram.nodes, hasLength(1));
      f.undo(); // เอาสัญลักษณ์ออก
      expect(f.diagram.nodes, isEmpty);
      expect(f.reviewNotes.single.id, n.id);
      f.undo(); // เอาโน้ตออก
      expect(f.reviewNotes, isEmpty);
      f.redo();
      f.redo();
      expect(f.diagram.nodes, hasLength(1));
      expect(f.reviewNotes, hasLength(1));
    });

    test('ทำสำเนาเอกสาร: โน้ตไม่ติดไปด้วย (เป็นงานของต้นฉบับ)', () {
      w.controllerOf(id)!.addReviewNote('ของต้นฉบับ');
      final copy = w.duplicateDocument(id)!;
      expect(copy.reviewNotes, isEmpty);
      expect(w.workspace.documentById(id)!.reviewNotes, hasLength(1));
    });
  });
}
