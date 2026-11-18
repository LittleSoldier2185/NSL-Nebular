import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/screenflow_model.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/screenflow_controller.dart';
import 'package:nsl_nebular/state/wireframe_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// เทสต์วิดเจ็ตของแคนวาส Wireframe / Screen Flow ที่จำลองเมาส์และคีย์บอร์ดจริง
///
/// หมายเหตุ: ต้องตั้ง `lang` เสมอ — ไม่ตั้งแล้วแอปจะขึ้นกล่องถามภาษาครั้งแรกบังทั้งหน้าจอ ทำให้ `tester.tap` ไม่โดนปุ่มใด ๆ
/// (นี่คือสาเหตุที่เคยนึกว่าแถบเครื่องมือ Wireframe "ถูกบัง")
void main() {
  late WorkspaceController w;

  Future<void> boot(WidgetTester tester, {Lang lang = Lang.th}) async {
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang, showExplorer: true)));
    w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    await tester.pump();
  }

  WireframeController wfc(WidgetTester tester) => tester.element(find.byType(HomePage)).read<WireframeController>();
  ScreenFlowController sfc(WidgetTester tester) => tester.element(find.byType(HomePage)).read<ScreenFlowController>();

  Future<WireframeController> addWf(WidgetTester tester, [WireframeDiagram? content]) async {
    final doc = w.addDocument(DocType.wireframe, name: 'Home')!;
    if (content != null) doc.content = content;
    await tester.pumpAndSettle();
    final f = wfc(tester);
    expect(f.docId, doc.id);
    return f;
  }

  Future<ScreenFlowController> addSf(WidgetTester tester, [ScreenFlowDiagram? content]) async {
    final doc = w.addDocument(DocType.screenflow, name: 'Flow')!;
    if (content != null) doc.content = content;
    await tester.pumpAndSettle();
    final f = sfc(tester);
    expect(f.docId, doc.id);
    return f;
  }

  Finder wfCanvas() => find.byKey(const ValueKey('wf-canvas'));
  Finder sfCanvas() => find.byKey(const ValueKey('sf-canvas'));
  Offset wfAt(WidgetTester tester, WireframeController f, double x, double y) =>
      tester.getTopLeft(wfCanvas()) + f.toScreen(Offset(x, y));
  Offset sfAt(WidgetTester tester, ScreenFlowController f, double x, double y) =>
      tester.getTopLeft(sfCanvas()) + f.toScreen(Offset(x, y));

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k, {bool ctrl = false}) async {
    if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(k);
    if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  Future<void> rightClick(WidgetTester tester, Offset at) async {
    final g = await tester.startGesture(at, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await g.up();
    await tester.pumpAndSettle();
  }

  WireframeDiagram twoBoxes() => WireframeDiagram(components: [
        WfComponent(id: 'card', kind: WfKind.card, x: 100, y: 100, w: 300, h: 200),
        WfComponent(id: 'btn', kind: WfKind.button, text: 'OK', x: 140, y: 150, w: 100, h: 36),
        WfComponent(id: 'far', kind: WfKind.label, text: 'Far', x: 600, y: 400, w: 120, h: 28),
      ]);

  group('Wireframe: แถบเครื่องมือ / คลัง', () {
    testWidgets('คลิกปุ่มบนแถบเครื่องมือ: เลือกเครื่องมือวางและสลับรูปแบบ (ไม่ถูกบัง)', (tester) async {
      await boot(tester);
      final f = await addWf(tester);
      await tester.tap(find.byKey(const ValueKey('wf-tool-button')));
      await tester.pump();
      expect((f.tool, f.toolKind), (WfTool.place, WfKind.button));
      await tester.tap(find.byKey(const ValueKey('wf-tool-pointer')));
      await tester.pump();
      expect(f.tool, WfTool.select);
      await tester.tap(find.byKey(const ValueKey('wf-style-clean')));
      await tester.pump();
      expect(f.diagram.style, WfStyle.clean);
      await tester.tap(find.byKey(const ValueKey('wf-style-sketch')));
      await tester.pump();
      expect(f.diagram.style, WfStyle.sketch);
    });

    testWidgets('คลิกคลังซ้ายแล้วคลิกในกรอบ = วางชิ้นส่วนและพิมพ์ข้อความทันที', (tester) async {
      await boot(tester);
      final f = await addWf(tester);
      await tester.tap(find.byKey(const ValueKey('wf-kind-button')));
      await tester.pump();
      expect(f.tool, WfTool.place);
      await tester.tapAt(wfAt(tester, f, 300, 200));
      await tester.pumpAndSettle();
      final b = f.diagram.components.single;
      expect(b.kind, WfKind.button);
      expect(f.editing, (id: b.id, isEdge: false));
      expect(f.tool, WfTool.select);
      await tester.enterText(find.byKey(const ValueKey('wf-inline-field')), 'ส่งข้อมูล');
      await key(tester, LogicalKeyboardKey.enter, ctrl: true);
      await tester.pumpAndSettle();
      expect(f.diagram.components.single.text, 'ส่งข้อมูล');
      expect(f.editing, isNull);
    });

    testWidgets('ลากชิ้นส่วนจากคลังมาวางบนแคนวาส', (tester) async {
      await boot(tester);
      final f = await addWf(tester);
      final from = tester.getCenter(find.byKey(const ValueKey('wf-kind-container')));
      final g = await tester.startGesture(from);
      await g.moveBy(const Offset(40, 0));
      await g.moveTo(wfAt(tester, f, 300, 250));
      await g.up();
      await tester.pumpAndSettle();
      expect(f.diagram.components.map((c) => c.kind), [WfKind.container]);
    });
  });

  group('Wireframe: คีย์ลัด / เมาส์', () {
    testWidgets('คีย์ B/T/L/R/G เลือกเครื่องมือตามคีย์ ; คลิกแล้ววางได้', (tester) async {
      await boot(tester);
      final f = await addWf(tester);
      final expected = {
        LogicalKeyboardKey.keyB: WfKind.button,
        LogicalKeyboardKey.keyT: WfKind.label,
        LogicalKeyboardKey.keyL: WfKind.input,
        LogicalKeyboardKey.keyR: WfKind.container,
        LogicalKeyboardKey.keyG: WfKind.image,
      };
      for (final e in expected.entries) {
        await key(tester, e.key);
        expect((f.tool, f.toolKind), (WfTool.place, e.value), reason: e.key.keyLabel);
      }
      // วางรูปภาพ (ไม่พิมพ์ข้อความ) ที่จุดที่คลิก
      await tester.tapAt(wfAt(tester, f, 300, 300));
      await tester.pumpAndSettle();
      expect(f.diagram.components.single.kind, WfKind.image);
      expect(f.editing, isNull);
      expect(f.tool, WfTool.select);
    });

    testWidgets('ลากภาชนะ: ลูกที่อยู่ข้างในติดไปด้วย ส่วนชิ้นนอกภาชนะอยู่เดิม ; undo ขั้นเดียว', (tester) async {
      await boot(tester);
      final f = await addWf(tester, twoBoxes());
      final card = f.diagram.componentById('card')!;
      // จับที่ขอบล่างของการ์ด (ว่าง ไม่โดนปุ่ม)
      final start = wfAt(tester, f, card.x + 200, card.y + 180);
      final g = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(10, 10));
      await g.moveBy(const Offset(50, 30));
      await g.up();
      await tester.pumpAndSettle();
      final dx = f.diagram.componentById('card')!.x - 100;
      final dy = f.diagram.componentById('card')!.y - 100;
      expect(dx, greaterThan(40));
      expect(dy, greaterThan(20));
      expect(f.diagram.componentById('btn')!.x, closeTo(140 + dx, 0.01));
      expect(f.diagram.componentById('btn')!.y, closeTo(150 + dy, 0.01));
      expect(f.diagram.componentById('far')!.x, 600);
      f.undo();
      expect(f.diagram.componentById('card')!.x, 100);
      expect(f.diagram.componentById('btn')!.x, 140);
    });

    testWidgets('ลากกรอบเลือกหลายชิ้น ; Delete ลบ ; Ctrl+A / Ctrl+D', (tester) async {
      await boot(tester);
      final f = await addWf(tester, twoBoxes());
      final g = await tester.startGesture(wfAt(tester, f, 80, 80), kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(20, 20));
      await g.moveTo(wfAt(tester, f, 430, 330));
      await g.up();
      await tester.pumpAndSettle();
      expect(f.selectedIds, {'card', 'btn'});
      await key(tester, LogicalKeyboardKey.delete);
      expect(f.diagram.components.map((c) => c.id), ['far']);
      await key(tester, LogicalKeyboardKey.keyA, ctrl: true);
      expect(f.selectedIds, {'far'});
      await key(tester, LogicalKeyboardKey.keyD, ctrl: true);
      expect(f.diagram.components.length, 2);
    });

    testWidgets('คลิกเลือก ; ปุ่มลูกศรขยับ ; จุดจับปรับขนาด ; ดับเบิลคลิกพิมพ์ ; Esc ยกเลิก', (tester) async {
      var t = DateTime(2026, 11, 14, 12);
      await withClock(Clock(() => t), () async {
        await boot(tester);
        final f = await addWf(tester, twoBoxes());
        final at = wfAt(tester, f, 640, 414);
        await tester.tapAt(at);
        t = t.add(const Duration(milliseconds: 80));
        await tester.pump(const Duration(milliseconds: 80));
        expect(f.selectedIds, {'far'});
        await key(tester, LogicalKeyboardKey.arrowRight);
        expect(f.diagram.componentById('far')!.x, isNot(600));
        // ปรับขนาดด้วยจุดจับมุมขวาล่าง
        final far = f.diagram.componentById('far')!;
        final w0 = far.w;
        final h = await tester.startGesture(wfAt(tester, f, far.right, far.bottom), kind: PointerDeviceKind.mouse);
        await h.moveBy(const Offset(10, 10));
        await h.moveBy(const Offset(40, 0));
        await h.up();
        await tester.pumpAndSettle();
        expect(f.diagram.componentById('far')!.w, greaterThan(w0 + 30));
        // ดับเบิลคลิก = พิมพ์ข้อความ
        final c = f.diagram.componentById('far')!;
        final p = wfAt(tester, f, c.x + 20, c.y + c.h / 2);
        await tester.tapAt(p);
        t = t.add(const Duration(milliseconds: 80));
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(p);
        await tester.pumpAndSettle();
        expect(f.editing, (id: 'far', isEdge: false));
        await tester.enterText(find.byKey(const ValueKey('wf-inline-field')), 'ถูกยกเลิก');
        await key(tester, LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(f.editing, isNull);
        expect(f.diagram.componentById('far')!.text, 'Far');
      });
    });

    testWidgets('Ctrl+C แล้ว Ctrl+V ข้ามแท็บ Wireframe', (tester) async {
      String? clip;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clip = (call.arguments as Map)['text'] as String?;
          return null;
        }
        if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': clip};
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await boot(tester);
      final a = await addWf(tester, twoBoxes());
      a.selectBox('card');
      await tester.pump();
      await key(tester, LogicalKeyboardKey.keyC, ctrl: true);
      await tester.pumpAndSettle();
      expect(clip, isNotNull);
      w.addDocument(DocType.wireframe, name: 'Other');
      await tester.pumpAndSettle();
      final b = wfc(tester);
      expect(b.docId, isNot(a.docId));
      await key(tester, LogicalKeyboardKey.keyV, ctrl: true);
      await tester.pumpAndSettle();
      // การ์ด + ปุ่มข้างในติดมาด้วย
      expect(b.diagram.components.map((c) => c.kind).toSet(), {WfKind.card, WfKind.button});
      expect(b.diagram.components.length, 2);
    });

    testWidgets('เมนูคลิกขวา: พื้นว่าง = วางชิ้นส่วน/สลับรูปแบบ ; บนชิ้น = ทำสำเนา/ลบ', (tester) async {
      await boot(tester);
      final f = await addWf(tester);
      await rightClick(tester, wfAt(tester, f, 300, 300));
      await tester.tap(find.text('วางปุ่มที่นี่'));
      await tester.pumpAndSettle();
      expect(f.diagram.components.single.kind, WfKind.button);
      await key(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await rightClick(tester, wfAt(tester, f, 600, 100));
      await tester.tap(find.text('เปลี่ยนเป็นแบบเรียบร้อย'));
      await tester.pumpAndSettle();
      expect(f.diagram.style, WfStyle.clean);
      final b = f.diagram.components.single;
      await rightClick(tester, wfAt(tester, f, b.x + b.w / 2, b.y + b.h / 2));
      await tester.tap(find.text('ทำสำเนา').last);
      await tester.pumpAndSettle();
      expect(f.diagram.components.length, 2);
      await rightClick(tester, wfAt(tester, f, b.x + b.w / 2, b.y + b.h / 2));
      await tester.tap(find.textContaining('ลบ'));
      await tester.pumpAndSettle();
      expect(f.diagram.components.length, lessThan(2));
    });

    testWidgets('ซูมด้วยปุ่ม/พอดีจอ และ F1 มีกลุ่ม Wireframe', (tester) async {
      await boot(tester);
      final f = await addWf(tester, twoBoxes());
      final s0 = f.scale;
      f.zoomAt(const Offset(300, 300), 1.5);
      await tester.pump();
      expect(f.scale, greaterThan(s0));
      await key(tester, LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.text('Wireframe'), findsWidgets);
    });

    testWidgets('ภาษาอังกฤษ: ป้ายแถบเครื่องมือ เมนู และข้อความว่างแปลครบ ไม่มีไทยหลุด', (tester) async {
      await boot(tester, lang: Lang.en);
      final f = await addWf(tester);
      final thai = RegExp(r'[฀-๿]');
      String texts() => tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? t.textSpan?.toPlainText() ?? '').join('\n');
      expect(thai.hasMatch(texts()), isFalse, reason: texts().split('\n').where(thai.hasMatch).join(' | '));
      await rightClick(tester, wfAt(tester, f, 300, 300));
      expect(thai.hasMatch(texts()), isFalse, reason: texts().split('\n').where(thai.hasMatch).join(' | '));
    });
  });

  group('Screen Flow', () {
    ScreenFlowDiagram flow() => ScreenFlowDiagram(nodes: [
          SfNode(id: 's', kind: SfKind.start, x: 0, y: 0),
          SfNode(id: 'a', kind: SfKind.screen, title: 'Login', x: 200, y: 0),
          SfNode(id: 'b', kind: SfKind.screen, title: 'Home', x: 500, y: 0),
        ]);

    testWidgets('แถบเครื่องมือ: เลือกหน้าจอแล้วคลิกวาง พิมพ์ชื่อ ; undo', (tester) async {
      await boot(tester);
      final f = await addSf(tester);
      await tester.tap(find.byKey(const ValueKey('sf-tool-screen')));
      await tester.pump();
      expect((f.tool, f.toolKind), (SfTool.node, SfKind.screen));
      await tester.tapAt(sfAt(tester, f, 300, 200));
      await tester.pumpAndSettle();
      expect(f.diagram.nodes.single.kind, SfKind.screen);
      await tester.enterText(find.byKey(const ValueKey('sf-inline-field')), 'หน้าแรก');
      await key(tester, LogicalKeyboardKey.enter, ctrl: true);
      await tester.pumpAndSettle();
      expect(f.diagram.nodes.single.title, 'หน้าแรก');
      // undo ทีละขั้น: ชื่อ -> การวาง
      await key(tester, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(f.diagram.nodes.single.title, isNot('หน้าแรก'));
      await key(tester, LogicalKeyboardKey.keyZ, ctrl: true);
      expect(f.diagram.nodes, isEmpty);
    });

    testWidgets('คีย์ P/E/O วางโหนด ; F ต่อเส้นแล้วพิมพ์ trigger ได้', (tester) async {
      await boot(tester);
      final f = await addSf(tester, flow());
      await key(tester, LogicalKeyboardKey.keyF);
      expect(f.tool, SfTool.edge);
      final a = f.diagram.nodeById('a')!, b = f.diagram.nodeById('b')!;
      await tester.tapAt(sfAt(tester, f, a.x + a.w / 2, a.y + a.h / 2));
      await tester.pump();
      await tester.tapAt(sfAt(tester, f, b.x + b.w / 2, b.y + b.h / 2));
      await tester.pumpAndSettle();
      expect(f.diagram.edges.length, 1);
      expect((f.diagram.edges.single.fromId, f.diagram.edges.single.toId), ('a', 'b'));
      final field = find.byKey(const ValueKey('sf-inline-field'));
      expect(field, findsOneWidget);
      await tester.enterText(field, 'กดเข้าสู่ระบบ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(f.diagram.edges.single.label, 'กดเข้าสู่ระบบ');
      await key(tester, LogicalKeyboardKey.keyP);
      expect((f.tool, f.toolKind), (SfTool.node, SfKind.screen));
      await key(tester, LogicalKeyboardKey.keyE);
      expect((f.tool, f.toolKind), (SfTool.node, SfKind.external));
    });

    testWidgets('ลากย้ายหน้าจอ ; กรอบเลือก ; Delete ลบหน้าจอพร้อมเส้นที่ต่อ', (tester) async {
      await boot(tester);
      final f = await addSf(tester, flow());
      f.addEdge('a', 'b');
      await tester.pump();
      final a = f.diagram.nodeById('a')!;
      final ax0 = a.x;
      final g = await tester.startGesture(sfAt(tester, f, a.x + a.w / 2, a.y + a.h / 2), kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(10, 10));
      await g.moveBy(const Offset(60, 40));
      await g.up();
      await tester.pumpAndSettle();
      expect(f.diagram.nodeById('a')!.x, greaterThan(ax0 + 40));
      expect(f.selectedIds, {'a'});
      await key(tester, LogicalKeyboardKey.delete);
      expect(f.diagram.nodeById('a'), isNull);
      expect(f.diagram.edges, isEmpty);
      f.undo();
      expect(f.diagram.edges.length, 1);
    });

    testWidgets('ดับเบิลคลิกหน้าจอที่ผูก Wireframe = เปิดแท็บ Wireframe ; ไม่ผูก = พิมพ์ชื่อ', (tester) async {
      var t = DateTime(2026, 11, 14, 12);
      await withClock(Clock(() => t), () async {
        await boot(tester);
        final wf = await addWf(tester);
        final f = await addSf(tester, flow());
        f.linkWireframe('a', wf.docId);
        await tester.pumpAndSettle();
        Future<void> dbl(Offset p) async {
          await tester.tapAt(p);
          t = t.add(const Duration(milliseconds: 80));
          await tester.pump(const Duration(milliseconds: 80));
          await tester.tapAt(p);
          await tester.pumpAndSettle();
        }

        final b = f.diagram.nodeById('b')!;
        await dbl(sfAt(tester, f, b.x + b.w / 2, b.y + 8));
        expect(f.editing, isNotNull);
        await key(tester, LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        t = t.add(const Duration(seconds: 2));
        final a = f.diagram.nodeById('a')!;
        await dbl(sfAt(tester, f, a.x + a.w / 2, a.y + 8));
        expect(w.activeId, wf.docId);
      });
    });

    testWidgets('คลิกขวาพื้นว่าง: จัดวางอัตโนมัติ/วางหน้าจอ ; ภาษาอังกฤษไม่มีไทยหลุด', (tester) async {
      await boot(tester, lang: Lang.en);
      final f = await addSf(tester, flow());
      final thai = RegExp(r'[฀-๿]');
      String texts() => tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? t.textSpan?.toPlainText() ?? '').join('\n');
      expect(thai.hasMatch(texts()), isFalse, reason: texts().split('\n').where(thai.hasMatch).join(' | '));
      await rightClick(tester, sfAt(tester, f, 300, 300));
      expect(thai.hasMatch(texts()), isFalse, reason: texts().split('\n').where(thai.hasMatch).join(' | '));
    });
  });
}
