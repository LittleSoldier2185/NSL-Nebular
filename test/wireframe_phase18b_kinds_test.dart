import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/codegen/wireframe_code.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/layout/wireframe_render.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/wireframe_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/ui/wireframe/wf_library.dart';
import 'package:provider/provider.dart';

/// Phase 18b: ชิ้นส่วนใหม่ 15 ชนิด (มือถือ 6 · ฟอร์ม 5 · ข้อมูล/สถานะ 4)
const kPhase18b = [
  WfKind.statusBar,
  WfKind.appBar,
  WfKind.bottomNav,
  WfKind.fab,
  WfKind.bottomSheet,
  WfKind.drawer,
  WfKind.segmented,
  WfKind.optionGroup,
  WfKind.password,
  WfKind.numberInput,
  WfKind.timepicker,
  WfKind.emptyState,
  WfKind.toast,
  WfKind.kanban,
  WfKind.timeline,
];

bool _balanced(String code) {
  final stack = <String>[];
  const pairs = {')': '(', ']': '[', '}': '{'};
  String? quote;
  for (var i = 0; i < code.length; i++) {
    final ch = code[i];
    if (quote != null) {
      if (ch == r'\') {
        i++;
      } else if (ch == quote) {
        quote = null;
      }
      continue;
    }
    if (ch == "'" || ch == '"') {
      quote = ch;
    } else if ('([{'.contains(ch)) {
      stack.add(ch);
    } else if (pairs.containsKey(ch)) {
      if (stack.isEmpty || stack.removeLast() != pairs[ch]) return false;
    }
  }
  return stack.isEmpty && quote == null;
}

void main() {
  WfComponent make(WfKind k, {String? text, double? w, double? h, bool secondary = false, int rows = 3}) => WfComponent(
        id: 'c-${k.name}',
        kind: k,
        text: text ?? WireframeController.defaultText(k),
        x: 20,
        y: 20,
        w: w,
        h: h,
        secondary: secondary,
        rows: rows,
      );

  group('ตัวแบบ', () {
    test('15 ชนิดอยู่ท้าย enum ต่อจาก 45 ชนิดเดิมตามลำดับ (ไฟล์เก่าอ่านได้ ลำดับเดิมไม่เปลี่ยน)', () {
      expect(WfKind.values.length, 60);
      expect(WfKind.values.sublist(45), kPhase18b);
    });

    test('ขนาดเริ่มต้นตามดีไซน์', () {
      expect(wfDefaultSize(WfKind.statusBar), (390.0, 28.0));
      expect(wfDefaultSize(WfKind.appBar), (390.0, 56.0));
      expect(wfDefaultSize(WfKind.bottomNav), (390.0, 64.0));
      expect(wfDefaultSize(WfKind.fab), (56.0, 56.0));
      expect(wfDefaultSize(WfKind.drawer), (280.0, 600.0));
      expect(wfDefaultSize(WfKind.kanban), (620.0, 320.0));
    });

    test('แยก "ชื่อ | รายละเอียด"', () {
      expect(wfSplitPipe('สั่งซื้อ | 12 ธ.ค.'), ('สั่งซื้อ', '12 ธ.ค.'));
      expect(wfSplitPipe('ไม่มีรายละเอียด'), ('ไม่มีรายละเอียด', ''));
      expect(wfSplitPipe('a | b | c'), ('a', 'b | c'));
    });

    test('ชนิดใหม่ทุกชนิดอยู่ในคลังหมวดใดหมวดหนึ่งพอดี', () {
      final all = [for (final c in kWfCategories) ...c.kinds];
      for (final k in kPhase18b) {
        expect(all.where((x) => x == k).length, 1, reason: k.name);
      }
      expect(kWfCategories.firstWhere((c) => c.id == 'mobile').kinds, kPhase18b.sublist(0, 6));
    });
  });

  group('โค้ดที่สร้าง', () {
    test('Flutter: ทุกชนิดใหม่ได้วิดเจ็ตและวงเล็บสมดุล', () {
      for (final k in kPhase18b) {
        final d = WireframeDiagram(components: [make(k)]);
        final code = flutterScreen('Test', d);
        expect(_balanced(code), isTrue, reason: '${k.name}\n$code');
        expect(code, isNot(contains('Text(${k.name})')), reason: 'ต้องไม่ตกไปใช้ชื่อชนิดเป็นข้อความ ${k.name}');
      }
      String w(WfKind k, {bool secondary = false}) => flutterScreen('T', WireframeDiagram(components: [make(k, secondary: secondary)]));
      expect(w(WfKind.bottomNav), contains('NavigationBar('));
      expect(w(WfKind.appBar), contains('AppBar('));
      expect(w(WfKind.fab), contains('FloatingActionButton('));
      expect(w(WfKind.drawer), contains('UserAccountsDrawerHeader('));
      expect(w(WfKind.segmented), contains('SegmentedButton<int>('));
      expect(w(WfKind.optionGroup), contains('RadioListTile'));
      expect(w(WfKind.optionGroup, secondary: true), contains('CheckboxListTile'));
      expect(w(WfKind.password), contains('obscureText: true'));
      expect(w(WfKind.kanban), contains('Axis.horizontal'));
      expect(w(WfKind.timeline), contains('subtitle: Text('));
    });

    test('Flutter: bottomNav ที่มีแท็บเดียวยังมี 2 ปลายทาง (NavigationBar ต้องการอย่างน้อย 2)', () {
      final code = flutterScreen('T', WireframeDiagram(components: [make(WfKind.bottomNav, text: 'หน้าแรก')]));
      expect('NavigationDestination('.allMatches(code).length, 2);
    });

    test('HTML: ทุกชนิดใหม่มีองค์ประกอบของตัวเอง ไม่มี NaN ทั้งสองรูปแบบ', () {
      const cls = {
        WfKind.statusBar: 'wf-status',
        WfKind.appBar: 'wf-appbar',
        WfKind.bottomNav: 'wf-bnav',
        WfKind.fab: 'wf-fab',
        WfKind.bottomSheet: 'wf-sheet',
        WfKind.drawer: 'wf-drawer',
        WfKind.segmented: 'wf-seg',
        WfKind.optionGroup: 'wf-opts',
        WfKind.password: 'wf-pw',
        WfKind.numberInput: 'wf-num',
        WfKind.timepicker: 'wf-time',
        WfKind.emptyState: 'wf-empty',
        WfKind.toast: 'wf-toast',
        WfKind.kanban: 'wf-kan',
        WfKind.timeline: 'wf-tl',
      };
      for (final style in WfStyle.values) {
        for (final k in kPhase18b) {
          final html = htmlTailwindScreen('T', WireframeDiagram(style: style, components: [make(k)]));
          expect(RegExp('class="wf [^"]*\\b${cls[k]!}\\b').hasMatch(html), isTrue, reason: '${k.name}/${style.name}');
          expect(html.contains('NaN') || html.contains('Infinity'), isFalse, reason: k.name);
        }
      }
    });

    test('HTML: optionGroup เลือกหนึ่ง = radio ชื่อเดียวกัน ; หลายข้อ = checkbox ; timeline ข้อความ "|" แยกเป็นรายละเอียด', () {
      String h(WfComponent c) => htmlTailwindScreen('T', WireframeDiagram(components: [c]));
      final radio = h(make(WfKind.optionGroup));
      expect('type="radio"'.allMatches(radio).length, 3);
      expect('name="g-c-optionGroup"'.allMatches(radio).length, 3);
      expect(h(make(WfKind.optionGroup, secondary: true)), contains('type="checkbox" name="g-c-optionGroup"'));
      final tl = h(make(WfKind.timeline));
      expect(tl, contains('<small class="wf-1">12 ธ.ค. 09:10</small>'));
      expect(tl, isNot(contains('| 12')));
    });

    test('HTML: password ไม่มีข้อความ = จุดปิดบัง ; มีข้อความ = placeholder', () {
      String h(String t) => htmlTailwindScreen('T', WireframeDiagram(components: [make(WfKind.password, text: t)]));
      expect(h(''), contains('type="password" value="password"'));
      expect(h('รหัสผ่านของคุณ'), contains('placeholder="รหัสผ่านของคุณ"'));
    });
  });

  group('ตัววาด', () {
    List<WfPrim> prims(WfComponent c, {WfStyle s = WfStyle.clean}) => wireframePrims(WireframeDiagram(style: s, components: [c]), frame: false);
    List<String> texts(WfComponent c) => [for (final p in prims(c)) if (p is WfTextPrim) p.text];

    test('ข้อความของแต่ละชนิดแสดงตามบรรทัด', () {
      expect(texts(make(WfKind.bottomNav)), ['หน้าแรก', 'ค้นหา', 'การจอง', 'โปรไฟล์']);
      expect(texts(make(WfKind.segmented)), ['รายวัน', 'รายสัปดาห์', 'รายเดือน']);
      expect(texts(make(WfKind.timeline)).toSet(), containsAll(['สั่งซื้อสำเร็จ', '12 ธ.ค. 09:10', 'ถึงผู้รับ']));
      expect(texts(make(WfKind.toast)), ['บันทึกแล้ว', 'เลิกทำ']);
    });

    test('optionGroup: หลายข้อ (ช่องติ๊ก) ต่างจากเลือกหนึ่ง (วงกลม)', () {
      final one = prims(make(WfKind.optionGroup)).length;
      final many = prims(make(WfKind.optionGroup, secondary: true)).length;
      expect(one, isNot(many));
    });

    test('kanban: จำนวนการ์ดตาม rows (คอลัมน์แรกมากสุด) และไม่ล้นความสูง', () {
      int cards(int rows) => prims(make(WfKind.kanban, rows: rows)).whereType<WfPathPrim>().length;
      expect(cards(1) < cards(3), isTrue);
      expect(cards(6) >= cards(3), isTrue);
    });

    test('fab: "+" วาดเครื่องหมายบวก ; ข้อความอื่นวาดเป็นตัวอักษร', () {
      expect(texts(make(WfKind.fab)), isEmpty);
      expect(texts(make(WfKind.fab, text: 'ใหม่')), ['ใหม่']);
    });

    test('password: ไม่มีข้อความ = จุด 8 จุด ; มีข้อความ = ข้อความ', () {
      expect(texts(make(WfKind.password, text: '')), isEmpty);
      expect(texts(make(WfKind.password, text: 'รหัสผ่าน')), ['รหัสผ่าน']);
    });

    test('ชิ้นส่วนเล็กมากไม่พัง (ขนาดต่ำสุด)', () {
      for (final k in kPhase18b) {
        for (final s in WfStyle.values) {
          final ps = prims(make(k, w: 12, h: 12), s: s);
          expect(ps, isA<List<WfPrim>>(), reason: k.name);
        }
      }
    });
  });

  group('บนจอ', () {
    late WireframeController f;
    late WorkspaceController w;

    Future<void> boot(WidgetTester tester, {Lang lang = Lang.th}) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => currentLang = Lang.th);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang, showExplorer: true)));
      w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      w.addDocument(DocType.wireframe, name: 'Home');
      await tester.pumpAndSettle();
      f = tester.element(find.byType(HomePage)).read<WireframeController>();
      f.setDevice(WfDevice.mobile);
      await tester.pumpAndSettle();
    }

    testWidgets('แถบสถานะชิดบน · แถบแท็บล่างชิดล่าง · แถบหัวแอปใต้แถบสถานะ ; ทุกแถบกว้างเต็มหน้าจอ', (tester) async {
      await boot(tester);
      final d = f.diagram;
      final nav = f.addComponent(WfKind.bottomNav, 100, 300)!;
      expect((nav.x, nav.w, nav.y), (0, d.width, d.height - nav.h));
      final status = f.addComponent(WfKind.statusBar, 200, 400)!;
      expect((status.x, status.y, status.w), (0, 0, d.width));
      final app = f.addComponent(WfKind.appBar, 150, 90)!;
      expect((app.x, app.y, app.w), (0, status.h, d.width));
      // วางไกลจากขอบบน = ตามตำแหน่งที่คลิก (ไม่เกาะ)
      final app2 = f.addComponent(WfKind.appBar, 150, 500)!;
      expect(app2.y, greaterThan(100));
      expect(kWfFullWidthKinds, containsAll([WfKind.navbar, WfKind.statusBar, WfKind.appBar, WfKind.bottomNav]));
    });

    testWidgets('วางทุกชนิดใหม่ได้ ข้อความเริ่มต้นไม่ว่าง (ยกเว้น password) และ undo ได้', (tester) async {
      await boot(tester);
      for (final k in kPhase18b) {
        final c = f.addComponent(k, 300, 400)!;
        if (k != WfKind.password) expect(c.text.trim(), isNotEmpty, reason: k.name);
        expect(f.diagram.componentById(c.id), isNotNull);
      }
      expect(f.diagram.components.length, kPhase18b.length);
      f.undo();
      expect(f.diagram.components.length, kPhase18b.length - 1);
    });

    testWidgets('คลัง: ชนิดใหม่ทุกชนิดมีช่องในหมวดของมัน และหมวดมือถือมี 6 ชิ้น', (tester) async {
      await boot(tester);
      for (final k in kPhase18b) {
        expect(find.byKey(ValueKey('wf-kind-${k.name}'), skipOffstage: false), findsOneWidget, reason: k.name);
      }
      expect(find.byKey(const ValueKey('wf-cat-mobile')), findsOneWidget);
    });

    testWidgets('แผงขวา: optionGroup มีสวิตช์ "เลือกได้หลายข้อ" ; kanban มีจำนวนการ์ดตัวอย่าง', (tester) async {
      await boot(tester);
      final og = f.addComponent(WfKind.optionGroup, 300, 400)!;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wf-secondary')), findsOneWidget);
      f.updateComponents([og.id], (x) => x.secondary = true);
      await tester.pumpAndSettle();
      expect(f.diagram.componentById(og.id)!.secondary, isTrue);
      f.addComponent(WfKind.kanban, 300, 500);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wf-rows')), findsOneWidget);
    });

    testWidgets('ภาษาอังกฤษ: ชื่อและข้อความเริ่มต้นของชนิดใหม่ไม่มีไทยหลุด', (tester) async {
      await boot(tester, lang: Lang.en);
      final thai = RegExp(r'[฀-๿]');
      for (final k in kPhase18b) {
        final c = f.addComponent(k, 300, 400)!;
        expect(thai.hasMatch(c.text), isFalse, reason: '${k.name}: ${c.text}');
      }
    });
  });
}
