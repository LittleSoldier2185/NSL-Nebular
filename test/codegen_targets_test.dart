import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/codegen/gen_targets.dart';
import 'package:nsl_nebular/core/codegen/gen_writer.dart';
import 'package:nsl_nebular/core/codegen/laravel.dart';
import 'package:nsl_nebular/core/codegen/wireframe_code.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/index_model.dart';
import 'package:nsl_nebular/core/models/relation_model.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';

/// Phase 10: สร้างโค้ดหลายเป้าหมาย — snapshot ของทุกเป้าหมาย + การเขียนลงโฟลเดอร์ที่ไม่ทับไฟล์ที่แก้ด้วยมือ
///
/// สร้าง/อัปเดตไฟล์อ้างอิง: `UPDATE_GOLDENS=1 flutter test test/codegen_targets_test.dart` แล้วตรวจ diff ด้วยตา
void main() {
  WorkspaceController shop() {
    final w = WorkspaceController();
    w.workspace.name = 'Shop';
    w.mainEr.project.tables
      ..add(TableModel(id: 'c', name: 'customers', comment: 'ลูกค้า', columns: [
        ColumnModel(id: 'c1', name: 'id', type: DataType.bigint, isPrimaryKey: true, autoIncrement: true),
        ColumnModel(id: 'c2', name: 'email', type: DataType.varchar, length: 120, notNull: true, unique: true),
        ColumnModel(id: 'c3', name: 'created_at', type: DataType.timestamp, defaultValue: 'CURRENT_TIMESTAMP'),
      ]))
      ..add(TableModel(id: 'o', name: 'orders', columns: [
        ColumnModel(id: 'o1', name: 'id', type: DataType.bigint, isPrimaryKey: true, autoIncrement: true),
        ColumnModel(id: 'o2', name: 'customer_id', type: DataType.bigint, notNull: true),
        ColumnModel(id: 'o3', name: 'status', type: DataType.varchar, length: 20, notNull: true, defaultValue: "'pending'", comment: 'สถานะ'),
        ColumnModel(id: 'o4', name: 'total', type: DataType.decimal, length: 10, scale: 2),
      ], indexes: [
        IndexModel(id: 'i', name: 'idx_orders_status', columnIds: ['o3']),
      ]));
    w.mainEr.project.relations.add(RelationModel(id: 'r', fromTableId: 'o', fromColumnId: 'o2', toTableId: 'c', toColumnId: 'c1', onDelete: RefAction.cascade));
    final api = w.apiController(w.addDocument(DocType.api, name: 'Store API')!.id)!;
    api.generateCrud(w.mainEr.docId, w.mainEr.project.tableById('o')!);
    api.updateEndpoint(api.api.endpoints[1].id, (e) => e.auth = true);
    api.addEndpoint(method: ApiMethod.post, path: '/auth/login', group: 'auth');
    final wf = w.addDocument(DocType.wireframe, name: 'Cart Page')!;
    wf.wireframe!.components.addAll([
      WfComponent(id: 'h', kind: WfKind.heading, text: 'ตะกร้าของฉัน', x: 20, y: 20),
      WfComponent(id: 'l', kind: WfKind.list, text: 'สินค้า A\nสินค้า B', x: 20, y: 80),
      WfComponent(id: 'q', kind: WfKind.input, text: 'โค้ดส่วนลด', x: 20, y: 200),
      WfComponent(id: 'c', kind: WfKind.checkbox, text: 'รับใบกำกับภาษี', x: 20, y: 260, checked: true),
      WfComponent(id: 's', kind: WfKind.button, text: 'สั่งซื้อ', x: 300, y: 320),
      WfComponent(id: 'b', kind: WfKind.button, text: 'กลับ', x: 20, y: 322, secondary: true),
    ]);
    return w;
  }

  final update = Platform.environment['UPDATE_GOLDENS'] == '1';
  final goldens = Directory('test/goldens/codegen');

  group('snapshot ทุกเป้าหมาย', () {
    for (final t in GenTarget.values) {
      test(t.name, () {
        final w = shop();
        addTearDown(w.dispose);
        final r = generateFiles(w.workspace, {t});
        if (t == GenTarget.seedSql) {
          expect(r.files, isEmpty, reason: 'ไม่มีข้อมูลตั้งต้น = ไม่สร้างไฟล์');
          return;
        }
        expect(r.files, isNotEmpty);
        expect(r.warnings, isEmpty);
        for (final f in r.files) {
          expect(f.target, t);
          final g = File('${goldens.path}/${t.name}/${f.path.replaceAll('/', '__')}');
          if (update) {
            g.parent.createSync(recursive: true);
            g.writeAsStringSync(f.content);
          }
          expect(g.existsSync(), isTrue, reason: 'ไม่มีไฟล์อ้างอิง ${g.path} — รันด้วย UPDATE_GOLDENS=1');
          expect(f.content.replaceAll('\r\n', '\n'), g.readAsStringSync().replaceAll('\r\n', '\n'), reason: f.path);
        }
      });
    }
  });

  test('ผลคงที่: สร้างสองครั้งได้ไฟล์เดิมทุกตัวอักษร ; path เรียงและไม่ซ้ำ', () {
    final w = shop();
    addTearDown(w.dispose);
    final a = generateFiles(w.workspace, GenTarget.values.toSet());
    final b = generateFiles(w.workspace, GenTarget.values.toSet());
    expect([for (final f in a.files) '${f.path}\n${f.content}'], [for (final f in b.files) '${f.path}\n${f.content}']);
    final paths = a.files.map((f) => f.path).toList();
    expect(paths, [...paths]..sort());
    expect(paths.toSet().length, paths.length);
  });

  test('Laravel migration: ไฟล์ละตาราง + FK แยกไฟล์ท้ายสุด ; ชนิด/ค่าเริ่มต้น/คอมเมนต์ ; action ตามมาตรฐาน', () {
    final w = shop();
    addTearDown(w.dispose);
    final m = laravelMigrations(w.mainEr.project);
    expect(m.map((f) => f.path.split('/').last), [
      '0001_01_01_000001_create_customers_table.php',
      '0001_01_01_000002_create_orders_table.php',
      '0001_01_01_000003_add_foreign_keys.php',
    ]);
    expect(m[0].content, contains(r"$table->id();"));
    expect(m[0].content, contains(r"$table->string('email', 120)->unique();"));
    expect(m[0].content, contains(r"$table->timestamp('created_at')->nullable()->useCurrent();"));
    expect(m[1].content, contains(r"$table->string('status', 20)->default('pending')->comment('สถานะ');"));
    expect(m[1].content, contains(r"$table->index(['status'], 'idx_orders_status');"));
    expect(m[2].content, contains(r"->onDelete('cascade')"));
    final api = w.workspace.documentsOf(DocType.api).single.api!;
    expect(api.endpoints.map(laravelAction).take(5), ['index', 'store', 'show', 'update', 'destroy']);
  });

  test('ER หลายอันแยกโฟลเดอร์ ; เอกสารชื่อไทยได้ชื่อสำรองไม่ซ้ำ ; ข้อมูลตั้งต้นผิด = ข้ามพร้อมคำเตือน', () {
    final w = shop();
    addTearDown(w.dispose);
    final e2 = w.addDocument(DocType.er, name: 'บัญชี')!;
    e2.er!.tables.add(TableModel(id: 'x', name: 'ledger', columns: [ColumnModel(id: 'x1', name: 'id', isPrimaryKey: true)]));
    final r = generateFiles(w.workspace, {GenTarget.sqlDdl, GenTarget.typescript});
    expect(r.files.map((f) => f.path), containsAll(['database/er/schema.sql', 'database/er_2/schema.sql', 'types/models_er.ts', 'types/models_er_2.ts']));
    final t = w.mainEr.project.tableById('o')!;
    t.seedRows.add({'o1': 'ไม่ใช่ตัวเลข'});
    final s = generateFiles(w.workspace, {GenTarget.seedSql});
    expect(s.warnings, hasLength(1));
  });

  test(r"Flutter: ข้อความที่มี $ / ' / \ ถูก escape ให้เป็นสตริง Dart ที่ถูกต้อง", () {
    final d = WireframeDiagram(components: [WfComponent(id: 'a', kind: WfKind.label, text: r"ราคา $5 'ลด' \")]);
    expect(flutterScreen('X', d), contains(r"Text('ราคา \$5 \'ลด\' \\')"));
  });

  test('เป้าหมายเลือกได้เมื่อมีเอกสารต้นทางที่มีเนื้อหา', () {
    final w = WorkspaceController();
    addTearDown(w.dispose);
    expect(GenTarget.values.where((t) => targetAvailable(w.workspace, t)), isEmpty);
    w.mainEr.project.tables.add(TableModel(id: 'a', name: 'a'));
    expect(GenTarget.values.where((t) => targetAvailable(w.workspace, t)).map((t) => t.from).toSet(), {DocType.er});
  });

  group('เขียนลงโฟลเดอร์', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('nsl_gen_'));
    tearDown(() async => dir.delete(recursive: true));

    GenFile file(String path, String content) => GenFile(path, content, target: GenTarget.sqlDdl, origin: 'ER');

    test('ครั้งแรก = สร้าง ; ซ้ำไม่เปลี่ยน = unchanged ; เนื้อหาใหม่ที่เราเคยเขียน = เขียนทับได้', () async {
      var plan = await planWrite(dir, [file('a/x.sql', 'v1'), file('b.txt', 'b')]);
      expect((plan.create.length, plan.edited.length), (2, 0));
      expect(await applyWrite(plan), 2);
      expect(File('${dir.path}/a/x.sql').readAsStringSync(), 'v1');
      expect(File('${dir.path}/$kGenManifest').existsSync(), isTrue);

      plan = await planWrite(dir, [file('a/x.sql', 'v1')]);
      expect(plan.unchanged, hasLength(1));
      plan = await planWrite(dir, [file('a/x.sql', 'v2')]);
      expect(plan.overwrite, hasLength(1));
      await applyWrite(plan);
      expect(File('${dir.path}/a/x.sql').readAsStringSync(), 'v2');
    });

    test('ไฟล์ที่ถูกแก้ด้วยมือ / มีอยู่ก่อนแล้ว: ไม่เขียนทับจนกว่าจะยืนยัน ; CRLF ไม่นับว่าแก้', () async {
      await applyWrite(await planWrite(dir, [file('x.sql', 'line1\nline2\n')]));
      File('${dir.path}/x.sql').writeAsStringSync('line1\r\nline2\r\n'); // Git บน Windows แปลงขึ้นบรรทัด
      expect((await planWrite(dir, [file('x.sql', 'line1\nline2\nline3\n')])).overwrite, hasLength(1));

      File('${dir.path}/x.sql').writeAsStringSync('-- แก้เอง\n');
      File('${dir.path}/mine.txt').writeAsStringSync('ของผู้ใช้');
      final plan = await planWrite(dir, [file('x.sql', 'new'), file('mine.txt', 'gen')]);
      expect(plan.edited.map((f) => f.path).toSet(), {'x.sql', 'mine.txt'});
      expect(await applyWrite(plan), 0);
      expect(File('${dir.path}/x.sql').readAsStringSync(), '-- แก้เอง\n');
      expect(await applyWrite(plan, overwriteEdited: true), 2);
      expect(File('${dir.path}/mine.txt').readAsStringSync(), 'gen');
    });
  });
}
