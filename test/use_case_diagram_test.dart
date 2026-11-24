import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/export/usecase_svg.dart';
import 'package:nsl_nebular/core/layout/usecase_layout.dart';
import 'package:nsl_nebular/core/models/use_case.dart';
import 'package:nsl_nebular/core/storage/project_codec.dart';
import 'package:nsl_nebular/core/validate/usecase_validator.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// Phase 31 (ส่วนแกน): extend · ตัวตรวจวงจร · จัดวางอัตโนมัติ · ส่งออก SVG · ตำแหน่งที่ผู้ใช้ลาก
void main() {
  late WorkspaceController w;
  setUp(() {
    w = WorkspaceController();
    w.showUseCases(); // Undo/Redo ใช้ประวัติโปรเจกต์เฉพาะหน้า Use Case / ความต้องการ / Mock
  });
  tearDown(() => w.dispose());

  UseCase uc(String name, {String actor = 'Guest', String secondary = ''}) {
    final u = w.addUseCase(name: name, actor: actor);
    if (secondary.isNotEmpty) w.updateUseCase(u.id, (x) => x.secondaryActor = secondary);
    return u;
  }

  Set<String> codes() => {for (final i in validateUseCases(w.workspace)) i.code};

  group('โมเดล extend', () {
    test('เขียน-อ่านไฟล์ครบ (ฐาน + เงื่อนไข) ; เขียนซ้ำตรงเดิม ; ไม่มี extend = ไม่เขียนคีย์', () {
      final a = uc('จองห้อง'), b = uc('ใช้โค้ดส่วนลด');
      expect(jsonEncode(w.useCaseById(a.id)!.toJson()).contains('extends'), isFalse);
      w.updateUseCase(b.id, (x) => x.extendsFrom.add(UcExtend(baseId: a.id, condition: 'มีโค้ดส่วนลด')));
      final copy = copyWorkspace(w.workspace);
      final e = copy.useCases.last.extendsFrom.single;
      expect((e.baseId, e.condition), (a.id, 'มีโค้ดส่วนลด'));
      expect(jsonEncode(encodeProjectMap(copy)), jsonEncode(encodeProjectMap(w.workspace)));
    });

    test('ข้อมูลเสียถูกข้าม ; คีย์ที่ไม่รู้จักเขียนกลับ', () {
      final j = encodeProjectMap(w.workspace);
      (j['meta'] as Map)['useCases'] = [
        {
          'id': 'u1',
          'name': 'x',
          'extends': [
            {'base': 'u2', 'cond': 'c', 'future': 7},
            {'cond': 'ไม่มีฐาน'},
            'ขยะ',
            {'base': ''},
          ],
        },
      ];
      final ws = decodeProjectMap(j);
      final ex = ws.useCases.single.extendsFrom;
      expect(ex.length, 1);
      expect(ex.single.extra['future'], 7);
      expect((encodeProjectMap(ws)['meta']['useCases'][0]['extends'] as List).single['future'], 7);
    });

    test('ลบ Use Case ฐาน = ลบ extend ที่ชี้มาและตำแหน่งในแผนภาพ ; ย้อนกลับได้ครบ', () {
      final a = uc('ฐาน'), b = uc('ส่วนขยาย');
      w.updateUseCase(b.id, (x) => x.extendsFrom.add(UcExtend(baseId: a.id)));
      w.setUseCaseNodePosition('uc:${a.id}', 10, 20);
      w.deleteUseCase(a.id);
      expect(w.useCaseById(b.id)!.extendsFrom, isEmpty);
      expect(w.useCaseLayout.containsKey('uc:${a.id}'), isFalse);
      w.undo();
      expect(w.useCaseById(b.id)!.extendsFrom.single.baseId, a.id);
      expect(w.useCaseLayout['uc:${a.id}'], (10.0, 20.0));
    });

    test('ป้ายประวัติของการแก้ extend', () {
      final a = uc('ฐาน'), b = uc('ขยาย');
      w.updateUseCase(b.id, (x) => x.extendsFrom.add(UcExtend(baseId: a.id)));
      expect(w.projectHistory.undoLabel, 'แก้การขยาย Use Case');
    });
  });

  group('ตัวตรวจ extend / วงจร', () {
    test('ขยายตัวเอง / ฐานที่ไม่มี = error', () {
      final a = uc('A');
      w.updateUseCase(a.id, (x) => x.extendsFrom..add(UcExtend(baseId: a.id))..add(UcExtend(baseId: 'หาย')));
      expect(codes(), containsAll(['uc_extend_self', 'uc_extend_missing']));
    });

    test('วงจร include/extend (A→B→C→A) : ทุกข้อบนวงถูกเตือน ; ไม่เป็นวงไม่เตือน ; ผสม include+extend นับ', () {
      final a = uc('A'), b = uc('B'), c = uc('C'), d = uc('D');
      w.updateUseCase(a.id, (x) => x.includes.add(b.id));
      w.updateUseCase(b.id, (x) => x.extendsFrom.add(UcExtend(baseId: c.id)));
      expect(codes().contains('uc_cycle'), isFalse, reason: 'ยังไม่ปิดวง');
      w.updateUseCase(c.id, (x) => x.includes.add(a.id));
      final cyc = validateUseCases(w.workspace).where((i) => i.code == 'uc_cycle').map((i) => i.ucId).toSet();
      expect(cyc, {a.id, b.id, c.id});
      expect(cyc.contains(d.id), isFalse, reason: 'ข้อที่ไม่อยู่บนวงไม่ถูกเตือน');
      w.updateUseCase(d.id, (x) => x.includes.add(a.id)); // ชี้เข้าวงแต่ไม่อยู่บนวง
      expect(validateUseCases(w.workspace).where((i) => i.code == 'uc_cycle').map((i) => i.ucId).toSet(), {a.id, b.id, c.id});
    });
  });

  group('จัดวางอัตโนมัติ', () {
    bool overlap(UcNode a, UcNode b) => a.x < b.right && b.x < a.right && a.y < b.bottom && b.y < a.bottom;

    test('ไม่มี Use Case = ภาพว่าง', () {
      final d = layoutUseCaseDiagram(w.workspace);
      expect((d.isEmpty, d.boundary, d.bounds), (true, null, null));
    });

    for (final n in [1, 4, 5, 12, 13, 30]) {
      test('$n Use Case : โหนดไม่ทับกัน อยู่ในกรอบ ผู้กระทำหลักซ้าย/รองขวา เส้นครบ', () {
        final actors = ['Guest', 'Admin', 'Staff'];
        for (var i = 0; i < n; i++) {
          uc('UC $i', actor: actors[i % 3], secondary: i % 4 == 0 ? 'Payment Gateway, ระบบอีเมล' : '');
        }
        // include/extend ระหว่างข้อที่ติดกัน (ไม่เป็นวง)
        for (var i = 1; i < n; i += 3) {
          w.updateUseCase(w.useCases[i].id, (x) => x.includes.add(w.useCases[i - 1].id));
          if (i + 1 < n) w.updateUseCase(w.useCases[i + 1].id, (x) => x.extendsFrom.add(UcExtend(baseId: w.useCases[i].id)));
        }
        final d = layoutUseCaseDiagram(w.workspace);
        final nodes = d.nodes;
        for (var i = 0; i < nodes.length; i++) {
          for (var j = i + 1; j < nodes.length; j++) {
            expect(overlap(nodes[i], nodes[j]), isFalse, reason: '${nodes[i].key} ทับ ${nodes[j].key}');
          }
        }
        final b = d.boundary!;
        for (final x in nodes.where((e) => !e.isActor)) {
          expect(x.x >= b.x && x.right <= b.x + b.w && x.y >= b.y && x.bottom <= b.y + b.h, isTrue, reason: x.key);
        }
        for (final a in ['Guest', 'Admin', 'Staff'].where((a) => n > actors.indexOf(a))) {
          expect(d.node(ucActorKey(a))!.right, lessThanOrEqualTo(b.x), reason: 'ผู้กระทำหลัก $a อยู่ซ้ายกรอบ');
        }
        for (final a in ['Payment Gateway', 'ระบบอีเมล']) {
          expect(d.node(ucActorKey(a))!.x, greaterThanOrEqualTo(b.x + b.w), reason: 'ผู้กระทำรอง $a อยู่ขวากรอบ');
        }
        final assoc = d.edges.where((e) => e.kind == UcEdgeKind.association).length;
        final expectAssoc = n + [for (var i = 0; i < n; i += 4) 2].fold<int>(0, (p, q) => p + q);
        expect(assoc, expectAssoc);
        final bounds = d.bounds!;
        for (final x in nodes) {
          expect(x.x >= bounds.left && x.right <= bounds.right && x.y >= bounds.top && x.bottom <= bounds.bottom, isTrue);
        }
      });
    }

    test('ผลคงที่ (เรียกซ้ำได้เหมือนเดิม) ; ผู้กระทำที่เป็นทั้งหลักและรองอยู่ฝั่งซ้ายที่เดียว', () {
      uc('A', actor: 'Guest', secondary: 'Admin');
      uc('B', actor: 'Admin');
      final d1 = layoutUseCaseDiagram(w.workspace), d2 = layoutUseCaseDiagram(w.workspace);
      expect([for (final n in d1.nodes) '${n.key}@${n.x},${n.y}'], [for (final n in d2.nodes) '${n.key}@${n.x},${n.y}']);
      expect(d1.nodes.where((n) => n.key == ucActorKey('Admin')).length, 1, reason: 'ไม่ซ้ำสองฝั่ง');
      expect(d1.node(ucActorKey('Admin'))!.right, lessThanOrEqualTo(d1.boundary!.x));
      expect(d1.edges.where((e) => e.fromKey == ucActorKey('Admin')).length, 2, reason: 'ยังมีเส้นถึงทั้งสองข้อ');
    });

    test('เส้น include/extend เฉพาะที่ปลายทางยังมีอยู่ ; extend พก เงื่อนไข', () {
      final a = uc('A'), b = uc('B');
      w.updateUseCase(a.id, (x) => x.includes.addAll([b.id, 'หาย', a.id]));
      w.updateUseCase(b.id, (x) => x.extendsFrom.addAll([UcExtend(baseId: a.id, condition: ' มีโค้ด '), UcExtend(baseId: 'หาย')]));
      final d = layoutUseCaseDiagram(w.workspace);
      expect(d.edges.where((e) => e.kind == UcEdgeKind.include).length, 1);
      final ex = d.edges.where((e) => e.kind == UcEdgeKind.extend).single;
      expect((ex.fromKey, ex.toKey, ex.condition), (ucNodeKey(b.id), ucNodeKey(a.id), 'มีโค้ด'));
    });

    test('ตำแหน่งที่ผู้ใช้ลากทับตำแหน่งอัตโนมัติ และกรอบระบบขยายตาม ; คีย์ที่ไม่มีถูกข้าม', () {
      final a = uc('A'), b = uc('B');
      final base = layoutUseCaseDiagram(w.workspace);
      final moved = layoutUseCaseDiagram(w.workspace, overrides: {ucNodeKey(b.id): (900, 700), 'uc:หาย': (1, 1)});
      expect((moved.node(ucNodeKey(b.id))!.x, moved.node(ucNodeKey(b.id))!.y), (900.0, 700.0));
      expect(moved.node(ucNodeKey(a.id))!.x, base.node(ucNodeKey(a.id))!.x, reason: 'ข้ออื่นอยู่เดิม');
      expect(moved.boundary!.w, greaterThan(base.boundary!.w));
      expect(moved.boundary!.h, greaterThan(base.boundary!.h));
      expect(moved.nodes.length, base.nodes.length);
    });
  });

  group('ส่งออก SVG', () {
    test('ไม่มี Use Case = null', () => expect(exportUseCaseSvg(w.workspace), isNull));

    test('มีโครงครบ : วงรีต่อ Use Case, ผู้กระทำ, include/extend พร้อมป้าย, ชื่อระบบ (escape), ธีม/โปร่งใส', () {
      w.workspace.name = 'ร้าน <A&B>';
      final a = uc('จองห้อง', secondary: 'Payment Gateway'), b = uc('ชำระเงิน');
      final c = uc('ใช้โค้ดส่วนลด');
      w.updateUseCase(a.id, (x) => x.includes.add(b.id));
      w.updateUseCase(c.id, (x) => x.extendsFrom.add(UcExtend(baseId: a.id, condition: 'มีโค้ด')));
      final svg = exportUseCaseSvg(w.workspace)!;
      expect(svg.startsWith('<svg'), isTrue);
      expect(svg.trimRight().endsWith('</svg>'), isTrue);
      expect('<ellipse'.allMatches(svg).length, 6, reason: '3 Use Case × (พื้น + สีอ่อน)');
      expect(svg, contains('ร้าน &lt;A&amp;B&gt;'));
      expect(svg, contains('«include»'));
      expect(svg, contains('«extend»'));
      expect(svg, contains('[มีโค้ด]'));
      expect(svg, contains('Gateway'), reason: 'ชื่อผู้กระทำรองถูกตัดบรรทัดเป็น Payment / Gateway');
      expect(svg, contains('UC-01'));
      expect(svg, contains('<rect x='), reason: 'มีพื้นหลัง/กรอบ');
      final dark = exportUseCaseSvg(w.workspace, dark: true)!;
      expect(dark, isNot(svg));
      expect(dark, contains('#121820'));
      final transparent = exportUseCaseSvg(w.workspace, transparent: true)!;
      expect(transparent, isNot(contains('fill="#F6F8FB"')));
      expect(transparent.length, lessThan(svg.length));
      expect(svg, isNot(contains('NaN')));
    });

    test('ชื่อยาวถูกตัดเป็น 2 บรรทัดและมี … ; ตำแหน่งที่ลากมีผลกับภาพ', () {
      final a = uc('ชื่อ Use Case ที่ยาวมากมากมากมากมากมากมากมากมากมากมากมากมากมากมากมาก ' * 2);
      final plain = exportUseCaseSvg(w.workspace)!;
      expect(plain, contains('…'));
      final moved = exportUseCaseSvg(w.workspace, overrides: {ucNodeKey(a.id): (800, 600)})!;
      expect(moved, isNot(plain));
    });
  });

  group('ตำแหน่งที่ผู้ใช้ลาก (ตัวควบคุม)', () {
    test('ตั้งตำแหน่ง → ย้อนทั้งการลากต่อเนื่องเป็นขั้นเดียว → ทำซ้ำ → จัดวางใหม่ย้อนได้', () {
      final a = uc('A');
      final before = w.projectHistory.undoCount;
      for (final x in [10.0, 20.0, 35.0, 50.0]) {
        w.setUseCaseNodePosition('uc:${a.id}', x, x * 2);
      }
      expect(w.useCaseLayout['uc:${a.id}'], (50.0, 100.0));
      expect(w.projectHistory.undoCount, before + 1, reason: 'ลากต่อเนื่อง = ขั้นเดียว');
      expect(w.projectHistory.undoLabel, 'ย้ายในแผนภาพ Use Case');
      w.undo();
      expect(w.useCaseLayout, isEmpty);
      expect(w.workspace.meta.extra.containsKey('useCaseLayout'), isFalse);
      w.redo();
      expect(w.useCaseLayout['uc:${a.id}'], (50.0, 100.0));
      w.resetUseCaseLayout();
      expect(w.useCaseLayout, isEmpty);
      w.undo();
      expect(w.useCaseLayout['uc:${a.id}'], (50.0, 100.0));
    });

    test('ค่าเดิมซ้ำไม่เข้าประวัติ ; อยู่รอดข้ามการบันทึก/เปิดไฟล์ ; ข้อมูลเสียถูกข้าม', () {
      final a = uc('A');
      w.setUseCaseNodePosition('uc:${a.id}', 5, 6);
      final n = w.projectHistory.undoCount;
      w.setUseCaseNodePosition('uc:${a.id}', 5, 6);
      expect(w.projectHistory.undoCount, n);
      final copy = copyWorkspace(w.workspace);
      expect(copy.meta.extra['useCaseLayout'], {'uc:${a.id}': [5.0, 6.0]});
      w.workspace.meta.extra['useCaseLayout'] = {'uc:${a.id}': [1, 2], 'actor:x': 'ขยะ', 'bad': [1], 'k': [1, 'z']};
      expect(w.useCaseLayout, {'uc:${a.id}': (1.0, 2.0)});
    });

    test('resetUseCaseLayout ตอนยังไม่มีตำแหน่ง = ไม่ทำอะไร', () {
      final n = w.projectHistory.undoCount;
      w.resetUseCaseLayout();
      expect(w.projectHistory.undoCount, n);
    });
  });
  group('หน้าจอ: ขยายจาก Use Case อื่น (extend)', () {
    late WorkspaceController wc;
    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true)));
      wc = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      wc.showUseCases();
      await tester.pumpAndSettle();
    }

    testWidgets('เลือกฐานจากเมนู → ขึ้นป้าย ; แตะป้ายแก้เงื่อนไข ; กากบาทเอาออก ; ย้อนได้', (tester) async {
      await boot(tester);
      final base = wc.addUseCase(name: 'จองห้อง', actor: 'Guest');
      final ext = wc.addUseCase(name: 'ใช้โค้ดส่วนลด', actor: 'Guest');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('uc-item-${ext.id}')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('uc-ext-add')));
      await tester.tap(find.byKey(const ValueKey('uc-ext-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('จองห้อง').last);
      await tester.pumpAndSettle();
      expect(wc.useCaseById(ext.id)!.extendsFrom.single.baseId, base.id);
      expect(find.byKey(ValueKey('uc-ext-${base.id}')), findsOneWidget);
      expect(wc.projectHistory.undoLabel, 'แก้การขยาย Use Case');

      await tester.tap(find.byKey(ValueKey('uc-ext-${base.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('uc-ext-dialog')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('uc-ext-condition')), '  มีโค้ดส่วนลด ');
      await tester.tap(find.byKey(const ValueKey('uc-ext-ok')));
      await tester.pumpAndSettle();
      expect(wc.useCaseById(ext.id)!.extendsFrom.single.condition, 'มีโค้ดส่วนลด');
      expect(find.textContaining('[มีโค้ดส่วนลด]'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byKey(ValueKey('uc-ext-${base.id}')), matching: find.byIcon(Icons.close_rounded)));
      await tester.pumpAndSettle();
      expect(wc.useCaseById(ext.id)!.extendsFrom, isEmpty);
      wc.undo();
      await tester.pumpAndSettle();
      expect(wc.useCaseById(ext.id)!.extendsFrom.single.condition, 'มีโค้ดส่วนลด');
      expect(tester.takeException(), isNull);
    });

    testWidgets('ยกเลิกกล่องเงื่อนไข = ไม่เปลี่ยน ; ฐานที่หายแสดงเป็น ? ไม่ล้ม', (tester) async {
      await boot(tester);
      final ext = wc.addUseCase(name: 'ขยาย', actor: 'Guest');
      wc.updateUseCase(ext.id, (x) => x.extendsFrom.add(UcExtend(baseId: 'หาย', condition: 'เดิม')));
      await tester.pumpAndSettle();
      expect(find.textContaining('? · [เดิม]'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('uc-ext-หาย')));
      await tester.tap(find.byKey(const ValueKey('uc-ext-หาย')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('uc-ext-condition')), 'ใหม่');
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(wc.useCaseById(ext.id)!.extendsFrom.single.condition, 'เดิม');
      expect(tester.takeException(), isNull);
    });
  });
}
