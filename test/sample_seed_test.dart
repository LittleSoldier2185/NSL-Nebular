import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/export/sample_data.dart';
import 'package:nsl_nebular/core/export/seed_data.dart';
import 'package:nsl_nebular/core/mock/mock_engine.dart';
import 'package:nsl_nebular/core/mock/mock_settings.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/relation_model.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/cli/nebular_api.dart' show loadProject;
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/project_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/app_actions.dart';
import 'package:nsl_nebular/ui/create_table_dialog.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// Phase 33: ข้อมูลตัวอย่างสร้างเอง (generateSampleSeeds) ใช้กับข้อมูลตั้งต้นของตารางและ Mock Server
void main() {
  /// users(id AI PK, email UNIQUE NOT NULL, name) <- orders(id AI PK, user_id FK NOT NULL, total decimal)
  Project shop({List<Map<String, String?>> userSeed = const []}) => Project(name: 'shop', dialect: Dialect.mysql, tables: [
        TableModel(id: 'u', name: 'users', columns: [
          ColumnModel(id: 'u1', name: 'id', isPrimaryKey: true, autoIncrement: true),
          ColumnModel(id: 'u2', name: 'email', type: DataType.varchar, length: 60, notNull: true, unique: true),
          ColumnModel(id: 'u3', name: 'name', type: DataType.varchar, length: 40),
        ], seedRows: userSeed),
        TableModel(id: 'o', name: 'orders', columns: [
          ColumnModel(id: 'o1', name: 'id', isPrimaryKey: true, autoIncrement: true),
          ColumnModel(id: 'o2', name: 'user_id', notNull: true),
          ColumnModel(id: 'o3', name: 'total', type: DataType.decimal, length: 10, scale: 2),
        ]),
      ], relations: [
        RelationModel(id: 'r1', fromTableId: 'o', fromColumnId: 'o2', toTableId: 'u', toColumnId: 'u1'),
      ]);

  group('generateSampleSeeds', () {
    test('ตารางแม่ก่อนลูก FK ชี้ค่าที่มีจริง ; AUTO INCREMENT ไม่อยู่ในแถว ; จำนวนตามที่ขอ', () {
      final s = generateSampleSeeds(shop(), rows: 7);
      expect(s['u']!.length, 7);
      expect(s['o']!.length, 7);
      expect(s['u']!.every((r) => !r.containsKey('u1')), isTrue); // id เป็น AUTO INCREMENT
      expect(s['o']!.every((r) => !r.containsKey('o1')), isTrue);
      final ids = {for (var i = 1; i <= 7; i++) '$i'};
      expect(s['o']!.every((r) => ids.contains(r['o2'])), isTrue);
      final emails = [for (final r in s['u']!) r['u2']];
      expect(emails.toSet().length, emails.length); // UNIQUE ไม่ซ้ำ
    });

    test('ผลคงที่ด้วย seed เดียวกัน และต่างเมื่อเปลี่ยน seed', () {
      final p = shop();
      expect(generateSampleSeeds(p, rows: 5, seed: 3), generateSampleSeeds(p, rows: 5, seed: 3));
      expect(generateSampleSeeds(p, rows: 5, seed: 3)['o'], isNot(generateSampleSeeds(p, rows: 5, seed: 4)['o']));
    });

    test('ผ่านการตรวจข้อมูลตั้งต้น (validateSeed) ไม่มีปัญหา', () {
      final p = shop();
      final s = generateSampleSeeds(p, rows: 12);
      for (final t in p.tables) {
        t.seedRows = s[t.id]!;
      }
      expect(validateSeed(p), isEmpty);
    });

    test('tableIds : สร้างเฉพาะตารางที่ขอ (ลูกยังชี้แถวของแม่ที่สร้างไว้เบื้องหลัง)', () {
      final s = generateSampleSeeds(shop(), rows: 4, tableIds: {'o'});
      expect(s.keys, ['o']);
      expect(s['o']!.every((r) => {'1', '2', '3', '4'}.contains(r['o2'])), isTrue);
    });

    test('ไม่ระบุ tableIds : ข้ามตารางที่มีข้อมูลตั้งต้นอยู่แล้ว และใช้ค่าของมันเป็นแม่ของ FK', () {
      final p = shop(userSeed: [
        {'u2': 'a@x.com', 'u3': 'A'},
        {'u1': '50', 'u2': 'b@x.com'},
        {'u2': 'c@x.com'},
      ]);
      final s = generateSampleSeeds(p, rows: 20);
      expect(s.containsKey('u'), isFalse);
      // id ของแม่ = 51, 50, 52 (แถวที่ไม่ใส่ต่อจากเลขสูงสุดที่มี เหมือนที่ Mock ทำ)
      expect(s['o']!.every((r) => {'51', '50', '52'}.contains(r['o2'])), isTrue);
    });

    test('จำนวนแถวถูกบีบให้อยู่ใน 1..1000', () {
      expect(generateSampleSeeds(shop(), rows: 0)['u']!.length, 1);
      expect(generateSampleSeeds(shop(), rows: 5000)['u']!.length, 1000);
    });

    test('Hotel Booking (9 ตาราง FK ซ้อน) : ทุกตารางมีข้อมูล ตรวจผ่านไม่มีปัญหา', () async {
      final w = await loadProject('samples/hotel_booking.nsln');
      final er = w.documents.firstWhere((d) => d.er != null).er!;
      for (final t in er.tables) {
        t.seedRows = [];
      }
      final s = generateSampleSeeds(er, rows: 8);
      expect(s.length, er.tables.where((t) => t.columns.isNotEmpty).length);
      for (final t in er.tables) {
        t.seedRows = s[t.id] ?? [];
      }
      expect(validateSeed(er), isEmpty);
    });
  });

  group('Mock : สร้างข้อมูลตัวอย่างให้ตารางที่ไม่มี seed', () {
    late WorkspaceController w;
    late ApiDocument api;
    late MockSettings settings;
    late MockEngine engine;

    Object? get(String path) => jsonDecode(engine.handle(MockRequest(method: 'GET', path: path, query: const {}, body: '')).reply.body);

    setUp(() {
      w = WorkspaceController();
      final er = w.mainEr.project;
      final p = shop();
      er.tables.addAll(p.tables);
      er.relations.addAll(p.relations);
      api = w.addDocument(DocType.api, name: 'Shop')!.api!;
      api.endpoints.addAll([
        ApiEndpoint(id: 'lu', method: ApiMethod.get, path: '/users', table: ApiTableRef(docId: w.mainEr.docId, tableId: 'u'), responses: [ApiResponse(status: 200)]),
        ApiEndpoint(id: 'lo', method: ApiMethod.get, path: '/orders', table: ApiTableRef(docId: w.mainEr.docId, tableId: 'o'), responses: [ApiResponse(status: 200)]),
        ApiEndpoint(id: 'pu', method: ApiMethod.post, path: '/users', table: ApiTableRef(docId: w.mainEr.docId, tableId: 'u'), fields: [ApiField(id: 'f1', name: 'email', required: true)]),
      ]);
      settings = const MockSettings();
      engine = MockEngine(api: () => api, workspace: () => w.workspace, settings: () => settings, random: Random(1));
    });

    test('ค่าเริ่มต้นเปิด : ตอบ 10 แถว ไม่ใช่ [] ; FK ของ orders ชี้ users ที่ตอบจริง', () {
      final users = get('/users') as List;
      final orders = get('/orders') as List;
      expect(users.length, 10);
      expect(orders.length, 10);
      final ids = {for (final u in users) (u as Map)['id']};
      expect(ids, {for (var i = 1; i <= 10; i++) i});
      expect(orders.every((o) => ids.contains((o as Map)['user_id'])), isTrue);
      expect({for (final u in users) (u as Map)['email']}.length, 10); // UNIQUE
    });

    test('จำนวนแถวตามค่าตั้ง ; ปิด = [] เหมือนเดิม', () {
      settings = const MockSettings(sampleRows: 3);
      expect((get('/users') as List).length, 3);
      settings = const MockSettings(autoSample: false);
      engine.reset();
      expect(get('/users'), isEmpty);
    });

    test('ตารางที่มี seed ใช้ seed ของตัวเอง ไม่สร้างทับ', () {
      w.mainEr.project.tableById('u')!.seedRows = [
        {'u2': 'only@x.com'}
      ];
      final users = get('/users') as List;
      expect(users.length, 1);
      expect((users.single as Map)['email'], 'only@x.com');
      // orders ที่ไม่มี seed ยังชี้ users ที่มีอยู่จริง (id 1)
      expect((get('/orders') as List).every((o) => (o as Map)['user_id'] == 1), isTrue);
    });

    test('reset แล้วได้ชุดเดิม (คงที่) ; POST เพิ่มต่อจากเลขสูงสุด', () {
      final before = get('/users');
      engine.handle(MockRequest(method: 'POST', path: '/users', query: const {}, body: jsonEncode({'email': 'new@x.com'})));
      expect((get('/users') as List).length, 11);
      expect(((get('/users') as List).last as Map)['id'], 11);
      engine.reset();
      expect(get('/users'), before);
    });
  });

  group('ค่าตั้ง Mock : ไฟล์เก่าไม่มีคีย์ = เปิด', () {
    test('ค่าเริ่มต้นไม่ถูกเขียนลง JSON ; ค่าที่ต่างถูกเก็บและอ่านกลับได้', () {
      expect(const MockSettings().toJson().containsKey('sample'), isFalse);
      expect(const MockSettings().toJson().containsKey('sampleRows'), isFalse);
      final back = MockSettings.fromJson(const MockSettings(autoSample: false, sampleRows: 25).toJson());
      expect(back.autoSample, isFalse);
      expect(back.sampleRows, 25);
      expect(MockSettings.fromJson({'port': 9000}).autoSample, isTrue);
      expect(MockSettings.fromJson({'sampleRows': 99999}).sampleRows, kMockMaxSampleRows);
      expect(const MockSettings().copyWith(sampleRows: 0).sampleRows, 1);
    });
  });

  group('หน้าจอ', () {
    late ProjectController c;

    Future<void> boot(WidgetTester tester, Project p) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings()));
      c = tester.element(find.byType(HomePage)).read<ProjectController>();
      c.loadProject(p, null);
      await tester.pump();
      AppActions(tester.element(find.byType(HomePage))).editTableStructure('o', TableDialogTab.seed);
      await tester.pumpAndSettle();
    }

    testWidgets('ปุ่ม "สร้างข้อมูลตัวอย่าง" : ถามจำนวน เติมแถวลงตาราง แล้วบันทึก ; ย้อนกลับได้', (tester) async {
      await boot(tester, shop());
      await tester.tap(find.byKey(const ValueKey('seed-generate')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('seed-gen-warn')), findsNothing); // ยังไม่มีแถวเดิม
      await tester.enterText(find.byKey(const ValueKey('seed-gen-count')), '4');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('seed-gen-ok')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ct-save')));
      await tester.pumpAndSettle();
      final rows = c.project.tableById('o')!.seedRows;
      expect(rows.length, 4);
      expect(rows.every((r) => {'1', '2', '3', '4'}.contains(r['o2'])), isTrue);
      c.undo();
      expect(c.project.tableById('o')!.seedRows, isEmpty);
    });

    testWidgets('มีแถวเดิม = เตือนว่าจะถูกแทนที่ ; จำนวนผิด = ปุ่มสร้างกดไม่ได้', (tester) async {
      final p = shop();
      p.tableById('o')!.seedRows = [
        {'o2': '1'},
        {'o2': '1'}
      ];
      await boot(tester, p);
      await tester.tap(find.byKey(const ValueKey('seed-generate')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('seed-gen-warn')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('seed-gen-count')), '0');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('seed-gen-ok'))).onPressed, isNull);
    });
  });
}
