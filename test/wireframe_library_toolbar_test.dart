import 'dart:convert';
import 'dart:io';

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
import 'package:nsl_nebular/ui/wireframe/wf_library.dart';
import 'package:nsl_nebular/ui/wireframe/wf_panels.dart' show WireframeLeftPanel;
import 'package:nsl_nebular/ui/wireframe/wf_toolbar.dart';
import 'package:provider/provider.dart';

/// Phase 18: แถบเครื่องมือเต็มความกว้าง + คลังชิ้นส่วน 6 หมวด (แบบ A กริด / แบบ B รายการ) + ใช้ล่าสุด
void main() {
  group('หมวดของคลัง', () {
    test('ทุกชนิดอยู่ในหมวดเดียวพอดี (ครบ ไม่ซ้ำ)', () {
      final all = [for (final c in kWfCategories) ...c.kinds];
      expect(all.toSet(), WfKind.values.toSet());
      expect(all.length, WfKind.values.length);
      expect(kWfCategories.length, 7); // 6 หมวดเดิม + มือถือ (แม่แบบ/ของฉันเป็นหมวดพิเศษแยกจากชนิด)
    });

    test('แถบวางด่วน: สี่ตัวคงที่ + ช่องที่ 5 = ใช้ล่าสุดที่ไม่ซ้ำ ไม่มี = รูปภาพ', () {
      expect(wfQuickKinds(const []), [...kWfQuickKinds, WfKind.image]);
      expect(wfQuickKinds([WfKind.button, WfKind.chart, WfKind.table]).last, WfKind.chart);
      expect(wfQuickKinds([WfKind.label]).last, WfKind.image);
    });
  });

  group('ใช้ล่าสุด (AppSettings)', () {
    test('ใหม่สุดก่อน ไม่ซ้ำ ไม่เกิน 6 ; ใช้ชิ้นเดิมซ้ำ = ย้ายขึ้นหน้า', () {
      final s = AppSettings();
      for (final k in [WfKind.chart, WfKind.table, WfKind.card, WfKind.tabs, WfKind.modal, WfKind.badge, WfKind.chip]) {
        s.addWfRecent(k);
      }
      expect(s.wfRecentKinds.length, AppSettings.kWfRecentMax);
      expect(s.wfRecentKinds.first, WfKind.chip);
      expect(s.wfRecentKinds, isNot(contains(WfKind.chart))); // ตกขอบ
      s.addWfRecent(WfKind.card);
      expect(s.wfRecentKinds.first, WfKind.card);
      expect(s.wfRecentKinds.where((k) => k == WfKind.card).length, 1);
    });

    test('บันทึกลงไฟล์ตั้งค่าและอ่านกลับได้ ; ชื่อที่ไม่รู้จักถูกข้าม ; ไม่มีใน JSON เมื่อว่าง', () {
      final dir = Directory.systemTemp.createTempSync('wfrecent');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/settings.json');
      final s = AppSettings(file: file, lang: Lang.th);
      expect(file.existsSync(), isFalse);
      s.addWfRecent(WfKind.table);
      s.addWfRecent(WfKind.chart);
      s.setWfLibraryList(true);
      final m = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(m['wfRecent'], ['chart', 'table']);
      expect(m['wfList'], true);

      final back = AppSettings.load(file);
      expect(back.wfRecentKinds, [WfKind.chart, WfKind.table]);
      expect(back.wfLibraryList, isTrue);

      m['wfRecent'] = ['chart', 'ghost', 7, 'table'];
      file.writeAsStringSync(jsonEncode(m));
      expect(AppSettings.load(file).wfRecentKinds, [WfKind.chart, WfKind.table]);
    });

    test('ค่าเริ่มต้น: ไม่มีประวัติ มุมมองกริด', () {
      final s = AppSettings();
      expect(s.wfRecentKinds, isEmpty);
      expect(s.wfLibraryList, isFalse);
    });
  });

  testWidgets('รูปย่อวาดได้ครบทุกชนิดโดยไม่ error', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Wrap(children: [for (final k in WfKind.values) WfKindThumb(k, color: Colors.black)]),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(WfKindThumb), findsNWidgets(WfKind.values.length));
  });

  group('บนจอ', () {
    late WireframeController f;
    late AppSettings settings;

    Future<void> boot(WidgetTester tester, {Lang lang = Lang.th, Size size = const Size(1600, 1000), bool explorer = true}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => currentLang = Lang.th);
      settings = AppSettings(lang: lang, showExplorer: explorer);
      await tester.pumpWidget(NslDevApp(settings: settings));
      final w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      w.addDocument(DocType.wireframe, name: 'Home');
      await tester.pumpAndSettle();
      f = tester.element(find.byType(HomePage)).read<WireframeController>();
    }

    testWidgets('แถบเครื่องมือเต็มความกว้างเหนือแคนวาส: เลือก · วางด่วน 5 · เพิ่มเติม · ร่าง/เรียบร้อย · ผลตรวจ · Snap · ส่งออก', (tester) async {
      await boot(tester);
      final bar = find.byKey(const ValueKey('wf-toolbar'));
      expect(bar, findsOneWidget);
      expect(tester.getSize(bar).height, 44);
      // เต็มความกว้างของพื้นที่แคนวาส (ไม่ใช่กล่องลอยกลางจอ)
      expect(tester.getSize(bar).width, tester.getSize(find.byKey(const ValueKey('wf-canvas'))).width);
      for (final k in ['pointer', 'label', 'button', 'input', 'container', 'image']) {
        expect(find.byKey(ValueKey('wf-tool-$k')), findsOneWidget, reason: k);
      }
      for (final k in ['wf-more', 'wf-style-sketch', 'wf-style-clean', 'wf-rules', 'wf-snap', 'wf-export']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      // แถบอยู่เหนือแคนวาส
      expect(tester.getBottomLeft(bar).dy, lessThanOrEqualTo(tester.getTopLeft(find.byKey(const ValueKey('wf-canvas'))).dy + 0.5));
    });

    testWidgets('ปุ่มวางด่วนเลือกเครื่องมือ ; เลือก = กลับมาเป็นตัวชี้ ; ร่าง/เรียบร้อยสลับได้ ; Snap สลับค่าตั้ง', (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('wf-tool-input')));
      await tester.pump();
      expect((f.tool, f.toolKind), (WfTool.place, WfKind.input));
      await tester.tap(find.byKey(const ValueKey('wf-tool-pointer')));
      await tester.pump();
      expect(f.tool, WfTool.select);
      await tester.tap(find.byKey(const ValueKey('wf-style-clean')));
      await tester.pump();
      expect(f.diagram.style, WfStyle.clean);
      final snap0 = settings.snapToGrid;
      await tester.tap(find.byKey(const ValueKey('wf-snap')));
      await tester.pump();
      expect(settings.snapToGrid, !snap0);
    });

    testWidgets('วางชิ้นส่วนแล้วเข้า "ใช้ล่าสุด" และช่องที่ 5 ของแถบวางด่วนเปลี่ยนตาม', (tester) async {
      await boot(tester);
      expect(find.byKey(const ValueKey('wf-tool-image')), findsOneWidget);
      expect(find.text('ใช้ล่าสุด'), findsNothing);
      f.setPlaceTool(WfKind.chart);
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('wf-canvas'))));
      await tester.pumpAndSettle();
      expect(f.diagram.components.where((c) => c.kind == WfKind.chart).length, 1);
      expect(settings.wfRecentKinds, [WfKind.chart]);
      expect(find.text('ใช้ล่าสุด'), findsOneWidget);
      expect(find.byKey(const ValueKey('wf-recent-chart')), findsOneWidget);
      expect(find.byKey(const ValueKey('wf-tool-chart')), findsOneWidget); // ช่องที่ 5
      expect(find.byKey(const ValueKey('wf-tool-image')), findsNothing);
      // ชิ้นล่าสุดที่เป็นหนึ่งในสี่ตัวคงที่ ไม่แทนช่องที่ 5
      settings.addWfRecent(WfKind.button);
      await tester.pump();
      expect(find.byKey(const ValueKey('wf-tool-chart')), findsOneWidget);
    });

    testWidgets('คลัง: หมวดพับ/ขยายได้ ; ค้นหาเปิดทุกหมวดที่มีผลและซ่อนที่ไม่มี ; ไม่พบ = ข้อความ', (tester) async {
      await boot(tester);
      for (final c in kWfCategories) {
        expect(find.byKey(ValueKey('wf-cat-${c.id}')), findsOneWidget, reason: c.id);
      }
      expect(find.byKey(const ValueKey('wf-kind-table')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('wf-cat-data')));
      await tester.tap(find.byKey(const ValueKey('wf-cat-data')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wf-kind-table')), findsNothing);
      expect(find.byKey(const ValueKey('wf-kind-button')), findsOneWidget); // หมวดอื่นไม่กระทบ
      await tester.ensureVisible(find.byKey(const ValueKey('wf-cat-data')));
      await tester.tap(find.byKey(const ValueKey('wf-cat-data')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wf-kind-table')), findsOneWidget);

      // ค้นหา: หมวดที่พับอยู่ก็เปิดให้เห็นผล และหมวดที่ไม่มีผลหายไป
      await tester.ensureVisible(find.byKey(const ValueKey('wf-cat-media')));
      await tester.tap(find.byKey(const ValueKey('wf-cat-media')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('wf-search')), 'image');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wf-kind-image')), findsOneWidget);
      expect(find.byKey(const ValueKey('wf-cat-form')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('wf-search')), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.textContaining('ไม่พบชิ้นส่วนที่ตรงกับ'), findsOneWidget);
    });

    testWidgets('พับทุกหมวด: แผงซ้ายยังเต็มความสูง ไม่หดแล้วลอยกลางแนวตั้ง', (tester) async {
      await boot(tester);
      double panelH() => tester.getSize(find.byType(WireframeLeftPanel)).height;
      // ความสูงพื้นที่ใต้แท็บ = แถบเครื่องมือ 44 + แคนวาส
      final body = 44 + tester.getSize(find.byKey(const ValueKey('wf-canvas'))).height;
      expect(panelH(), body);
      for (final c in kWfCategories) {
        await tester.ensureVisible(find.byKey(ValueKey('wf-cat-${c.id}')));
        await tester.tap(find.byKey(ValueKey('wf-cat-${c.id}')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('wf-kind-button')), findsNothing);
      expect(panelH(), body);
      expect(tester.getTopLeft(find.byType(WireframeLeftPanel)).dy, tester.getTopLeft(find.byKey(const ValueKey('wf-toolbar'))).dy);
    });

    testWidgets('สลับมุมมองกริด/รายการ: ชิ้นส่วนเดิมครบ ลากและคลิกได้ และจำค่าไว้ในตั้งค่า', (tester) async {
      await boot(tester);
      final tileSize = tester.getSize(find.byKey(const ValueKey('wf-kind-button')));
      await tester.tap(find.byKey(const ValueKey('wf-view-list')));
      await tester.pumpAndSettle();
      expect(settings.wfLibraryList, isTrue);
      for (final k in WfKind.values) {
        expect(find.byKey(ValueKey('wf-kind-${k.name}'), skipOffstage: false), findsOneWidget, reason: k.name);
      }
      final rowSize = tester.getSize(find.byKey(const ValueKey('wf-kind-button')));
      expect(rowSize.width, greaterThan(tileSize.width * 1.5)); // แถวกว้างเต็มแผง
      await tester.tap(find.byKey(const ValueKey('wf-kind-button')));
      await tester.pump();
      expect((f.tool, f.toolKind), (WfTool.place, WfKind.button));
      await tester.tap(find.byKey(const ValueKey('wf-view-grid')));
      await tester.pumpAndSettle();
      expect(settings.wfLibraryList, isFalse);
      expect(tester.getSize(find.byKey(const ValueKey('wf-kind-button'))), tileSize);
    });

    testWidgets('ปุ่ม "เพิ่มเติม" ย้ายโฟกัสไปช่องค้นหาของคลัง', (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('wf-more')));
      await tester.pump();
      final field = tester.widget<TextField>(find.byKey(const ValueKey('wf-search')));
      expect(field.focusNode!.hasFocus, isTrue);
    });

    testWidgets('ปุ่มวางไม่ล้นเมื่อแผงซ้ายแคบสุด และแถบเครื่องมือไม่ล้นเมื่อหน้าต่างแคบ', (tester) async {
      await boot(tester, size: const Size(1000, 800), explorer: false); // พื้นที่แคนวาสเหลือราว 470px
      settings.layout.setLeft(PanelLayout.kLeftMin);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('wf-view-list')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ภาษาอังกฤษ: ไม่มีข้อความไทยหลุดในแถบเครื่องมือและคลัง', (tester) async {
      await boot(tester, lang: Lang.en);
      settings.addWfRecent(WfKind.chart);
      await tester.pumpAndSettle();
      final thai = RegExp(r'[฀-๿]');
      for (final root in [find.byKey(const ValueKey('wf-toolbar')), find.byType(WireframeLeftPanel)]) {
        for (final t in tester.widgetList<Text>(find.descendant(of: root, matching: find.byType(Text)))) {
          expect(thai.hasMatch(t.data ?? ''), isFalse, reason: '${t.data}');
        }
      }
      await tester.enterText(find.byKey(const ValueKey('wf-search')), 'zzzz');
      await tester.pumpAndSettle();
      expect(thai.hasMatch(tester.widget<Text>(find.textContaining('No components match')).data!), isFalse);
    });
  });
}
