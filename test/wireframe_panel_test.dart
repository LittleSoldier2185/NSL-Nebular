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

  final layersHead = find.byKey(const ValueKey('wf-fold-layers-head'));

  testWidgets('แผงสูงเต็มคอลัมน์ ; ภาพย่อ ; เลเยอร์อยู่ล่างสุด (ใต้ส่วนตรวจสอบ) ; หน้าจอว่าง = ข้อความว่าง', (tester) async {
    await boot(tester);
    final panel = find.byType(WireframeRightPanel);
    expect(tester.getSize(panel).height, greaterThan(800), reason: 'ไม่ใช่แค่ความสูงเนื้อหา');
    expect(find.byKey(const ValueKey('wf-page-thumb')), findsOneWidget);
    expect(find.byKey(const ValueKey('wf-panel-style')), findsOneWidget);
    expect(find.byKey(const ValueKey('wf-layers-empty')), findsOneWidget);
    final checksY = tester.getTopLeft(find.byKey(const ValueKey('wf-fold-checks-head'))).dy;
    expect(tester.getTopLeft(layersHead).dy, greaterThan(checksY));
    expect(find.byKey(const ValueKey('wf-fold-flow-head')), findsNothing, reason: 'ไม่มี Screen Flow ใช้ ไม่แสดงส่วนนี้');
  });

  testWidgets('คลิกหัวส่วน = พับ/กาง ; เนื้อหาที่พับไม่ถูกสร้าง ; สถานะจำข้ามการเลือกชิ้นส่วน', (tester) async {
    await boot(tester);
    expect(find.byKey(const ValueKey('wf-device')), findsNothing, reason: 'ขนาดหน้าจอพับอยู่ตอนเริ่ม');
    await tester.tap(find.byKey(const ValueKey('wf-fold-size-head')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wf-device')), findsOneWidget);
    expect(find.byKey(const ValueKey('wf-frame-w-1440')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('wf-fold-look-head')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wf-panel-style')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('wf-fold-look-head'))); // คืนค่า
    await tester.tap(find.byKey(const ValueKey('wf-fold-size-head')));
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
    double iconX(String id) => tester.getTopLeft(find.descendant(of: find.byKey(ValueKey('wf-item-$id')), matching: find.byType(Icon)).first).dx;
    expect(iconX(btn.id), greaterThan(iconX(box.id)),
        reason: 'ปุ่มอยู่ในกล่อง = เยื้องเข้า');

    await tester.ensureVisible(find.byKey(ValueKey('wf-item-${box.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('wf-item-${box.id}')));
    await tester.pumpAndSettle();
    expect(f.selectedIds, {box.id});
    // คุณสมบัติของชิ้นที่เลือกอยู่เหนือเลเยอร์
    expect(find.byKey(const ValueKey('wf-panel-style')), findsNothing);
    expect(tester.getTopLeft(find.byKey(const ValueKey('wf-bold'))).dy, lessThan(tester.getTopLeft(layersHead).dy));

    // แผงซ้ายไม่มีรายการชิ้นส่วนแล้ว
    expect(find.descendant(of: find.byType(WireframeLeftPanel), matching: find.byKey(ValueKey('wf-item-${box.id}'))), findsNothing);
    expect(tester.takeException(), isNull);
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
}
