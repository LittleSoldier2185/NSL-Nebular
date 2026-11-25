import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/layout/wireframe_slots.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/wireframe_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// แก้รายการของชิ้นที่มีหลายค่า (ตาราง แท็บ รายการ ฯลฯ) ในการ์ดใต้ชิ้นส่วน + ข้อความเดียวทับเฉพาะข้อความ
void main() {
  late WorkspaceController w;
  late WireframeController f;

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true)));
    w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    w.addDocument(DocType.wireframe, name: 'Home');
    await tester.pumpAndSettle();
    f = tester.element(find.byType(HomePage)).read<WireframeController>();
  }

  test('wfItemsKind: ตาราง/แท็บ/รายการ/เมนู = รายการหลายค่า ; ปุ่ม/ย่อหน้า/tree = ไม่ใช่', () {
    for (final k in [WfKind.table, WfKind.tabs, WfKind.list, WfKind.sidebar, WfKind.bottomNav, WfKind.stepper]) {
      expect(wfItemsKind(k), isTrue, reason: '$k');
    }
    for (final k in [WfKind.button, WfKind.paragraph, WfKind.textarea, WfKind.tree, WfKind.label]) {
      expect(wfItemsKind(k), isFalse, reason: '$k');
    }
  });

  testWidgets('ตาราง: การ์ดมีแถวต่อคอลัมน์ ; พิมพ์แล้วตารางเปลี่ยนสด ; บันทึกแล้ว undo ขั้นเดียว', (tester) async {
    await boot(tester);
    final t = f.addComponent(WfKind.table, 500, 300)!;
    final original = List.of(f.diagram.componentById(t.id)!.columns);
    f.beginEdit(t.id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wf-items-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('wf-inline-field')), findsNothing, reason: 'ไม่ใช้ช่องพิมพ์รวมที่บังทั้งชิ้น');
    expect(find.byKey(const ValueKey('wf-item-0')), findsOneWidget);
    expect(find.byKey(ValueKey('wf-item-${original.length - 1}')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('wf-item-0')), 'รหัส');
    await tester.pump();
    expect(f.diagram.componentById(t.id)!.columns.first, 'รหัส', reason: 'แสดงสดระหว่างพิมพ์');
    expect(f.editing, isNotNull);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(f.editing, isNull);
    expect(f.diagram.componentById(t.id)!.columns.first, 'รหัส');
    f.undo();
    await tester.pumpAndSettle();
    expect(f.diagram.componentById(t.id)!.columns, original, reason: 'ทั้งช่วงเป็นขั้นเดียว');
  });

  testWidgets('Esc = คืนค่าเดิม ; แถวว่าง = ลบรายการตอนบันทึก ; เพิ่มรายการ และ Enter เพิ่มต่อจากแถว', (tester) async {
    await boot(tester);
    final l = f.addComponent(WfKind.list, 500, 300)!;
    final before = f.diagram.componentById(l.id)!.items;
    f.beginEdit(l.id);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('wf-item-0')), 'เปลี่ยน');
    await tester.pump();
    expect(f.diagram.componentById(l.id)!.items.first, 'เปลี่ยน');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(f.diagram.componentById(l.id)!.items, before, reason: 'Esc คืนค่าเดิม');
    expect(f.editing, isNull);

    f.beginEdit(l.id);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wf-items-add')));
    await tester.pumpAndSettle();
    expect(f.diagram.componentById(l.id)!.items.length, before.length + 1);
    expect(f.diagram.componentById(l.id)!.items.last, 'รายการใหม่');
    await tester.tap(find.byKey(const ValueKey('wf-item-del-0')));
    await tester.pumpAndSettle();
    expect(f.diagram.componentById(l.id)!.items.length, before.length);
    expect(f.diagram.componentById(l.id)!.items.first, before[1]);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(f.editing, isNull);
  });

  testWidgets('ชิ้นที่หมุนอยู่ก็แก้รายการในการ์ดได้ (ไม่ขึ้นกับรูปทรง)', (tester) async {
    await boot(tester);
    final t = f.addComponent(WfKind.table, 500, 300)!;
    f.updateComponents([t.id], (c) => c.rotation = 15);
    f.beginEdit(t.id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wf-items-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('wf-item-0')), findsOneWidget);
  });

  testWidgets('ชิ้นข้อความเดียว (สวิตช์/ป้าย/ปุ่ม): ใช้การ์ดข้อความแบบเดียวกัน ; พิมพ์แล้วชิ้นเปลี่ยนสด ; Enter = บันทึก ; undo ขั้นเดียว', (tester) async {
    await boot(tester);
    final t = f.addComponent(WfKind.toggle, 500, 300)!;
    final before = f.diagram.componentById(t.id)!.text;
    f.beginEdit(t.id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wf-text-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('wf-items-card')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('wf-inline-field')), 'เปิดโหมดมืด');
    await tester.pump();
    expect(f.diagram.componentById(t.id)!.text, 'เปิดโหมดมืด', reason: 'แสดงสดระหว่างพิมพ์');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(f.editing, isNull);
    expect(f.diagram.componentById(t.id)!.text, 'เปิดโหมดมืด');
    f.undo();
    await tester.pumpAndSettle();
    expect(f.diagram.componentById(t.id)!.text, before);
  });

  testWidgets('ข้อความเดียว: Esc คืนค่าเดิม ; ชิ้นที่หมุนอยู่ก็แก้ได้ ; ย่อหน้าใช้ช่องหลายบรรทัดในการ์ด', (tester) async {
    await boot(tester);
    final b = f.addComponent(WfKind.button, 500, 300)!;
    f.updateComponents([b.id], (c) => c.rotation = 20);
    final before = f.diagram.componentById(b.id)!.text;
    f.beginEdit(b.id);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('wf-inline-field')), 'ยกเลิกนะ');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(f.diagram.componentById(b.id)!.text, before);
    expect(f.editing, isNull);

    final p = f.addComponent(WfKind.paragraph, 500, 500)!;
    f.beginEdit(p.id);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('wf-inline-field'))).maxLines, greaterThan(1));
  });

  test('wfKindHasText: ชนิดที่ไม่แสดงข้อความ = รูป ไอคอน เส้นคั่น แผนที่ ฯลฯ ; ปุ่ม/ป้าย/ตาราง/สวิตช์ = มี', () {
    for (final k in [WfKind.image, WfKind.icon, WfKind.divider, WfKind.map, WfKind.chart, WfKind.slider, WfKind.avatar]) {
      expect(wfKindHasText(k), isFalse, reason: '$k');
    }
    for (final k in [WfKind.button, WfKind.label, WfKind.table, WfKind.toggle, WfKind.tabs, WfKind.container]) {
      expect(wfKindHasText(k), isTrue, reason: '$k');
    }
  });

  group('ชิ้นที่ไม่มีข้อความ', () {
    testWidgets('F2 / ดับเบิลคลิก (beginEdit) ไม่เปิดช่องพิมพ์ ; แผงขวาไม่มีช่องข้อความ', (tester) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true)));
      final w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      w.addDocument(DocType.wireframe, name: 'Home');
      await tester.pumpAndSettle();
      final f = tester.element(find.byType(HomePage)).read<WireframeController>();
      final img = f.addComponent(WfKind.image, 400, 300)!;
      final btn = f.addComponent(WfKind.button, 700, 300)!;

      f.beginEdit(img.id);
      await tester.pumpAndSettle();
      expect(f.editing, isNull);
      f.selectBox(img.id);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wf-no-text')), findsOneWidget);

      f.beginEdit(btn.id);
      await tester.pumpAndSettle();
      expect(f.editing, isNotNull);
    });
  });

  testWidgets('คลิกที่อื่น = บันทึก (หลังเปิดการ์ดพ้นช่วงกันคลิกค้างจากดับเบิลคลิก) ; คลิกในการ์ดไม่บันทึก', (tester) async {
    await boot(tester);
    final b = f.addComponent(WfKind.button, 500, 300)!;
    f.beginEdit(b.id);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('wf-inline-field')), 'คลิกแล้วบันทึก');
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 450)));
    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('wf-text-card'))) + const Offset(6, 6)); // ขอบในของการ์ด
    await tester.pump();
    expect(f.editing, isNotNull, reason: 'คลิกในการ์ดไม่ใช่คลิกที่อื่น');
    await tester.tapAt(const Offset(900, 120)); // พื้นแคนวาสนอกการ์ด
    await tester.pumpAndSettle();
    expect(f.editing, isNull);
    expect(f.diagram.componentById(b.id)!.text, 'คลิกแล้วบันทึก');
  });

  group('แผงขวา: ตัวแก้รายการ', () {
    Future<void> openPanel(WidgetTester tester, String id) async {
      f.selectBox(id);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('wf-prop-items-add')));
      await tester.pumpAndSettle();
    }

    testWidgets('ตาราง: แถวต่อคอลัมน์ ; แก้ชื่อ / เพิ่ม / ลบ มีผลกับตาราง ; ช่องว่างตอนออกจากช่อง = ลบ', (tester) async {
      await boot(tester);
      final t = f.addComponent(WfKind.table, 500, 300)!;
      final n0 = f.diagram.componentById(t.id)!.columns.length;
      await openPanel(tester, t.id);
      expect(find.byKey(const ValueKey('wf-prop-item-0')), findsOneWidget);
      expect(find.byKey(ValueKey('wf-prop-item-${n0 - 1}')), findsOneWidget);
      expect(find.byKey(const ValueKey('wf-columns-x')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('wf-prop-item-0')), 'รหัส');
      await tester.testTextInput.receiveAction(TextInputAction.done); // Enter = เพิ่มคอลัมน์ต่อจากแถวนี้
      await tester.pumpAndSettle();
      var cols = f.diagram.componentById(t.id)!.columns;
      expect(cols.first, 'รหัส');
      expect(cols[1], 'คอลัมน์ใหม่');
      expect(cols.length, n0 + 1);

      await tester.ensureVisible(find.byKey(const ValueKey('wf-prop-item-del-1')));
      await tester.tap(find.byKey(const ValueKey('wf-prop-item-del-1')));
      await tester.pumpAndSettle();
      cols = f.diagram.componentById(t.id)!.columns;
      expect(cols.length, n0);
      expect(cols.contains('คอลัมน์ใหม่'), isFalse);

      await tester.ensureVisible(find.byKey(const ValueKey('wf-prop-items-add')));
      await tester.tap(find.byKey(const ValueKey('wf-prop-items-add')));
      await tester.pumpAndSettle();
      expect(f.diagram.componentById(t.id)!.columns.last, 'คอลัมน์ใหม่');
    });

    testWidgets('รายการ (list/tabs ฯลฯ) ใช้ตัวแก้เดียวกันกับข้อความ ; undo แล้วแผงโหลดค่าใหม่', (tester) async {
      await boot(tester);
      final l = f.addComponent(WfKind.list, 500, 300)!;
      final before = f.diagram.componentById(l.id)!.items;
      await openPanel(tester, l.id);
      await tester.enterText(find.byKey(const ValueKey('wf-prop-item-0')), 'ใหม่เอี่ยม');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(f.diagram.componentById(l.id)!.items.first, 'ใหม่เอี่ยม');
      f.undo();
      await tester.pumpAndSettle();
      expect(f.diagram.componentById(l.id)!.items, before);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('wf-prop-item-0'))).controller!.text, before.first);
    });

    testWidgets('จำนวนแถวตัวอย่าง: ปุ่ม − / + (0–12)', (tester) async {
      await boot(tester);
      final t = f.addComponent(WfKind.table, 500, 300)!;
      final r0 = f.diagram.componentById(t.id)!.rows;
      await openPanel(tester, t.id);
      await tester.ensureVisible(find.byKey(const ValueKey('wf-rows-inc')));
      await tester.tap(find.byKey(const ValueKey('wf-rows-inc')));
      await tester.pumpAndSettle();
      expect(f.diagram.componentById(t.id)!.rows, r0 + 1);
      await tester.tap(find.byKey(const ValueKey('wf-rows-dec')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wf-rows-dec')));
      await tester.pumpAndSettle();
      expect(f.diagram.componentById(t.id)!.rows, r0 - 1);
      expect(find.byKey(const ValueKey('wf-rows')), findsOneWidget);
    });
  });
}
