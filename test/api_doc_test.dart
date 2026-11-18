import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/storage/project_codec.dart';
import 'package:nsl_nebular/core/validate/api_validator.dart';
import 'package:nsl_nebular/core/validate/workspace_validator.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/api_controller.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// Phase 8: เอกสาร API
void main() {
  /// ER: orders(id PK auto, customer_id bigint NOT NULL, note text NULL, total decimal NOT NULL default 0)
  void seedEr(WorkspaceController w) {
    w.mainEr.project.tables.add(TableModel(id: 'o', name: 'orders', columns: [
      ColumnModel(id: 'o1', name: 'id', isPrimaryKey: true, autoIncrement: true),
      ColumnModel(id: 'o2', name: 'customer_id', type: DataType.bigint, notNull: true),
      ColumnModel(id: 'o3', name: 'note', type: DataType.text, comment: 'หมายเหตุ'),
      ColumnModel(id: 'o4', name: 'total', type: DataType.decimal, notNull: true, defaultValue: '0'),
    ]));
  }

  group('โมเดลและไฟล์', () {
    test('ApiDocument ไป-กลับ JSON ครบ ; ข้อมูลเสียถูกข้ามทีละรายการ', () {
      final doc = ApiDocument(title: 'Store', version: '2', baseUrl: 'https://x', endpoints: [
        ApiEndpoint(
          id: 'e1',
          method: ApiMethod.post,
          path: '/orders',
          summary: 's',
          group: 'g',
          auth: true,
          table: const ApiTableRef(docId: 'er', tableId: 'o'),
          fields: [ApiField(id: 'f', name: 'qty', type: ApiType.integer, required: true, column: const ApiTableRef(docId: 'er', tableId: 'o', columnId: 'c'))],
          responses: [ApiResponse(status: 201, description: 'ok', example: '{"id":1}')],
        ),
      ]);
      final back = ApiDocument.fromJson(jsonDecode(jsonEncode(doc.toJson())));
      expect(jsonEncode(back.toJson()), jsonEncode(doc.toJson()));
      final bad = ApiDocument.fromJson({
        'endpoints': [
          {'id': 'a', 'method': 'teleport', 'responses': [{'status': 999}, {'status': 200}]},
          {'id': 'a'},
          'x',
        ],
      });
      expect(bad.endpoints.single.method, ApiMethod.get);
      expect(bad.endpoints.single.responses.map((r) => r.status), [200]);
    });

    test('กลุ่มจาก path และพารามิเตอร์ใน path', () {
      final e = ApiEndpoint(id: 'x', path: '/orders/{id}/items/{itemId}');
      expect(e.effectiveGroup, 'orders');
      expect(e.pathParams, ['id', 'itemId']);
      expect((e..group = 'Billing').effectiveGroup, 'Billing');
    });

    test('ชนิดในไฟล์ "api" บันทึก/เปิดซ้ำได้ ; รุ่นก่อน Phase 8 (ชนิดไม่รู้จัก) เขียนกลับครบ', () {
      final w = WorkspaceController();
      addTearDown(w.dispose);
      final d = w.addDocument(DocType.api, name: 'Store API')!;
      w.apiController(d.id)!.addEndpoint(method: ApiMethod.post, path: 'orders');
      final j = jsonDecode(jsonEncode(encodeProjectMap(w.workspace))) as Map<String, dynamic>;
      final back = decodeProjectMap(j).documentById(d.id)!;
      expect(back.type, DocType.api);
      expect(back.api!.endpoints.single.title, 'POST /orders');
      // จำลองรุ่นเก่า: เนื้อหาเป็น RawDocContent แล้วเขียนกลับ
      final raw = ProjectDocument(id: d.id, typeName: 'api', name: 'Store API', content: RawDocContent((j['documents'] as List).last['content']));
      final again = decodeProjectMap(jsonDecode(jsonEncode(encodeProjectMap(Workspace(documents: [raw])))) as Map<String, dynamic>);
      expect(again.documents.single.api!.endpoints.single.path, '/orders');
    });
  });

  group('controller', () {
    late WorkspaceController w;
    late ApiController a;
    setUp(() {
      w = WorkspaceController();
      seedEr(w);
      a = w.apiController(w.addDocument(DocType.api)!.id)!;
    });
    tearDown(() => w.dispose());

    test('path ถูกจัดรูปแบบ ; แก้ที่ไม่เปลี่ยนอะไร = ไม่เข้าประวัติ ; undo/redo', () {
      final e = a.addEndpoint(path: ' orders//list/ ')!;
      expect(e.path, '/orders/list');
      expect(a.updateEndpoint(e.id, (x) => x.path = '/orders/list'), isFalse);
      expect(a.updateEndpoint(e.id, (x) => x.method = ApiMethod.delete), isTrue);
      a.undo();
      expect(a.api.endpointById(e.id)!.method, ApiMethod.get);
      a.undo();
      expect(a.api.endpoints, isEmpty);
      a.redo();
      expect(a.api.endpoints, hasLength(1));
    });

    test('สร้าง CRUD: 5 endpoint ผูกตาราง ; POST มีฟิลด์จากคอลัมน์ (ข้าม PK auto, บังคับตาม NOT NULL ไม่มีค่าเริ่มต้น) ; undo ขั้นเดียว ; ซ้ำไม่สร้างใหม่', () {
      final t = w.mainEr.project.tableById('o')!;
      expect(a.generateCrud(w.mainEr.docId, t), 5);
      expect(a.api.endpoints.map((e) => e.title),
          ['GET /orders', 'POST /orders', 'GET /orders/{id}', 'PATCH /orders/{id}', 'DELETE /orders/{id}']);
      final post = a.api.endpoints[1];
      expect(post.fields.map((f) => (f.name, f.type, f.required)), [
        ('customer_id', ApiType.integer, true),
        ('note', ApiType.string, false),
        ('total', ApiType.number, false),
      ]);
      expect(post.fields.first.column, ApiTableRef(docId: w.mainEr.docId, tableId: 'o', columnId: 'o2'));
      expect(a.api.endpoints[3].fields.every((f) => !f.required), isTrue); // PATCH ไม่บังคับ
      expect(a.generateCrud(w.mainEr.docId, t), 0);
      a.undo();
      expect(a.api.endpoints, isEmpty);
    });

    test('ดึงฟิลด์จากตาราง: เพิ่มเฉพาะที่ยังไม่มีชื่อซ้ำ', () {
      final e = a.addEndpoint(method: ApiMethod.post, path: '/orders', table: ApiTableRef(docId: w.mainEr.docId, tableId: 'o'))!;
      a.addField(e.id, name: 'note');
      expect(a.pullFieldsFromTable(e.id), 2);
      expect(a.pullFieldsFromTable(e.id), 0);
    });

    test('ทำสำเนา / ลบ endpoint ; response เพิ่มเรียงตามรหัส ไม่ซ้ำ', () {
      final e = a.addEndpoint(method: ApiMethod.post, path: '/x')!;
      final c = a.duplicateEndpoint(e.id)!;
      expect(c.id, isNot(e.id));
      expect(a.api.endpoints, hasLength(2));
      expect(a.addResponse(e.id, 400), isTrue);
      expect(a.addResponse(e.id, 400), isFalse);
      expect(a.api.endpointById(e.id)!.responses.map((r) => r.status), [201, 400]);
      expect(a.deleteEndpoint(c.id), isTrue);
      expect(a.selectedId, isNull);
    });

    test('เอกสารตัวแทน (detached) แก้ไม่ได้', () {
      final d = ApiController.detached(w);
      addTearDown(d.dispose);
      expect(d.addEndpoint(), isNull);
    });
  });

  group('ตัวตรวจ', () {
    late WorkspaceController w;
    late ApiController a;
    setUp(() {
      w = WorkspaceController();
      seedEr(w);
      a = w.apiController(w.addDocument(DocType.api)!.id)!;
    });
    tearDown(() => w.dispose());

    List<String> codes() => [for (final i in validateApi(a.api, workspace: w.workspace, docId: a.docId)) i.code];

    test('ไม่มี endpoint = info ; ตารางที่ยังไม่มี endpoint = info', () {
      expect(codes(), containsAll(['api_empty', 'api_table_uncovered']));
      a.generateCrud(w.mainEr.docId, w.mainEr.project.tableById('o')!);
      expect(codes(), isNot(contains('api_table_uncovered')));
      expect(codes(), isNot(contains('api_empty')));
    });

    test('ชนิดไม่ตรง / บังคับแต่คอลัมน์รับ NULL / ซ้ำ / GET มี body / ไม่มี response', () {
      final ref = ApiTableRef(docId: w.mainEr.docId, tableId: 'o');
      final e = a.addEndpoint(method: ApiMethod.post, path: '/o', table: ref)!;
      a.addField(e.id, name: 'note', type: ApiType.integer, required: true, column: ApiTableRef(docId: ref.docId, tableId: 'o', columnId: 'o3'));
      a.addField(e.id, name: 'note');
      a.addEndpoint(method: ApiMethod.post, path: '/o');
      final g = a.addEndpoint(path: '/g')!;
      a.addField(g.id, name: 'x');
      a.removeResponse(g.id, 200);
      expect(codes(), containsAll(['api_type_mismatch', 'api_required_nullable', 'api_field_dup', 'api_dup_endpoint', 'api_body_not_allowed', 'api_no_response']));
    });

    test('ลบตาราง/คอลัมน์ใน ER = ปัญหาข้ามเอกสาร (ขึ้นในหน้า Home)', () {
      a.generateCrud(w.mainEr.docId, w.mainEr.project.tableById('o')!);
      w.mainEr.project.tableById('o')!.columns.removeWhere((c) => c.id == 'o2');
      expect(codes(), contains('api_column_missing'));
      w.mainEr.project.tables.clear();
      expect(codes(), contains('api_table_missing'));
      final cross = crossDocIssues(validateWorkspace(w.workspace)).map((x) => x.issue.code).toSet();
      expect(cross, containsAll(['api_table_missing', 'api_column_missing']));
    });
  });

  group('หน้าจอ', () {
    late WorkspaceController w;

    Future<void> boot(WidgetTester tester, {Lang lang = Lang.th}) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang, showExplorer: true)));
      w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      seedEr(w);
      await tester.pump();
    }

    testWidgets('เพิ่ม API จากเมนูแท็บ → สร้าง CRUD จากแผงซ้าย → เลือก endpoint แก้ path ; Delete ลบ endpoint ไม่แตะ ER', (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('tab-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('API (Endpoint)').last);
      await tester.pumpAndSettle();
      expect(w.activeDocument.type, DocType.api);
      expect(find.byKey(const ValueKey('api-editor-empty')), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('api-crud-${w.mainEr.docId}-o')));
      await tester.pumpAndSettle();
      final a = w.currentApi;
      expect(a.api.endpoints, hasLength(5));
      expect(find.byKey(ValueKey('api-editor-${a.selectedId}')), findsOneWidget);

      final post = a.api.endpoints[1];
      await tester.tap(find.byKey(ValueKey('api-ep-${post.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('api-field-name-${post.fields.first.id}')), findsOneWidget);
      final path = find.descendant(of: find.byKey(ValueKey('api-path-${post.id}')), matching: find.byType(EditableText));
      await tester.enterText(path, '/v1/orders');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(a.api.endpointById(post.id)!.path, '/v1/orders');

      await tester.tap(find.byKey(ValueKey('api-ep-${post.id}'))); // คลิกในแผง = โฟกัสกลับหน้าหลัก
      await tester.pumpAndSettle();
      final tables = w.mainEr.project.tables.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(a.api.endpointById(post.id), isNull);
      expect(w.mainEr.project.tables.length, tables);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Project Home มีการ์ด API ; แถบไอคอนมีปุ่ม API', (tester) async {
      await boot(tester);
      w.showHome();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-type-api')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('home-type-count-api'))).data, '0');
    });

    testWidgets('ภาษาอังกฤษ: หน้า API ไม่มีอักษรไทยหลุด', (tester) async {
      await boot(tester, lang: Lang.en);
      addTearDown(() => currentLang = Lang.th);
      final d = w.addDocument(DocType.api)!;
      w.apiController(d.id)!.generateCrud(w.mainEr.docId, w.mainEr.project.tableById('o')!);
      await tester.pumpAndSettle();
      final thai = RegExp(r'[฀-๿]');
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final s = t.data ?? t.textSpan?.toPlainText() ?? '';
        // ชื่อเอกสาร/คอมเมนต์คอลัมน์เป็นข้อมูลผู้ใช้ — ไม่นับ
        if (s.contains('หมายเหตุ')) continue;
        expect(thai.hasMatch(s), isFalse, reason: s);
      }
    });
  });
}
