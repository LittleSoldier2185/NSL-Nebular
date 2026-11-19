import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/layout/dfd_layout.dart';
import 'package:nsl_nebular/core/models/dfd_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/state/dfd_controller.dart';
import 'package:nsl_nebular/state/project_controller.dart';

import 'support/project_helpers.dart';

import 'migration_fixtures.dart';

DfdNode e(String id) => DfdNode(id: id, kind: DfdKind.entity, name: id);
DfdNode p(String id) =>
    DfdNode(id: id, kind: DfdKind.process, name: id, number: '1.0');
DfdNode s(String id) =>
    DfdNode(id: id, kind: DfdKind.store, name: id, number: 'D1');
DfdFlow f(String a, String b) =>
    DfdFlow(id: '$a$b', fromId: a, toId: b, label: 'x');

void main() {
  test('ว่าง = ไม่มีอะไร', () => expect(dfdAutoLayout(DfdDiagram()), isEmpty));

  test('เรียงเป็นชั้นตามทิศทางข้อมูล: entity → process → store ซ้ายไปขวา', () {
    final d = DfdDiagram(
      nodes: [s('s'), p('p'), e('e')],
      flows: [f('e', 'p'), f('p', 's')],
    );
    final r = dfdAutoLayout(d);
    expect(r['e']!.x, lessThan(r['p']!.x));
    expect(r['p']!.x, lessThan(r['s']!.x));
    // ไม่ซ้อนกัน : ระยะห่างแนวนอนอย่างน้อย kDfdLayerGap
    expect(r['p']!.x - (r['e']!.x + 150), greaterThanOrEqualTo(kDfdLayerGap));
  });

  test('วัตถุในชั้นเดียวกันไม่ซ้อนกันและเว้นระยะ', () {
    final d = DfdDiagram(
      nodes: [e('a'), e('b'), e('c'), p('p')],
      flows: [f('a', 'p'), f('b', 'p'), f('c', 'p')],
    );
    final r = dfdAutoLayout(d);
    final ys = [r['a']!.y, r['b']!.y, r['c']!.y]..sort();
    expect(ys[1] - ys[0], greaterThanOrEqualTo(56 + kDfdRowGap));
    expect(ys[2] - ys[1], greaterThanOrEqualTo(56 + kDfdRowGap));
  });

  test('วงจร (process ↔ store) ไม่ทำให้ค้างหรือพัง และทุกวัตถุได้ตำแหน่ง', () {
    final d = DfdDiagram(
      nodes: [e('e'), p('p'), s('s')],
      flows: [f('e', 'p'), f('p', 's'), f('s', 'p')],
    );
    final r = dfdAutoLayout(d);
    expect(r.keys.toSet(), {'e', 'p', 's'});
    expect(r['e']!.x, lessThan(r['p']!.x));
  });

  test(
    'วัตถุที่ไม่มีเส้นก็ได้ตำแหน่ง และผลเหมือนเดิมทุกครั้ง; มุมซ้ายบนคงที่เดิม',
    () {
      final d = DfdDiagram(
        nodes: [
          e('a')
            ..x = 500
            ..y = 300,
          p('b')
            ..x = 900
            ..y = 700,
          s('lonely')
            ..x = 50
            ..y = 80,
        ],
        flows: [f('a', 'b')],
      );
      final r1 = dfdAutoLayout(d), r2 = dfdAutoLayout(d);
      expect(r1.length, 3);
      for (final k in r1.keys) {
        expect((r1[k]!.x, r1[k]!.y), (r2[k]!.x, r2[k]!.y));
      }
      final minX = r1.values.map((v) => v.x).reduce((a, b) => a < b ? a : b);
      final minY = r1.values.map((v) => v.y).reduce((a, b) => a < b ? a : b);
      expect((minX, minY), (50, 80));
    },
  );

  test('entity: ออกมากกว่า = ซ้าย, เข้าอย่างเดียว = ขวา, เสมอที่ระบบเดียว = แจกให้สมดุล', () {
    final d = DfdDiagram(
      nodes: [e('guest'), e('admin'), e('gw'), p('sys')],
      flows: [
        DfdFlow(id: '1', fromId: 'guest', toId: 'sys', label: 'a'),
        DfdFlow(id: '2', fromId: 'guest', toId: 'sys', label: 'b'),
        DfdFlow(id: '3', fromId: 'sys', toId: 'guest', label: 'c'),
        DfdFlow(id: '4', fromId: 'sys', toId: 'admin', label: 'd'),
        DfdFlow(id: '5', fromId: 'gw', toId: 'sys', label: 'e'),
        DfdFlow(id: '6', fromId: 'sys', toId: 'gw', label: 'f'),
      ],
    );
    final r = dfdAutoLayout(d);
    expect(r['guest']!.x, lessThan(r['sys']!.x));
    expect(r['admin']!.x, greaterThan(r['sys']!.x));
    expect(r['gw']!.x, greaterThan(r['sys']!.x)); // ซ้ายหนักกว่า → gw ไปขวา
  });

  test('data store ที่อ่าน/เขียนอย่างเดียวอยู่ถัดจาก process (ไม่ขวางเส้นของ entity)', () {
    final d = DfdDiagram(
      nodes: [e('e'), p('p'), s('rd'), s('wr')],
      flows: [f('e', 'p'), f('rd', 'p'), f('p', 'wr')],
    );
    final r = dfdAutoLayout(d);
    expect(r['e']!.x, lessThan(r['p']!.x));
    expect(r['rd']!.x, greaterThan(r['p']!.x));
    expect(r['wr']!.x, greaterThan(r['p']!.x));
  });

  test('process ที่ไม่ส่งข้อมูลถึงกันอยู่คอลัมน์เดียวกัน', () {
    final d = DfdDiagram(
      nodes: [e('e'), p('a'), p('b'), p('c')],
      flows: [f('e', 'a'), f('e', 'b'), f('e', 'c')],
    );
    final r = dfdAutoLayout(d);
    expect(r['a']!.x, r['b']!.x);
    expect(r['b']!.x, r['c']!.x);
  });

  test('เส้นหลายเส้นด้านเดียวกัน: ขยายความสูงให้ช่องห่าง kDfdSlotGap (ขยายอย่างเดียว) ; ช่องคอลัมน์ยาวตามป้าย', () {
    final d = DfdDiagram(
      nodes: [e('e'), p('p')],
      flows: [
        for (var i = 0; i < 5; i++)
          DfdFlow(
            id: 'f$i',
            fromId: i.isEven ? 'e' : 'p',
            toId: i.isEven ? 'p' : 'e',
            label: 'x',
          ),
      ],
    );
    final plan = dfdLayoutPlan(d);
    expect(plan.heights['e'], 16 + kDfdSlotGap * 4);
    expect(plan.heights['p'], 32 + kDfdSlotGap * 4); // process มุมมนต้องเว้นมุมละ 16

    double gap(String label) {
      final g = DfdDiagram(
        nodes: [e('e'), p('p')],
        flows: [DfdFlow(id: 'a', fromId: 'e', toId: 'p', label: label)],
      );
      final r = dfdAutoLayout(g);
      return r['p']!.x - (r['e']!.x + 150);
    }

    expect(gap('x'), kDfdLayerGap);
    expect(
      gap('ป้ายชื่อเส้นที่ยาวมากๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆ'),
      greaterThan(kDfdLayerGap),
    );
  });
  test(
    'DfdController.autoLayout: undo ขั้นเดียว ; จัดซ้ำแล้วไม่เปลี่ยน = false',
    () {
      final pc = ProjectController(base());
      final tab = pc.addDiagram(DocType.dfd)!.id;
      final d = dfdCtl(pc, tab);
      final a = d.addNode(DfdKind.entity, 300, 300)!;
      final b = d.addNode(DfdKind.process, 100, 100)!;
      d.setTool(DfdTool.flow);
      d.linkClick(a.id);
      d.linkClick(b.id);
      final before = {for (final n in pc.dfdOf(tab).nodes) n.id: (n.x, n.y)};
      expect(d.autoLayout(), true);
      final after = pc.dfdOf(tab);
      expect(after.nodeById(a.id)!.x, lessThan(after.nodeById(b.id)!.x));
      expect(d.autoLayout(), false);
      d.undo();
      for (final n in pc.dfdOf(tab).nodes) {
        expect((n.x, n.y), before[n.id]);
      }
    },
  );
}
