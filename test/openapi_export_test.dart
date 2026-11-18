import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/export/html_doc_export.dart';
import 'package:nsl_nebular/core/export/markdown_export.dart';
import 'package:nsl_nebular/core/export/openapi_export.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';

/// Phase 8d: ส่งออก OpenAPI 3.1 และส่วน API ในเอกสาร
void main() {
  late WorkspaceController w;
  late ProjectDocument apiDoc;
  setUp(() {
    w = WorkspaceController();
    w.mainEr.project.tables.add(TableModel(id: 'o', name: 'orders', columns: [
      ColumnModel(id: 'o1', name: 'id', isPrimaryKey: true, autoIncrement: true),
      ColumnModel(id: 'o2', name: 'customer_id', type: DataType.bigint, notNull: true, comment: 'ลูกค้าที่สั่ง'),
    ]));
    apiDoc = w.addDocument(DocType.api, name: 'Store API')!;
    final a = w.apiController(apiDoc.id)!;
    a.generateCrud(w.mainEr.docId, w.mainEr.project.tableById('o')!);
    final post = a.api.endpoints[1];
    a.updateEndpoint(post.id, (e) => e.auth = true);
    a.updateResponse(post.id, 201, (r) => r.example = '{"id": 1042}');
    a.setInfo(title: 'Store', version: '1.2.0', baseUrl: 'https://api.example.com');
  });
  tearDown(() => w.dispose());

  test('โครง OpenAPI 3.1: info / servers / paths / method / operationId ไม่ซ้ำ', () {
    final o = openApiDocument(apiDoc.api!, w: w.workspace);
    expect(o['openapi'], '3.1.0');
    expect(o['info'], {'title': 'Store', 'version': '1.2.0'});
    expect(o['servers'], [
      {'url': 'https://api.example.com'},
    ]);
    final paths = o['paths'] as Map;
    expect(paths.keys, ['/orders', '/orders/{id}']);
    expect((paths['/orders'] as Map).keys, ['get', 'post']);
    expect((paths['/orders/{id}'] as Map).keys, ['get', 'patch', 'delete']);
    final ids = [for (final p in paths.values) for (final op in (p as Map).values) (op as Map)['operationId']];
    expect(ids.toSet().length, ids.length);
    expect(ids, contains('getOrdersById'));
  });

  test('requestBody: properties ชนิดตามคอลัมน์ required ตามฟิลด์บังคับ คำอธิบายจากคอมเมนต์คอลัมน์ ; path parameter ; security', () {
    final o = openApiDocument(apiDoc.api!, w: w.workspace);
    final post = ((o['paths'] as Map)['/orders'] as Map)['post'] as Map;
    final schema = (((post['requestBody'] as Map)['content'] as Map)['application/json'] as Map)['schema'] as Map;
    expect(schema['properties'], {
      'customer_id': {'type': 'integer', 'description': 'ลูกค้าที่สั่ง'},
    });
    expect(schema['required'], ['customer_id']);
    expect(post['security'], [
      {'bearerAuth': <String>[]},
    ]);
    expect(((o['components'] as Map)['securitySchemes'] as Map).keys, ['bearerAuth']);
    final created = (post['responses'] as Map)['201'] as Map;
    expect(created['description'], 'Created');
    expect(((created['content'] as Map)['application/json'] as Map)['example'], {'id': 1042});
    final get = ((o['paths'] as Map)['/orders/{id}'] as Map)['get'] as Map;
    expect((get['parameters'] as List).single, {
      'name': 'id',
      'in': 'path',
      'required': true,
      'schema': {'type': 'string'},
    });
    expect(get.containsKey('requestBody'), isFalse);
  });

  test('ตัวอย่างที่ไม่ใช่ JSON ส่งเป็นข้อความ ; ไม่มี response = default ; ไม่มีชื่อ API ใช้ชื่อเอกสาร ; ผลเป็น JSON ที่อ่านกลับได้', () {
    final api = ApiDocument(endpoints: [
      ApiEndpoint(id: 'x', path: '/ping', responses: [ApiResponse(status: 200, example: 'pong')]),
      ApiEndpoint(id: 'y', path: '/none'),
    ]);
    final o = jsonDecode(exportOpenApiJson(api, fallbackTitle: 'Doc')) as Map;
    expect((o['info'] as Map)['title'], 'Doc');
    expect(((((o['paths'] as Map)['/ping'] as Map)['get'] as Map)['responses'] as Map)['200'], {
      'description': 'OK',
      'content': {
        'application/json': {'example': 'pong'},
      },
    });
    expect(((((o['paths'] as Map)['/none'] as Map)['get'] as Map)['responses'] as Map).keys, ['default']);
    expect(o.containsKey('servers'), isFalse);
    expect(o.containsKey('components'), isFalse);
  });

  test('เอกสาร Markdown/HTML มีส่วน API (ตาราง endpoint)', () {
    final md = exportWorkspaceDictionary(w.workspace);
    expect(md, contains('## API: Store API'));
    expect(md, contains('| POST | `/orders` |'));
    expect(md, contains('- API: Store API — 5 endpoint'));
    final html = exportHtmlDocument(w.workspace, includeDiagrams: false);
    expect(html, contains('id="api-'));
    expect(html, contains('<code>/orders/{id}</code>'));
  });
}
