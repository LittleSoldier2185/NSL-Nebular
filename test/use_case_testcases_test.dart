import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/export/usecase_testcases.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/requirement.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/use_case.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';

/// Phase 32 (ส่วนแกน): สร้างกรณีทดสอบจาก Use Case + ส่งออก Markdown (ตาราง / Given-When-Then) และ CSV
void main() {
  late WorkspaceController w;
  late ProjectDocument api;
  late ApiEndpoint ep;
  setUp(() {
    w = WorkspaceController();
    w.mainEr.project.tables.add(TableModel(id: 'b', name: 'bookings'));
    api = w.addDocument(DocType.api, name: 'Hotel API')!;
    ep = w.apiController(api.id)!.addEndpoint(method: ApiMethod.post, path: '/bookings')!;
  });
  tearDown(() {
    currentLang = Lang.th;
    w.dispose();
  });

  /// จองห้อง : 3 ขั้น (ผู้ใช้ · ระบบ · ระบบ) + ทางเลือก 2a (กลับขั้น 1) + ข้อผิดพลาด 3x (จบ)
  UseCase seed({String name = 'จองห้องพัก', String code = 'UC-01'}) {
    final u = w.addUseCase(name: name, actor: 'Guest');
    w.updateUseCase(u.id, (x) {
      x.code = code;
      x.priority = UcPriority.high;
      x.preconditions = 'เข้าสู่ระบบแล้ว';
      x.postconditions = 'มีการจองในระบบ';
      x.steps
        ..add(UcStep(id: 's1', who: UcWho.user, text: 'เลือกห้อง'))
        ..add(UcStep(id: 's2', who: UcWho.system, text: 'ตรวจห้องว่าง', links: [TraceLink(api.id, ep.id)]))
        ..add(UcStep(id: 's3', who: UcWho.system, text: 'บันทึกการจอง', links: [TraceLink(w.mainEr.docId, 'b')]));
      x.branches
        ..add(UcBranch(id: 'b1', atStepId: 's2', condition: 'ห้องเต็ม', outcome: 'เสนอห้องอื่น', returnStepId: 's1'))
        ..add(UcBranch(id: 'b2', atStepId: 's3', exception: true, condition: 'ฐานข้อมูลล่ม', outcome: 'แจ้งลองใหม่', ends: true));
    });
    return u;
  }

  group('ตัวสร้างกรณีทดสอบ', () {
    test('ไม่มี Use Case = ไม่มีกรณี', () => expect(generateTestCases(w.workspace), isEmpty));

    test('จำนวน = 1 + ทางเลือก + ข้อผิดพลาด ต่อ Use Case ; รหัสไม่ซ้ำ ; ลำดับ หลัก → ทางเลือก/ข้อผิดพลาดตามที่เขียน', () {
      seed();
      seed(name: 'ชำระเงิน', code: 'UC-02');
      final cases = generateTestCases(w.workspace);
      expect(cases.length, 6);
      expect(cases.map((c) => c.id).toSet().length, 6);
      expect(cases.map((c) => c.id).take(3), ['TC-UC01-01', 'TC-UC01-02', 'TC-UC01-03']);
      expect(cases.map((c) => c.kind).take(3), [TcKind.main, TcKind.alternative, TcKind.exception]);
      expect(cases[1].branchLabel, '2a');
      expect(cases[2].branchLabel, '3x');
    });

    test('กรณีหลัก : ทุกขั้นตอน ผลที่คาดหวัง = ผลลัพธ์เมื่อสำเร็จ ; ไม่มี → ขั้นตอนของระบบขั้นสุดท้าย', () {
      final u = seed();
      var main = generateTestCases(w.workspace).first;
      expect(main.steps.map((s) => (s.who, s.text)), [(UcWho.user, 'เลือกห้อง'), (UcWho.system, 'ตรวจห้องว่าง'), (UcWho.system, 'บันทึกการจอง')]);
      expect((main.expected, main.precondition, main.priority), ('มีการจองในระบบ', 'เข้าสู่ระบบแล้ว', UcPriority.high));
      expect(main.title, 'จองห้องพัก — ขั้นตอนหลัก');
      w.updateUseCase(u.id, (x) => x.postconditions = '');
      main = generateTestCases(w.workspace).first;
      expect(main.expected, 'บันทึกการจอง');
    });

    test('ทางเลือก : ขั้น 1..n-1 + เงื่อนไขที่ขั้น n + ผล + ปลายทาง (กลับไปขั้น k ไม่ขยายวงวน) ; ข้อผิดพลาดจบ', () {
      seed();
      final alt = generateTestCases(w.workspace)[1];
      expect(alt.steps.map((s) => s.text), ['เลือกห้อง', 'ที่ขั้นที่ 2 : เมื่อ ห้องเต็ม', 'เสนอห้องอื่น', 'กลับไปขั้นที่ 1']);
      expect(alt.steps[1].isCondition, isTrue);
      expect(alt.expected, 'เสนอห้องอื่น · กลับไปขั้นที่ 1');
      expect(alt.title, 'จองห้องพัก — 2a ห้องเต็ม');
      final ex = generateTestCases(w.workspace)[2];
      expect(ex.steps.map((s) => s.text), ['เลือกห้อง', 'ตรวจห้องว่าง', 'ที่ขั้นที่ 3 : เมื่อ ฐานข้อมูลล่ม', 'แจ้งลองใหม่', 'จบ Use Case']);
      expect(ex.kind, TcKind.exception);
      expect(ex.expected, 'แจ้งลองใหม่ · จบ Use Case');
    });

    test('ที่ขั้นแรก : ไม่มีขั้นก่อนหน้า ; ทางเลือกไม่มีผล/ปลายทาง : แสดง (ยังไม่ระบุ)', () {
      final u = seed();
      w.updateUseCase(u.id, (x) {
        x.branches
          ..clear()
          ..add(UcBranch(id: 'z', atStepId: 's1', condition: ''));
      });
      final alt = generateTestCases(w.workspace)[1];
      expect(alt.steps.length, 2);
      expect(alt.steps.first.text, 'ที่ขั้นที่ 1 : เมื่อ (ยังไม่ระบุเงื่อนไข)');
      expect(alt.steps.last.text, '(ยังไม่ระบุ)');
    });

    test('ข้ามทางเลือกที่อ้างขั้นที่ไม่มีแล้ว ; ขั้นว่างแสดง (ยังไม่ได้เขียน) ; ไม่มีขั้นตอน = ยังมีกรณีหลัก', () {
      final u = seed();
      w.updateUseCase(u.id, (x) {
        x.branches.add(UcBranch(id: 'gone', atStepId: 'หาย', condition: 'x', ends: true));
        x.steps.add(UcStep(id: 's4', text: '  '));
      });
      final cases = generateTestCases(w.workspace);
      expect(cases.length, 3, reason: 'หลัก + 2 ทางเลือกที่ใช้ได้ ; ตัวที่อ้างขั้นที่หายถูกข้าม');
      expect(cases.first.steps.last.text, '(ยังไม่ได้เขียน)');
      final empty = w.addUseCase(name: 'ว่าง', actor: 'x');
      final c = generateTestCases(w.workspace).where((e) => e.ucId == empty.id).toList();
      expect(c.length, 1);
      expect(c.single.steps, isEmpty);
      expect(c.single.expected, '');
    });

    test('อ้างอิงจากลิงก์ของขั้นตอน (เฉพาะขั้นที่เข้ากรณีนั้น) : endpoint · ตาราง ; REQ จาก Use Case', () {
      final r = w.addRequirement(text: 'จอง');
      final u = seed();
      w.updateUseCase(u.id, (x) => x.reqIds.add(r.id));
      final cases = generateTestCases(w.workspace);
      expect(cases[0].refs.map((e) => '${e.type.name}:${e.label}'), ['api:POST /bookings', 'er:bookings']);
      expect(cases[0].reqCodes, ['REQ-01']);
      expect(cases[1].refs.map((e) => e.type.name), ['api'], reason: '2a เกิดที่ขั้น 2 : ใช้แค่ขั้น 1–2 → ไม่แตะตาราง bookings ของขั้น 3');
      expect(cases[1].refsOf(DocType.er), isEmpty);
      expect(cases[2].refs.map((e) => e.type.name), ['api', 'er']);
      w.deleteDocument(api.id);
      expect(generateTestCases(w.workspace)[0].refs.map((e) => e.type.name), ['er'], reason: 'ลิงก์ที่ขาดไม่ปรากฏ ไม่ล้ม');
    });

    test('รหัส Use Case ซ้ำ/ว่าง ยังได้รหัสกรณีทดสอบไม่ซ้ำ', () {
      seed(code: 'UC-01');
      seed(name: 'อีกข้อ', code: 'UC 01');
      seed(name: 'ไม่มีรหัส', code: '');
      final ids = generateTestCases(w.workspace).map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids.any((i) => i.startsWith('TC-UC3-')), isTrue, reason: 'รหัสว่าง → ตั้งจากลำดับของ Use Case (ข้อที่ 3)');
    });

    test('สรุป: จำนวนต่อชนิดและความครอบคลุมความต้องการ', () {
      final r1 = w.addRequirement(text: 'จอง');
      w.addRequirement(text: 'ชำระเงิน');
      final u = seed();
      w.updateUseCase(u.id, (x) => x.reqIds.add(r1.id));
      final s = testCaseSummary(w.workspace);
      expect((s.total, s.main, s.alternative, s.exception), (3, 1, 1, 1));
      expect((s.reqCovered, s.reqTotal), (1, 2));
    });
  });

  group('Markdown', () {
    test('แบบตาราง : หัวข้อ ตาราง หนึ่งแถวต่อกรณี ขั้นตอนคั่นด้วย <br> ; | ถูก escape', () {
      final u = seed();
      w.updateUseCase(u.id, (x) => x.steps.first.text = 'เลือก A | B');
      final md = exportTestCasesMarkdown(w.workspace);
      expect(md, contains('# untitled — กรณีทดสอบ'));
      expect(md, contains('3 กรณี : หลัก 1 · ทางเลือก 1 · ข้อผิดพลาด 1'));
      expect(md, contains('## UC-01 จองห้องพัก'));
      expect(md, contains('| รหัส | ประเภท | เงื่อนไขก่อนเริ่ม | ขั้นตอน | ผลที่คาดหวัง | อ้างอิง |'));
      expect('| TC-UC01-'.allMatches(md).length, 3);
      expect(md, contains(r'1. [ผู้ใช้] เลือก A \| B<br>2. [ระบบ] ตรวจห้องว่าง'));
      expect(md, contains('| ทางเลือก 2a |'));
      expect(md, contains('API: POST /bookings'));
    });

    test('แบบ Given/When/Then : Given จากเงื่อนไขก่อนเริ่ม ; ผู้ใช้ = When ระบบ = Then ; ปิดด้วย Then ผลที่คาดหวัง', () {
      seed();
      final md = exportTestCasesMarkdown(w.workspace, style: TcMarkdownStyle.givenWhenThen);
      expect(md, contains('### TC-UC01-01 จองห้องพัก — ขั้นตอนหลัก'));
      expect(md, contains('**Given** เข้าสู่ระบบแล้ว'));
      expect(md, contains('- **When** เลือกห้อง'));
      expect(md, contains('- **Then** ตรวจห้องว่าง'));
      expect(md, contains('- **When** ที่ขั้นที่ 2 : เมื่อ ห้องเต็ม'), reason: 'บรรทัดเงื่อนไขเป็น When');
      expect(md, contains('- **Then** มีการจองในระบบ'));
    });

    test('ไม่มี Use Case = บอกว่าว่าง ; ภาษาอังกฤษแปลหัวตาราง', () {
      expect(exportTestCasesMarkdown(w.workspace), contains('ยังไม่มี Use Case จึงยังไม่มีกรณีทดสอบ'));
      currentLang = Lang.en;
      seed(name: 'Book a room');
      final md = exportTestCasesMarkdown(w.workspace);
      expect(md, contains('Test cases'));
      expect(md, contains('| ID | Type | Preconditions | Steps | Expected result | References |'));
    });
  });

  group('CSV', () {
    /// ตัวอ่าน CSV ตามมาตรฐาน RFC 4180 (ไว้ตรวจว่าเขียนแล้วอ่านกลับได้ตรง)
    List<List<String>> parse(String text) {
      final rows = <List<String>>[];
      var row = <String>[], f = StringBuffer(), q = false;
      for (var i = 0; i < text.length; i++) {
        final ch = text[i];
        if (q) {
          if (ch == '"') {
            if (i + 1 < text.length && text[i + 1] == '"') {
              f.write('"');
              i++;
            } else {
              q = false;
            }
          } else {
            f.write(ch);
          }
        } else if (ch == '"') {
          q = true;
        } else if (ch == ',') {
          row.add(f.toString());
          f = StringBuffer();
        } else if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
          row.add(f.toString());
          rows.add(row);
          row = [];
          f = StringBuffer();
          i++;
        } else {
          f.write(ch);
        }
      }
      return rows;
    }

    test('BOM + หัว 10 คอลัมน์ + บรรทัดจบ CRLF ; อ่านกลับได้ตรง (ไทย เครื่องหมายจุลภาค อัญประกาศ ขึ้นบรรทัดใหม่ในเซลล์)', () {
      final u = seed();
      w.updateUseCase(u.id, (x) {
        x.steps.first.text = 'เลือก "ห้อง", พัก';
        x.preconditions = 'เข้าสู่ระบบ\nและมีบัตร';
      });
      final csv = exportTestCasesCsv(w.workspace);
      expect(csv.startsWith('﻿'), isTrue);
      expect(csv.endsWith('\r\n'), isTrue);
      final rows = parse(csv.substring(1));
      expect(rows.length, 4, reason: 'หัว + 3 กรณี');
      expect(rows.every((r) => r.length == 10), isTrue, reason: 'ทุกแถว 10 ช่อง');
      expect(rows.first.first, 'รหัส');
      final main = rows[1];
      expect(main[0], 'TC-UC01-01');
      expect(main[1], 'UC-01 จองห้องพัก');
      expect(main[5], 'เข้าสู่ระบบ และมีบัตร', reason: 'ข้อความของ Use Case ถูกยุบช่องว่าง/ขึ้นบรรทัดใหม่เป็นช่องว่างเดียว');
      expect(main[6], '1. [ผู้ใช้] เลือก "ห้อง", พัก\n2. [ระบบ] ตรวจห้องว่าง\n3. [ระบบ] บันทึกการจอง');
      expect(main[7], 'มีการจองในระบบ');
      expect(main[9], 'API: POST /bookings, ER: bookings');
      expect(rows[2][2], 'ทางเลือก 2a');
    });

    test('ไม่มี Use Case = มีแค่แถวหัว', () {
      final rows = parse(exportTestCasesCsv(w.workspace).substring(1));
      expect(rows.length, 1);
    });
  });
}
