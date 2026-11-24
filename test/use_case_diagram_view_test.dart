import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/layout/usecase_layout.dart';
import 'package:nsl_nebular/core/models/use_case.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/ui/usecase_diagram.dart';
import 'package:provider/provider.dart';

/// Phase 31: แท็บ "แผนภาพ" ของหน้า Use Case (แบบ B : ผืนผ้าใบ + แผงสรุปขวา)
void main() {
  late WorkspaceController wc;
  late UseCase a, b, c;

  Future<void> boot(WidgetTester tester, {Size size = const Size(1600, 950), bool explorer = true, Lang lang = Lang.th, bool seed = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => currentLang = Lang.th);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang, showExplorer: explorer)));
    wc = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    if (seed) {
      a = wc.addUseCase(name: 'จองห้อง', actor: 'Guest');
      b = wc.addUseCase(name: 'ชำระเงิน', actor: 'Guest');
      c = wc.addUseCase(name: 'เพิ่มห้อง', actor: 'Admin');
      wc.updateUseCase(a.id, (x) {
        x.secondaryActor = 'Payment Gateway';
        x.goal = 'จองห้องได้ในครั้งเดียว';
        x.steps.addAll([UcStep(id: 's1', text: 'เลือกห้อง'), UcStep(id: 's2', who: UcWho.system, text: 'ยืนยัน')]);
        x.branches.add(UcBranch(id: 'b1', atStepId: 's2', condition: 'ห้องเต็ม', ends: true));
        x.includes.add(b.id);
      });
      wc.updateUseCase(c.id, (x) => x.extendsFrom.add(UcExtend(baseId: a.id, condition: 'ต้องเป็นผู้ดูแล')));
    }
    wc.showUseCases();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uc-tab-diagram')));
    await tester.pumpAndSettle();
  }

  /// ตำแหน่งบนจอของจุด ([fx],[fy]) (สัดส่วนในโหนด) ภายใต้การแปลง [t] ที่ได้จาก "พอดีจอ" ตอนเปิดแท็บ
  Offset screen(WidgetTester tester, ({double scale, double dx, double dy}) t, UcNode n, {double fx = 0.5, double fy = 0.5}) {
    final tl = tester.getTopLeft(find.byKey(const ValueKey('uc-diagram')));
    return tl + Offset(t.dx + (n.x + n.w * fx) * t.scale, t.dy + (n.y + n.h * fy) * t.scale);
  }

  ({UcDiagram d, ({double scale, double dx, double dy}) t}) layoutNow(WidgetTester tester) {
    final d = layoutUseCaseDiagram(wc.workspace, overrides: wc.useCaseLayout);
    final size = tester.getSize(find.byKey(const ValueKey('uc-diagram')));
    return (d: d, t: ucFitTransform(d.bounds!, size.width, size.height));
  }

  String zoom(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('uc-dg-zoom-label'))).data!;

  testWidgets('แท็บแผนภาพมีผืนผ้าใบ + แผงสรุปขวา ; เริ่มที่ Use Case ที่เลือกอยู่ ; สรุปบอกผู้กระทำ ขั้นตอน ความสัมพันธ์', (tester) async {
    await boot(tester);
    expect(find.byKey(const ValueKey('uc-diagram')), findsOneWidget);
    expect(find.byKey(const ValueKey('uc-dg-inspector')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('uc-dg-counts'))).data, '3 Use Case · 3 ผู้กระทำ');
    // ตอนเปิดแท็บ ข้อที่เลือกในสเปกคือข้อแรก (a)
    expect(find.descendant(of: find.byKey(const ValueKey('uc-dg-inspector')), matching: find.text('จองห้อง')), findsOneWidget);
    expect(find.text('2 ขั้นตอน · 1 ทางเลือก · 0 ข้อผิดพลาด'), findsOneWidget);
    expect(find.text('Guest · Payment Gateway'), findsOneWidget);
    expect(find.textContaining('«include» UC-02'), findsOneWidget);
    expect(find.text('← UC-03 เพิ่มห้อง'), findsOneWidget, reason: 'ถูกขยายโดย UC-03');
    expect(tester.takeException(), isNull);
  });

  testWidgets('คลิกวงรีเลือกข้อ ; คลิกผู้กระทำดูรายการ Use Case ของเขา ; คลิกพื้นว่าง = ภาพรวม', (tester) async {
    await boot(tester);
    final l = layoutNow(tester);
    await tester.tapAt(screen(tester, l.t, l.d.node(ucNodeKey(c.id))!));
    await tester.pump();
    expect(find.descendant(of: find.byKey(const ValueKey('uc-dg-inspector')), matching: find.text('เพิ่มห้อง')), findsOneWidget);
    expect(find.textContaining('«extend» UC-01 จองห้อง [ต้องเป็นผู้ดูแล]'), findsOneWidget);
    expect(find.text('ผู้กระทำรอง / ระบบภายนอก'), findsNothing);

    await tester.tapAt(screen(tester, l.t, l.d.node(ucActorKey('Payment Gateway'))!, fy: 0.3));
    await tester.pump();
    expect(find.text('ผู้กระทำรอง / ระบบภายนอก'), findsOneWidget);
    expect(find.byKey(ValueKey('uc-dg-actor-uc-${a.id}')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('uc-dg-actor-uc-${a.id}')));
    await tester.pump();
    expect(find.byKey(const ValueKey('uc-dg-open-spec')), findsOneWidget);

    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('uc-diagram'))) + const Offset(4, 4));
    await tester.pump();
    expect(find.text('ภาพรวม'), findsOneWidget);
  });

  testWidgets('ดับเบิลคลิกวงรี และปุ่ม "แก้สเปก" = ไปแท็บสเปกของข้อนั้น', (tester) async {
    await boot(tester);
    final l = layoutNow(tester);
    final p = screen(tester, l.t, l.d.node(ucNodeKey(b.id))!);
    await tester.tapAt(p);
    await tester.tapAt(p);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('uc-editor-${b.id}')), findsOneWidget);
    expect(find.byKey(const ValueKey('uc-diagram')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('uc-tab-diagram')));
    await tester.pumpAndSettle();
    final l2 = layoutNow(tester);
    await tester.tapAt(screen(tester, l2.t, l2.d.node(ucNodeKey(c.id))!));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('uc-dg-open-spec')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('uc-editor-${c.id}')), findsOneWidget);
  });

  testWidgets('ลากวงรี = จัดตำแหน่ง (เก็บในไฟล์ ย้อนได้) ; จัดวางใหม่ล้างตำแหน่ง ; ลากพื้นว่าง = เลื่อนภาพ ไม่แตะตำแหน่ง', (tester) async {
    await boot(tester);
    final l = layoutNow(tester);
    final n0 = l.d.node(ucNodeKey(b.id))!;
    expect(wc.useCaseLayout, isEmpty);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('uc-dg-reset'))).onPressed, isNull);

    await tester.dragFrom(screen(tester, l.t, n0), const Offset(90, 60));
    await tester.pumpAndSettle();
    final moved = wc.useCaseLayout[ucNodeKey(b.id)]!;
    expect(moved.$1 - n0.x, inInclusiveRange(40 / l.t.scale, 90 / l.t.scale), reason: 'ขยับตามเมาส์ (หักระยะ slop ก่อนเริ่มลาก)');
    expect(moved.$2 - n0.y, inInclusiveRange(20 / l.t.scale, 60 / l.t.scale));
    expect(wc.projectHistory.undoLabel, 'ย้ายในแผนภาพ Use Case');
    expect(wc.projectHistory.undoCount, greaterThan(0));
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('uc-dg-reset'))).onPressed, isNotNull);

    wc.undo();
    await tester.pumpAndSettle();
    expect(wc.useCaseLayout, isEmpty, reason: 'ย้อนได้ทั้งการลาก');
    wc.redo();
    await tester.pumpAndSettle();
    expect(wc.useCaseLayout.containsKey(ucNodeKey(b.id)), isTrue);
    await tester.tap(find.byKey(const ValueKey('uc-dg-reset')));
    await tester.pumpAndSettle();
    expect(wc.useCaseLayout, isEmpty);

    // ลากพื้นว่าง : เลื่อนภาพ ไม่สร้างตำแหน่ง
    await tester.dragFrom(tester.getTopLeft(find.byKey(const ValueKey('uc-diagram'))) + const Offset(6, 6), const Offset(50, 30));
    await tester.pumpAndSettle();
    expect(wc.useCaseLayout, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ซูมเข้า/ออก/พอดีจอ ; เมาส์ล้อซูม', (tester) async {
    await boot(tester);
    final z0 = zoom(tester);
    await tester.tap(find.byKey(const ValueKey('uc-dg-zoom-in')));
    await tester.pump();
    final zin = int.parse(zoom(tester).replaceAll('%', ''));
    expect(zin, greaterThan(int.parse(z0.replaceAll('%', ''))));
    await tester.tap(find.byKey(const ValueKey('uc-dg-zoom-out')));
    await tester.tap(find.byKey(const ValueKey('uc-dg-zoom-out')));
    await tester.pump();
    expect(int.parse(zoom(tester).replaceAll('%', '')), lessThan(int.parse(z0.replaceAll('%', ''))));
    await tester.tap(find.byKey(const ValueKey('uc-dg-fit')));
    await tester.pump();
    expect(zoom(tester), z0, reason: 'พอดีจอกลับค่าเดิม');
    final center = tester.getCenter(find.byKey(const ValueKey('uc-diagram')));
    final pointer = TestPointer(1, PointerDeviceKind.mouse)..hover(center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(int.parse(zoom(tester).replaceAll('%', '')), greaterThan(int.parse(z0.replaceAll('%', ''))), reason: 'ล้อเลื่อนขึ้น = ซูมเข้า');
  });

  testWidgets('ตำนานเปิด/ปิดได้ ; เมนูส่งออกมี PNG และ SVG', (tester) async {
    await boot(tester);
    expect(find.byKey(const ValueKey('uc-dg-legend-box')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('uc-dg-legend')));
    await tester.pump();
    expect(find.byKey(const ValueKey('uc-dg-legend-box')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('uc-dg-export')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('uc-dg-export-png')), findsOneWidget);
    expect(find.byKey(const ValueKey('uc-dg-export-svg')), findsOneWidget);
  });

  testWidgets('ยังไม่มี Use Case: บอกให้ไปเขียนในแท็บสเปก ไม่ล้ม', (tester) async {
    await boot(tester, seed: false);
    // ไม่มี Use Case หน้าแสดงสถานะว่างของทั้งหน้า (ยังไม่มีแท็บ) — เพิ่มแล้วลบให้เหลือหน้าแผนภาพว่าง
    expect(find.byKey(const ValueKey('uc-empty')), findsOneWidget);
    wc.addUseCase(name: 'x', actor: 'y');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('uc-tab-diagram')));
    await tester.pumpAndSettle();
    wc.deleteUseCase(wc.useCases.first.id);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ส่งออก PNG: ได้ภาพ PNG จริง (ลายเซ็น 89 50 4E 47) ขนาดตรงขอบเขต ; ไม่มี Use Case = null', (tester) async {
    await boot(tester);
    final d = layoutUseCaseDiagram(wc.workspace);
    final png = await tester.runAsync(() => exportUseCasePng(d));
    expect(png, isNotNull);
    expect(png!.bytes.take(4), [0x89, 0x50, 0x4E, 0x47]);
    final b = d.bounds!;
    expect(png.width, ((b.right - b.left) * png.scale).ceil());
    expect(png.height, ((b.bottom - b.top) * png.scale).ceil());
    final dark = await tester.runAsync(() => exportUseCasePng(d, dark: true));
    expect(dark!.bytes, isNot(png.bytes));
    expect(await tester.runAsync(() => exportUseCasePng(const UcDiagram(nodes: [], edges: [], boundary: null, bounds: null, systemName: 'x'))), isNull);
  });

  testWidgets('จอแคบ (900px ไม่มีตัวสำรวจ): แผงสรุปอยู่ใต้ผืนผ้าใบ ไม่ล้น', (tester) async {
    await boot(tester, size: const Size(900, 900), explorer: false);
    expect(find.byKey(const ValueKey('uc-dg-inspector')), findsOneWidget);
    final canvas = tester.getRect(find.byKey(const ValueKey('uc-diagram')));
    final insp = tester.getRect(find.byKey(const ValueKey('uc-dg-inspector')));
    expect(insp.top, greaterThanOrEqualTo(canvas.bottom - 1), reason: 'แผงอยู่ใต้ภาพ');
    expect(tester.takeException(), isNull);
  });

  testWidgets('ภาษาอังกฤษ: แถบเครื่องมือและแผงสรุปไม่มีไทยหลุด (ยกเว้นข้อมูลที่ผู้ใช้เขียน)', (tester) async {
    await boot(tester, lang: Lang.en);
    final thai = RegExp(r'[฀-๿]');
    const userData = {'จองห้อง', 'ชำระเงิน', 'เพิ่มห้อง', 'จองห้องได้ในครั้งเดียว', 'ต้องเป็นผู้ดูแล'};
    for (final key in ['uc-dg-inspector', 'uc-dg-counts', 'uc-dg-zoom-label']) {
      for (final t in tester.widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))) {
        final s = t.data ?? t.textSpan?.toPlainText() ?? '';
        if (userData.any(s.contains)) continue;
        expect(thai.hasMatch(s), isFalse, reason: s);
      }
    }
    expect(find.text('Fit to screen'), findsOneWidget);
    expect(find.text('Edit spec →'), findsOneWidget);
  });
}
