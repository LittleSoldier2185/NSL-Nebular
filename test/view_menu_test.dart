import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/canvas/canvas_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// เมนูมุมมอง/เครื่องมือแบบใหม่ (ตามแบบใน Artifact "เมนูมุมมองใหม่"): หมวด + คอลัมน์ติ๊ก + เปลี่ยนตามชนิดเอกสาร + คีย์ลัดใหม่
void main() {
  late WorkspaceController w;
  late CanvasController cv;
  late AppSettings s;

  Future<void> boot(WidgetTester tester, {Lang lang = Lang.th}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => currentLang = Lang.th);
    s = AppSettings(lang: lang, showExplorer: true);
    await tester.pumpWidget(NslDevApp(settings: s));
    final ctx = tester.element(find.byType(HomePage));
    w = ctx.read<WorkspaceController>();
    cv = ctx.read<CanvasController>();
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, String menu) async {
    await tester.tap(find.text(menu));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey k, {bool shift = false}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(k);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String label) =>
      tester.widget<PopupMenuItem<VoidCallback>>(find.ancestor(of: find.text(label), matching: find.byType(PopupMenuItem<VoidCallback>))).enabled;

  Finder checked(String label) => find.byKey(ValueKey('menu-checked-$label'));

  testWidgets('ER: มีหมวด แผง/หน้า/แคนวาส(ER) ; ติ๊กอยู่คอลัมน์แยก ; รายการค่าแคนวาสของ ER ครบ', (tester) async {
    await boot(tester);
    await open(tester, 'มุมมอง');
    for (final t in ['แผง', 'หน้า', 'แคนวาส', 'ER']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(checked('ตัวสำรวจโปรเจกต์'), findsOneWidget);
    expect(checked('จัดแนวตามตาราง (Snap)'), findsOneWidget);
    expect(find.text('ขนาดกระดาน…'), findsOneWidget);
    expect(find.text('เส้นความสัมพันธ์ (FK)…'), findsOneWidget);
    expect(enabled(tester, 'SQL Preview'), isTrue);
    // เครื่องมือย้ายออกไปเมนูเครื่องมือ
    expect(find.text('Mock Server'), findsNothing);
    expect(find.text('สร้างโค้ด'), findsNothing);
    await close(tester);
  });

  testWidgets('ER: SQL Preview / ปัญหาในเอกสารนี้ สลับแผงล่าง (กดซ้ำ = ย่อ) ; ติ๊กตามแท็บที่แสดง', (tester) async {
    await boot(tester);
    cv.showDock(DockTab.sql);
    await tester.pump();
    await open(tester, 'มุมมอง');
    expect(checked('SQL Preview'), findsOneWidget);
    expect(checked('ปัญหาในเอกสารนี้'), findsNothing);
    await tester.tap(find.text('ปัญหาในเอกสารนี้'));
    await tester.pumpAndSettle();
    expect(cv.dockTab, DockTab.issues);
    expect(cv.dockCollapsed, isFalse);

    await ctrl(tester, LogicalKeyboardKey.keyI, shift: true); // กดซ้ำ = ย่อ
    expect(cv.dockCollapsed, isTrue);
    await ctrl(tester, LogicalKeyboardKey.keyJ); // Ctrl+J = เปิด SQL
    expect(cv.dockCollapsed, isFalse);
    expect(cv.dockTab, DockTab.sql);
  });

  testWidgets('DFD: SQL Preview เป็นสีเทา + ป้าย "เฉพาะ ER" ; ขนาดกระดาน/เส้น FK ซ่อน ; หมวดแคนวาสบอก DFD', (tester) async {
    await boot(tester);
    w.addDocument(DocType.dfd, name: 'Level 0');
    await tester.pump();
    await open(tester, 'มุมมอง');
    expect(enabled(tester, 'SQL Preview'), isFalse);
    expect(find.text('เฉพาะ ER'), findsOneWidget);
    expect(find.text('ขนาดกระดาน…'), findsNothing);
    expect(find.text('เส้นความสัมพันธ์ (FK)…'), findsNothing);
    expect(find.text('DFD'), findsWidgets);
    expect(find.text('จัดแนวตามตาราง (Snap)'), findsOneWidget);
    await close(tester);

    // Ctrl+Shift+I บน DFD = กล่องปัญหาเฉพาะเอกสารนี้
    await ctrl(tester, LogicalKeyboardKey.keyI, shift: true);
    expect(find.byKey(const ValueKey('workspace-issues')), findsOneWidget);
    expect(find.text('ปัญหาในเอกสารนี้'), findsOneWidget);
  });

  testWidgets('API (ไม่มีแคนวาส): ไม่มีหมวดแคนวาส ; พอดีหน้าจอ/ซูมใช้ไม่ได้', (tester) async {
    await boot(tester);
    w.addDocument(DocType.api, name: 'API');
    await tester.pump();
    await open(tester, 'มุมมอง');
    expect(find.text('แคนวาส'), findsNothing);
    expect(enabled(tester, 'พอดีหน้าจอ'), isFalse);
    await close(tester);
  });

  testWidgets('เมนูเครื่องมือ: ค้นหา/ตรวจ/สร้าง ; สร้างโค้ดเปิดหน้า และติ๊กเมื่อเปิดอยู่', (tester) async {
    await boot(tester);
    await open(tester, 'เครื่องมือ');
    for (final t in ['ค้นหา', 'ตรวจ', 'สร้าง', 'Command palette', 'ปัญหาทั้งโปรเจกต์…', 'สร้างโค้ด', 'Mock Server']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.byKey(const ValueKey('menu-mock-running')), findsNothing);
    await tester.tap(find.text('สร้างโค้ด'));
    await tester.pumpAndSettle();
    expect(w.page, WorkspacePage.codegen);
    await open(tester, 'เครื่องมือ');
    expect(checked('สร้างโค้ด'), findsOneWidget);
    await close(tester);
  });

  testWidgets('คีย์ลัดใหม่: Ctrl+B ตัวสำรวจ · Ctrl+H Home (กดซ้ำกลับ) · Ctrl+Shift+N แผงโน้ต · Ctrl+Shift+H ประวัติ · Ctrl+Shift+B สร้างโค้ด · Ctrl+Shift+P ปัญหาทั้งโปรเจกต์', (tester) async {
    await boot(tester);
    await ctrl(tester, LogicalKeyboardKey.keyB);
    expect(s.showExplorer, isFalse);
    await ctrl(tester, LogicalKeyboardKey.keyB);
    expect(s.showExplorer, isTrue);

    await ctrl(tester, LogicalKeyboardKey.keyH);
    expect(w.homeView, isTrue);
    await ctrl(tester, LogicalKeyboardKey.keyH);
    expect(w.homeView, isFalse);

    await ctrl(tester, LogicalKeyboardKey.keyN, shift: true);
    expect(w.notesPanel, isTrue);
    await ctrl(tester, LogicalKeyboardKey.keyN, shift: true);
    expect(w.notesPanel, isFalse);

    await ctrl(tester, LogicalKeyboardKey.keyH, shift: true);
    expect(w.page, WorkspacePage.history);
    await ctrl(tester, LogicalKeyboardKey.keyB, shift: true);
    expect(w.page, WorkspacePage.codegen);

    await ctrl(tester, LogicalKeyboardKey.keyP, shift: true);
    expect(find.text('ปัญหาที่ตรวจพบทั้งโปรเจกต์'), findsOneWidget);
  });

  testWidgets('ภาษาอังกฤษ: หมวดและรายการแปลครบ ไม่ล้น', (tester) async {
    await boot(tester, lang: Lang.en);
    await open(tester, 'View');
    for (final t in ['Panels', 'Pages', 'Canvas', 'Problems in this document', 'Note pins on canvas']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await close(tester);
    await open(tester, 'Tools');
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Check'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });
}
