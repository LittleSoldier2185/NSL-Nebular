import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/export/diagram_text_export.dart';
import 'package:nsl_nebular/core/export/svg_export.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/layout/diagram_geometry.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/relation_model.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/project_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

/// Phase 17b: ผู้ใช้กำหนดสัญลักษณ์ปลายเส้น ER เอง (ฝั่งแม่ / ฝั่งลูกจำนวน / ฝั่งลูกขั้นต่ำ) — เอกสารล้วน ไม่เปลี่ยน DDL
void main() {
  RelationModel rel(Project p) => p.relations.single;

  group('ตัวแบบ / ไฟล์', () {
    test('ค่าเริ่มต้นเป็นอัตโนมัติ และไม่เขียนฟิลด์ลงไฟล์', () {
      final r = rel(base());
      expect(r.parentCard, isNull);
      expect(r.childMax, isNull);
      expect(r.childMin, isNull);
      final j = r.toJson();
      expect(j.containsKey('parentCard'), isFalse);
      expect(j.containsKey('childMax'), isFalse);
      expect(j.containsKey('childMin'), isFalse);
    });

    test('บันทึกแล้วอ่านกลับได้ครบ', () {
      final p = base();
      rel(p)
        ..parentCard = ParentCard.zeroOne
        ..childMax = ChildMax.one
        ..childMin = ChildMin.one;
      final back = rel(clone(p));
      expect(back.parentCard, ParentCard.zeroOne);
      expect(back.childMax, ChildMax.one);
      expect(back.childMin, ChildMin.one);
    });

    test('ชื่อที่ไม่รู้จัก/ชนิดผิด = อัตโนมัติ (ไฟล์จากรุ่นใหม่กว่าหรือแก้มือไม่พัง)', () {
      final j = rel(base()).toJson()
        ..['parentCard'] = 'maybe'
        ..['childMax'] = 3
        ..['childMin'] = null;
      final r = RelationModel.fromJson(j);
      expect(r.parentCard, isNull);
      expect(r.childMax, isNull);
      expect(r.childMin, isNull);
    });

    test('ไม่มีผลกับ DDL', () {
      // ตรวจผ่านการเทียบ JSON ของตาราง/คอลัมน์: ค่าที่ตั้งอยู่ในความสัมพันธ์เท่านั้น ไม่แตะคอลัมน์
      final p = base();
      final before = tb(p, 'to').toJson().toString();
      rel(p)
        ..childMax = ChildMax.one
        ..parentCard = ParentCard.zeroOne;
      expect(tb(p, 'to').toJson().toString(), before);
    });
  });

  group('relationCardinality: ผู้ใช้กำหนดทับค่าอนุมานทีละส่วน', () {
    test('ไม่กำหนด = อนุมานจากสคีมา (user_id NOT NULL ไม่ UNIQUE -> แม่หนึ่งเดียว ลูกหลาย ไม่บังคับ)', () {
      final p = base();
      final c = relationCardinality(rel(p), tb(p, 'to'), cl(p, 'to', 'o2'));
      expect(c.parentRequired, isTrue);
      expect(c.childOne, isFalse);
      expect(c.childRequired, isFalse);
    });

    test('กำหนดทีละส่วน ส่วนที่เหลือยังอัตโนมัติ', () {
      final p = base();
      rel(p).childMin = ChildMin.one;
      var c = relationCardinality(rel(p), tb(p, 'to'), cl(p, 'to', 'o2'));
      expect(c.childRequired, isTrue);
      expect(c.parentRequired, isTrue);
      expect(c.childOne, isFalse);

      rel(p)
        ..childMax = ChildMax.one
        ..parentCard = ParentCard.zeroOne;
      c = relationCardinality(rel(p), tb(p, 'to'), cl(p, 'to', 'o2'));
      expect(c.childOne, isTrue);
      expect(c.parentRequired, isFalse);
    });

    test('ค่าที่ผู้ใช้ตั้งชนะสคีมา: FK เป็น UNIQUE แต่เลือก "หลาย"', () {
      final p = base();
      cl(p, 'to', 'o2').unique = true;
      expect(autoCardinality(tb(p, 'to'), cl(p, 'to', 'o2')).childOne, isTrue);
      rel(p).childMax = ChildMax.many;
      expect(relationCardinality(rel(p), tb(p, 'to'), cl(p, 'to', 'o2')).childOne, isFalse);
    });

    test('relationGeometry ใช้ค่าที่กำหนด', () {
      final p = base();
      rel(p)
        ..childMax = ChildMax.one
        ..childMin = ChildMin.one
        ..parentCard = ParentCard.zeroOne;
      final g = relationGeometry(p, rel(p))!;
      expect(g.oneToOne, isTrue);
      expect(g.childRequired, isTrue);
      expect(g.mandatory, isFalse);
    });
  });

  group('ส่งออก', () {
    test('Mermaid: ขั้นต่ำ/จำนวนฝั่งลูก และฝั่งแม่ตามที่กำหนด', () {
      final p = base();
      expect(exportMermaid(p), contains('}o--||'));
      rel(p).childMin = ChildMin.one;
      expect(exportMermaid(p), contains('}|--||'));
      rel(p).childMax = ChildMax.one;
      expect(exportMermaid(p), contains('||--||'));
      rel(p)
        ..childMin = ChildMin.zero
        ..parentCard = ParentCard.zeroOne;
      expect(exportMermaid(p), contains('|o--o|'));
    });

    test('DBML: หนึ่ง = "-" หลาย = ">" (ขั้นต่ำใส่ไม่ได้)', () {
      final p = base();
      expect(exportDbml(p), contains(' > '));
      rel(p).childMax = ChildMax.one;
      expect(exportDbml(p), contains('.user_id - '));
    });

    test('SVG: อย่างน้อย 1 = ไม่มีวงกลมศูนย์ฝั่งลูก (ขีดแทน)', () {
      final p = base();
      p.tables[1].x = 400;
      int circles(String s) => RegExp(r'<circle').allMatches(s).length;
      int paths(String s) => RegExp(r'<path').allMatches(s).length;
      final auto = exportSvg(p)!;
      rel(p).childMin = ChildMin.one;
      final one = exportSvg(p)!;
      expect(circles(one), circles(auto) - 1);
      expect(paths(one), paths(auto) + 1);
    });
  });

  group('ตัวควบคุม', () {
    test('ตั้งค่า / กลับเป็นอัตโนมัติ / undo', () {
      final c = ProjectController()..loadProject(base(), null);
      c.setRelationChildMin('r1', ChildMin.one);
      c.setRelationParentCard('r1', ParentCard.zeroOne);
      c.setRelationChildMax('r1', ChildMax.one);
      expect(rel(c.project).childMin, ChildMin.one);
      expect(rel(c.project).parentCard, ParentCard.zeroOne);
      expect(rel(c.project).childMax, ChildMax.one);
      c.setRelationChildMin('r1', null);
      expect(rel(c.project).childMin, isNull);
      c.undo();
      expect(rel(c.project).childMin, ChildMin.one);
    });

    test('ตั้งค่าเดิมซ้ำ = ไม่เข้าประวัติ ; id ที่ไม่มี = ไม่ทำอะไร', () {
      final c = ProjectController()..loadProject(base(), null);
      c.setRelationChildMin('r1', null);
      expect(c.canUndo, isFalse);
      c.setRelationChildMin('nope', ChildMin.one);
      expect(c.canUndo, isFalse);
    });

    test('ทำสำเนาตารางพร้อมความสัมพันธ์: คงสัญลักษณ์ที่กำหนดไว้', () {
      final c = ProjectController()..loadProject(base(), null);
      c.setRelationChildMin('r1', ChildMin.one);
      c.setRelationParentCard('r1', ParentCard.zeroOne);
      c.selectAllTables();
      c.duplicateSelected();
      expect(c.project.relations.length, 2);
      final copy = c.project.relations.firstWhere((r) => r.id != 'r1');
      expect(copy.childMin, ChildMin.one);
      expect(copy.parentCard, ParentCard.zeroOne);
      expect(copy.childMax, isNull);
    });
  });

  group('แผงขวา (แบบ B)', () {
    late ProjectController c;

    Future<void> boot(WidgetTester tester, {Lang lang = Lang.th}) async {
      tester.view.physicalSize = const Size(1440, 936);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang)));
      c = tester.element(find.byType(HomePage)).read<ProjectController>();
      c.loadProject(base(), null);
      c.selectTable('to', columnId: 'o2'); // orders.user_id = คอลัมน์ FK
      await tester.pumpAndSettle();
    }

    Future<void> pick(WidgetTester tester, String key) async {
      final f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets('มีภาพตัวอย่างและปุ่มครบ 3 กลุ่ม ; เริ่มต้นเป็นอัตโนมัติ ไม่มีแถบเตือน', (tester) async {
      await boot(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('card-preview')));
      expect(find.byKey(const ValueKey('card-preview')), findsOneWidget);
      for (final k in [
        'card-parent-auto', 'card-parent-zeroOne', 'card-parent-one',
        'card-cmax-auto', 'card-cmax-one', 'card-cmax-many',
        'card-cmin-auto', 'card-cmin-zero', 'card-cmin-one',
      ]) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      expect(find.byKey(const ValueKey('card-parent-reset')), findsNothing);
      expect(find.byKey(const ValueKey('card-warn-min1')), findsNothing);
      expect(find.byKey(const ValueKey('card-warn-uq')), findsNothing);
    });

    testWidgets('กดปุ่มแล้วบันทึกในความสัมพันธ์ ; "กลับเป็นอัตโนมัติ" ล้างค่า', (tester) async {
      await boot(tester);
      await pick(tester, 'card-parent-zeroOne');
      expect(rel(c.project).parentCard, ParentCard.zeroOne);
      expect(find.byKey(const ValueKey('card-parent-reset')), findsOneWidget);
      await pick(tester, 'card-parent-reset');
      expect(rel(c.project).parentCard, isNull);
      expect(find.byKey(const ValueKey('card-parent-reset')), findsNothing);
    });

    testWidgets('อย่างน้อย 1: ขึ้นข้อความว่าเป็นเอกสารอย่างเดียว ไม่มีปุ่มแก้สคีมา', (tester) async {
      await boot(tester);
      await pick(tester, 'card-cmin-one');
      expect(rel(c.project).childMin, ChildMin.one);
      expect(find.byKey(const ValueKey('card-warn-min1')), findsOneWidget);
      expect(find.byKey(const ValueKey('card-warn-min1-fix')), findsNothing);
    });

    testWidgets('เลือก "หนึ่ง" ทั้งที่ FK ไม่ UNIQUE: เตือน + ปุ่มตั้ง UNIQUE แก้สคีมาได้ และเตือนหาย', (tester) async {
      await boot(tester);
      await pick(tester, 'card-cmax-one');
      expect(find.byKey(const ValueKey('card-warn-uq')), findsOneWidget);
      expect(cl(c.project, 'to', 'o2').unique, isFalse);
      await pick(tester, 'card-warn-uq-fix');
      expect(cl(c.project, 'to', 'o2').unique, isTrue);
      expect(find.byKey(const ValueKey('card-warn-uq')), findsNothing);
    });

    testWidgets('เลือก "หนึ่งเดียว" ทั้งที่ FK เป็น NULL ได้: เตือน + ปุ่มตั้ง NOT NULL', (tester) async {
      await boot(tester);
      c.updateColumn('to', 'o2', (x) => x.notNull = false);
      await tester.pumpAndSettle();
      await pick(tester, 'card-parent-one');
      expect(find.byKey(const ValueKey('card-warn-nn')), findsOneWidget);
      await pick(tester, 'card-warn-nn-fix');
      expect(cl(c.project, 'to', 'o2').notNull, isTrue);
      expect(find.byKey(const ValueKey('card-warn-nn')), findsNothing);
    });

    testWidgets('เลือก "ศูนย์หรือหนึ่ง" ทั้งที่ FK เป็น NOT NULL: เตือน + ปุ่มเอา NOT NULL ออก', (tester) async {
      await boot(tester);
      await pick(tester, 'card-parent-zeroOne');
      expect(find.byKey(const ValueKey('card-warn-nnoff')), findsOneWidget);
      await pick(tester, 'card-warn-nnoff-fix');
      expect(cl(c.project, 'to', 'o2').notNull, isFalse);
    });

    testWidgets('ภาษาอังกฤษ: ไม่มีข้อความไทยหลุดในส่วนนี้', (tester) async {
      await boot(tester, lang: Lang.en);
      await pick(tester, 'card-cmin-one');
      await pick(tester, 'card-cmax-one');
      await pick(tester, 'card-parent-zeroOne');
      final thai = RegExp(r'[฀-๿]');
      for (final k in ['card-preview', 'card-parent-auto', 'card-cmax-auto', 'card-cmin-auto', 'card-warn-min1', 'card-warn-uq', 'card-warn-nnoff']) {
        for (final t in tester.widgetList<Text>(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(Text)))) {
          expect(thai.hasMatch(t.data ?? ''), isFalse, reason: '$k: ${t.data}');
        }
      }
      expect(find.text('Relationship'), findsOneWidget);
    });
  });
}
