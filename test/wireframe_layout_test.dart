import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/codegen/wireframe_code.dart';
import 'package:nsl_nebular/core/codegen/wireframe_layout.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';

/// Phase 35: จัดผังหน้าจอ Wireframe เป็นแถว/คอลัมน์/ซ้อน สำหรับโค้ด Flutter
void main() {
  WfComponent c(String id, double x, double y, double w, double h, {WfKind kind = WfKind.button, bool hidden = false, double rotation = 0}) =>
      WfComponent(id: id, kind: kind, x: x, y: y, w: w, h: h, hidden: hidden, rotation: rotation, text: id);
  WfNode tree(List<WfComponent> list) => wfLayoutTree(WireframeDiagram(components: list))!;
  String shape(WfNode n) => switch (n) {
        WfLeafNode() => n.component.id + (n.inner == null ? '' : '{${shape(n.inner!)}}'),
        WfLineNode() => '${n.vertical ? 'col' : 'row'}[${n.children.map(shape).join(' ')}]',
        WfStackNode() => 'stack[${n.children.map(shape).join(' ')}]',
      };

  test('บนลงล่าง = คอลัมน์ ; อยู่ระดับเดียวกัน = แถว (เรียงตามตำแหน่ง ไม่ใช่ลำดับที่วาง)', () {
    final t = tree([c('bottom', 20, 200, 100, 40), c('right', 200, 25, 100, 40), c('left', 20, 20, 100, 40)]);
    expect(shape(t), 'col[row[left right] bottom]');
  });

  test('สองคอลัมน์ที่สูงเหลื่อมกัน = แถวของคอลัมน์ ; ขอบชนกันพอดียังแยกได้', () {
    final t = tree([
      c('a', 0, 0, 100, 100),
      c('b', 0, 100, 100, 200),
      c('x', 200, 50, 100, 100),
      c('y', 200, 150, 100, 100),
    ]);
    expect(shape(t), 'row[col[a b] col[x y]]');
  });

  test('ชิ้นที่ทับกัน = ซ้อน ตามลำดับการซ้อนเดิม', () {
    final t = tree([c('under', 20, 40, 200, 100), c('over', 10, 20, 100, 50)]);
    expect(shape(t), 'stack[under over]');
  });

  test('ชิ้นที่เลยขอบหน้าจอ = วางตามตำแหน่ง (ช่องว่างติดลบใช้ใน Row/Column ไม่ได้)', () {
    expect(tree([c('out', -20, 10, 100, 40), c('in', 10, 100, 100, 40)]), isA<WfStackNode>());
    expect(tree([c('wide', 1400, 10, 100, 40)]), isA<WfStackNode>());
  });

  test('ภาชนะ: ชิ้นข้างในจัดผังในกรอบของภาชนะ ; ชิ้นที่ซ่อน (และลูกของภาชนะที่ซ่อน) ไม่อยู่ในผัง', () {
    final t = tree([
      c('card', 20, 20, 400, 300, kind: WfKind.card),
      c('one', 40, 40, 100, 40),
      c('two', 40, 100, 100, 40),
      c('box', 600, 20, 300, 200, kind: WfKind.container, hidden: true),
      c('child', 620, 40, 100, 40),
    ]);
    expect(shape(t), 'col[card{col[one two]}]');
    expect(wfLayoutTree(WireframeDiagram(components: [c('h', 0, 0, 10, 10, hidden: true)])), isNull);
  });

  test('ผลบวกช่องว่างกับขนาดใน Row/Column ไม่เกินกรอบ แม้พิกัดมีทศนิยม', () {
    final t = tree([for (var i = 0; i < 10; i++) c('n$i', 0.5, i * 40.4 + 0.5, 100.6, 40.4)]);
    void check(WfNode n) {
      if (n is! WfLineNode) return;
      var at = n.vertical ? n.rect.top : n.rect.left;
      for (final k in n.children) {
        expect(n.vertical ? k.rect.top : k.rect.left, greaterThanOrEqualTo(at));
        at = n.vertical ? k.rect.bottom : k.rect.right;
        check(k);
      }
      expect(at, lessThanOrEqualTo(n.vertical ? n.rect.bottom : n.rect.right));
    }

    check(t);
  });

  test('โค้ด: ชิ้นซ่อนอยู่แบบมองไม่เห็น ; ชิ้นหมุนใช้ Transform.rotate และ import dart:math เฉพาะเมื่อใช้', () {
    final plain = flutterScreen('A', WireframeDiagram(components: [c('go', 10, 10, 100, 40)]));
    expect(plain, isNot(contains('dart:math')));
    expect(plain, isNot(contains('Visibility(')));
    final d = WireframeDiagram(components: [c('turn', 10, 10, 100, 40, rotation: 90), c('secret', 10, 200, 100, 40, hidden: true)]);
    final code = flutterScreen('B', d);
    expect(code, contains("import 'dart:math' as math;"));
    expect(code, contains('angle: 90.0 * math.pi / 180'));
    expect(code, contains('visible: false'));
    expect(code, contains("Text('secret')"));
  });

  test('ภาชนะที่มีชิ้นข้างในไม่ถูกครอบด้วยตัวเลื่อน (การ์ดต้องเต็มกรอบ) ; ขั้นตอนแนวนอนเห็นครบทุกขั้น', () {
    final card = flutterScreen('C', WireframeDiagram(components: [c('card', 0, 0, 400, 300, kind: WfKind.card), c('in', 20, 60, 100, 40)]));
    expect(card, isNot(contains('SingleChildScrollView(child: Card')));
    final steps = flutterScreen('S', WireframeDiagram(components: [WfComponent(id: 's', kind: WfKind.stepper, w: 600, h: 60, text: 'หนึ่ง\nสอง\nสาม')]));
    expect(steps, isNot(contains('Stepper(')));
    for (final s in ['หนึ่ง', 'สอง', 'สาม']) {
      expect(steps, contains("'$s'"));
    }
  });
}
