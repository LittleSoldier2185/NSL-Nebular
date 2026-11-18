import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/flowchart_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/flowchart_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/flowchart/fc_library.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// Phase 4: คลังรูปทรง Flowchart แบบหมวด + ค้นหา + มุมมองรายชื่อ
void main() {
  test('ทุกรูปทรงอยู่ในหมวดเดียวพอดี', () {
    final all = [for (final l in kFcShapeCategories.values) ...l];
    expect(all.length, FcShape.values.length);
    expect(all.toSet(), FcShape.values.toSet());
    expect(kFcShapeCategories.keys.toList(), FcShapeCategory.values);
  });

  test('ข้อความค้นหามีทั้งชื่อมาตรฐาน ป้ายไทย และชื่อในไฟล์', () {
    final t = fcShapeSearchText(FcShape.paperTape);
    expect(t, contains('paper tape'));
    expect(t, contains('เทปกระดาษ'));
    expect(t, contains('papertape'));
  });

  late WorkspaceController w;

  Future<FlowchartController> boot(WidgetTester tester, {Lang lang = Lang.th}) async {
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang, showExplorer: true)));
    w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    w.addDocument(DocType.flowchart, name: 'Flow');
    await tester.pumpAndSettle();
    return tester.element(find.byType(HomePage)).read<FlowchartController>();
  }

  Finder tiles() => find.byWidgetPredicate((wd) => wd.key is ValueKey<String> && (wd.key! as ValueKey<String>).value.startsWith('fc-shape-'));

  Future<void> search(WidgetTester tester, String q) async {
    await tester.enterText(find.byKey(const ValueKey('fc-search')), q);
    await tester.pumpAndSettle();
  }

  testWidgets('แสดง 5 หมวดและครบทุกรูปทรง ; คลิกช่อง = เลือกเครื่องมือวางรูปทรงนั้น', (tester) async {
    final f = await boot(tester);
    for (final c in FcShapeCategory.values) {
      expect(find.byKey(ValueKey('fc-lib-cat-${c.name}')), findsOneWidget);
    }
    expect(tiles(), findsNWidgets(FcShape.values.length));
    await tester.ensureVisible(find.byKey(const ValueKey('fc-shape-summingJunction')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fc-shape-summingJunction')));
    await tester.pump();
    expect((f.tool, f.toolShape), (FcTool.shape, FcShape.summingJunction));
    expect(tester.takeException(), isNull);
  });

  testWidgets('พับหมวดได้ ; ค้นหาแล้วกางทุกหมวดที่มีผล', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('fc-lib-cat-data')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fc-shape-paperTape')), findsNothing);
    expect(find.byKey(const ValueKey('fc-shape-process')), findsOneWidget);

    await search(tester, 'เทป');
    expect(find.byKey(const ValueKey('fc-shape-paperTape')), findsOneWidget); // หมวดที่พับไว้กางเองตอนค้นหา
    expect(find.byKey(const ValueKey('fc-shape-sequentialData')), findsOneWidget);
    expect(tiles(), findsNWidgets(2));
    expect(find.byKey(const ValueKey('fc-lib-cat-basic')), findsNothing); // หมวดที่ไม่มีผลถูกซ่อน

    await search(tester, 'merge');
    expect(tiles(), findsOneWidget);
    await search(tester, 'zzzz');
    expect(find.text('ไม่พบรูปทรงที่ตรงกับคำค้น'), findsOneWidget);
  });

  testWidgets('สลับมุมมองรายชื่อ: แสดงชื่อมาตรฐาน · ป้ายไทย และยังคลิกเลือกได้', (tester) async {
    final f = await boot(tester);
    await tester.tap(find.byKey(const ValueKey('fc-lib-view')));
    await tester.pumpAndSettle();
    expect(find.text('Process · กระบวนการ'), findsOneWidget);
    await tester.ensureVisible(find.text('Delay · รอ/หน่วงเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delay · รอ/หน่วงเวลา'));
    await tester.pump();
    expect(f.toolShape, FcShape.delay);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ลากจากคลังไปวางบนแคนวาส = ได้สัญลักษณ์ใหม่ชนิดนั้น', (tester) async {
    final f = await boot(tester);
    final from = tester.getCenter(find.byKey(const ValueKey('fc-shape-delay')));
    final to = tester.getCenter(find.byKey(const ValueKey('fc-canvas')));
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await g.moveTo(to, timeStamp: const Duration(milliseconds: 100));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(f.diagram.nodes.map((n) => n.shape), [FcShape.delay]);
  });

  testWidgets('ภาษาอังกฤษ: หมวดและชื่อในคลังไม่มีไทย', (tester) async {
    await boot(tester, lang: Lang.en);
    addTearDown(() => currentLang = Lang.th);
    expect(find.text('Data & storage'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fc-lib-view')));
    await tester.pumpAndSettle();
    final thai = RegExp(r'[฀-๿]');
    final lib = find.byType(FcShapeLibrary);
    for (final t in tester.widgetList<Text>(find.descendant(of: lib, matching: find.byType(Text)))) {
      expect(thai.hasMatch(t.data ?? t.textSpan?.toPlainText() ?? ''), isFalse, reason: t.data);
    }
  });
}
