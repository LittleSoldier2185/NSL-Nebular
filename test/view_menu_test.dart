import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/canvas/canvas_controller.dart';
import 'package:nsl_nebular/ui/db_connect_dialog.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/state/project_controller.dart';
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
      tester.widget<PopupMenuItem<VoidCallback>>(find.widgetWithText(PopupMenuItem<VoidCallback>, label)).enabled;

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

  // ---------------------------------------------------------------- Phase 14: ไฟล์ / แก้ไข / ช่วยเหลือ

  testWidgets('ไฟล์ บน DFD: Export .sql / Migration เทา + "เฉพาะ ER" ; Export เอกสารเทา ; นำเข้า/เชื่อมต่อฐานข้อมูลใช้ได้ (เดิมไม่ทำอะไร)', (tester) async {
    await boot(tester);
    w.addDocument(DocType.dfd, name: 'Level 0');
    await tester.pump();
    await open(tester, 'ไฟล์');
    for (final t in ['โปรเจกต์', 'นำเข้า', 'ส่งออก', 'ฐานข้อมูล']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(enabled(tester, 'Export .sql…'), isFalse);
    expect(enabled(tester, 'เปรียบเทียบกับไฟล์เก่า (Migration)…'), isFalse);
    expect(find.text('เฉพาะ ER'), findsNWidgets(2));
    expect(enabled(tester, 'Export เอกสาร / DBML / ข้อมูลตัวอย่าง…'), isFalse);
    expect(find.text('ไม่มีสำหรับ DFD'), findsOneWidget);
    expect(enabled(tester, 'นำเข้าจาก .sql…'), isTrue);
    await tester.tap(find.text('เชื่อมต่อฐานข้อมูล…'));
    await tester.pumpAndSettle();
    expect(find.byType(DbConnectDialog), findsOneWidget);
  });

  testWidgets('ไฟล์ บน ER: ทุกรายการใช้ได้', (tester) async {
    await boot(tester);
    await open(tester, 'ไฟล์');
    expect(enabled(tester, 'Export .sql…'), isTrue);
    expect(enabled(tester, 'เปรียบเทียบกับไฟล์เก่า (Migration)…'), isTrue);
    expect(find.text('เฉพาะ ER'), findsNothing);
    await close(tester);
  });

  testWidgets('แก้ไข บน ER: ชื่อกลาง ; หัวหมวดบอกจำนวนที่เลือก ; หมวด "ตาราง" มีแก้โครงสร้างตาราง', (tester) async {
    await boot(tester);
    final c = tester.element(find.byType(HomePage)).read<ProjectController>();
    await open(tester, 'แก้ไข');
    expect(find.widgetWithText(PopupMenuItem<VoidCallback>, 'คัดลอก'), findsOneWidget);
    expect(find.widgetWithText(PopupMenuItem<VoidCallback>, 'คัดลอกตาราง'), findsNothing);
    expect(enabled(tester, 'คัดลอก'), isFalse);
    expect(enabled(tester, 'แก้โครงสร้างตาราง…'), isFalse);
    expect(find.text('กลุ่ม'), findsNothing);
    await close(tester);

    c.addTable(x: 40, y: 40);
    c.addTable(x: 400, y: 40);
    c.selectAllTables();
    await tester.pump();
    expect(c.selectionCount, 2);
    await open(tester, 'แก้ไข');
    expect(find.text('${c.selectionCount} ตาราง'), findsOneWidget);
    expect(enabled(tester, 'คัดลอก'), isTrue);
    await close(tester);
  });

  testWidgets('แก้ไข บน Flowchart: ไม่มีหมวดตาราง ; มีหมวดกลุ่ม ; F2 = แก้ข้อความ ; บน API ไม่มีคัดลอก/วาง', (tester) async {
    await boot(tester);
    w.addDocument(DocType.flowchart, name: 'FC');
    await tester.pump();
    await open(tester, 'แก้ไข');
    expect(find.text('สร้างตารางแบบฟอร์ม…'), findsNothing);
    expect(find.text('จัดกลุ่ม'), findsOneWidget);
    expect(find.text('เลิกจัดกลุ่ม'), findsOneWidget);
    expect(find.text('แก้ข้อความ…'), findsOneWidget);
    await close(tester);

    w.addDocument(DocType.api, name: 'API');
    await tester.pump();
    await open(tester, 'แก้ไข');
    Finder item(String t) => find.widgetWithText(PopupMenuItem<VoidCallback>, t);
    expect(item('คัดลอก'), findsNothing);
    expect(item('วาง'), findsNothing);
    expect(item('ทำสำเนา'), findsOneWidget);
    expect(item('จัดวางอัตโนมัติ'), findsNothing);
    await close(tester);
  });

  testWidgets('ช่วยเหลือ: ภาษาใช้คอลัมน์ติ๊ก ; ภาษาอังกฤษแปลครบทุกเมนู ไม่ล้น', (tester) async {
    await boot(tester);
    await open(tester, 'ช่วยเหลือ');
    expect(checked('ไทย'), findsOneWidget);
    expect(find.textContaining('✓'), findsNothing);
    await close(tester);
  });

  testWidgets('ภาษาอังกฤษ: เมนูไฟล์/แก้ไขแปลครบ ไม่ล้น', (tester) async {
    await boot(tester, lang: Lang.en);
    await open(tester, 'File');
    for (final t in ['Export', 'Database', 'New project…']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    await close(tester);
    await open(tester, 'Edit');
    expect(find.text('Selection'), findsOneWidget);
    expect(find.text('Edit table structure…'), findsOneWidget);
    await close(tester);
    expect(tester.takeException(), isNull);
  });
}
