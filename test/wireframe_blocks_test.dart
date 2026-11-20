import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/layout/wireframe_render.dart';
import 'package:nsl_nebular/core/models/wf_block.dart';
import 'package:nsl_nebular/core/models/wf_templates.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/wireframe_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/ui/wireframe/wf_actions.dart';
import 'package:provider/provider.dart';

/// Phase 18b: แม่แบบสำเร็จรูป 8 ชุด + "บันทึกเป็นบล็อกของฉัน"
void main() {
  WfBlock sample({String id = 'my-1', String name = 'ชุดทดสอบ'}) => WfBlock(
        id: id,
        name: name,
        w: 200,
        h: 100,
        parts: [
          WfComponent(id: 'a', kind: WfKind.container, x: 0, y: 0, w: 200, h: 100),
          WfComponent(id: 'b', kind: WfKind.button, text: 'OK', x: 10, y: 20, w: 80, h: 40),
          WfComponent(id: 'c', kind: WfKind.label, text: 'L', x: 100, y: 20, w: 80, h: 24),
        ],
      );

  group('แม่แบบ 8 ชุด', () {
    test('มี 8 ชุด รหัสไม่ซ้ำ ชื่อไม่ว่าง ทุกชิ้นอยู่ในกรอบของบล็อก', () {
      final all = wfTemplateBlocks();
      expect(all.length, 8);
      expect(all.map((b) => b.id).toSet().length, 8);
      for (final b in all) {
        expect(b.isTemplate, isTrue);
        expect(b.name.trim(), isNotEmpty);
        expect(b.parts, isNotEmpty, reason: b.id);
        expect(b.parts.map((p) => p.id).toSet().length, b.parts.length, reason: '${b.id} id ซ้ำ');
        for (final p in b.parts) {
          expect(p.x >= -0.01 && p.y >= -0.01, isTrue, reason: '${b.id}/${p.kind.name} ล้นซ้ายบน');
          expect(p.x + p.w <= b.w + 0.5 && p.y + p.h <= b.h + 0.5, isTrue, reason: '${b.id}/${p.kind.name} ล้นขวาล่าง (${p.x + p.w}x${p.y + p.h} > ${b.w}x${b.h})');
        }
      }
    });

    test('ชื่อ 8 ชุดตามดีไซน์', () {
      expect(wfTemplateBlocks().map((b) => b.id), [
        'tpl-login', 'tpl-signup', 'tpl-profile', 'tpl-product', 'tpl-cart-row', 'tpl-pricing', 'tpl-hero', 'tpl-page-header',
      ]);
    });

    test('วาดได้ทั้งสองรูปแบบ ไม่มี NaN ; รูปย่อมีขนาดตามบล็อก', () {
      for (final b in wfTemplateBlocks()) {
        for (final s in WfStyle.values) {
          final d = b.previewDiagram(style: s);
          expect(d.width, b.w + 8);
          expect(wireframePrims(d, frame: false), isNotEmpty, reason: b.id);
        }
      }
    });

    test('ภาษาอังกฤษ: ชื่อและข้อความทุกชิ้นไม่มีไทยหลุด', () {
      final before = currentLang;
      addTearDown(() => currentLang = before);
      currentLang = Lang.en;
      // ตัวอักษรไทยทั้งช่วง ยกเว้นสัญลักษณ์เงินบาท ฿ (U+0E3F) ซึ่งเป็นสกุลเงินในข้อมูลตัวอย่าง
      final thai = RegExp(r'[฀-฾เ-๿]');
      for (final b in wfTemplateBlocks()) {
        expect(thai.hasMatch(b.name), isFalse, reason: b.name);
        for (final p in b.parts) {
          expect(thai.hasMatch(p.text), isFalse, reason: '${b.id}: ${p.text}');
        }
      }
    });
  });

  group('WfBlock', () {
    test('JSON เขียน-อ่านครบ', () {
      final b = WfBlock.tryFromJson(jsonDecode(jsonEncode(sample().toJson())))!;
      expect((b.id, b.name, b.w, b.h, b.parts.length), ('my-1', 'ชุดทดสอบ', 200.0, 100.0, 3));
      expect(b.parts[1].text, 'OK');
      expect(b.isTemplate, isFalse);
    });

    test('ข้อมูลเสียถูกปฏิเสธ (null) ไม่พัง', () {
      expect(WfBlock.tryFromJson(null), isNull);
      expect(WfBlock.tryFromJson('x'), isNull);
      expect(WfBlock.tryFromJson({'id': 'a', 'name': 'n', 'w': 10, 'h': 10, 'parts': []}), isNull);
      expect(WfBlock.tryFromJson({'id': '', 'name': 'n', 'w': 10, 'h': 10, 'parts': [sample().parts.first.toJson()]}), isNull);
      expect(WfBlock.tryFromJson({'id': 'a', 'name': 'n', 'w': -1, 'h': 10, 'parts': [sample().parts.first.toJson()]}), isNull);
      expect(WfBlock.tryFromJson({'id': 'a', 'name': 'n', 'w': 'x', 'h': 10, 'parts': [sample().parts.first.toJson()]}), isNull);
      // ชิ้นที่อ่านไม่ได้ถูกข้าม ชิ้นที่ดียังอยู่
      final ok = WfBlock.tryFromJson({'id': 'a', 'name': 'n', 'w': 10, 'h': 10, 'parts': ['junk', sample().parts.first.toJson()]})!;
      expect(ok.parts.length, 1);
    });

    test('fromComponents: พิกัดสัมพัทธ์มุมซ้ายบน=0,0 ; ตัดกลุ่ม/ล็อก/ซ่อนเดิมทิ้ง ; ขนาดคือกรอบรวม', () {
      final src = [
        WfComponent(id: 'x', kind: WfKind.button, x: 300, y: 200, w: 100, h: 40)
          ..group = 'g1'
          ..locked = true
          ..hidden = true,
        WfComponent(id: 'y', kind: WfKind.label, x: 340, y: 260, w: 80, h: 20),
      ];
      final b = WfBlock.fromComponents('b1', 'ชื่อ', src)!;
      expect((b.w, b.h), (120.0, 80.0));
      expect((b.parts[0].x, b.parts[0].y), (0, 0));
      expect((b.parts[1].x, b.parts[1].y), (40, 60));
      expect(b.parts[0].group, isNull);
      expect(b.parts[0].locked, isFalse);
      expect(b.parts[0].hidden, isFalse);
      expect(WfBlock.fromComponents('b', 'n', const []), isNull);
    });
  });

  group('ของฉัน (AppSettings)', () {
    test('เพิ่ม เปลี่ยนชื่อ ลบ ; บล็อกซ้ำ id = แทนที่', () {
      final s = AppSettings();
      s.addWfMyBlock(sample());
      s.addWfMyBlock(sample(id: 'my-2', name: 'สอง'));
      expect(s.wfMyBlocks.map((b) => b.name), ['ชุดทดสอบ', 'สอง']);
      s.renameWfMyBlock('my-1', '  ใหม่  ');
      expect(s.wfMyBlocks.first.name, 'ใหม่');
      s.renameWfMyBlock('my-1', '   '); // ชื่อว่าง = ไม่เปลี่ยน
      expect(s.wfMyBlocks.first.name, 'ใหม่');
      s.addWfMyBlock(sample(id: 'my-2', name: 'สองใหม่'));
      expect(s.wfMyBlocks.length, 2);
      expect(s.wfMyBlocks.last.name, 'สองใหม่');
      s.removeWfMyBlock('my-1');
      expect(s.wfMyBlocks.map((b) => b.id), ['my-2']);
      s.removeWfMyBlock('nope');
      expect(s.wfMyBlocks.length, 1);
    });

    test('เก็บไม่เกิน 100 บล็อก (ตัดเก่าสุด)', () {
      final s = AppSettings();
      for (var i = 0; i < AppSettings.kWfMyBlocksMax + 5; i++) {
        s.addWfMyBlock(sample(id: 'b$i', name: 'n$i'));
      }
      expect(s.wfMyBlocks.length, AppSettings.kWfMyBlocksMax);
      expect(s.wfMyBlocks.first.id, 'b5');
      expect(s.wfMyBlocks.last.id, 'b${AppSettings.kWfMyBlocksMax + 4}');
    });

    test('บันทึกลงไฟล์ตั้งค่าของเครื่องและอ่านกลับได้ ; รายการเสียถูกข้าม ; ว่าง = ไม่มีคีย์', () {
      final dir = Directory.systemTemp.createTempSync('wfblocks');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/settings.json');
      final s = AppSettings(file: file, lang: Lang.th);
      s.addWfMyBlock(sample());
      final m = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect((m['wfBlocks'] as List).length, 1);
      expect(AppSettings.load(file).wfMyBlocks.single.parts.length, 3);

      m['wfBlocks'] = [...(m['wfBlocks'] as List), 'junk', {'id': 1}];
      file.writeAsStringSync(jsonEncode(m));
      expect(AppSettings.load(file).wfMyBlocks.length, 1);

      s.removeWfMyBlock('my-1');
      expect((jsonDecode(file.readAsStringSync()) as Map).containsKey('wfBlocks'), isFalse);
    });

    test('ไม่ลงไฟล์โปรเจกต์: เอกสาร Wireframe ไม่มีเรื่องบล็อก', () {
      final d = WireframeDiagram(components: sample().parts);
      expect(jsonEncode(d.toJson()).contains('wfBlocks'), isFalse);
    });
  });

  group('บนจอ', () {
    late WireframeController f;
    late WorkspaceController w;
    late AppSettings settings;

    Future<void> boot(WidgetTester tester, {Lang lang = Lang.th, List<WfBlock> mine = const []}) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => currentLang = Lang.th);
      settings = AppSettings(lang: lang, showExplorer: true, wfBlocks: mine);
      await tester.pumpWidget(NslDevApp(settings: settings));
      w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      w.addDocument(DocType.wireframe, name: 'Home');
      await tester.pumpAndSettle();
      f = tester.element(find.byType(HomePage)).read<WireframeController>();
    }

    Future<void> tapVisible(WidgetTester tester, String key) async {
      final fnd = find.byKey(ValueKey(key));
      await tester.ensureVisible(fnd);
      await tester.pumpAndSettle();
      await tester.tap(fnd);
      await tester.pumpAndSettle();
    }

    testWidgets('วางบล็อก: id ใหม่ทุกชิ้น เป็นกลุ่มเดียวชื่อเดียวกับบล็อก ศูนย์กลางตรงจุดที่วาง เลือกทั้งชุด undo ขั้นเดียว', (tester) async {
      await boot(tester);
      final b = sample();
      final ids = f.insertBlock(b, 500, 400);
      expect(ids.length, 3);
      expect(ids.toSet().length, 3);
      expect(ids.any((id) => b.parts.map((p) => p.id).contains(id)), isFalse);
      final comps = [for (final id in ids) f.diagram.componentById(id)!];
      // ศูนย์กลางกรอบของบล็อก (200x100) อยู่ที่ (500,400)
      expect((comps[0].x, comps[0].y), (400, 350));
      expect((comps[1].x, comps[1].y), (410, 370));
      final groupIds = comps.map((c) => c.group).toSet();
      expect(groupIds.length, 1);
      expect(groupIds.single, isNotNull);
      expect(f.diagram.groups.where((g) => g.id == groupIds.single).single.name, 'ชุดทดสอบ');
      // ลูกในภาชนะไม่ถูกเลือกซ้ำ: เลือกแค่ชิ้นบนสุด (ภาชนะ) เหมือนการวางจากคลิปบอร์ด
      expect(f.selectedIds, {ids[0]});
      expect(f.tool, WfTool.select);
      expect(f.toolBlock, isNull);
      f.undo();
      expect(f.diagram.components, isEmpty);
      expect(f.diagram.groups, isEmpty);
    });

    testWidgets('วางบล็อกสองครั้ง = สองกลุ่มแยกกัน ; snap จัดตามตาราง ; บล็อกว่างไม่ทำอะไร', (tester) async {
      await boot(tester);
      f.insertBlock(sample(), 300, 300);
      f.insertBlock(sample(), 300, 300);
      expect(f.diagram.components.map((c) => c.group).toSet().length, 2);
      expect(f.insertBlock(WfBlock(id: 'e', name: 'e', w: 1, h: 1, parts: []), 0, 0), isEmpty);
      final before = f.diagram.components.length;
      final ids = f.insertBlock(sample(), 503, 407, snap: true);
      final first = f.diagram.componentById(ids.first)!;
      expect(first.x % 8 == 0 || first.x % 10 == 0 || first.x % 5 == 0, isTrue, reason: '${first.x}');
      expect(f.diagram.components.length, before + 3);
    });

    testWidgets('ผูกข้อมูล ER ที่ตั้งไว้ในบล็อกติดไปด้วย', (tester) async {
      await boot(tester);
      final p = WfComponent(id: 'p', kind: WfKind.input, x: 0, y: 0, w: 100, h: 40)..ref = const WfDataRef(docId: 'd', tableId: 't', columnId: 'c');
      final ids = f.insertBlock(WfBlock(id: 'r', name: 'r', w: 100, h: 40, parts: [p]), 200, 200);
      final r = f.diagram.componentById(ids.single)!.ref!;
      expect((r.docId, r.tableId, r.columnId), ('d', 't', 'c'));
    });

    testWidgets('blockFromSelection: รวมลูกในภาชนะ พิกัดสัมพัทธ์ ; ไม่ได้เลือก = null', (tester) async {
      await boot(tester);
      expect(f.blockFromSelection('i', 'n'), isNull);
      final box = f.addComponent(WfKind.container, 400, 300)!; // 320x200 ที่ (240,200)
      final inner = f.addComponent(WfKind.button, 400, 300)!; // อยู่ในภาชนะ
      f.setSelection([box.id]);
      final blk = f.blockFromSelection('i', 'n')!;
      expect(blk.parts.length, 2, reason: 'ลูกในภาชนะติดไปด้วย');
      expect(blk.parts.map((p) => p.kind), containsAll([WfKind.container, WfKind.button]));
      expect(blk.parts.any((p) => p.id == inner.id || p.x == 0 && p.y == 0), isTrue);
      expect((blk.w, blk.h), (box.w, box.h));
    });

    testWidgets('คลัง: หมวดแม่แบบมี 8 ช่อง · หมวดของฉันว่างมีข้อความบอกวิธี', (tester) async {
      await boot(tester);
      expect(find.byKey(const ValueKey('wf-cat-blocks')), findsOneWidget);
      expect(find.byKey(const ValueKey('wf-cat-mine')), findsOneWidget);
      for (final b in wfTemplateBlocks()) {
        expect(find.byKey(ValueKey('wf-block-${b.id}'), skipOffstage: false), findsOneWidget, reason: b.id);
      }
      expect(find.byKey(const ValueKey('wf-mine-empty'), skipOffstage: false), findsOneWidget);
    });

    testWidgets('คลิกแม่แบบ = เลือกเครื่องมือวางบล็อก ; คลิกบนแคนวาส = วางเป็นกลุ่ม ; ปุ่มชิ้นส่วนไม่ไฮไลต์ตอนเลือกบล็อก', (tester) async {
      await boot(tester);
      await tapVisible(tester, 'wf-block-tpl-login');
      expect(f.tool, WfTool.place);
      expect(f.toolBlock?.id, 'tpl-login');
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('wf-canvas'))));
      await tester.pumpAndSettle();
      final tpl = wfTemplateBlocks().firstWhere((b) => b.id == 'tpl-login');
      expect(f.diagram.components.length, tpl.parts.length);
      expect(f.diagram.components.map((c) => c.group).toSet().length, 1);
      expect(f.toolBlock, isNull);
      expect(f.tool, WfTool.select);
    });

    testWidgets('Esc ยกเลิกเครื่องมือบล็อก ; เลือกชิ้นส่วนธรรมดาแทน = ล้างบล็อก', (tester) async {
      await boot(tester);
      f.setPlaceBlockTool(sample());
      expect(f.toolBlock, isNotNull);
      f.escape();
      expect(f.tool, WfTool.select);
      expect(f.toolBlock, isNull);
      f.setPlaceBlockTool(sample());
      f.setPlaceTool(WfKind.button);
      expect((f.tool, f.toolKind, f.toolBlock), (WfTool.place, WfKind.button, null));
    });

    testWidgets('ลากแม่แบบจากคลังไปวางบนแคนวาส', (tester) async {
      await boot(tester);
      final tile = find.byKey(const ValueKey('wf-block-tpl-product'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      final g = await tester.startGesture(tester.getCenter(tile));
      await g.moveBy(const Offset(40, 0));
      await g.moveTo(tester.getCenter(find.byKey(const ValueKey('wf-canvas'))));
      await g.up();
      await tester.pumpAndSettle();
      expect(f.diagram.components.length, wfTemplateBlocks().firstWhere((b) => b.id == 'tpl-product').parts.length);
    });

    testWidgets('ค้นหาครอบคลุมบล็อก: "ตะกร้า" เจอแถวสินค้าในตะกร้า ; ไม่พบ = ข้อความ', (tester) async {
      await boot(tester, mine: [sample(name: 'ฟอร์มค้นหาห้อง')]);
      await tester.enterText(find.byKey(const ValueKey('wf-search')), 'ตะกร้า');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wf-block-tpl-cart-row')), findsOneWidget);
      expect(find.byKey(const ValueKey('wf-block-tpl-login')), findsNothing);
      expect(find.byKey(const ValueKey('wf-cat-mine')), findsNothing); // ไม่มีผลในของฉัน
      await tester.enterText(find.byKey(const ValueKey('wf-search')), 'ค้นหาห้อง');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wf-block-my-1')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('wf-search')), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.textContaining('ไม่พบชิ้นส่วนที่ตรงกับ'), findsOneWidget);
    });

    testWidgets('มุมมองรายการแสดงบล็อกเป็นแถวและวางได้', (tester) async {
      await boot(tester, mine: [sample()]);
      settings.setWfLibraryList(true);
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('wf-block-my-1'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(tester.getSize(row).width, greaterThan(150));
      await tester.tap(row);
      await tester.pump();
      expect(f.toolBlock?.id, 'my-1');
    });

    testWidgets('ของฉัน: คลิกขวา > เปลี่ยนชื่อ / ลบ', (tester) async {
      await boot(tester, mine: [sample()]);
      final tile = find.byKey(const ValueKey('wf-block-my-1'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('เปลี่ยนชื่อ…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'ชื่อใหม่');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(settings.wfMyBlocks.single.name, 'ชื่อใหม่');

      await tester.tap(find.byKey(const ValueKey('wf-block-my-1')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลบบล็อก'));
      await tester.pumpAndSettle();
      expect(settings.wfMyBlocks, isEmpty);
      expect(find.byKey(const ValueKey('wf-mine-empty'), skipOffstage: false), findsOneWidget);
    });

    testWidgets('คลิกขวาที่ชิ้นบนแคนวาส > บันทึกเป็นบล็อกของฉัน… > ตั้งชื่อ > เข้าหมวดของฉัน', (tester) async {
      await boot(tester);
      final a = f.addComponent(WfKind.button, 400, 300)!;
      final b2 = f.addComponent(WfKind.input, 700, 300)!;
      f.setSelection([a.id, b2.id]);
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(HomePage));
      await withClock(Clock.fixed(DateTime(2026, 11, 20, 10)), () async {
        final fut = WireframeActions(ctx).saveSelectionAsBlock();
        await tester.pumpAndSettle();
        expect(find.textContaining('บันทึก 2 ชิ้นส่วนเป็นบล็อกของฉัน'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, 'แถวค้นหา');
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(await fut, isTrue);
      });
      final saved = settings.wfMyBlocks.single;
      expect(saved.name, 'แถวค้นหา');
      expect(saved.parts.length, 2);
      expect(saved.id, startsWith('my-'));
      expect(find.byKey(ValueKey('wf-block-${saved.id}'), skipOffstage: false), findsOneWidget);
      expect(find.byKey(const ValueKey('wf-mine-empty'), skipOffstage: false), findsNothing);
      // วางกลับ = ได้ 2 ชิ้นใหม่
      final before = f.diagram.components.length;
      f.insertBlock(saved, 900, 600);
      expect(f.diagram.components.length, before + 2);
    });

    testWidgets('ยกเลิกกล่องตั้งชื่อ = ไม่บันทึก ; ไม่ได้เลือกอะไร = ไม่ถามเลย', (tester) async {
      await boot(tester);
      final ctx = tester.element(find.byType(HomePage));
      expect(await WireframeActions(ctx).saveSelectionAsBlock(), isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      final a = f.addComponent(WfKind.button, 400, 300)!;
      f.setSelection([a.id]);
      final fut = WireframeActions(ctx).saveSelectionAsBlock();
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(await fut, isFalse);
      expect(settings.wfMyBlocks, isEmpty);
    });

    testWidgets('ภาษาอังกฤษ: หัวข้อหมวดและข้อความของหมวดของฉันไม่มีไทยหลุด', (tester) async {
      await boot(tester, lang: Lang.en);
      final thai = RegExp(r'[฀-๿]');
      for (final k in ['wf-cat-blocks', 'wf-cat-mine', 'wf-mine-empty']) {
        final root = find.byKey(ValueKey(k), skipOffstage: false);
        final texts = k == 'wf-mine-empty' ? [tester.widget<Text>(find.descendant(of: root, matching: find.byType(Text), skipOffstage: false))] : tester.widgetList<Text>(find.descendant(of: root, matching: find.byType(Text), skipOffstage: false)).toList();
        for (final t in texts) {
          expect(thai.hasMatch(t.data ?? ''), isFalse, reason: '$k: ${t.data}');
        }
      }
    });
  });
}
