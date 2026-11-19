import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/parser/sql_decode.dart';
import 'package:nsl_nebular/core/parser/sql_importer.dart';
import 'package:nsl_nebular/state/project_controller.dart';
import 'package:nsl_nebular/ui/import_dialog.dart';

Uint8List utf16(String s, {required bool le, bool bom = true}) {
  final out = <int>[];
  if (bom) out.addAll(le ? [0xFF, 0xFE] : [0xFE, 0xFF]);
  for (final u in s.codeUnits) {
    out.addAll(le ? [u & 0xFF, u >> 8] : [u >> 8, u & 0xFF]);
  }
  return Uint8List.fromList(out);
}

void main() {
  group('decodeSqlBytes', () {
    const text = 'CREATE TABLE `ลูกค้า` (id INT); -- ไทย 😀';

    test('UTF-8 ไม่มี BOM / มี BOM', () {
      expect(decodeSqlBytes(Uint8List.fromList(utf8.encode(text))), text);
      expect(decodeSqlBytes(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)])), text);
    });

    test('UTF-16 LE / BE (SSMS) รวม emoji ที่เป็น surrogate pair', () {
      expect(decodeSqlBytes(utf16(text, le: true)), text);
      expect(decodeSqlBytes(utf16(text, le: false)), text);
    });

    test('ไบต์เสียไม่ทำให้ทั้งไฟล์พัง', () {
      final s = decodeSqlBytes(Uint8List.fromList([...utf8.encode('abc'), 0xFF, 0xC3, ...utf8.encode('xyz')]));
      expect(s.startsWith('abc'), true);
      expect(s.endsWith('xyz'), true);
    });

    test('ไฟล์ว่าง', () {
      expect(decodeSqlBytes(Uint8List(0)), '');
    });

    test('ไฟล์ UTF-16 ของ SSMS import ได้จริงตั้งแต่ไบต์ถึงโมเดล', () {
      final sql = 'CREATE TABLE [dbo].[ผู้ใช้] ([Id] INT IDENTITY(1,1) NOT NULL PRIMARY KEY)\r\nGO\r\n';
      final r = importSql(decodeSqlBytes(utf16(sql, le: true)));
      expect(r.project.tables.single.name, 'ผู้ใช้');
      expect(r.project.tables.single.columns.single.autoIncrement, true);
    });
  });

  group('ProjectController.loadImported', () {
    test('ถือว่ายังไม่บันทึก ไม่มีไฟล์ และล้างประวัติ', () {
      final c = ProjectController();
      c.addTable();
      final r = importSql('CREATE TABLE a (id INT PRIMARY KEY);');
      c.loadImported(r.project);
      expect(c.dirty, true);
      expect(c.filePath, isNull);
      expect(c.canUndo, false);
      expect(c.project.tables.single.name, 'a');
      expect(c.issues.where((i) => i.code == 'no_pk'), isEmpty);
    });
  });

  group('WorkspaceController: นำเข้าเป็น ER ใหม่ / แทนที่ ER ที่เปิด', () {
    test('โปรเจกต์ใหม่ที่ยังไม่แตะ = pristine ; แก้แล้ว/มีไฟล์ = ไม่ใช่', () {
      final c = ProjectController();
      expect(c.workspaceController.isPristine, true);
      c.addTable();
      expect(c.workspaceController.isPristine, false);
    });

    test('ER ใหม่: เอกสารเดิมอยู่ครบ ชื่อตามที่นำเข้า (ซ้ำต่อเลข) เปิดแท็บใหม่ ชื่อโปรเจกต์ไม่เปลี่ยน', () {
      final c = ProjectController();
      c.addTable();
      final wc = c.workspaceController;
      final before = wc.workspace.name;
      final r = importSql('CREATE TABLE a (id INT PRIMARY KEY);', name: 'shop');
      final doc = wc.importAsNewEr(r.project, name: 'shop');
      expect(wc.documents.length, 2);
      expect(doc.name, 'shop');
      expect(wc.activeId, doc.id);
      expect(wc.currentEr.project.tables.single.name, 'a');
      expect(c.project.tables.length, 1); // ER เดิมไม่ถูกแตะ
      expect(wc.workspace.name, before);
      expect(wc.dirty, true);
      final again = wc.importAsNewEr(importSql('CREATE TABLE b (id INT);').project, name: 'shop');
      expect(again.name, isNot('shop'));
    });

    test('แทนที่ ER ที่เปิด: undo ได้ขั้นเดียว ชื่อเอกสารคงเดิม', () {
      final c = ProjectController();
      c.addTable();
      final wc = c.workspaceController;
      final oldName = c.project.tables.single.name;
      final er = wc.importReplaceCurrentEr(importSql('CREATE TABLE x (id INT PRIMARY KEY); CREATE TABLE y (id INT);').project);
      expect(identical(er, c), true);
      expect(wc.documents.length, 1);
      expect(c.project.tables.map((t) => t.name), ['x', 'y']);
      c.undo();
      expect(c.project.tables.single.name, oldName);
    });
  });

  group('ImportPreviewDialog', () {
    Future<ImportTarget? Function()> open(WidgetTester tester, String sql, {String? erName}) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ImportTarget? popped;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async => popped = await showDialog<ImportTarget>(
                context: ctx,
                builder: (_) => ImportPreviewDialog(result: importSql(sql), fileName: 'x.sql', currentErName: erName),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => popped;
    }

    testWidgets('มี ER ที่เปิดอยู่: เลือกปลายทางได้ ค่าเริ่มต้น = ER ใหม่', (tester) async {
      final result = await open(tester, 'CREATE TABLE a (id INT PRIMARY KEY);', erName: 'ร้านค้า');
      expect(find.text('การนำเข้าจะแทนที่โปรเจกต์ที่เปิดอยู่'), findsNothing);
      expect(find.text('แทนที่ ER ที่เปิดอยู่: ร้านค้า'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'นำเข้า'));
      await tester.pumpAndSettle();
      expect(result(), ImportTarget.newEr);

      final r2 = await open(tester, 'CREATE TABLE a (id INT PRIMARY KEY);', erName: 'ร้านค้า');
      await tester.tap(find.byKey(const ValueKey('import-target-replaceEr')));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'นำเข้า'));
      await tester.pumpAndSettle();
      expect(r2(), ImportTarget.replaceEr);
    });

    testWidgets('สรุปจำนวน + ไม่มี ER ที่เปิด = นำเข้าเป็นโปรเจกต์ใหม่', (tester) async {
      ImportTarget? result;
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showDialog<ImportTarget>(
                context: ctx,
                builder: (_) => ImportPreviewDialog(
                  result: importSql('''
CREATE TABLE a (id INT PRIMARY KEY);
CREATE TABLE b (id INT PRIMARY KEY, a_id INT REFERENCES a(id), g GEOMETRY);
INSERT INTO a VALUES (1);
'''),
                  fileName: 'shop.sql',
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('นำเข้า shop.sql'), findsOneWidget);
      expect(find.textContaining('2 ตาราง · 4 คอลัมน์ · 1 ความสัมพันธ์ FK'), findsOneWidget);
      expect(find.textContaining('GEOMETRY'), findsOneWidget); // คำเตือนชนิดที่ไม่รู้จัก
      expect(find.textContaining('INSERT'), findsOneWidget); // ข้อมูลเพิ่มเติม

      expect(find.text('การนำเข้าจะแทนที่โปรเจกต์ที่เปิดอยู่'), findsOneWidget);
      expect(find.byKey(const ValueKey('import-target-newEr')), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'นำเข้า'));
      await tester.pumpAndSettle();
      expect(result, ImportTarget.newProject);
    });

    testWidgets('ไม่พบตาราง: ปุ่มนำเข้ากดไม่ได้ ยกเลิกคืน null', (tester) async {
      final result = await open(tester, 'SELECT 1;', erName: 'ER');
      expect(find.text('ไม่พบ CREATE TABLE ในไฟล์นี้'), findsOneWidget);
      final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'นำเข้า'));
      expect(btn.onPressed, isNull);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportPreviewDialog), findsNothing);
      expect(result(), isNull);
    });
  });
}
