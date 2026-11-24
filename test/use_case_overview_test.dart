import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/cli/nebular_api.dart';
import 'package:nsl_nebular/core/export/html_doc_export.dart';
import 'package:nsl_nebular/core/export/markdown_export.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/requirement.dart' show TraceLink;
import 'package:nsl_nebular/core/models/use_case.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/storage/project_codec.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/ui/workspace_issues_dialog.dart';
import 'package:provider/provider.dart';

/// Phase 30: Use Case — ลากเรียง + ผลตรวจ/ส่งออก/CLI ระดับโปรเจกต์
void main() {
  /// Use Case ที่มีปัญหา : ไม่มีผู้กระทำ (error) + ทางเลือกที่ขั้น s2 ไม่บอกทางกลับ (error)
  UseCase seedBroken(WorkspaceController w) {
    final u = w.addUseCase(name: 'จองห้อง');
    w.updateUseCase(u.id, (x) {
      x.steps
        ..add(UcStep(id: 's1', text: 'เลือก'))
        ..add(UcStep(id: 's2', text: 'ยืนยัน'))
        ..add(UcStep(id: 's3', text: 'จบ'));
      x.branches.add(UcBranch(id: 'b1', atStepId: 's2', condition: 'ห้องเต็ม')); // ไม่จบ ไม่กลับ
    });
    return u;
  }

  group('แกน: ผลตรวจรวม / ส่งออก / CLI', () {
    late WorkspaceController w;
    setUp(() => w = WorkspaceController());
    tearDown(() => w.dispose());

    test('projectIssueCounts = ปัญหาของเอกสาร + Use Case ; ไม่มี Use Case = เท่ากับเดิม', () {
      final base = w.projectIssueCounts;
      expect(base.errors, w.workspaceIssues.where((i) => i.issue.severity.name == 'error').length);
      seedBroken(w);
      final uc = w.useCaseIssues;
      final c = w.projectIssueCounts;
      expect(c.errors, base.errors + uc.where((i) => i.severity.name == 'error').length);
      expect(c.warnings, base.warnings + uc.where((i) => i.severity.name == 'warning').length);
      expect(uc.map((i) => i.code), containsAll(['uc_no_actor', 'uc_branch_no_target']));
      final issue = uc.firstWhere((i) => i.code == 'uc_no_actor').toIssue();
      expect((issue.code, issue.tableId), ('uc_no_actor', uc.first.ucId));
    });

    test('showUseCase: ตั้งโฟกัสแล้วอ่านได้ครั้งเดียว ; เปิดหน้า Use Case ; อยู่หน้าเดิมแล้วก็แจ้งหน้าจอ', () {
      final u = seedBroken(w);
      var notified = 0;
      w.addListener(() => notified++);
      w.showUseCase(u.id, stepId: 's2');
      expect(w.page, WorkspacePage.useCases);
      final f = w.takeUseCaseFocus();
      expect((f?.id, f?.stepId), (u.id, 's2'));
      expect(w.takeUseCaseFocus(), isNull, reason: 'อ่านได้ครั้งเดียว');
      final before = notified;
      w.showUseCase(u.id); // อยู่หน้านี้แล้ว
      expect(notified, greaterThan(before), reason: 'ต้องแจ้งให้หน้าจอเลือกข้อใหม่');
    });

    test('ส่งออกทั้งโปรเจกต์ (Markdown/HTML/พจนานุกรม) มีส่วน Use Case ; ไม่มี Use Case = ไม่มีส่วนนี้', () {
      final none = exportWorkspaceDictionary(w.workspace);
      expect(none.contains('## Use Case'), isFalse);
      expect(exportHtmlDocument(w.workspace, includeDiagrams: false).contains('id="usecases"'), isFalse);

      final u = seedBroken(w);
      w.updateUseCase(u.id, (x) {
        x.actor = 'Guest';
        x.goal = 'จองห้องพัก';
      });
      final md = exportWorkspaceDictionary(w.workspace);
      expect(md, contains('## Use Case'));
      expect(md, contains('### UC-01 จองห้อง'));
      expect(md, contains('1. [ผู้ใช้] เลือก'));
      expect(md, contains('2a ห้องเต็ม'));
      final html = exportHtmlDocument(w.workspace, includeDiagrams: false);
      expect(html, contains('id="usecases"'));
      expect(html, contains('UC-01'));
      expect(html, contains('ห้องเต็ม'));
      expect(html, contains('<ol>'));
    });

    test('ส่งออกมี Use Case ทั้งกรณีโปรเจกต์ ER เดียว (ทางลัดเดิม) และหลายเอกสาร', () {
      seedBroken(w);
      expect(w.documents.length, 1, reason: 'ER เดียว');
      expect(exportWorkspaceDictionary(w.workspace), contains('## Use Case'));
      w.addDocument(DocType.dfd, name: 'DFD');
      expect(exportWorkspaceDictionary(w.workspace), contains('## Use Case'));
    });

    test('CLI: info นับ Use Case และรวมผลตรวจ ; validate รายงาน Use Case แยก type = usecase ; กรองระดับได้', () {
      final r0 = validateReport(w.workspace);
      expect(r0['issues'].where((i) => i['type'] == 'usecase'), isEmpty);
      final u = seedBroken(w);
      final info = projectInfo(w.workspace);
      expect(info['useCases'], 1);
      final infoIssues = info['issues'] as Map;
      final rep = validateReport(w.workspace);
      final ucItems = (rep['issues'] as List).where((i) => i['type'] == 'usecase').toList();
      expect(ucItems.map((i) => i['code']), containsAll(['uc_no_actor', 'uc_branch_no_target']));
      expect(ucItems.first['elementId'], u.id);
      expect(ucItems.firstWhere((i) => i['code'] == 'uc_branch_no_target')['stepId'], isNull, reason: 'ปัญหาของทางเลือกไม่ผูกขั้นเดียว');
      expect(infoIssues['errors'], rep['errors'], reason: 'info กับ validate นับตรงกัน');
      final onlyErrors = validateReport(w.workspace, minSeverity: parseSeverity('error'));
      expect((onlyErrors['issues'] as List).every((i) => i['severity'] == 'error'), isTrue);
      jsonEncode(rep); // แปลงเป็น JSON ได้
    });

    test('เขียน-อ่านไฟล์: ลำดับขั้นตอนที่ลากเรียงยังคงอยู่', () {
      final u = seedBroken(w);
      w.updateUseCase(u.id, (x) => x.steps.insert(0, x.steps.removeAt(2)));
      final copy = copyWorkspace(w.workspace);
      expect(copy.useCases.single.steps.map((s) => s.id), ['s3', 's1', 's2']);
    });
  });

  group('หน้าจอ', () {
    late WorkspaceController wc;
    Future<void> boot(WidgetTester tester, {Size size = const Size(1600, 950)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true)));
      wc = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      wc.showUseCases();
      await tester.pumpAndSettle();
    }

    Future<void> drag(WidgetTester tester, Finder handle, Offset by) async {
      await tester.ensureVisible(handle);
      await tester.pumpAndSettle();
      final g = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 50));
      await g.moveBy(Offset(0, by.dy / 2));
      await tester.pump(const Duration(milliseconds: 50));
      await g.moveBy(Offset(0, by.dy / 2));
      await tester.pump(const Duration(milliseconds: 50));
      await g.up();
      await tester.pumpAndSettle();
    }

    testWidgets('ลากมือจับขั้นตอนไปเรียงใหม่ : ลำดับเปลี่ยน เลขขั้นเปลี่ยน ทางเลือกยังชี้ขั้นเดิม ; ย้อนกลับได้', (tester) async {
      await boot(tester);
      final u = seedBroken(wc);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('uc-step-drag-s1')), findsOneWidget);
      final labelBefore = wc.useCaseById(u.id)!.branchLabel(u.branches.single);
      expect(labelBefore, '2a');

      // ลากขั้นที่ 3 ขึ้นไปบนสุด
      await drag(tester, find.byKey(const ValueKey('uc-step-drag-s3')), const Offset(0, -460));
      expect(wc.useCaseById(u.id)!.steps.map((s) => s.id), ['s3', 's1', 's2']);
      expect(wc.undoLabel, 'ย้ายขั้นตอน');
      // s2 กลายเป็นขั้นที่ 3 → ป้ายทางเลือกเปลี่ยนเป็น 3a (อ้างด้วย id จึงไม่พัง)
      expect(wc.useCaseById(u.id)!.branches.single.atStepId, 's2');
      expect(find.byKey(const ValueKey('uc-branch-label-b1')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('uc-branch-label-b1'))).data, '3a');

      wc.undo();
      await tester.pumpAndSettle();
      expect(wc.useCaseById(u.id)!.steps.map((s) => s.id), ['s1', 's2', 's3']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ปุ่ม ▲▼ ยังใช้ได้ (คีย์บอร์ด) คู่กับการลาก', (tester) async {
      await boot(tester);
      final u = seedBroken(wc);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('uc-step-down-s1')));
      await tester.tap(find.byKey(const ValueKey('uc-step-down-s1')));
      await tester.pumpAndSettle();
      expect(wc.useCaseById(u.id)!.steps.map((s) => s.id), ['s2', 's1', 's3']);
    });

    testWidgets('ลากเรียงทางเลือก/ข้อผิดพลาด : ป้าย a/b สลับตามลำดับ', (tester) async {
      await boot(tester);
      final u = seedBroken(wc);
      wc.updateUseCase(u.id, (x) => x.branches.add(UcBranch(id: 'b2', atStepId: 's2', condition: 'บัตรหมดอายุ', ends: true)));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('uc-branch-label-b1'))).data, '2a');
      expect(tester.widget<Text>(find.byKey(const ValueKey('uc-branch-label-b2'))).data, '2b');
      await drag(tester, find.byKey(const ValueKey('uc-branch-drag-b2')), const Offset(0, -330));
      expect(wc.useCaseById(u.id)!.branches.map((b) => b.id), ['b2', 'b1']);
      expect(tester.widget<Text>(find.byKey(const ValueKey('uc-branch-label-b2'))).data, '2a');
      expect(tester.widget<Text>(find.byKey(const ValueKey('uc-branch-label-b1'))).data, '2b');
    });

    testWidgets('หน้าต่างปัญหาทั้งโปรเจกต์: มีกลุ่ม Use Case ; กดแล้วไปหน้า Use Case เลือกข้อและเลื่อนไปที่ขั้นตอน', (tester) async {
      await boot(tester);
      final u = seedBroken(wc);
      // ลิงก์ขั้นตอน s3 ไปเอกสารที่ไม่มี → ปัญหาที่ผูกกับขั้นตอน
      wc.updateUseCase(u.id, (x) => x.stepById('s3')!.links.add(TraceLink('หาย')));
      final second = wc.addUseCase(name: 'ข้ออื่น', actor: 'Admin'); // ข้อที่สอง (ปัญหาน้อยกว่า) ไว้ให้มีการเปลี่ยนข้อ
      wc.showHome();
      await tester.pumpAndSettle();
      showWorkspaceIssues(tester.element(find.byType(HomePage)));
      await tester.pumpAndSettle();
      expect(find.text('Use Case'), findsWidgets);
      final broken = find.byKey(ValueKey('workspace-issue-uc-uc_link_broken-${u.id}'));
      expect(broken, findsOneWidget);
      await tester.ensureVisible(broken);
      await tester.tap(broken);
      await tester.pumpAndSettle();
      expect(wc.page, WorkspacePage.useCases);
      expect(find.byKey(ValueKey('uc-editor-${u.id}')), findsOneWidget, reason: 'เลือกข้อที่มีปัญหา ไม่ใช่ข้อแรกอื่น');
      expect(find.byKey(ValueKey('uc-editor-${second.id}')), findsNothing);
      expect(wc.takeUseCaseFocus(), isNull, reason: 'หน้าจออ่านคำขอไปแล้ว');
      expect(tester.takeException(), isNull);
    });

    testWidgets('หน้าต่างปัญหา: กรองเอกสารเดียว = ไม่แสดง Use Case ; สรุปรวมนับ Use Case', (tester) async {
      await boot(tester);
      seedBroken(wc);
      wc.showHome();
      await tester.pumpAndSettle();
      showWorkspaceIssues(tester.element(find.byType(HomePage)), docId: wc.mainEr.docId);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('workspace-issues')), findsOneWidget);
      expect(find.textContaining('workspace-issue-uc'), findsNothing);
      expect(find.byWidgetPredicate((w) => w.key.toString().contains('workspace-issue-uc')), findsNothing);
      await tester.tap(find.text('ปิด'));
      await tester.pumpAndSettle();

      showWorkspaceIssues(tester.element(find.byType(HomePage)));
      await tester.pumpAndSettle();
      final c = wc.projectIssueCounts;
      expect(tester.widget<Text>(find.byKey(const ValueKey('workspace-issues-summary'))).data, contains('${c.errors} ข้อผิดพลาด · ${c.warnings} คำเตือน'));
    });

    testWidgets('แถบสถานะบนหน้า Use Case และตัวเลขบน Home นับปัญหา Use Case ด้วย', (tester) async {
      await boot(tester);
      seedBroken(wc);
      await tester.pumpAndSettle();
      final c = wc.projectIssueCounts;
      expect(c.errors, greaterThan(0));
      expect(find.descendant(of: find.byKey(const ValueKey('status-issues')), matching: find.text('${c.errors} ข้อผิดพลาด · ${c.warnings} คำเตือน')), findsOneWidget);
      wc.showHome();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('home-issue-totals')));
      expect(tester.widget<Text>(find.byKey(const ValueKey('home-issue-totals'))).data, contains('${c.errors} ข้อผิดพลาด · ${c.warnings} คำเตือน'));
    });
    testWidgets('Home: แถบสรุป Use Case (แบบ B) — ยังไม่มี = ข้อความ + ปุ่มเริ่มเขียน (ไม่มีปุ่มส่งออก) ; กดแล้วเปิดหน้า Use Case', (tester) async {
      await boot(tester);
      wc.showHome();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-uc-strip')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-uc-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-uc-export')), findsNothing);
      expect(find.text('+ เริ่มเขียน Use Case'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('home-uc-open')));
      await tester.tap(find.byKey(const ValueKey('home-uc-open')));
      await tester.pumpAndSettle();
      expect(wc.page, WorkspacePage.useCases);
    });

    testWidgets('Home: แถบสรุปบอกจำนวนข้อ ขั้นตอน ความต้องการที่มี Use Case (มีแถบความคืบหน้า) และปัญหา ตรงกับข้อมูลจริง', (tester) async {
      await boot(tester);
      final r1 = wc.addRequirement(text: 'จอง');
      wc.addRequirement(text: 'ชำระเงิน');
      final u = seedBroken(wc);
      wc.updateUseCase(u.id, (x) => x.reqIds.add(r1.id));
      wc.addUseCase(name: 'ข้อสอง', actor: 'Admin');
      wc.showHome();
      await tester.pumpAndSettle();
      String t(String k) => tester.widget<Text>(find.byKey(ValueKey(k))).data!;
      expect(t('home-uc-count'), '2');
      expect(t('home-uc-steps'), '3');
      expect(t('home-uc-cover'), '1 / 2');
      expect(find.byType(LinearProgressIndicator), findsWidgets);
      final issues = wc.useCaseIssues.where((i) => i.severity.name != 'info').length;
      expect(issues, greaterThan(0));
      expect(t('home-uc-issues'), '$issues');
      expect(find.byKey(const ValueKey('home-uc-empty')), findsNothing);
      expect(find.byKey(const ValueKey('home-uc-export')), findsOneWidget);
      expect(find.text('เปิด Use Case →'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('home-uc-open')));
      await tester.tap(find.byKey(const ValueKey('home-uc-open')));
      await tester.pumpAndSettle();
      expect(wc.page, WorkspacePage.useCases);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Home: ไม่มีความต้องการ = ไม่แสดงช่องความครอบคลุม ; ไม่มีปัญหา = 0', (tester) async {
      await boot(tester);
      final u = wc.addUseCase(name: 'ครบ', actor: 'Guest');
      wc.updateUseCase(u.id, (x) => x.steps.add(UcStep(id: 's', text: 'ทำ')));
      wc.showHome();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-uc-cover')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const ValueKey('home-uc-issues'))).data, '0');
    });

  });
}
