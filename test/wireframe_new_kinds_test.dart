import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/codegen/wireframe_code.dart';
import 'package:nsl_nebular/core/export/wireframe_svg.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/layout/wireframe_render.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/validate/wireframe_validator.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/wireframe_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/ui/wireframe/wf_view.dart' show wfKindIcon;
import 'package:provider/provider.dart';

/// ชิ้นส่วนที่เพิ่มภายหลัง (16 ชนิด)
const kNew = [
  WfKind.link,
  WfKind.chip,
  WfKind.progress,
  WfKind.alert,
  WfKind.datepicker,
  WfKind.upload,
  WfKind.stepper,
  WfKind.rating,
  WfKind.video,
  WfKind.accordion,
  WfKind.footer,
  WfKind.tooltip,
  WfKind.skeleton,
  WfKind.calendar,
  WfKind.stat,
  WfKind.tree,
];

/// วงเล็บ ()[]{} สมดุล (ข้ามข้อความในเครื่องหมายคำพูด) — ตรวจโค้ดที่สร้างแบบหยาบ ๆ
bool balanced(String code) {
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
  WfComponent make(WfKind k, {String? text, double? w, double? h}) =>
      WfComponent(id: 'c-${k.name}', kind: k, text: text ?? WireframeController.defaultText(k), x: 40, y: 40, w: w, h: h);

  group('ทุกชนิด (รวมชนิดใหม่) วาดได้ทั้งสองรูปแบบ', () {
    test('มี 60 ชนิด ; ชนิดเดิม 29 ชนิดแรกและ 16 ชนิดถัดมายังอยู่ลำดับเดิม (ชนิดใหม่ต่อท้าย)', () {
      expect(WfKind.values.length, 60);
      expect(WfKind.values.sublist(0, 29).last, WfKind.chart);
      expect(WfKind.values.sublist(29, 45), kNew);
    });

    test('ทุกชนิด: วาดแล้วมีชิ้นวาด พิกัดเป็นตัวเลขจริง ไม่ล้นกรอบของชิ้นเกินเล็กน้อย ทั้งแบบร่างและแบบเรียบร้อย ; SVG ไม่มี NaN', () {
      for (final style in WfStyle.values) {
        for (final k in WfKind.values) {
          final c = make(k);
          final d = WireframeDiagram(style: style, components: [c]);
          final prims = wireframePrims(d, frame: false);
          expect(prims, isNotEmpty, reason: '${k.name}/${style.name}');
          void check(List<WfPrim> ps) {
            for (final p in ps) {
              switch (p) {
                case WfGroupPrim():
                  check(p.children);
                case WfPathPrim():
                  for (final cmd in p.cmds) {
                    for (final (x, y) in cmd.$2) {
                      expect(x.isFinite && y.isFinite, isTrue, reason: '${k.name} พิกัดไม่ใช่ตัวเลข');
                      expect(x, inInclusiveRange(c.x - 8, c.right + 8), reason: '${k.name} ล้นกรอบแนวนอน');
                      expect(y, inInclusiveRange(c.y - 8, c.bottom + 12), reason: '${k.name} ล้นกรอบแนวตั้ง');
                    }
                  }
                case WfTextPrim():
                  expect(p.x >= c.x - 1 && p.x + p.w <= c.right + 1, isTrue, reason: '${k.name} กรอบข้อความล้นแนวนอน (${p.x}..${p.x + p.w})');
                  expect(p.w >= 0 && p.h >= 0, isTrue);
              }
            }
          }

          check(prims);
          final svg = exportWireframeSvg(d);
          expect(svg.contains('NaN') || svg.contains('Infinity'), isFalse, reason: k.name);
        }
      }
    });

    test('ทุกชนิดมีชื่อ ไอคอน ขนาดเริ่มต้นที่ใช้ได้ และชื่อภาษาอังกฤษไม่มีไทยหลุด', () {
      final thai = RegExp(r'[฀-๿]');
      final before = currentLang;
      addTearDown(() => currentLang = before);
      currentLang = Lang.en;
      for (final k in WfKind.values) {
        final (w, h) = wfDefaultSize(k);
        expect(w >= 8 && h >= 8, isTrue, reason: k.name);
        expect(wfKindIcon(k), isA<IconData>());
        expect(wfKindLabel(k).trim(), isNotEmpty);
        expect(thai.hasMatch(wfKindLabel(k)), isFalse, reason: '${k.name}: ${wfKindLabel(k)}');
        expect(thai.hasMatch(WireframeController.defaultText(k)), isFalse, reason: 'ข้อความเริ่มต้นของ ${k.name}');
      }
    });
  });

  group('พฤติกรรมของชนิดใหม่', () {
    List<WfPathPrim> paths(WfComponent c, {WfStyle s = WfStyle.clean}) => [
          for (final p in wireframePrims(WireframeDiagram(style: s, components: [c]), frame: false)) if (p is WfPathPrim) p,
        ];

    test('progress: อ่านเปอร์เซ็นต์จากข้อความ — 100% เต็มราง ; 0% ไม่มีแถบเต็ม ; ข้อความอ่านไม่ได้ = 60%', () {
      double fillWidth(String t) {
        final ps = paths(make(WfKind.progress, text: t, w: 200, h: 10));
        // แถบสีที่เติมคือชิ้นสุดท้ายที่มี fill
        final filled = ps.where((p) => p.fill != null).toList();
        if (filled.length < 2) return 0;
        final xs = [for (final cmd in filled.last.cmds) for (final (x, _) in cmd.$2) x];
        return xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b);
      }

      expect(fillWidth('100%'), closeTo(fillWidth('250'), 0.01), reason: 'เกิน 100 ถูกตัดที่ 100');
      expect(fillWidth('100%'), greaterThan(fillWidth('60%')));
      expect(fillWidth('60%'), closeTo(fillWidth('ไม่ใช่เลข'), 0.01));
      expect(fillWidth('0%'), lessThan(fillWidth('60%')));
    });

    test('stepper/accordion/tree: จำนวนบรรทัดของข้อความ = จำนวนขั้น/หัวข้อ/โหนด ; tree เยื้องตามช่องว่างนำหน้า', () {
      List<String> texts(WfComponent c) => [
            for (final p in wireframePrims(WireframeDiagram(components: [c]), frame: false)) if (p is WfTextPrim) p.text,
          ];
      expect(texts(make(WfKind.stepper, text: 'A\nB\nC\nD', w: 600, h: 60)).where((t) => 'ABCD'.contains(t) && t.isNotEmpty).length, 4);
      expect(texts(make(WfKind.accordion, text: 'x1\nx2', h: 200)), containsAll(['x1', 'x2']));
      final tree = [
        for (final p in wireframePrims(WireframeDiagram(components: [make(WfKind.tree, text: 'root\n  kid\n    leaf', h: 120)]), frame: false))
          if (p is WfTextPrim) p
      ];
      expect([for (final t in tree) t.text], ['root', 'kid', 'leaf']);
      expect(tree[1].x, greaterThan(tree[0].x));
      expect(tree[2].x, greaterThan(tree[1].x));
    });

    test('stat: บรรทัดเดียว = แสดงเป็นตัวเลขใหญ่ ; สองบรรทัด = ป้าย + ตัวเลข', () {
      double size(WfComponent c, String t) => [
            for (final p in wireframePrims(WireframeDiagram(components: [c]), frame: false)) if (p is WfTextPrim && p.text == t) p.size,
          ].single;
      final two = make(WfKind.stat, text: 'Sales\n99');
      expect(size(two, '99'), greaterThan(size(two, 'Sales')));
      final one = make(WfKind.stat, text: '42');
      expect(size(one, '42'), greaterThan(20));
    });

    test('footer เป็นภาชนะ (ชิ้นที่อยู่ข้างในเป็นลูก) ; datepicker ผูกข้อมูล ER ได้ ; ชิ้นใหม่ไม่ถูกตัวตรวจติดว่าไม่มีข้อความ (ที่ไม่ต้องมี)', () {
      expect(kWfContainerKinds, contains(WfKind.footer));
      expect(kWfBindableKinds, contains(WfKind.datepicker));
      final d = WireframeDiagram(components: [
        WfComponent(id: 'f', kind: WfKind.footer, x: 0, y: 700, w: 600, h: 80),
        WfComponent(id: 'l', kind: WfKind.link, text: 'x', x: 20, y: 720, w: 100, h: 24),
      ]);
      expect(wfParentMap(d), {'l': 'f'});
      final empties = WireframeDiagram(components: [for (final k in [WfKind.rating, WfKind.video, WfKind.skeleton]) make(k, text: '')]);
      expect(validateWireframe(empties).where((i) => i.code.contains('empty') || i.code.contains('text')), isEmpty);
    });
  });

  group('สร้างโค้ดจากชนิดใหม่', () {
    test('Flutter และ HTML ของทุกชนิด: ไม่ว่าง วงเล็บสมดุล ; ชนิดใหม่ใช้วิดเจ็ต/แท็กที่ตรงความหมาย', () {
      for (final k in WfKind.values) {
        final d = WireframeDiagram(components: [make(k)]);
        final flutter = flutterScreen('Home', d);
        final html = htmlTailwindScreen('Home', d);
        expect(balanced(flutter), isTrue, reason: 'Flutter ${k.name}');
        expect(html.contains('null'), isFalse, reason: 'HTML ${k.name}');
        expect(html.contains(r'$'), isFalse, reason: 'HTML ${k.name} มี \$ หลุดจาก interpolation');
      }
      String fl(WfKind k, {String? text}) => flutterScreen('Home', WireframeDiagram(components: [make(k, text: text)]));
      String ht(WfKind k, {String? text}) => htmlTailwindScreen('Home', WireframeDiagram(components: [make(k, text: text)]));
      expect(fl(WfKind.progress, text: '25%'), contains('LinearProgressIndicator(value: 0.25)'));
      expect(ht(WfKind.progress, text: '25%'), contains('aria-valuenow="25"'));
      expect(fl(WfKind.link), contains('TextButton'));
      expect(ht(WfKind.link), contains('<a class="wf wf-t wf-link"'));
      expect(fl(WfKind.stepper, text: 'a\nb'), contains('Stepper('));
      expect(ht(WfKind.stepper, text: 'a\nb'), contains('<ol'));
      expect(fl(WfKind.accordion, text: 'a\nb'), contains('ExpansionTile'));
      expect(ht(WfKind.accordion, text: 'a\nb'), contains('<details'));
      expect(fl(WfKind.calendar), contains('CalendarDatePicker'));
      expect(ht(WfKind.datepicker), contains("this.type='date'"));
      expect(ht(WfKind.upload), contains('type="file"'));
      expect(fl(WfKind.tree, text: 'r\n  k'), contains('left: 16.0'));
      expect(ht(WfKind.tree, text: 'r\n  k'), contains('padding-left:24px'));
      expect(fl(WfKind.stat, text: 'L\n5'), contains('headlineMedium'));
      // ข้อความที่มี $ ต้องไม่ทำให้โค้ดพัง
      expect(balanced(fl(WfKind.alert, text: r'ราคา $5 และ ${x}')), isTrue);
    });
  });

  group('บนจอ', () {
    late WorkspaceController w;
    late WireframeController f;

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true)));
      w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      w.addDocument(DocType.wireframe, name: 'Home');
      await tester.pumpAndSettle();
      f = tester.element(find.byType(HomePage)).read<WireframeController>();
    }

    testWidgets('คลังมีครบทุกชนิด ; ค้นหา "ปฏิทิน" เหลือชนิดเดียว ; คลิกแล้ววางลงแคนวาสได้ชิ้นที่มีข้อความเริ่มต้น', (tester) async {
      await boot(tester);
      for (final k in kNew) {
        expect(find.byKey(ValueKey('wf-kind-${k.name}'), skipOffstage: false), findsOneWidget, reason: k.name);
      }
      await tester.enterText(find.byKey(const ValueKey('wf-search')), 'ปฏิทิน');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wf-kind-calendar')), findsOneWidget);
      expect(find.byKey(const ValueKey('wf-kind-chip')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('wf-kind-calendar')));
      await tester.pumpAndSettle();
      expect(f.tool, WfTool.place);
      expect(f.toolKind, WfKind.calendar);
      final c = f.addComponent(WfKind.calendar, 600, 400)!;
      expect(c.text, isNotEmpty);
      expect((c.w, c.h), wfDefaultSize(WfKind.calendar));
      expect(tester.takeException(), isNull);
    });
  });
}
