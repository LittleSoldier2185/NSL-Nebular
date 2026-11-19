import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/export/wireframe_svg.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/layout/dfd_resize.dart' show DfdHandle;
import 'package:nsl_nebular/core/layout/box_ops.dart' show BoxAlign;
import 'package:nsl_nebular/core/layout/wireframe_render.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/wireframe_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/ui/wireframe/wf_painter.dart';
import 'package:nsl_nebular/ui/wireframe/wf_panels.dart';
import 'package:nsl_nebular/ui/wireframe/wf_view.dart' show wfFrameLabel;
import 'package:provider/provider.dart';

/// Wireframe: เลเยอร์แบบ Adobe (ซ่อน/ล็อก/กลุ่ม) + หมุน + ที่เก็บภาพ
void main() {
  group('โมเดล', () {
    test('ไป-กลับ JSON ครบ ; ชิ้นเดิมไม่มีคีย์ใหม่ (ไฟล์เก่าเขียนกลับเหมือนเดิม) ; มุมถูกทำให้อยู่ใน 0–360', () {
      final c = WfComponent(id: 'a', kind: WfKind.button, hidden: true, locked: true, group: 'g1', rotation: -90);
      expect(c.rotation, 270);
      final back = WfComponent.tryFromJson(jsonDecode(jsonEncode(c.toJson())))!;
      expect(back.toJson(), c.toJson());
      final plain = WfComponent(id: 'b', kind: WfKind.label).toJson();
      expect(plain.keys, isNot(contains('hidden')));
      expect(plain.keys, isNot(contains('rotation')));
      expect(plain.keys, isNot(contains('group')));
      expect(WfComponent.tryFromJson({'id': 'x', 'kind': 'label', 'rotation': 'abc', 'group': ''})!.group, isNull);
      expect(wfNormAngle(725), 5);
      expect(wfNormAngle(double.nan), 0);
    });

    test('จุดบนชิ้นที่หมุน ; กรอบครอบหลังหมุน', () {
      final c = WfComponent(id: 'a', kind: WfKind.container, x: 0, y: 0, w: 200, h: 20, rotation: 90);
      // หมุน 90° รอบ (100,10): กลายเป็นแท่งตั้ง x 90–110, y -90–110
      expect(wfContains(c, 100, -80), isTrue);
      expect(wfContains(c, 10, 10), isFalse);
      final b = wfBounds(c);
      expect(b.left, closeTo(90, 1e-6));
      expect(b.top, closeTo(-90, 1e-6));
      expect(b.bottom, closeTo(110, 1e-6));
    });

    test('ซ่อน: ไม่ถูกวาด (ภาชนะที่ซ่อน ลูกซ่อนตาม) ; หมุน = ชิ้นวาดแบบกลุ่มหมุน ; SVG มี rotate และขอบเขตคิดการหมุน', () {
      final d = WireframeDiagram(components: [
        WfComponent(id: 'box', kind: WfKind.container, x: 0, y: 0, w: 300, h: 300, hidden: true),
        WfComponent(id: 'kid', kind: WfKind.button, x: 20, y: 20, w: 100, h: 40),
        WfComponent(id: 'rot', kind: WfKind.button, x: 500, y: 500, w: 100, h: 40, rotation: 30),
      ]);
      expect(wfHiddenIds(d), {'box', 'kid'});
      final prims = wireframePrims(d, frame: false);
      expect(prims.single, isA<WfGroupPrim>());
      expect((prims.single as WfGroupPrim).degrees, 30);
      final svg = exportWireframeSvg(d);
      expect(svg, contains('rotate(30 550 520)'));
      d.components.last.rotation = 0;
      d.components[0].hidden = false;
      expect(wireframePrims(d, frame: false).whereType<WfGroupPrim>(), isEmpty);
    });
  });

  group('controller', () {
    late WorkspaceController w;
    late WireframeController f;

    setUp(() {
      w = WorkspaceController();
      final doc = w.addDocument(DocType.wireframe, name: 'Home')!;
      f = w.wireframeController(doc.id)!;
      f.diagram.components.addAll([
        WfComponent(id: 'a', kind: WfKind.button, x: 0, y: 0, w: 100, h: 40),
        WfComponent(id: 'b', kind: WfKind.label, x: 200, y: 0, w: 100, h: 40),
        WfComponent(id: 'c', kind: WfKind.input, x: 400, y: 0, w: 100, h: 40),
      ]);
    });

    test('ล็อก: ย้าย/ขยับ/ลบ/ปรับขนาด/หมุน/จัดแนวไม่ได้ ; Ctrl+A และกรอบลากไม่เลือก ; ซ่อนก็ไม่ถูกเลือกบนแคนวาส', () {
      f.setLocked(['a'], true);
      f.setHidden(['c'], true);
      f.selectBox('a');
      expect(f.nudge(10, 0), isFalse);
      expect(f.diagram.componentById('a')!.x, 0);
      expect(f.deleteSelection(), 0);
      expect(f.handleAt(const Offset(100, 40)), isNull);
      expect(f.rotateHandleAt(f.rotateHandlePos(f.diagram.componentById('a')!)), isFalse);
      f.setRotation(['a'], 45);
      expect(f.diagram.componentById('a')!.rotation, 0);

      f.selectAll();
      expect(f.selectedIds, {'b'});
      expect(f.marqueeHits(const Rect.fromLTWH(-10, -10, 1000, 100)), {'b'});

      f.setSelection(['a', 'b']);
      f.align(BoxAlign.right);
      expect(f.diagram.componentById('a')!.x, 0, reason: 'ชิ้นที่ล็อกไม่ขยับ');
      expect(f.diagram.componentById('b')!.x, 200);
      f.undo();
      f.undo();
      expect(f.diagram.componentById('c')!.hidden, isFalse, reason: 'undo ได้');
    });

    test('กลุ่ม: Ctrl+G รวมสมาชิกให้ติดกันในลำดับการซ้อน ; คลิกชิ้นเดียวได้ทั้งกลุ่ม ; exact เลือกชิ้นเดียว ; เลิกกลุ่ม ; undo', () {
      f.setSelection(['a', 'c']);
      final g = f.groupSelection()!;
      expect([for (final x in f.diagram.components) x.id], ['b', 'a', 'c']);
      expect(f.diagram.componentById('a')!.group, g);
      f.clearSelection();
      f.selectBox('a');
      expect(f.selectedIds, {'a', 'c'});
      f.selectBox('a', exact: true);
      expect(f.selectedIds, {'a'});
      f.setSelection(['c']);
      expect(f.selectedIds, {'a', 'c'});
      // ย้ายทั้งกลุ่ม
      f.nudge(5, 0);
      expect(f.diagram.componentById('a')!.x, 5);
      expect(f.diagram.componentById('c')!.x, 405);
      expect(f.ungroupSelection(), isTrue);
      expect(f.diagram.componentById('a')!.group, isNull);
      f.undo();
      expect(f.diagram.componentById('a')!.group, g);
    });

    test('ทำสำเนากลุ่ม = กลุ่มใหม่ของตัวเอง (ไม่ปนต้นฉบับ) และสำเนาไม่ล็อก', () {
      f.setSelection(['a', 'b']);
      final g = f.groupSelection()!;
      f.setLocked(['a'], true);
      f.selectBox('b');
      expect(f.duplicateSelection(), 2);
      final copies = f.diagram.components.where((x) => !{'a', 'b', 'c'}.contains(x.id)).toList();
      expect(copies.map((x) => x.group).toSet().single, isNot(g));
      expect(copies.every((x) => !x.locked), isTrue);
    });

    test('หมุน: ตั้งค่า/บวกเพิ่ม ; ลากจุดหมุน (Shift ปัด 15°) ; ปรับขนาดชิ้นที่หมุนแล้วขอบตรงข้ามอยู่กับที่', () {
      f.setRotation(['a'], 90, relative: true);
      f.setRotation(['a'], 90, relative: true);
      expect(f.diagram.componentById('a')!.rotation, 180);
      f.setRotation(['a'], 0);

      f.selectBox('b');
      final b = f.diagram.componentById('b')!;
      expect(f.rotateHandleAt(f.rotateHandlePos(b)), isTrue);
      f.beginRotate();
      // ชี้ไปทางขวาของจุดกึ่งกลาง = 90°
      f.rotateToward(Offset(b.x + b.w / 2 + 100, b.y + b.h / 2 + 3), snap: true);
      f.endRotate();
      expect(b.rotation, 90);
      f.undo();
      expect(f.diagram.componentById('b')!.rotation, 0);

      // ชิ้นหมุน 90°: ลากจุดจับขวา (ในพิกัดของชิ้น) ลงล่าง 20 = กว้างขึ้น 20 ; จุดกึ่งกลางเลื่อนลง 10
      f.setRotation(['c'], 90);
      f.selectBox('c');
      final c0 = f.diagram.componentById('c')!;
      final center0 = Offset(c0.x + c0.w / 2, c0.y + c0.h / 2);
      f.beginResize(DfdHandle.e);
      f.resizeBy(0, 20);
      f.endResize();
      final c1 = f.diagram.componentById('c')!;
      expect(c1.w, closeTo(120, 1e-6));
      expect(c1.h, closeTo(40, 1e-6));
      expect(c1.x + c1.w / 2, closeTo(center0.dx, 1e-6));
      expect(c1.y + c1.h / 2, closeTo(center0.dy + 10, 1e-6));
    });

    test('ผลตรวจถูกเก็บไว้: ไม่เปลี่ยน = object เดิม ; ระหว่างลากใช้ผลเดิม ; แก้แล้วคำนวณใหม่', () {
      final i1 = f.issues;
      expect(identical(f.issues, i1), isTrue);
      f.selectBox('a');
      f.beginMove();
      f.moveBy(3000, 0);
      expect(identical(f.issues, i1), isTrue, reason: 'ระหว่างลาก');
      f.endMove();
      expect(identical(f.issues, i1), isFalse);
      expect(f.issues.any((i) => i.tableId == 'a'), isTrue, reason: 'ชิ้นออกนอกกรอบหน้าจอ');
    });

    test('ผลตรวจทั้งโปรเจกต์ใช้ร่วมกัน และไม่ตรวจใหม่ระหว่างลาก', () {
      final all = w.workspaceIssues;
      expect(identical(w.workspaceIssues, all), isTrue);
      f.selectBox('a');
      f.beginMove();
      f.moveBy(10, 0);
      expect(identical(w.workspaceIssues, all), isTrue);
      f.endMove();
      expect(identical(w.workspaceIssues, all), isFalse);
    });
  });

  group('ลากเรียงเลเยอร์', () {
    late WorkspaceController w;
    late WireframeController f;
    final collapsed = <String>{};

    /// ลำดับชิ้นจากบนสุด (แบบที่เห็นในแผงเลเยอร์) พร้อมกลุ่ม
    String order() => [for (final c in f.diagram.components.reversed) c.group == null ? c.id : '${c.id}@${c.group}'].join(' ');
    String rows() => f.layerRows(collapsed).join(' ');

    setUp(() {
      collapsed.clear();
      w = WorkspaceController();
      final doc = w.addDocument(DocType.wireframe, name: 'Home')!;
      f = w.wireframeController(doc.id)!;
      // ล่างสุด -> บนสุด: a b c d e
      f.diagram.components.addAll([
        for (final (i, id) in ['a', 'b', 'c', 'd', 'e'].indexed) WfComponent(id: id, kind: WfKind.button, x: i * 150.0, y: 0, w: 100, h: 40),
      ]);
    });

    String groupOf(Iterable<String> ids) {
      f.setSelection(ids, exact: true);
      return f.groupSelection()!;
    }

    test('ชิ้นเดี่ยว: ลากล่างสุดขึ้นบนสุด / บนสุดลงล่างสุด ; undo ขั้นเดียว ; วางที่เดิม = ไม่เปลี่ยน', () {
      expect(rows(), 'e d c b a');
      expect(f.moveLayerRow(collapsed, 4, 0), isTrue);
      expect(order(), 'a e d c b');
      expect(f.moveLayerRow(collapsed, 1, 4), isTrue);
      expect(order(), 'a d c b e');
      f.undo();
      expect(order(), 'a e d c b');
      expect(f.moveLayerRow(collapsed, 2, 2), isFalse);
    });

    test('ลากหัวกลุ่ม = ย้ายทั้งกลุ่ม ; พับอยู่ก็ย้ายครบ ; ไม่แทรกกลางกลุ่มอื่น', () {
      final g = groupOf(['c', 'd']);
      expect(rows(), 'e G($g) d@$g c@$g b a');
      expect(f.moveLayerRow(collapsed, 1, 4), isTrue); // หลังเอาหัวออก: e d c b a → วางก่อน a (ดัชนี 4)
      expect(order(), 'e b d@$g c@$g a');

      collapsed.add(g);
      expect(rows(), 'e b G($g,closed) a');
      expect(f.moveLayerRow(collapsed, 2, 0), isTrue);
      expect(order(), 'd@$g c@$g e b a');

      collapsed.clear();
      final h = groupOf(['e', 'b']);
      expect(rows(), 'G($g) d@$g c@$g G($h) e@$h b@$h a');
      // ยกกลุ่ม h ขึ้นบนสุดก่อน
      expect(f.moveLayerRow(collapsed, 3, 0), isTrue);
      expect(rows(), 'G($h) e@$h b@$h G($g) d@$g c@$g a');
      // ลากกลุ่ม h ไปวางระหว่าง d กับ c (กลางกลุ่ม g) → เลื่อนไปหลังกลุ่ม g ; กลุ่ม g ไม่ถูกแทรก
      // หลังเอาหัว h ออก: e b G(g) d c a → ดัชนี 4 = ก่อน c
      expect(f.moveLayerRow(collapsed, 0, 4), isTrue);
      expect(order(), 'd@$g c@$g e@$h b@$h a');
    });

    test('ลากชิ้นเข้ากลุ่ม (ใต้หัวกลุ่ม / เหนือสมาชิก) ; ลากออกนอกกลุ่ม ; กลุ่มเหลือชิ้นเดียว = ยุบ', () {
      final g = groupOf(['c', 'd']);
      expect(rows(), 'e G($g) d@$g c@$g b a');
      expect(f.moveLayerRow(collapsed, 0, 1), isTrue); // e ไปใต้หัวกลุ่ม
      expect(order(), 'e@$g d@$g c@$g b a');
      expect(f.moveLayerRow(collapsed, 5, 3), isTrue); // a ไปเหนือ c (สมาชิก)
      expect(order(), 'e@$g d@$g a@$g c@$g b');

      // ลากสมาชิกลงไปใต้ b = ออกจากกลุ่ม
      expect(f.moveLayerRow(collapsed, 1, 5), isTrue);
      expect(order(), 'd@$g a@$g c@$g b e');
      // ลากสมาชิกตัวท้ายไปวางที่เดิมถัดจากสมาชิก = ยังอยู่กลุ่ม (ไม่หลุดเพราะลากนิดเดียว)
      expect(f.moveLayerRow(collapsed, 3, 3), isFalse);

      // เอาออกจนเหลือชิ้นเดียว → ยุบกลุ่ม
      f.moveLayerRow(collapsed, 1, 5);
      f.moveLayerRow(collapsed, 1, 5);
      expect(f.layerRows(collapsed).any((r) => r.header), isFalse);
      expect(f.diagram.components.every((c) => c.group == null), isTrue);
    });
  });

  group('ที่เก็บภาพ', () {
    test('ย้าย/หมุน/ซ่อน-แสดง ไม่สร้างภาพใหม่ ; เปลี่ยนข้อความ/สี/รูปแบบ = ภาพใหม่', () {
      WfPictureCache.clear();
      final d = WireframeDiagram(components: [WfComponent(id: 'a', kind: WfKind.button, text: 'ok', x: 10, y: 10, w: 100, h: 40)]);
      void paint() {
        final rec = ui.PictureRecorder();
        paintWireframe(Canvas(rec), d);
        rec.endRecording();
      }

      paint();
      final n = WfPictureCache.length;
      expect(n, 2, reason: 'กรอบหน้าจอ + ปุ่ม');
      d.components.first
        ..x = 300
        ..rotation = 45;
      paint();
      expect(WfPictureCache.length, n);
      d.components.first.text = 'changed';
      paint();
      expect(WfPictureCache.length, n + 1);
      d.style = WfStyle.clean;
      paint();
      expect(WfPictureCache.length, n + 3);
    });
  });

  group('บนจอ', () {
    late WorkspaceController w;
    late WireframeController f;

    Future<void> boot(WidgetTester tester, {Lang lang = Lang.th}) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang, showExplorer: true)));
      w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      w.addDocument(DocType.wireframe, name: 'Home');
      await tester.pumpAndSettle();
      f = tester.element(find.byType(HomePage)).read<WireframeController>();
    }

    Finder inPanel(Finder m) => find.descendant(of: find.byType(WireframeRightPanel), matching: m);

    testWidgets('ภาพย่อและขนาดหน้าจออยู่บนสุดเสมอ แม้เลือกชิ้นส่วน ; ขนาดไม่ซ้ำสองครั้ง', (tester) async {
      await boot(tester);
      final size = tester.widget<Text>(find.byKey(const ValueKey('wf-page-size'))).data!;
      expect(size, wfFrameLabel(f.diagram));
      expect(RegExp('1440').allMatches(size).length, 1);
      final a = f.addComponent(WfKind.button, 300, 200)!;
      f.cancelEditing();
      f.selectBox(a.id);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wf-page-thumb')), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const ValueKey('wf-page-thumb'))).dy,
          lessThan(tester.getTopLeft(find.byKey(const ValueKey('wf-delete'))).dy));
      expect(find.byKey(const ValueKey('wf-rotation-0')), findsOneWidget);
    });

    testWidgets('เลเยอร์: ตา = ซ่อน/แสดง ; กุญแจ = ล็อก ; Ctrl+G แล้วมีแถวกลุ่ม พับได้ ; คลิกสมาชิก = เลือกชิ้นเดียว', (tester) async {
      await boot(tester);
      final a = f.addComponent(WfKind.button, 300, 200)!;
      final b = f.addComponent(WfKind.label, 600, 200)!;
      f.cancelEditing();
      await tester.pumpAndSettle();

      Future<void> tapKey(String k) async {
        await tester.ensureVisible(find.byKey(ValueKey(k)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(k)));
        await tester.pumpAndSettle();
      }

      await tapKey('wf-eye-${a.id}');
      expect(f.diagram.componentById(a.id)!.hidden, isTrue);
      await tapKey('wf-eye-${a.id}');
      expect(f.diagram.componentById(a.id)!.hidden, isFalse);
      await tapKey('wf-lock-${b.id}');
      expect(f.diagram.componentById(b.id)!.locked, isTrue);

      f.setSelection([a.id, b.id]);
      await tester.pumpAndSettle();
      await tapKey('wf-layer-group');
      final g = f.diagram.componentById(a.id)!.group!;
      expect(inPanel(find.byKey(ValueKey('wf-group-$g'))), findsOneWidget);
      expect(find.text('กลุ่ม · 2 ชิ้น'), findsOneWidget);

      await tapKey('wf-item-${a.id}');
      expect(f.selectedIds, {a.id});
      await tapKey('wf-group-$g');
      expect(f.selectedIds, {a.id, b.id});

      await tapKey('wf-group-toggle-$g');
      expect(find.byKey(ValueKey('wf-item-${a.id}')), findsNothing);
      await tapKey('wf-group-toggle-$g');
      expect(find.byKey(ValueKey('wf-item-${a.id}')), findsOneWidget);

      // กุญแจของกลุ่มล็อกทุกชิ้น
      await tapKey('wf-lock-$g');
      expect(f.diagram.components.every((c) => c.locked), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ลากแถวในแผงเลเยอร์ด้วยเมาส์ = เปลี่ยนลำดับการซ้อน (undo ได้) ; คลิกแถวยังเลือกได้ตามเดิม', (tester) async {
      await boot(tester);
      final a = f.addComponent(WfKind.button, 300, 200)!;
      final b = f.addComponent(WfKind.label, 600, 200)!;
      final c = f.addComponent(WfKind.input, 900, 200)!;
      f.cancelEditing();
      f.clearSelection();
      await tester.pumpAndSettle();
      List<String> z() => [for (final x in f.diagram.components) x.id];
      expect(z(), [a.id, b.id, c.id]);

      final rowA = find.byKey(ValueKey('wf-layer-row-${a.id}'));
      final rowC = find.byKey(ValueKey('wf-layer-row-${c.id}'));
      await tester.ensureVisible(rowA);
      await tester.pumpAndSettle();
      // a อยู่แถวล่างสุด (ล่างสุดของการซ้อน) → ลากขึ้นไปเหนือ c (บนสุด)
      final from = tester.getCenter(rowA);
      final to = tester.getTopLeft(rowC) + const Offset(20, 2);
      final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(z(), [b.id, c.id, a.id], reason: 'a ขึ้นบนสุด');
      f.undo();
      await tester.pumpAndSettle();
      expect(z(), [a.id, b.id, c.id]);

      await tester.tap(find.byKey(ValueKey('wf-item-${b.id}')));
      await tester.pumpAndSettle();
      expect(f.selectedIds, {b.id});
      expect(tester.takeException(), isNull);
    });

    testWidgets('บนแคนวาส: คลิกชิ้นที่ล็อกไม่โดน ; Ctrl+G / Ctrl+Shift+G ; ภาษาอังกฤษไม่มีไทยหลุดในแผง', (tester) async {
      await boot(tester, lang: Lang.en);
      final a = f.addComponent(WfKind.button, 300, 200)!;
      final b = f.addComponent(WfKind.label, 600, 200)!;
      f.cancelEditing();
      f.setLocked([a.id], true);
      await tester.pumpAndSettle();
      final canvas = find.byKey(const ValueKey('wf-canvas'));
      await tester.tapAt(tester.getTopLeft(canvas) + f.toScreen(const Offset(300, 200)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(f.selectedIds, isEmpty);

      f.setLocked([a.id], false);
      f.setSelection([a.id, b.id]);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(f.diagram.componentById(a.id)!.group, isNotNull);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(f.diagram.componentById(a.id)!.group, isNull);

      f.selectBox(a.id);
      await tester.pumpAndSettle();
      final thai = RegExp(r'[฀-๿]');
      final leaks = [
        for (final t in tester.widgetList<Text>(inPanel(find.byType(Text))))
          if (thai.hasMatch(t.data ?? '') && t.data != f.diagram.componentById(a.id)!.text) t.data,
      ];
      expect(leaks, isEmpty);
    });
  });
}
