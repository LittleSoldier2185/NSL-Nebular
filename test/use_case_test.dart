import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/export/usecase_export.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/requirement.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/use_case.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/storage/project_codec.dart';
import 'package:nsl_nebular/core/storage/project_subset.dart';
import 'package:nsl_nebular/core/validate/usecase_validator.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// Phase 27: Use Case ของโปรเจกต์ (รอบ 1 = สเปก + เอกสาร)
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
  tearDown(() => w.dispose());

  /// Use Case ครบ : 3 ขั้น, ทางเลือก 1 (กลับไปขั้น 1), ข้อผิดพลาด 1 (จบ)
  UseCase seed({String name = 'จองห้องพัก', String actor = 'Guest', WorkspaceController? c, ProjectDocument? apiDoc, ApiEndpoint? endpoint}) {
    final ctl = c ?? w, a = apiDoc ?? api, e = endpoint ?? ep;
    final u = ctl.addUseCase(name: name, actor: actor);
    ctl.updateUseCase(u.id, (x) {
      x.goal = 'จองห้องได้ในครั้งเดียว';
      x.secondaryActor = 'ระบบอีเมล, Payment Gateway';
      x.steps
        ..add(UcStep(id: 's1', who: UcWho.user, text: 'เลือกห้อง'))
        ..add(UcStep(id: 's2', who: UcWho.system, text: 'ตรวจห้องว่าง', links: [TraceLink(a.id, e.id)]))
        ..add(UcStep(id: 's3', who: UcWho.system, text: 'บันทึกการจอง', links: [TraceLink(ctl.mainEr.docId, 'b')]));
      x.branches
        ..add(UcBranch(id: 'b1', atStepId: 's2', condition: 'ห้องเต็ม', outcome: 'เสนอห้องอื่น', returnStepId: 's1'))
        ..add(UcBranch(id: 'b2', atStepId: 's3', exception: true, condition: 'ชำระเงินไม่สำเร็จ', outcome: 'ยกเลิกการจอง', ends: true));
    });
    return u;
  }

  group('โมเดลและไฟล์', () {
    test('รหัสถัดไปต่อจากเลขสูงสุด ; เพิ่ม/แก้/ลบ = dirty', () {
      w.markSaved('x.nsln');
      expect(w.addUseCase().code, 'UC-01');
      w.updateUseCase(w.useCases.first.id, (u) => u.code = 'UC-07');
      expect(w.addUseCase().code, 'UC-08');
      expect(w.dirty, isTrue);
      w.markSaved('x.nsln');
      expect(w.deleteUseCase(w.useCases.last.id), isTrue);
      expect(w.dirty, isTrue);
      expect(w.deleteUseCase('ไม่มี'), isFalse);
    });

    test('ลบ Use Case = เอาออกจากรายการ include ของข้ออื่น', () {
      final a = w.addUseCase(name: 'A'), b = w.addUseCase(name: 'B');
      w.updateUseCase(a.id, (u) => u.includes.add(b.id));
      w.deleteUseCase(b.id);
      expect(w.useCaseById(a.id)!.includes, isEmpty);
    });

    test('เขียน-อ่านไฟล์ (JSON v3) ครบทุกฟิลด์ ; ว่าง = ไม่เขียนคีย์ useCases', () {
      expect(encodeProjectMap(w.workspace)['meta'], isNot(contains('useCases')));
      final u = seed();
      w.updateUseCase(u.id, (x) {
        x.status = UcStatus.review;
        x.priority = UcPriority.high;
        x.trigger = 'กดจอง';
        x.preconditions = 'เข้าสู่ระบบแล้ว';
        x.postconditions = 'มีการจอง';
        x.reqIds.add('r1');
      });
      final copy = copyWorkspace(w.workspace);
      final c = copy.useCases.single;
      expect((c.code, c.name, c.actor, c.secondaryActor), ('UC-01', 'จองห้องพัก', 'Guest', 'ระบบอีเมล, Payment Gateway'));
      expect((c.status, c.priority, c.trigger), (UcStatus.review, UcPriority.high, 'กดจอง'));
      expect(c.reqIds, ['r1']);
      expect(c.steps.map((s) => (s.id, s.who, s.text)), [('s1', UcWho.user, 'เลือกห้อง'), ('s2', UcWho.system, 'ตรวจห้องว่าง'), ('s3', UcWho.system, 'บันทึกการจอง')]);
      expect(c.steps[1].links.single, TraceLink(api.id, ep.id));
      expect(c.branches[0].returnStepId, 's1');
      expect(c.branches[1].exception && c.branches[1].ends, isTrue);
      expect(jsonEncode(encodeProjectMap(copy)), jsonEncode(encodeProjectMap(w.workspace)), reason: 'เขียนซ้ำได้ตรงเดิม');
    });

    test('ข้อมูลเสียถูกข้าม ; id ซ้ำใช้ตัวแรก ; คีย์ที่ไม่รู้จักเขียนกลับครบ ; ค่าไม่รู้จัก = ค่าเริ่มต้น', () {
      final j = encodeProjectMap(w.workspace);
      (j['meta'] as Map)['useCases'] = [
        {'id': 'u1', 'name': 'ดี', 'future': {'x': 1}, 'status': 'วิเศษ', 'steps': [{'id': 's', 'who': '?', 'text': 't', 'k': 9}, 5, {'id': 's'}]},
        {'id': 'u1', 'name': 'ซ้ำ'},
        'ขยะ',
        {'name': 'ไม่มี id'},
      ];
      final ws = decodeProjectMap(j);
      expect(ws.useCases.length, 1);
      final u = ws.useCases.single;
      expect((u.name, u.status), ('ดี', UcStatus.draft));
      expect(u.steps.single.who, UcWho.user);
      final back = encodeProjectMap(ws)['meta']['useCases'][0] as Map;
      expect(back['future'], {'x': 1});
      expect((back['steps'] as List).single['k'], 9);
    });

    test('ป้ายทางเลือก: 2a, 2b (ทางเลือก) ; 3x (ข้อผิดพลาด) ; อ้างขั้นที่ไม่มี = ?a', () {
      final u = seed();
      u.branches.add(UcBranch(id: 'b3', atStepId: 's2', condition: 'อีกทาง', ends: true));
      u.branches.add(UcBranch(id: 'b4', atStepId: 'หาย', ends: true));
      expect([for (final b in u.branches) u.branchLabel(b)], ['2a', '3x', '2b', '?a']);
    });

    test('ส่งออกเฉพาะเอกสารที่เลือก: ตัดลิงก์ขั้นตอนที่ชี้เอกสารที่ไม่ได้เลือก', () {
      seed();
      final r = extractSubset(w.workspace, docIds: {w.mainEr.docId})!;
      final u = r.workspace.useCases.single;
      expect(u.stepById('s3')!.links, isNotEmpty, reason: 'ER ถูกเลือก');
      expect(u.stepById('s2')!.links, isEmpty, reason: 'API ไม่ได้เลือก');
      expect(r.droppedTraceLinks, 1);
      expect(w.useCases.single.stepById('s2')!.links, isNotEmpty, reason: 'ต้นฉบับไม่ถูกแก้');
    });
  });

  group('ตัวตรวจ', () {
    Set<String> codes([UseCase? only]) => {for (final i in validateUseCases(w.workspace)) if (only == null || i.ucId == only.id) i.code};

    test('Use Case ที่เขียนครบและผูก REQ = ไม่มีปัญหา', () {
      final r = w.addRequirement(text: 'จองห้อง');
      final u = seed();
      w.updateUseCase(u.id, (x) => x.reqIds.add(r.id));
      expect(validateUseCases(w.workspace), isEmpty);
    });

    test('ว่างเปล่า: ไม่มีชื่อ/ผู้กระทำ/ขั้นตอน', () {
      final u = w.addUseCase();
      expect(codes(u), {'uc_no_name', 'uc_no_actor', 'uc_no_steps'});
    });

    test('ทางเลือก: ไม่บอกทางกลับ = error ; ขั้นที่อ้างถูกลบ = error ; ไม่มีเงื่อนไข = warning', () {
      final u = seed();
      w.updateUseCase(u.id, (x) {
        x.branches.add(UcBranch(id: 'n1', atStepId: 's1', condition: 'x')); // ไม่จบ ไม่กลับ
        x.branches.add(UcBranch(id: 'n2', atStepId: 's1', condition: '', ends: true));
        x.steps.removeWhere((s) => s.id == 's3'); // b2 อ้างขั้นที่หาย
      });
      final i = validateUseCases(w.workspace);
      expect(i.where((x) => x.code == 'uc_branch_no_target').single.severity.name, 'error');
      expect(i.any((x) => x.code == 'uc_branch_step_missing'), isTrue);
      expect(i.where((x) => x.code == 'uc_branch_no_condition').single.severity.name, 'warning');
    });

    test('ลิงก์ขั้นตอนที่ชี้เอกสารถูกลบ = เตือน ระบุขั้น', () {
      final u = seed();
      w.deleteDocument(api.id);
      final i = validateUseCases(w.workspace).where((x) => x.code == 'uc_link_broken').single;
      expect(i.stepId, 's2');
      expect(i.ucId, u.id);
    });

    test('include: ตัวเอง/ที่ไม่มี = error', () {
      final a = w.addUseCase(name: 'A', actor: 'x');
      w.updateUseCase(a.id, (u) => u.includes.addAll([a.id, 'หาย']));
      expect(codes(a), containsAll(['uc_include_self', 'uc_include_missing']));
    });

    test('ความต้องการ: ไม่ผูก = เตือน ; REQ ที่ไม่มี Use Case = เตือนระดับโปรเจกต์ (เมื่อมี Use Case แล้ว) ; ครอบคลุมนับถูก', () {
      final r1 = w.addRequirement(text: 'จอง'), r2 = w.addRequirement(text: 'ชำระเงิน');
      expect(validateUseCases(w.workspace), isEmpty, reason: 'ยังไม่มี Use Case = ไม่เตือนทุก REQ');
      final u = seed();
      expect(codes(u), contains('uc_no_req'));
      w.updateUseCase(u.id, (x) => x.reqIds.add(r1.id));
      final proj = validateUseCases(w.workspace).where((x) => x.ucId == null).single;
      expect((proj.code, proj.reqId), ('req_no_usecase', r2.id));
      expect(useCaseCoverage(w.workspace), (covered: 1, total: 2));
      w.deleteRequirement(r1.id);
      expect(codes(u), contains('uc_req_missing'));
    });
  });

  group('ส่งออก Markdown', () {
    test('มีหัวข้อ ผู้กระทำ ขั้นตอน ลิงก์ ทางเลือก/ข้อผิดพลาด พร้อมปลายทาง', () {
      final r = w.addRequirement(text: 'จอง');
      final u = seed();
      w.updateUseCase(u.id, (x) => x.reqIds.add(r.id));
      final md = exportUseCaseMarkdown(w.workspace);
      expect(md, contains('# untitled — Use Case'));
      expect(md, contains('## UC-01 จองห้องพัก'));
      expect(md, contains('**ผู้กระทำหลัก:** Guest'));
      expect(md, contains('ระบบอีเมล, Payment Gateway'));
      expect(md, contains('REQ-01'));
      expect(md, contains('1. [ผู้ใช้] เลือกห้อง'));
      expect(md, contains('2. [ระบบ] ตรวจห้องว่าง — POST /bookings'));
      expect(md, contains('3. [ระบบ] บันทึกการจอง — bookings'));
      expect(md, contains('- 2a ห้องเต็ม → เสนอห้องอื่น · กลับไปขั้นที่ 1'));
      expect(md, contains('- 3x ชำระเงินไม่สำเร็จ → ยกเลิกการจอง · จบ Use Case'));
    });

    test('ลิงก์ที่ขาดและทางเลือกที่ไม่ระบุปลายทางไม่ทำให้พัง', () {
      final u = seed();
      w.deleteDocument(api.id);
      u.branches.add(UcBranch(id: 'z', atStepId: 's1', condition: 'x'));
      final md = exportUseCaseMarkdown(w.workspace);
      expect(md, contains('(ลิงก์ที่ขาด)'));
      expect(md, contains('(ยังไม่ระบุ)'));
    });

    test('ไม่มี Use Case = บอกว่าว่าง ; ภาษาอังกฤษไม่มีไทยหลุดในโครงเอกสาร', () {
      expect(exportUseCaseMarkdown(w.workspace), contains('ยังไม่มี Use Case'));
      currentLang = Lang.en;
      addTearDown(() => currentLang = Lang.th);
      seed(name: 'Book a room', actor: 'Guest');
      final md = exportUseCaseMarkdown(w.workspace);
      for (final line in md.split('\n')) {
        if (line.contains('Book a room') || line.contains('Guest')) continue;
        expect(RegExp(r'[฀-๿]').hasMatch(line.replaceAll(RegExp(r'(เลือกห้อง|ตรวจห้องว่าง|บันทึกการจอง|จองห้องได้ในครั้งเดียว|ห้องเต็ม|เสนอห้องอื่น|ชำระเงินไม่สำเร็จ|ยกเลิกการจอง|ระบบอีเมล)'), '')), isFalse, reason: line);
      }
    });
  });

  group('หน้าจอ', () {
    late WorkspaceController wc;
    late ProjectDocument wApi;
    late ApiEndpoint wEp;
    UseCase seedApp({String name = 'จองห้องพัก', String actor = 'Guest'}) => seed(name: name, actor: actor, c: wc, apiDoc: wApi, endpoint: wEp);
    Future<void> boot(WidgetTester tester, {Lang lang = Lang.th, Size size = const Size(1600, 950), bool explorer = true}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang, showExplorer: explorer)));
      wc = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      wc.mainEr.project.tables.add(TableModel(id: 'o', name: 'orders'));
      wc.mainEr.project.tables.add(TableModel(id: 'b', name: 'bookings'));
      wApi = wc.addDocument(DocType.api, name: 'Hotel API')!;
      wEp = wc.apiController(wApi.id)!.addEndpoint(method: ApiMethod.post, path: '/bookings')!;
      wc.showUseCases();
      await tester.pumpAndSettle();
    }

    final view = find.byKey(const ValueKey('usecase-view'));

    testWidgets('เข้าได้จากปุ่มบน Project Home ; ยังไม่มี = หน้าว่างพร้อมปุ่มเริ่ม', (tester) async {
      await boot(tester);
      wc.showHome();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-usecase')));
      await tester.pumpAndSettle();
      expect(view, findsOneWidget);
      expect(find.byKey(const ValueKey('uc-empty')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('uc-empty-add')));
      await tester.pumpAndSettle();
      expect(wc.useCases.length, 1);
      expect(find.byKey(const ValueKey('uc-empty')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('เขียนสเปก: ชื่อ ผู้กระทำ ขั้นตอน สลับผู้ทำ ทางเลือก ; รายการซ้ายและตรวจอัปเดต', (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('uc-add')));
      await tester.pumpAndSettle();
      final u = wc.useCases.single;
      expect(find.byKey(ValueKey('uc-issue-uc_no_name')), findsOneWidget);

      Future<void> type(String key, String text) async {
        await tester.enterText(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField)), text);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }

      await type('uc-name-${u.id}', 'จองห้องพัก');
      await type('uc-actor-${u.id}', 'Guest');
      expect((u.name, u.actor), ('จองห้องพัก', 'Guest'));
      expect(find.byKey(ValueKey('uc-issue-uc_no_name')), findsNothing);
      expect(find.byKey(ValueKey('uc-issue-uc_no_actor')), findsNothing);
      expect(find.descendant(of: find.byKey(ValueKey('uc-item-${u.id}')), matching: find.text('จองห้องพัก')), findsOneWidget);
      expect(find.text('Guest · 1'), findsOneWidget, reason: 'จัดกลุ่มตามผู้กระทำ');

      for (var i = 0; i < 2; i++) {
        await tester.ensureVisible(find.byKey(const ValueKey('uc-add-step')));
        await tester.tap(find.byKey(const ValueKey('uc-add-step')));
        await tester.pumpAndSettle();
      }
      expect(u.steps.length, 2);
      expect([for (final s in u.steps) s.who], [UcWho.user, UcWho.system], reason: 'ขั้นใหม่สลับผู้ทำให้');
      await type('uc-step-text-${u.steps[0].id}', 'เลือกห้อง');
      expect(u.steps[0].text, 'เลือกห้อง');
      await tester.tap(find.byKey(ValueKey('uc-step-who-${u.steps[0].id}')));
      await tester.pumpAndSettle();
      expect(u.steps[0].who, UcWho.system);

      await tester.tap(find.byKey(ValueKey('uc-step-down-${u.steps[0].id}')));
      await tester.pumpAndSettle();
      expect(u.steps.last.text, 'เลือกห้อง', reason: 'เลื่อนลงแล้วสลับลำดับ');

      await tester.ensureVisible(find.byKey(const ValueKey('uc-add-alt')));
      await tester.tap(find.byKey(const ValueKey('uc-add-alt')));
      await tester.pumpAndSettle();
      expect(u.branches.single.atStepId, u.steps.last.id);
      expect(find.byKey(ValueKey('uc-issue-uc_branch_no_target')), findsOneWidget, reason: 'ทางเลือกใหม่ยังไม่บอกทางกลับ');
      expect(tester.takeException(), isNull);
    });

    testWidgets('ผูกขั้นตอนกับตาราง ER จากเมนู ; ป้ายลิงก์แสดงชื่อ ; กดป้ายไปที่เอกสาร', (tester) async {
      await boot(tester);
      final u = seedApp();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('uc-step-link-s1')));
      await tester.tap(find.byKey(const ValueKey('uc-step-link-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('orders').last);
      await tester.pumpAndSettle();
      expect(u.stepById('s1')!.links.single, TraceLink(wc.mainEr.docId, 'o'));
      final chip = find.descendant(of: find.byKey(const ValueKey('uc-step-s1')), matching: find.text('ER Diagram · orders'));
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(view, findsNothing, reason: 'ไปที่เอกสาร ER');
      expect(wc.activeId, wc.mainEr.docId);
    });

    testWidgets('ลิงก์ที่ขาดแสดงเป็นป้ายเตือน ไม่ล้ม', (tester) async {
      await boot(tester);
      seedApp();
      wc.deleteDocument(wApi.id);
      wc.showUseCases();
      await tester.pumpAndSettle();
      expect(find.text('(ลิงก์ที่ขาด)'), findsWidgets);
      expect(find.byKey(const ValueKey('uc-issue-uc_link_broken')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ผูก REQ จากแผงขวา ; ความครอบคลุมอัปเดต ; ลบ Use Case ได้', (tester) async {
      await boot(tester);
      final r = wc.addRequirement(text: 'จองห้องออนไลน์');
      final u = seedApp();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('uc-cover-head')), findsOneWidget);
      expect(find.text('ครอบคลุมความต้องการ 0 / 1 ข้อ'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('uc-req-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('จองห้องออนไลน์').last);
      await tester.pumpAndSettle();
      expect(u.reqIds, [r.id]);
      expect(find.text('ครอบคลุมความต้องการ 1 / 1 ข้อ'), findsOneWidget);
      expect(find.byKey(ValueKey('uc-req-${r.id}')), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('uc-delete-${u.id}')));
      await tester.pumpAndSettle();
      expect(wc.useCases, isEmpty);
      expect(find.byKey(const ValueKey('uc-empty')), findsOneWidget);
    });

    testWidgets('แท็บเอกสาร: แสดงทุก Use Case อ่านอย่างเดียว ; ปุ่มส่งออกปิดเมื่อว่าง', (tester) async {
      await boot(tester);
      expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('uc-export'))).onPressed, isNull);
      seedApp();
      seedApp(name: 'ชำระเงิน', actor: 'Guest');
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('uc-export'))).onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('uc-tab-doc')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('uc-doc')), findsOneWidget);
      for (final u in wc.useCases) {
        expect(find.byKey(ValueKey('uc-doc-${u.id}')), findsOneWidget);
      }
      expect(find.textContaining('2a'), findsWidgets);
      expect(find.byType(TextField), findsNothing, reason: 'แท็บเอกสารแก้ไม่ได้');
      expect(tester.takeException(), isNull);
    });

    testWidgets('เลือก Use Case จากรายการ ; ค้นหากรองรายการ', (tester) async {
      await boot(tester);
      final a = seedApp(name: 'ค้นหาห้อง', actor: 'Guest');
      final b = seedApp(name: 'เพิ่มห้อง', actor: 'Admin');
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('uc-editor-${a.id}')), findsOneWidget, reason: 'เริ่มที่ข้อแรก');
      await tester.tap(find.byKey(ValueKey('uc-item-${b.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('uc-editor-${b.id}')), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('uc-search')), matching: find.byType(TextField)), 'ค้น');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('uc-item-${a.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('uc-item-${b.id}')), findsNothing);
    });

    testWidgets('พื้นที่แคบ (900px ปิดตัวสำรวจ): ไม่ล้น ; ภาษาอังกฤษ: ไม่มีข้อความไทยหลุดในโครงหน้า', (tester) async {
      await boot(tester, lang: Lang.en, size: const Size(900, 900), explorer: false);
      seedApp(name: 'Book a room', actor: 'Guest');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final thai = RegExp(r'[฀-๿]');
      const data = {'เลือกห้อง', 'ตรวจห้องว่าง', 'บันทึกการจอง', 'จองห้องได้ในครั้งเดียว', 'ห้องเต็ม', 'เสนอห้องอื่น', 'ชำระเงินไม่สำเร็จ', 'ยกเลิกการจอง'};
      for (final t in tester.widgetList<Text>(find.descendant(of: view, matching: find.byType(Text)))) {
        final s = t.data ?? t.textSpan?.toPlainText() ?? '';
        if (data.any(s.contains)) continue;
        expect(thai.hasMatch(s), isFalse, reason: s);
      }
    });
  });
}
