import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/dfd_model.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/export/workspace_summary.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/validate/workspace_validator.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/ui/project_home.dart';
import 'package:provider/provider.dart';

/// หน้า Project Home (ขั้น 9 ; ออกแบบใหม่ใน Phase 3 ตาม design/project/Home.dc.html)
void main() {
  late WorkspaceController w;
  final home = find.byKey(const ValueKey('project-home'));

  Future<void> boot(WidgetTester tester, {Lang lang = Lang.th, Size size = const Size(1440, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang, showExplorer: true)));
    w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    await tester.pump();
  }

  /// ER หลักมี 2 ตาราง (3 คอลัมน์) ; DFD 1 อันมีกระบวนการไม่มีชื่อ (ให้เกิดปัญหา)
  ProjectDocument seed() {
    w.mainEr.project.tables
      ..add(TableModel(id: 'a', name: 'users', columns: [ColumnModel(id: 'a1', name: 'id'), ColumnModel(id: 'a2', name: 'name')]))
      ..add(TableModel(id: 'b', name: 'orders', columns: [ColumnModel(id: 'b1', name: 'id')]));
    final d = w.addDocument(DocType.dfd, name: 'Level 0')!;
    d.dfd!.nodes.add(DfdNode(id: 'n1', kind: DfdKind.process, name: '', number: '1.0'));
    return d;
  }

  Future<void> openHome(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('explorer-home')));
    await tester.pump();
  }

  String txt(WidgetTester tester, String k) => tester.widget<Text>(find.byKey(ValueKey(k))).data!;

  testWidgets('เปิดจากปุ่มในตัวสำรวจโปรเจกต์ ; ปกติไม่แสดง', (tester) async {
    await boot(tester);
    expect(home, findsNothing);
    await openHome(tester);
    expect(home, findsOneWidget);
    expect(w.homeView, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('เปิดจากเมนูมุมมอง และจาก command palette', (tester) async {
    await boot(tester);
    await tester.tap(find.text('มุมมอง'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project Home'));
    await tester.pumpAndSettle();
    expect(home, findsOneWidget);

    w.openDocument(w.mainEr.docId);
    await tester.pump();
    expect(home, findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Project Home');
    await tester.pumpAndSettle();
    await tester.tap(find.text('หน้า Project Home').last);
    await tester.pumpAndSettle();
    expect(home, findsOneWidget);
  });

  testWidgets('การ์ดรายชนิด: จำนวนเอกสารและบรรทัดสรุปตรงกับ workspaceCounts ; ชนิดที่ไม่มี = 0 และปุ่ม "สร้าง"', (tester) async {
    await boot(tester);
    final d = seed();
    final e2 = w.addDocument(DocType.er, name: 'Billing')!;
    await openHome(tester);
    final c = workspaceCounts(w.workspace);
    expect(txt(tester, 'home-type-count-er'), '${c.ers}');
    expect(txt(tester, 'home-type-count-dfd'), '${c.dfds}');
    expect(txt(tester, 'home-type-count-flowchart'), '0');
    expect(txt(tester, 'home-type-detail-er'), '${c.tables} ตาราง · ${c.relations} ความสัมพันธ์');
    expect(txt(tester, 'home-type-detail-dfd'), '1 กระบวนการ · 0 คลังข้อมูล');
    expect(txt(tester, 'home-type-detail-wireframe'), 'ยังไม่มีเอกสารชนิดนี้');
    expect(find.descendant(of: find.byKey(const ValueKey('home-type-open-er')), matching: find.text('เปิด')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('home-type-open-flowchart')), matching: find.text('สร้าง')), findsOneWidget);
    expect(txt(tester, 'home-doc-count'), '3 เอกสาร');
    // ทุกเอกสารอยู่ในรายการ "เอกสารล่าสุด"
    for (final id in [w.mainEr.docId, d.id, e2.id]) {
      expect(find.byKey(ValueKey('home-card-$id')), findsOneWidget);
    }
  });

  testWidgets('ปุ่มเปิดของการ์ดชนิด: มีเอกสาร = เปิดตัวนั้น ; ไม่มี = สร้างใหม่', (tester) async {
    await boot(tester);
    final d = seed();
    await openHome(tester);
    await tester.tap(find.byKey(const ValueKey('home-type-open-dfd')));
    await tester.pumpAndSettle();
    expect(home, findsNothing);
    expect(w.activeId, d.id);

    await openHome(tester);
    final before = w.documents.length;
    await tester.tap(find.byKey(const ValueKey('home-type-open-screenflow')));
    await tester.pumpAndSettle();
    expect(w.documents.length, before + 1);
    expect(w.activeDocument.type, DocType.screenflow);
  });

  testWidgets('เอกสารล่าสุด: เรียงตามที่เปิดล่าสุดก่อน ; ที่ยังไม่เปิดต่อท้ายตามลำดับในไฟล์', (tester) async {
    await boot(tester);
    final d = seed(); // addDocument เปิดเอกสารใหม่ = ล่าสุด
    final f = w.addDocument(DocType.flowchart, name: 'Flow')!;
    w.openDocument(d.id);
    expect(w.recentDocuments.map((x) => x.id).toList(), [d.id, f.id, w.mainEr.docId]);
    await openHome(tester);
    final ys = [for (final id in [d.id, f.id, w.mainEr.docId]) tester.getTopLeft(find.byKey(ValueKey('home-card-$id'))).dy];
    expect(ys[0], lessThan(ys[1]));
    expect(ys[1], lessThan(ys[2]));
  });

  testWidgets('ปัญหาข้ามเอกสาร: ที่เก็บข้อมูลผูกกับตารางที่ถูกลบ ขึ้นในแผง กดแล้วไปที่ DFD', (tester) async {
    await boot(tester);
    seed();
    await openHome(tester);
    expect(find.descendant(of: find.byKey(const ValueKey('home-cross-count')), matching: find.text('0')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-cross-0')), findsNothing);

    final dfd = w.addDocument(DocType.dfd, name: 'Store doc')!;
    dfd.dfd!.nodes.add(DfdNode(id: 's1', kind: DfdKind.store, name: 'Orders', tableId: 'gone', tableDocId: w.mainEr.docId));
    await openHome(tester);
    expect(find.descendant(of: find.byKey(const ValueKey('home-cross-count')), matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('home-cross-0')), matching: find.text('ที่เก็บข้อมูลผูกกับตารางที่ไม่มีแล้ว')),
        findsOneWidget);
    // ปัญหาในเอกสารเดียว (กระบวนการไม่มีชื่อ) ไม่อยู่ในแผงนี้
    expect(find.byKey(const ValueKey('home-cross-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home-cross-0')));
    await tester.pumpAndSettle();
    expect(home, findsNothing);
    expect(w.activeId, dfd.id);
  });

  testWidgets('ป้ายปัญหาที่การ์ดรวมกันเท่ากับตัวเลขสรุป', (tester) async {
    await boot(tester);
    final d = seed();
    await openHome(tester);
    expect(find.byKey(ValueKey('home-issues-${d.id}')), findsOneWidget);
    final n = countIssues(validateWorkspace(w.workspace).map((x) => x.issue));
    final total = n.errors + n.warnings;
    expect(txt(tester, 'home-issue-totals'), 'ปัญหาทั้งโปรเจกต์: ${n.errors} ข้อผิดพลาด · ${n.warnings} คำเตือน →');
    var sum = 0;
    for (final doc in w.documents) {
      final f = find.descendant(of: find.byKey(ValueKey('home-issues-${doc.id}')), matching: find.byType(Text));
      if (f.evaluate().isNotEmpty) sum += int.parse(tester.widget<Text>(f).data!);
    }
    expect(total, greaterThan(0));
    expect(sum, total);
  });

  testWidgets('คลิกการ์ด = เปิดเอกสารและออกจากหน้า Home ; เอกสารที่ใช้งานอยู่แล้วก็ออก ; คลิกตัวสำรวจก็ออก', (tester) async {
    await boot(tester);
    final d = seed();
    w.openDocument(w.mainEr.docId);
    await openHome(tester);
    await tester.tap(find.byKey(ValueKey('home-card-${d.id}')));
    await tester.pumpAndSettle();
    expect(home, findsNothing);
    expect(w.activeId, d.id);

    await openHome(tester);
    await tester.tap(find.byKey(ValueKey('home-card-${d.id}'))); // ใช้งานอยู่แล้ว
    await tester.pumpAndSettle();
    expect(home, findsNothing);

    await openHome(tester);
    await tester.tap(find.byKey(ValueKey('explorer-row-${w.mainEr.docId}')));
    await tester.pumpAndSettle();
    expect(home, findsNothing);
    expect(w.activeId, w.mainEr.docId);
  });

  Future<void> addVia(WidgetTester tester, String type) async {
    await tester.tap(find.byKey(const ValueKey('home-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('home-add-$type')));
    await tester.pumpAndSettle();
  }

  testWidgets('ปุ่ม "+ เอกสารใหม่" (เมนูทุกชนิด) / ปัญหาทั้งโปรเจกต์', (tester) async {
    await boot(tester);
    await openHome(tester);
    await tester.tap(find.byKey(const ValueKey('home-new')));
    await tester.pumpAndSettle();
    for (final t in DocType.values) {
      expect(find.byKey(ValueKey('home-add-${t.name}')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('home-add-dfd')));
    await tester.pumpAndSettle();
    expect(w.activeDocument.type, DocType.dfd);
    expect(home, findsNothing);

    await openHome(tester);
    await addVia(tester, 'er');
    expect(w.activeDocument.type, DocType.er);
    expect(w.documents.length, 3);

    await openHome(tester);
    await tester.tap(find.byKey(const ValueKey('home-issues')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-issues')), findsOneWidget);
  });

  testWidgets('แสดงสถานะบันทึก ; การเปิดหน้า Home ไม่ทำให้โปรเจกต์ dirty', (tester) async {
    await boot(tester);
    await openHome(tester);
    expect(w.dirty, isFalse);
    expect(find.byKey(const ValueKey('home-dirty')), findsNothing);
    w.addDocument(DocType.dfd);
    await openHome(tester);
    expect(find.descendant(of: home, matching: find.text('● ยังไม่ได้บันทึก')), findsOneWidget);
    expect(find.text('ยังไม่ได้บันทึกเป็นไฟล์'), findsOneWidget);
  });

  testWidgets('ภาษาอังกฤษ: ไม่มีข้อความไทยหลุดในหน้า Home', (tester) async {
    await boot(tester, lang: Lang.en);
    seed();
    await openHome(tester);
    expect(find.text('+ New document'), findsOneWidget);
    expect(find.text('Recent documents'), findsOneWidget);
    expect(find.text('Cross-document issues'), findsOneWidget);
    expect(find.text('Not saved to a file yet'), findsOneWidget);
    final thai = RegExp(r'[฀-๿]');
    final texts = tester.widgetList<Text>(find.descendant(of: home, matching: find.byType(Text)));
    for (final t in texts) {
      expect(thai.hasMatch(t.data ?? ''), isFalse, reason: t.data);
    }
    currentLang = Lang.th;
  });

  testWidgets('พื้นที่แคบ (360px): หน้า Home ไม่ล้น แม้ชื่อเอกสารยาว', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final wc = WorkspaceController();
    addTearDown(wc.dispose);
    wc.mainEr.project.tables.add(TableModel(id: 'a', name: 'users', columns: [ColumnModel(id: 'a1', name: 'id')]));
    wc.addDocument(DocType.er, name: 'ชื่อแผนภาพที่ยาวมากมากมากมากมากมากมากมากมากมากมาก');
    wc.addDocument(DocType.dfd, name: 'Level 0');
    wc.showHome();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: wc,
      child: const MaterialApp(home: Scaffold(body: ProjectHomeView())),
    ));
    expect(home, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
