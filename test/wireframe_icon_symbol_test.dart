import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/codegen/wireframe_code.dart';
import 'package:nsl_nebular/core/codegen/wireframe_html.dart';
import 'package:nsl_nebular/core/export/wireframe_svg.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/wf_icons.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/wireframe_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// เลือกสัญลักษณ์ของชิ้นไอคอน
void main() {
  WireframeDiagram dia(String symbol) =>
      WireframeDiagram(components: [WfComponent(id: 'i', kind: WfKind.icon, x: 10, y: 10, w: 40, h: 40, symbol: symbol)]);

  test('ชุดสัญลักษณ์: id ไม่ซ้ำ ข้อมูลครบ ชื่อ Flutter ครบ', () {
    final ids = {for (final d in kWfIcons) d.id};
    expect(ids.length, kWfIcons.length);
    expect(wfIconById(kWfDefaultSymbol), isNotNull);
    for (final d in kWfIcons) {
      expect(d.ops, isNotEmpty, reason: d.id);
      expect(d.flutter, isNotEmpty);
      expect(d.th, isNotEmpty);
      expect(d.en, isNotEmpty);
      for (final (op, a) in d.ops) {
        expect(const ['L', 'P', 'C', 'R'], contains(op), reason: d.id);
        expect(a.length, switch (op) { 'C' => 3, 'R' => 5, _ => a.length }, reason: d.id);
        for (final v in a) {
          expect(v, inInclusiveRange(0, 24), reason: '${d.id} อยู่ในกริด 24×24');
        }
      }
    }
  });

  test('บันทึก/อ่านไฟล์: symbol กลับมาครบ ; ว่าง = ไม่เขียนลงไฟล์ (ไฟล์เก่าไม่เปลี่ยน)', () {
    final c = WfComponent(id: 'i', kind: WfKind.icon, symbol: 'home');
    expect(c.toJson()['symbol'], 'home');
    expect(WfComponent.tryFromJson(c.toJson())!.symbol, 'home');
    final old = WfComponent(id: 'o', kind: WfKind.icon);
    expect(old.toJson().containsKey('symbol'), isFalse);
    expect(WfComponent.tryFromJson(old.toJson())!.symbol, '');
  });

  test('ภาพ SVG: แต่ละสัญลักษณ์ได้ภาพต่างกัน และต่างจากกล่องแทนที่', () {
    final none = exportWireframeSvg(dia(''));
    final home = exportWireframeSvg(dia('home'));
    final search = exportWireframeSvg(dia('search'));
    expect(home, isNot(none));
    expect(home, isNot(search));
    expect(exportWireframeSvg(dia('home')), home, reason: 'ผลคงที่ (ไม่สุ่มเปลี่ยนทุกครั้ง)');
    expect(exportWireframeSvg(dia('ไม่มีสัญลักษณ์นี้')), none, reason: 'ชื่อที่ไม่รู้จัก = กล่องแทนที่');
  });

  test('HTML และโค้ด Flutter ใช้สัญลักษณ์ที่เลือก', () {
    final d = dia('cart');
    expect(wireframeHtmlPage('x', d), contains('<circle cx="9" cy="19.5" r="1.5"/>'));
    expect(flutterScreen('X', d), contains('Icons.shopping_cart_outlined'));
    expect(flutterScreen('X', dia('')), contains('Icons.star_outline'));
  });

  testWidgets('แผงขวา: ชิ้นไอคอนใหม่เป็นดาว ; คลิกเลือกสัญลักษณ์แล้วเปลี่ยน (undo ได้) ; ช่องแรก = กล่องแทนที่', (tester) async {
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true)));
    final w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    w.addDocument(DocType.wireframe, name: 'Home');
    await tester.pumpAndSettle();
    final f = tester.element(find.byType(HomePage)).read<WireframeController>();
    final ic = f.addComponent(WfKind.icon, 500, 300)!;
    expect(f.diagram.componentById(ic.id)!.symbol, 'star');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wf-symbol-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('wf-no-text')), findsNothing, reason: 'ไอคอนมีตัวเลือกสัญลักษณ์แทนข้อความ');

    await tester.ensureVisible(find.byKey(const ValueKey('wf-symbol-home')));
    await tester.tap(find.byKey(const ValueKey('wf-symbol-home')));
    await tester.pumpAndSettle();
    expect(f.diagram.componentById(ic.id)!.symbol, 'home');
    expect(tester.widget<Text>(find.byKey(const ValueKey('wf-symbol-name'))).data, 'หน้าแรก');

    await tester.tap(find.byKey(const ValueKey('wf-symbol-none')));
    await tester.pumpAndSettle();
    expect(f.diagram.componentById(ic.id)!.symbol, '');
    f.undo();
    await tester.pumpAndSettle();
    expect(f.diagram.componentById(ic.id)!.symbol, 'home');
  });
}
