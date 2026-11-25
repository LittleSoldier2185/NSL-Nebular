import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/wireframe_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/ui/wireframe/wf_panels.dart';
import 'package:provider/provider.dart';

/// แผงขวาของ Wireframe: ส่วนพับได้ + เลเยอร์ล่างสุด
void main() {
  late WorkspaceController w;
  late WireframeController f;

  Future<void> boot(WidgetTester tester, {Lang lang = Lang.th}) async {
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang, showExplorer: true)));
    final ctx = tester.element(find.byType(HomePage));
    w = ctx.read<WorkspaceController>();
    w.addDocument(DocType.wireframe, name: 'Home');
    await tester.pumpAndSettle();
    f = tester.element(find.byType(HomePage)).read<WireframeController>();
  }


  testWidgets('แผงสูงเต็มคอลัมน์ ; ภาพย่อ ; เลเยอร์อยู่ล่างสุด (ใต้ส่วนตรวจสอบ) ; หน้าจอว่าง = ข้อความว่าง', (tester) async {
    await boot(tester);
    final panel = find.byType(WireframeRightPanel);
    expect(tester.getSize(panel).height, greaterThan(800), reason: 'ไม่ใช่แค่ความสูงเนื้อหา');
    expect(find.byKey(const ValueKey('wf-page-thumb')), findsOneWidget);
    expect(find.byKey(const ValueKey('wf-panel-style')), findsOneWidget);
    expect(find.byKey(const ValueKey('wf-layers-empty')), findsOneWidget);
    // เลเยอร์ติดอยู่ล่างแผง (เลื่อนแยกจากส่วนบน) ; ส่วนตรวจสอบอยู่ในส่วนบน
    final layers = find.byKey(const ValueKey('wf-layers'));
    expect(tester.getBottomLeft(layers).dy, closeTo(tester.getBottomLeft(panel).dy, 1));
    expect(find.descendant(of: layers, matching: find.byKey(const ValueKey('wf-fold-checks-head'))), findsNothing);
    expect(find.byKey(const ValueKey('wf-fold-checks-head')), findsOneWidget);
    expect(find.byKey(const ValueKey('wf-fold-flow-head')), findsNothing, reason: 'ไม่มี Screen Flow ใช้ ไม่แสดงส่วนนี้');
  });

  testWidgets('คลิกหัวส่วน = พับ/กาง ; เนื้อหาที่พับไม่ถูกสร้าง ; สถานะจำข้ามการเลือกชิ้นส่วน', (tester) async {
    await boot(tester);
    Future<void> tapHead(String k) async {
      await tester.ensureVisible(find.byKey(ValueKey(k)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(k)));
    }

    expect(find.byKey(const ValueKey('wf-device')), findsNothing, reason: 'ขนาดหน้าจอพับอยู่ตอนเริ่ม');
    await tapHead('wf-fold-size-head');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wf-device')), findsOneWidget);
    expect(find.byKey(const ValueKey('wf-frame-w-1440')), findsOneWidget);

    await tapHead('wf-fold-look-head');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wf-panel-style')), findsNothing);
    await tapHead('wf-fold-look-head'); // คืนค่า
    await tapHead('wf-fold-size-head');
    await tester.pumpAndSettle();
  });

  testWidgets('เลเยอร์: บนสุดก่อน ; ลูกเยื้องเข้า ; คลิกแล้วเลือกชิ้น ; เลือกชิ้นแล้วเลเยอร์ยังอยู่ล่างสุดใต้คุณสมบัติ', (tester) async {
    await boot(tester);
    final box = f.addComponent(WfKind.container, 400, 300, text: 'กล่อง')!;
    final btn = f.addComponent(WfKind.button, 400, 300, text: 'ตกลง')!;
    await tester.pumpAndSettle();
    expect(find.text('2'), findsWidgets);

    final top = tester.getTopLeft(find.byKey(ValueKey('wf-item-${btn.id}'))).dy;
    final bottom = tester.getTopLeft(find.byKey(ValueKey('wf-item-${box.id}'))).dy;
    expect(top, lessThan(bottom), reason: 'ชิ้นที่วางทีหลัง (บนสุด) อยู่บนสุดของรายการ');
    double iconX(String id, IconData i) => tester.getTopLeft(find.descendant(of: find.byKey(ValueKey('wf-item-$id')), matching: find.byIcon(i))).dx;
    expect(iconX(btn.id, Icons.smart_button_outlined), greaterThan(iconX(box.id, Icons.crop_square_rounded)),
        reason: 'ปุ่มอยู่ในกล่อง = เยื้องเข้า');
    // ทั้งแถวเยื้อง (ช่องติ๊กก็ขยับ ไม่ใช่แค่ไอคอน) และกล่องบอกจำนวนชิ้นข้างใน
    double pickX(String id) => tester.getTopLeft(find.byKey(ValueKey('wf-pick-$id'))).dx;
    expect(pickX(btn.id), greaterThan(pickX(box.id)));
    expect(find.byKey(ValueKey('wf-kids-${box.id}')), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Tooltip && w.message == 'มี 1 ชิ้นข้างใน'), findsOneWidget);
    expect(find.byKey(ValueKey('wf-kids-${btn.id}')), findsNothing);

    await tester.ensureVisible(find.byKey(ValueKey('wf-item-${box.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('wf-item-${box.id}')));
    await tester.pumpAndSettle();
    expect(f.selectedIds, {box.id});
    // คุณสมบัติของชิ้นที่เลือกอยู่เหนือเลเยอร์
    expect(find.byKey(const ValueKey('wf-panel-style')), findsNothing);
    expect(find.byKey(const ValueKey('wf-bold')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('wf-layers')), matching: find.byKey(const ValueKey('wf-bold'))), findsNothing,
        reason: 'คุณสมบัติอยู่ส่วนบน ไม่ปนกับแผงเลเยอร์');
    expect(find.byKey(ValueKey('wf-item-${box.id}')), findsOneWidget, reason: 'เลือกชิ้นแล้วเลเยอร์ยังอยู่');

    // แผงซ้ายไม่มีรายการชิ้นส่วนแล้ว
    expect(find.descendant(of: find.byType(WireframeLeftPanel), matching: find.byKey(ValueKey('wf-item-${box.id}'))), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ตั้งค่าหน้าจอกดซ้ำได้หลายครั้ง (แผงวาดใหม่ทุกครั้ง): รูปแบบ ร่าง↔เรียบร้อย, สีเน้น, ขนาดหน้าจอ, กว้าง', (tester) async {
    await boot(tester);
    Future<void> tap(Finder x) async {
      await tester.ensureVisible(x);
      await tester.pumpAndSettle();
      await tester.tap(x);
      await tester.pumpAndSettle();
    }

    final style = find.byKey(const ValueKey('wf-panel-style'));
    for (final s in [WfStyle.clean, WfStyle.sketch, WfStyle.clean, WfStyle.sketch]) {
      await tap(find.descendant(of: style, matching: find.text(s == WfStyle.sketch ? 'ร่าง' : 'เรียบร้อย')));
      expect(f.diagram.style, s);
      expect(tester.widget<SegmentedButton<WfStyle>>(style).selected, {s}, reason: 'ปุ่มที่เลือกบนจอตรงกับค่าจริง');
    }

    final swatches = find.descendant(of: find.byType(WireframeRightPanel), matching: find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('wf-accent-')));
    expect(swatches, findsWidgets);
    final keys = [for (final e in tester.widgetList(swatches)) (e.key as ValueKey).value as String];
    final picks = keys.where((k) => RegExp(r'^wf-accent-\d+$').hasMatch(k)).take(3).toList();
    expect(picks.length, greaterThanOrEqualTo(2));
    final seen = <int>{};
    for (final k in [...picks, picks.first]) {
      await tap(find.byKey(ValueKey(k)));
      seen.add(f.diagram.accent);
    }
    expect(seen.length, picks.length, reason: 'กดสีต่าง ๆ ติดกันแล้วเปลี่ยนทุกครั้ง');

    await tap(find.byKey(const ValueKey('wf-fold-size-head')));
    for (final dev in [WfDevice.mobile, WfDevice.desktop, WfDevice.mobile]) {
      f.setDevice(dev); // ค่าเปลี่ยนจากที่อื่น (เช่น undo) ช่องในแผงต้องตามด้วย
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('wf-frame-w-${dev.width.round()}')), findsOneWidget);
    }
    for (final v in ['1000', '1100']) {
      final field = find.descendant(of: find.byKey(ValueKey('wf-frame-w-${f.diagram.width.round()}')), matching: find.byType(TextField));
      await tester.enterText(field, v);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(f.diagram.width, double.parse(v));
    }
    await tap(find.byKey(const ValueKey('wf-fold-size-head')));
  });

  testWidgets('แผงเลเยอร์ติดล่าง: เลือกชิ้นแล้วแถวไม่กระโดด ; ลากขอบบนปรับความสูง ; คลิกหัวพับ/กาง', (tester) async {
    await boot(tester);
    final a = f.addComponent(WfKind.button, 300, 200)!;
    f.cancelEditing();
    f.clearSelection();
    await tester.pumpAndSettle();
    final row = find.byKey(ValueKey('wf-item-${a.id}'));
    final y0 = tester.getTopLeft(row).dy;
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(f.selectedIds, {a.id});
    expect(tester.getTopLeft(row).dy, y0, reason: 'แผงด้านบนเปลี่ยนเป็นคุณสมบัติ แต่แถวเลเยอร์อยู่ที่เดิม');

    final layers = find.byKey(const ValueKey('wf-layers'));
    final h0 = tester.getSize(layers).height;
    await tester.drag(find.byKey(const ValueKey('wf-layers-resize')), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(tester.getSize(layers).height, greaterThan(h0 + 60));

    await tester.tap(find.byKey(const ValueKey('wf-fold-layers-head')));
    await tester.pumpAndSettle();
    expect(row, findsNothing);
    expect(tester.getSize(layers).height, lessThan(60));
    await tester.tap(find.byKey(const ValueKey('wf-fold-layers-head')));
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
  });

  testWidgets('ภาษาอังกฤษ: หัวส่วนและข้อความว่างแปลครบ', (tester) async {
    await boot(tester, lang: Lang.en);
    final thai = RegExp(r'[฀-๿]');
    final leaks = [
      for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(WireframeRightPanel), matching: find.byType(Text))))
        if (thai.hasMatch(t.data ?? '')) t.data,
    ];
    expect(leaks, isEmpty);
    expect(find.text('Layers'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
  });

  testWidgets('จัดแนวและกระจาย: เลือกชิ้นเดียวก็จัดชิดหน้าจอ/กึ่งกลางหน้าจอได้ ; เลือกหลายชิ้นมีสลับ ตามหน้าจอ/ตามกัน', (tester) async {
    await boot(tester);
    final a = f.addComponent(WfKind.button, 300, 200)!;
    f.selectBox(a.id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wf-align-section')), findsOneWidget);
    expect(find.byKey(const ValueKey('wf-align-target')), findsNothing, reason: 'ชิ้นเดียว ไม่มีให้เลือกว่าตามกัน');

    await tester.ensureVisible(find.byKey(const ValueKey('wf-al-left')));
    await tester.tap(find.byKey(const ValueKey('wf-al-left')));
    await tester.pumpAndSettle();
    expect(f.diagram.componentById(a.id)!.x, 0);

    await tester.ensureVisible(find.byKey(const ValueKey('wf-al-center')));
    await tester.tap(find.byKey(const ValueKey('wf-al-center')));
    await tester.pumpAndSettle();
    final c = f.diagram.componentById(a.id)!;
    expect(c.x + c.w / 2, closeTo(f.diagram.width / 2, 0.01));

    await tester.ensureVisible(find.byKey(const ValueKey('wf-al-bottom')));
    await tester.tap(find.byKey(const ValueKey('wf-al-bottom')));
    await tester.pumpAndSettle();
    final c2 = f.diagram.componentById(a.id)!;
    expect(c2.y + c2.h, closeTo(f.diagram.height.toDouble(), 0.01));

    // หลายชิ้น : ค่าเริ่มต้นชิดหน้าจอ ; สลับเป็นตามกันแล้วชิดซ้ายตามชิ้นซ้ายสุด
    final b = f.addComponent(WfKind.button, 700, 400)!;
    f.selectBox(a.id);
    f.selectBox(b.id, add: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wf-align-target')), findsOneWidget);
    await tester.ensureVisible(find.text('ตามกัน'));
    await tester.tap(find.text('ตามกัน'));
    await tester.pumpAndSettle();
    final leftMost = [f.diagram.componentById(a.id)!.x, f.diagram.componentById(b.id)!.x].reduce((p, q) => p < q ? p : q);
    await tester.ensureVisible(find.byKey(const ValueKey('wf-al-left')));
    await tester.tap(find.byKey(const ValueKey('wf-al-left')));
    await tester.pumpAndSettle();
    expect(f.diagram.componentById(a.id)!.x, closeTo(leftMost, 0.01));
    expect(f.diagram.componentById(b.id)!.x, closeTo(leftMost, 0.01));
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('wf-dist-h'))).onPressed, isNull, reason: 'กระจายต้อง 3 ชิ้นขึ้นไป');
  });
}
