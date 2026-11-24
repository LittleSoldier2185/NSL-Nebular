import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/mock/mock_engine.dart';
import 'package:nsl_nebular/core/mock/mock_settings.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';

/// Phase 11: ตัวตอบของ Mock Server (ไม่เปิดพอร์ต)
void main() {
  late WorkspaceController w;
  late ApiDocument api;
  late MockSettings settings;
  late MockEngine engine;

  /// ER: orders(id PK auto, name varchar NOT NULL, code varchar UNIQUE, qty int, paid bool) + seed 2 แถว (id แถวแรกใส่ 1, แถวสองไม่ใส่)
  ApiTableRef ref() => ApiTableRef(docId: w.mainEr.docId, tableId: 'o');

  setUp(() {
    w = WorkspaceController();
    w.mainEr.project.tables.add(TableModel(id: 'o', name: 'orders', columns: [
      ColumnModel(id: 'c1', name: 'id', isPrimaryKey: true, autoIncrement: true),
      ColumnModel(id: 'c2', name: 'name', type: DataType.varchar, length: 50, notNull: true),
      ColumnModel(id: 'c3', name: 'code', type: DataType.varchar, length: 20, unique: true),
      ColumnModel(id: 'c4', name: 'qty', type: DataType.integer),
      ColumnModel(id: 'c5', name: 'paid', type: DataType.boolean),
    ], seedRows: [
      {'c1': '1', 'c2': 'first', 'c3': 'A', 'c4': '3', 'c5': 'true'},
      {'c2': 'second', 'c3': 'B', 'c4': '5', 'c5': '0'},
    ]));
    final doc = w.addDocument(DocType.api, name: 'Shop')!;
    api = doc.api!;
    api.baseUrl = 'https://shop.example/v1';
    api.endpoints.addAll([
      ApiEndpoint(id: 'list', method: ApiMethod.get, path: '/orders', table: ref(), responses: [ApiResponse(status: 200)]),
      ApiEndpoint(id: 'get', method: ApiMethod.get, path: '/orders/{id}', table: ref()),
      ApiEndpoint(id: 'new', method: ApiMethod.get, path: '/orders/new', responses: [ApiResponse(status: 200, example: '{"form":true}')]),
      ApiEndpoint(
        id: 'create',
        method: ApiMethod.post,
        path: '/orders',
        table: ref(),
        auth: true,
        fields: [
          ApiField(id: 'f1', name: 'name', required: true),
          ApiField(id: 'f2', name: 'code'),
          ApiField(id: 'f3', name: 'qty', type: ApiType.integer),
        ],
        responses: [ApiResponse(status: 201), ApiResponse(status: 422, example: '{"custom":"bad"}')],
      ),
      ApiEndpoint(id: 'put', method: ApiMethod.put, path: '/orders/{id}', table: ref(), fields: [ApiField(id: 'g1', name: 'name', required: true)]),
      ApiEndpoint(id: 'patch', method: ApiMethod.patch, path: '/orders/{id}', table: ref(), fields: [ApiField(id: 'h1', name: 'name', required: true)]),
      ApiEndpoint(id: 'del', method: ApiMethod.delete, path: '/orders/{id}', table: ref()),
      ApiEndpoint(id: 'login', method: ApiMethod.post, path: '/login', responses: [ApiResponse(status: 200, example: '{"token":"t"}'), ApiResponse(status: 401, example: '{"error":"nope"}')]),
    ]);
    settings = const MockSettings();
    engine = MockEngine(api: () => api, workspace: () => w.workspace, settings: () => settings, random: Random(1));
  });

  MockResult call(String method, String path, {Object? body, Map<String, String>? query, Map<String, String>? headers}) =>
      engine.handle(MockRequest(method: method, path: path, query: query ?? const {}, headers: headers, body: body == null ? '' : (body is String ? body : jsonEncode(body))));

  Object? json(MockResult r) => jsonDecode(r.reply.body);
  const auth = {'Authorization': 'Bearer abc'};

  group('ข้อมูลจาก ER', () {
    test('GET รายการ: เริ่มจาก seed ตามชนิดคอลัมน์ ; AUTO INCREMENT ที่ seed ไม่ใส่ต่อจากเลขสูงสุด', () {
      final r = call('GET', '/orders');
      expect(r.reply.status, 200);
      expect(json(r), [
        {'id': 1, 'name': 'first', 'code': 'A', 'qty': 3, 'paid': true},
        {'id': 2, 'name': 'second', 'code': 'B', 'qty': 5, 'paid': false},
      ]);
      expect(r.entry.endpointId, 'list');
      expect(r.entry.unknown, isFalse);
    });

    test('GET รายการกรองตามคอลัมน์ด้วย query ; GET ตัวเดียวตามคีย์หลัก ; ไม่เจอ = 404', () {
      expect((json(call('GET', '/orders', query: {'code': 'B'})) as List).single['name'], 'second');
      expect((json(call('GET', '/orders/2')) as Map)['name'], 'second');
      final nf = call('GET', '/orders/99');
      expect(nf.reply.status, 404);
      expect(nf.entry.unknown, isFalse);
    });

    test('POST จำข้อมูล: ได้ id ถัดไป, เรียกรายการเห็นแถวใหม่ ; รหัสสำเร็จตามที่ประกาศ (201)', () {
      final r = call('POST', '/orders', body: {'name': 'third', 'code': 'C', 'qty': 7}, headers: auth);
      expect(r.reply.status, 201);
      expect(json(r), {'id': 3, 'name': 'third', 'code': 'C', 'qty': 7, 'paid': null});
      expect((json(call('GET', '/orders')) as List).length, 3);
      expect((json(call('GET', '/orders/3')) as Map)['code'], 'C');
    });

    test('POST ที่ UNIQUE ซ้ำ = 409 และไม่เพิ่มแถว', () {
      final r = call('POST', '/orders', body: {'name': 'x', 'code': 'A'}, headers: auth);
      expect(r.reply.status, 409);
      expect((json(call('GET', '/orders')) as List).length, 2);
    });

    test('PUT/PATCH แก้เฉพาะที่ส่งมา (ไม่แก้คีย์หลัก) ; DELETE ลบแล้ว GET = 404 ; ลบ/แก้ที่ไม่มี = 404', () {
      expect(json(call('PATCH', '/orders/1', body: {'name': 'renamed', 'id': 50})), containsPair('name', 'renamed'));
      expect((json(call('GET', '/orders/1')) as Map)['id'], 1);
      expect(call('PUT', '/orders/2', body: {'name': 'n2', 'qty': 9}).reply.status, 200); // qty ไม่อยู่ในสัญญาของ PUT = แค่คำเตือน
      expect((json(call('GET', '/orders/2')) as Map)['name'], 'n2');
      expect((json(call('GET', '/orders/2')) as Map)['qty'], 5, reason: 'ฟิลด์นอกสัญญาไม่ถูกนำไปใช้');
      final del = call('DELETE', '/orders/1');
      expect(del.reply.status, 204);
      expect(del.reply.body, isEmpty);
      expect(call('GET', '/orders/1').reply.status, 404);
      expect(call('DELETE', '/orders/1').reply.status, 404);
      expect(call('PUT', '/orders/77', body: {'name': 'x'}).reply.status, 404);
    });

    test('reset กลับไปเริ่มจาก seed', () {
      call('DELETE', '/orders/1');
      call('POST', '/orders', body: {'name': 'z', 'code': 'Z'}, headers: auth);
      engine.reset();
      expect((json(call('GET', '/orders')) as List).length, 2);
      expect(json(call('POST', '/orders', body: {'name': 'z', 'code': 'Z'}, headers: auth)), containsPair('id', 3));
    });
  });

  group('ค่าเริ่มต้นของคอลัมน์ (DEFAULT ใน ER)', () {
    // พบจากการทดสอบโปรเจกต์ตัวอย่างจองห้องพัก: ค่า 'guest' ถูกส่งกลับพร้อมเครื่องหมายคำพูดของ SQL และ CURRENT_TIMESTAMP ได้ null
    late MockEngine eng;
    setUp(() {
      w.mainEr.project.tables.add(TableModel(id: 'u', name: 'users', columns: [
        ColumnModel(id: 'u1', name: 'id', isPrimaryKey: true, autoIncrement: true),
        ColumnModel(id: 'u2', name: 'name', type: DataType.varchar, length: 40, notNull: true),
        ColumnModel(id: 'u3', name: 'role', type: DataType.varchar, length: 20, defaultValue: "'guest'"),
        ColumnModel(id: 'u4', name: 'motto', type: DataType.varchar, length: 40, defaultValue: "'it''s ok'"),
        ColumnModel(id: 'u5', name: 'created_at', type: DataType.timestamp, defaultValue: 'CURRENT_TIMESTAMP'),
        ColumnModel(id: 'u6', name: 'joined', type: DataType.date, defaultValue: 'CURRENT_DATE'),
        ColumnModel(id: 'u7', name: 'level', type: DataType.integer, defaultValue: '3'),
        ColumnModel(id: 'u8', name: 'vip', type: DataType.boolean, defaultValue: 'false'),
        ColumnModel(id: 'u9', name: 'nick', type: DataType.varchar, length: 20, defaultValue: 'NULL'),
      ], seedRows: [
        {'u2': 'seeded'}, // ไม่ใส่คอลัมน์ที่มี DEFAULT = ใช้ค่าเริ่มต้นเหมือนฐานข้อมูลจริง
      ]));
      final uref = ApiTableRef(docId: w.mainEr.docId, tableId: 'u');
      api.endpoints.addAll([
        ApiEndpoint(id: 'ul', method: ApiMethod.get, path: '/users', table: uref),
        ApiEndpoint(id: 'uc', method: ApiMethod.post, path: '/users', table: uref, fields: [ApiField(id: 'n', name: 'name', required: true)]),
      ]);
      eng = MockEngine(api: () => api, workspace: () => w.workspace, settings: () => settings, random: Random(1), clock: () => DateTime(2026, 11, 19, 8, 5, 9));
    });

    test('POST: ค่าเริ่มต้นแบบข้อความถอดเครื่องหมายคำพูด (รวม \'\' = \') ; ตัวเลข/บูลีนตามชนิด ; NULL = null ; เวลาปัจจุบันจากนาฬิกาที่ส่งให้', () {
      final r = eng.handle(MockRequest(method: 'POST', path: '/users', body: '{"name":"ann"}'));
      expect(r.reply.status, 201);
      expect(jsonDecode(r.reply.body), {
        'id': 2,
        'name': 'ann',
        'role': 'guest',
        'motto': "it's ok",
        'created_at': '2026-11-19 08:05:09',
        'joined': '2026-11-19',
        'level': 3,
        'vip': false,
        'nick': null,
      });
    });

    test('seed ที่ไม่ได้ใส่คอลัมน์ = ใช้ค่าเริ่มต้น (ไม่ใช่ null) ; ที่ใส่ไว้ = ค่าที่ใส่', () {
      final rows = jsonDecode(eng.handle(MockRequest(method: 'GET', path: '/users')).reply.body) as List;
      expect(rows.single['role'], 'guest');
      expect(rows.single['level'], 3);
      expect(rows.single['name'], 'seeded');
    });
  });

  group('เส้นทาง', () {
    test('path ที่ไม่มีใน API = 404 + unknown ; method ที่ไม่มี = 405 พร้อมรายการที่อนุญาต', () {
      final a = call('GET', '/nope');
      expect(a.reply.status, 404);
      expect(a.entry.unknown, isTrue);
      final b = call('PUT', '/orders');
      expect(b.reply.status, 405);
      expect(b.entry.unknown, isTrue);
      expect(b.reply.headers['allow'], 'GET, POST');
    });

    test('literal ชนะพารามิเตอร์ (/orders/new ไม่ถูกจับเป็น {id}) ; มี/ไม่มี prefix จาก baseUrl ก็ได้ ; ท้ายด้วย / ก็ได้', () {
      expect(json(call('GET', '/orders/new')), {'form': true});
      expect((json(call('GET', '/v1/orders/1')) as Map)['id'], 1);
      expect((json(call('GET', '/orders/1/')) as Map)['id'], 1);
    });

    test('API หายไป = 503', () {
      final e = MockEngine(api: () => null, workspace: () => w.workspace, settings: () => settings);
      expect(e.handle(MockRequest(method: 'GET', path: '/orders')).reply.status, 503);
    });
  });

  group('สัญญา API', () {
    test('endpoint ต้องล็อกอิน: ไม่มี Bearer = 401 (ใช้ตัวอย่างที่ประกาศถ้ามี)', () {
      expect(call('POST', '/orders', body: {'name': 'x'}).reply.status, 401);
      expect(call('POST', '/orders', body: {'name': 'x', 'code': 'Q'}, headers: {'authorization': 'bearer tok'}).reply.status, 201);
      expect(call('POST', '/orders', body: {'name': 'x'}, headers: {'Authorization': 'Basic abc'}).reply.status, 401);
    });

    test('ตรวจ body: ขาดฟิลด์บังคับ/ผิดชนิด/ไม่ใช่ JSON/ไม่ใช่ object → ปฏิเสธ (ใช้ 422 ที่ประกาศไว้ ไม่งั้น 400) ; บันทึกปัญหาใน log', () {
      final miss = call('POST', '/orders', body: <String, Object?>{}, headers: auth);
      expect(miss.reply.status, 422);
      expect(miss.entry.issues.single.code, 'required');
      expect(miss.entry.issues.single.field, 'name');
      expect(miss.entry.hasIssue, isTrue);

      final type = call('POST', '/orders', body: {'name': 'x', 'qty': 'many'}, headers: auth);
      expect(type.reply.status, 422);
      expect(type.entry.issues.single.code, 'type');
      expect((json(type) as Map)['problems'].single, containsPair('expected', 'integer'));

      expect(call('POST', '/orders', body: '{oops', headers: auth).entry.issues.single.code, 'invalid_json');
      expect(call('POST', '/orders', body: '[1]', headers: auth).entry.issues.single.code, 'not_object');
      // เมื่อไม่ประกาศ 422 จะได้ 400
      expect(call('PUT', '/orders/1', body: <String, Object?>{}).reply.status, 400);
    });

    test('ฟิลด์ที่ไม่มีในสัญญาเป็นแค่คำเตือน (ยังตอบสำเร็จ) ; PATCH ไม่บังคับฟิลด์ ; integer รับ 5.0', () {
      final r = call('POST', '/orders', body: {'name': 'x', 'extra': 1, 'qty': 5.0}, headers: auth);
      expect(r.reply.status, 201);
      expect(r.entry.issues.single.code, 'unknown_field');
      expect(r.entry.hasIssue, isFalse);
      expect(call('PATCH', '/orders/1', body: <String, Object?>{}).reply.status, 200);
    });

    test('endpoint ที่ไม่ผูกตาราง ตอบตามตัวอย่างที่ประกาศ', () {
      expect(json(call('POST', '/login', body: '')), {'token': 't'});
    });
  });

  group('สถานการณ์', () {
    test('บังคับ 409/401/500 (ใช้ตัวอย่างที่ประกาศถ้ามี) ข้ามการตรวจอื่น ๆ', () {
      settings = settings.withEndpoint('login', const MockEndpointSetting(scenario: MockScenario.unauthorized));
      final u = call('POST', '/login');
      expect(u.reply.status, 401);
      expect(json(u), {'error': 'nope'});
      expect(u.entry.scenario, MockScenario.unauthorized);

      settings = settings.withEndpoint('list', const MockEndpointSetting(scenario: MockScenario.serverError));
      expect(call('GET', '/orders').reply.status, 500);
      settings = settings.withEndpoint('list', const MockEndpointSetting(scenario: MockScenario.conflict));
      expect(call('GET', '/orders').reply.status, 409);
      settings = settings.withEndpoint('list', const MockEndpointSetting());
      expect(call('GET', '/orders').reply.status, 200);
    });

    test('หน่วงเวลาติดมากับคำตอบ (จำกัดไม่เกิน 30 วินาที)', () {
      settings = settings.withEndpoint('list', const MockEndpointSetting(delayMs: 250));
      expect(call('GET', '/orders').reply.delay, const Duration(milliseconds: 250));
      settings = settings.withEndpoint('list', const MockEndpointSetting(delayMs: 999999));
      expect(call('GET', '/orders').reply.delay, const Duration(milliseconds: kMockMaxDelayMs));
    });

    test('สุ่ม: ได้ทั้งปกติ/500/409 และ log บอกผลที่สุ่มได้ (ไม่ใช่ "สุ่ม")', () {
      settings = settings.withEndpoint('list', const MockEndpointSetting(scenario: MockScenario.random));
      final seen = <int>{};
      for (var i = 0; i < 200; i++) {
        final r = call('GET', '/orders');
        seen.add(r.reply.status);
        expect(r.entry.scenario, isNot(MockScenario.random));
      }
      expect(seen, {200, 500, 409});
    });

    test('แก้สถานการณ์ระหว่างรันมีผลทันที (engine อ่านค่าสด ๆ)', () {
      expect(call('GET', '/orders').reply.status, 200);
      settings = settings.withEndpoint('list', const MockEndpointSetting(scenario: MockScenario.serverError));
      expect(call('GET', '/orders').reply.status, 500);
    });
  });

  group('ค่าตั้งในไฟล์', () {
    test('ไป-กลับ JSON ; ค่าเริ่มต้นไม่ถูกเก็บ ; ข้อมูลเสียถูกข้าม ; พอร์ตนอกช่วง = ค่าเริ่มต้น', () {
      final s = const MockSettings(apiDocId: 'a1', port: 9000)
          .withEndpoint('e1', const MockEndpointSetting(scenario: MockScenario.conflict, delayMs: 100))
          .withEndpoint('e2', const MockEndpointSetting());
      final back = MockSettings.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(jsonEncode(back.toJson()), jsonEncode(s.toJson()));
      expect(back.endpoints.keys, ['e1']);
      expect(back.of('e1').scenario, MockScenario.conflict);
      expect(back.of('zzz').isDefault, isTrue);

      final bad = MockSettings.fromJson({'port': 99999, 'endpoints': {'a': 'x', 'b': {'s': 'teleport', 'delay': -5}, 'c': {'s': 'random'}}});
      expect(bad.port, kMockDefaultPort);
      expect(bad.endpoints.keys, ['c']);
      expect(MockSettings.fromJson(null).port, kMockDefaultPort);
    });

    test('เก็บใน meta.mock ของโปรเจกต์ ทำให้ dirty ; ค่าเท่าเดิมไม่ทำให้ dirty ; เอกสาร API ที่ใช้ = ตามที่เลือก ไม่ก็ตัวแรก', () {
      expect(w.mockApiDocument!.api, same(api));
      w.setMockSettings(const MockSettings(port: 9100));
      expect(w.dirty, isTrue);
      expect(w.mockSettings.port, 9100);
      final second = w.addDocument(DocType.api, name: 'Other')!;
      w.setMockSettings(w.mockSettings.copyWith(apiDocId: second.id));
      expect(w.mockApiDocument!.id, second.id);
      w.setMockSettings(w.mockSettings.copyWith(apiDocId: 'gone'));
      expect(w.mockApiDocument!.api, same(api), reason: 'เอกสารที่เลือกหายไป ใช้เอกสาร API แรก');
    });
  });
  group('บันทึกคำขอเก็บ body', () {
    test('เก็บ body ของคำขอและคำตอบ (ทั้งสำเร็จ/ไม่พบ endpoint)', () {
      final ok = call('POST', '/login', body: {'user': 'a'});
      expect(ok.entry.requestBody, '{"user":"a"}');
      expect(jsonDecode(ok.entry.responseBody), {'token': 't'});
      final nf = call('GET', '/nope');
      expect(nf.entry.unknown, isTrue);
      expect(nf.entry.requestBody, isEmpty);
      expect(nf.entry.responseBody, isNotEmpty, reason: 'คำตอบ 404 มี body');
    });

    test('body ยาวเกิน kMockBodyClip ถูกตัดและต่อท้าย …', () {
      final big = 'x' * (kMockBodyClip + 500);
      final r = call('POST', '/login', body: big);
      expect(r.entry.requestBody.length, kMockBodyClip + 1);
      expect(r.entry.requestBody.endsWith('…'), isTrue);
      expect(call('POST', '/login', body: 'x' * 10).entry.requestBody, 'x' * 10);
    });
  });

  group('ตัวนับการเปลี่ยนข้อมูล (changes) + reset', () {
    test('POST/PUT/DELETE ที่สำเร็จนับ ; GET และคำขอที่ล้มเหลวไม่นับ ; reset = 0 และข้อมูลกลับไปเริ่มจาก seed', () {
      expect(engine.changes, 0);
      call('GET', '/orders');
      call('GET', '/orders/1');
      expect(engine.changes, 0, reason: 'GET ไม่เปลี่ยนข้อมูล');
      expect(call('POST', '/orders', body: {'name': 'n1', 'code': 'K1'}, headers: auth).reply.status, 201);
      expect(engine.changes, 1);
      call('POST', '/orders', body: {'code': 'no-name'}, headers: auth);
      expect(engine.changes, 1, reason: 'ขาด name = 422 ไม่นับ');
      expect(call('PUT', '/orders/1', body: {'name': 'edited'}).reply.status, 200);
      expect(engine.changes, 2);
      expect(call('PUT', '/orders/999', body: {'name': 'x'}).reply.status, 404);
      expect(engine.changes, 2, reason: 'ไม่พบแถว = ไม่นับ');
      expect(call('DELETE', '/orders/1').reply.status, anyOf(200, 204));
      expect(engine.changes, 3);
      expect(call('DELETE', '/orders/1').reply.status, 404);
      expect(engine.changes, 3);

      engine.reset();
      expect(engine.changes, 0);
      final rows = json(call('GET', '/orders')) as List;
      expect(rows.length, 2, reason: 'กลับไปเริ่มจาก seed (2 แถว)');
      expect((rows.first as Map)['name'], isNot('edited'));
    });
  });

}
