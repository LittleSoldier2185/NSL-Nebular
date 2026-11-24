import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/export/mock_requests_export.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/mock/mock_engine.dart';
import 'package:nsl_nebular/core/mock/mock_settings.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/mock_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// Phase 34: Mock Server ตอบเป็นลำดับ + ส่งออกชุดคำขอ (Postman v2.1 / curl)
void main() {
  const retry = [MockScenario.normal, MockScenario.serverError, MockScenario.normal];

  group('ค่าตั้งลำดับ', () {
    test('มีลำดับ = ไม่ใช่ค่าเริ่มต้น ; เก็บลง JSON และอ่านกลับ ; เกิน 10 ขั้นถูกตัด', () {
      expect(const MockEndpointSetting().isDefault, isTrue);
      expect(const MockEndpointSetting(sequence: retry).isDefault, isFalse);
      final s = const MockSettings().withEndpoint('e', const MockEndpointSetting(sequence: retry));
      final back = MockSettings.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back.of('e').sequence, retry);
      final long = const MockSettings().withEndpoint('e', MockEndpointSetting(sequence: List.filled(14, MockScenario.conflict)));
      expect(long.of('e').sequence.length, kMockMaxSequence);
    });

    test('JSON ที่มีชื่อสถานการณ์เสียถูกข้ามทีละขั้น ; ไฟล์เก่าไม่มี seq = ว่าง', () {
      final s = MockSettings.fromJson({
        'endpoints': {
          'a': {'seq': ['normal', 'bogus', 'serverError', 7]},
          'b': {'s': 'conflict'},
        }
      });
      expect(s.of('a').sequence, [MockScenario.normal, MockScenario.serverError]);
      expect(s.of('b').sequence, isEmpty);
      expect(s.of('b').scenario, MockScenario.conflict);
    });
  });

  group('เอนจิน', () {
    late WorkspaceController w;
    late ApiDocument api;
    late MockSettings settings;
    late MockEngine engine;

    setUp(() {
      w = WorkspaceController();
      api = w.addDocument(DocType.api, name: 'Shop')!.api!;
      api.endpoints.addAll([
        ApiEndpoint(id: 'ping', path: '/ping', responses: [ApiResponse(status: 200, example: '{"ok":true}'), ApiResponse(status: 500, example: '{"err":1}')]),
        ApiEndpoint(id: 'other', path: '/other', responses: [ApiResponse(status: 200, example: '{}')]),
      ]);
      settings = const MockSettings().withEndpoint('ping', const MockEndpointSetting(sequence: retry));
      engine = MockEngine(api: () => api, workspace: () => w.workspace, settings: () => settings, random: Random(1));
    });

    MockResult hit(String path) => engine.handle(MockRequest(method: 'GET', path: path, query: const {}, body: ''));

    test('200 → 500 → 200 แล้ววนกลับ ; log บอกขั้นที่', () {
      final r = [for (var i = 0; i < 7; i++) hit('/ping')];
      expect([for (final x in r) x.reply.status], [200, 500, 200, 200, 500, 200, 200]);
      expect([for (final x in r) x.entry.seqStep], [1, 2, 3, 1, 2, 3, 1]);
      expect(r.first.entry.seqTotal, 3);
      expect(hit('/other').entry.seqStep, isNull); // endpoint อื่นไม่ใช้ลำดับ
    });

    test('นับแยกต่อ endpoint ; sequenceNextOf บอกขั้นถัดไป ; reset เริ่มขั้นแรกใหม่', () {
      expect(engine.sequenceNextOf('ping'), 1);
      hit('/ping');
      hit('/other');
      expect(engine.sequenceNextOf('ping'), 2);
      expect(engine.sequenceNextOf('other'), isNull);
      hit('/ping');
      hit('/ping');
      expect(engine.sequenceNextOf('ping'), 1); // ครบ 3 วนกลับ
      hit('/ping');
      engine.reset();
      expect(engine.sequenceNextOf('ping'), 1);
      expect(hit('/ping').reply.status, 200);
    });

    test('มีลำดับ = ไม่ใช้ปุ่มกลุ่มเดิม ; ลำดับว่าง = กลับไปใช้ปุ่มกลุ่ม', () {
      settings = const MockSettings().withEndpoint('ping', const MockEndpointSetting(scenario: MockScenario.conflict, sequence: [MockScenario.normal]));
      expect(hit('/ping').reply.status, 200);
      settings = const MockSettings().withEndpoint('ping', const MockEndpointSetting(scenario: MockScenario.conflict));
      expect(hit('/ping').reply.status, 409);
    });

    test('ขั้น "สุ่ม" อยู่ในลำดับได้ ; ผลของลำดับเปลี่ยนทันทีเมื่อแก้ค่าตั้งระหว่างรัน', () {
      settings = const MockSettings().withEndpoint('ping', const MockEndpointSetting(sequence: [MockScenario.random, MockScenario.unauthorized]));
      final first = hit('/ping');
      expect([200, 409, 500], contains(first.reply.status));
      expect(hit('/ping').reply.status, 401);
      settings = const MockSettings().withEndpoint('ping', const MockEndpointSetting(sequence: [MockScenario.serverError]));
      expect(hit('/ping').reply.status, 500); // ตัวนับยังเดินต่อ แต่ความยาวใหม่ = 1
    });
  });

  setUpAll(() => HttpOverrides.global = null); // เทสต์ปิดเครือข่ายจริงโดยปริยาย — ที่นี่ต้องยิงเข้า localhost

  group('HTTP จริง', () {
    late WorkspaceController w;
    late MockController mock;

    setUp(() {
      w = WorkspaceController();
      w.addDocument(DocType.api, name: 'Shop')!.api!.endpoints.add(
        ApiEndpoint(id: 'ping', path: '/ping', responses: [ApiResponse(status: 200, example: '{"ok":true}')]),
      );
      w.setMockSettings(const MockSettings(port: 0).withEndpoint('ping', const MockEndpointSetting(sequence: retry)));
      mock = MockController(w);
    });
    tearDown(() async {
      await mock.stop();
      mock.dispose();
    });

    Future<int> status() async {
      final c = HttpClient();
      try {
        final res = await (await c.getUrl(Uri.parse('${mock.url}/ping'))).close();
        await res.drain<void>();
        return res.statusCode;
      } finally {
        c.close(force: true);
      }
    }

    test('ยิงซ้ำได้ลำดับถูก ; รีเซ็ตเริ่มใหม่ ; หยุดแล้วเริ่มใหม่ก็เริ่มขั้นแรก', () async {
      expect(await mock.start(), isTrue);
      expect([for (var i = 0; i < 4; i++) await status()], [200, 500, 200, 200]);
      expect(mock.sequenceNextOf('ping'), 2);
      mock.resetData();
      expect(await status(), 200);
      expect(await status(), 500);
      await mock.stop();
      expect(mock.sequenceNextOf('ping'), isNull); // ไม่ได้รัน
      expect(await mock.start(), isTrue);
      expect(await status(), 200);
      expect(await status(), 500);
    });
  });

  group('ส่งออกชุดคำขอ', () {
    ApiDocument sample() => ApiDocument(title: 'ร้านค้า', version: '2.0', baseUrl: 'https://shop.example/v1', endpoints: [
          ApiEndpoint(id: 'a', method: ApiMethod.get, path: '/orders', group: 'Orders', summary: 'รายการสั่งซื้อ'),
          ApiEndpoint(id: 'b', method: ApiMethod.get, path: '/orders/{id}', group: 'Orders'),
          ApiEndpoint(id: 'c', method: ApiMethod.post, path: '/orders', group: 'Orders', auth: true, fields: [
            ApiField(id: 'f1', name: 'customer_name', required: true),
            ApiField(id: 'f2', name: 'email'),
            ApiField(id: 'f3', name: 'qty', type: ApiType.integer),
            ApiField(id: 'f4', name: 'paid', type: ApiType.boolean),
            ApiField(id: 'f5', name: '  '),
          ]),
          ApiEndpoint(id: 'd', method: ApiMethod.get, path: '/health'),
        ]);

    test('exampleBodyOf : เฉพาะเมธอดที่มี body และมีฟิลด์ ; ค่าตามชนิด/ชื่อ ; ข้ามชื่อว่าง', () {
      final api = sample();
      expect(exampleBodyOf(api.endpoints[0]), isNull);
      expect(exampleBodyOf(api.endpoints[2]), {'customer_name': 'Example', 'email': 'user@example.com', 'qty': 1, 'paid': true});
      expect(exampleBodyOf(ApiEndpoint(id: 'x', method: ApiMethod.post, path: '/x')), isNull);
    });

    test('Postman v2.1 : schema, ตัวแปร, โฟลเดอร์ตามกลุ่ม, ตัวแปร path, header ล็อกอิน, body JSON', () {
      final j = jsonDecode(exportPostmanCollection(sample(), baseUrl: 'http://127.0.0.1:9000')) as Map<String, dynamic>;
      expect(j['info']['schema'], 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json');
      expect(j['info']['name'], 'ร้านค้า');
      expect({for (final v in j['variable']) v['key']: v['value']}, {'baseUrl': 'http://127.0.0.1:9000', 'token': 'token'});
      final items = j['item'] as List;
      expect(items.length, 2); // โฟลเดอร์ Orders + health (ไม่ระบุกลุ่ม = ใช้ path ส่วนแรก)
      final folder = items.first as Map<String, dynamic>;
      expect(folder['name'], 'Orders');
      final reqs = folder['item'] as List;
      expect(reqs.length, 3);
      expect(reqs[0]['name'], 'GET /orders — รายการสั่งซื้อ');
      final byId = reqs[1]['request']['url'];
      expect(byId['raw'], '{{baseUrl}}/orders/:id');
      expect(byId['path'], ['orders', ':id']);
      expect(byId['variable'], [
        {'key': 'id', 'value': '1'}
      ]);
      final post = reqs[2]['request'] as Map<String, dynamic>;
      expect({for (final h in post['header']) h['key']: h['value']}, {'Content-Type': 'application/json', 'Authorization': 'Bearer {{token}}'});
      expect(jsonDecode(post['body']['raw']), {'customer_name': 'Example', 'email': 'user@example.com', 'qty': 1, 'paid': true});
      expect(post['body']['options']['raw']['language'], 'json');
      final health = ((items.last as Map)['item'] as List).single['request'] as Map;
      expect((items.last as Map)['name'], 'health');
      expect(health['method'], 'GET');
      expect(health['header'], isEmpty);
    });

    test('Postman : API ว่าง ไม่มีชื่อ = ใช้ชื่อ API ; ผลเป็น JSON ถูกต้อง ไทยไม่เพี้ยน', () {
      final text = exportPostmanCollection(ApiDocument());
      expect((jsonDecode(text) as Map)['info']['name'], 'API');
      expect((jsonDecode(text) as Map)['item'], isEmpty);
      expect(exportPostmanCollection(sample()), contains('รายการสั่งซื้อ')); // ไม่ escape เป็น \u
    });

    test('curl : ตัวแปรฐาน, ทุก endpoint, ใส่ค่า 1 ในตัวแปร path, header ล็อกอิน, body เครื่องหมายคำพูดเดี่ยวปลอดภัย', () {
      final api = sample();
      api.endpoints[2].fields.add(ApiField(id: 'f6', name: 'note'));
      final text = exportCurlScript(api);
      expect(text, startsWith('#!/usr/bin/env bash\n'));
      expect(text, contains('BASE_URL="\${BASE_URL:-http://127.0.0.1:8787}"'));
      expect(text, contains('curl -sS -i -X GET "\$BASE_URL/orders/1"'));
      expect(text, contains('curl -sS -i -X GET "\$BASE_URL/health"'));
      final post = text.split('\n').firstWhere((l) => l.startsWith('curl -sS -i -X POST'));
      expect(post, contains("-H 'Content-Type: application/json'"));
      expect(post, contains(r'-H "Authorization: Bearer $TOKEN"'));
      expect(post, contains(r'-d '));
      expect(text.contains('\r'), isFalse); // LF ล้วน (รันบน bash ได้)
      // เครื่องหมายคำพูดเดี่ยวในข้อความ : ไม่ทำให้ quote หลุด
      final tricky = ApiDocument(endpoints: [
        ApiEndpoint(id: 'x', method: ApiMethod.post, path: '/x', fields: [ApiField(id: 'f', name: "it's")]),
      ]);
      expect(exportCurlScript(tricky), contains(r"""-d '{"it'\''s":"string"}'"""));
    });

    test('curl : ข้อความหลายบรรทัดในชื่อ/สรุปไม่หลุดออกจากบรรทัดคอมเมนต์ (กันฉีดคำสั่ง)', () {
      final evil = ApiDocument(title: 'T\nrm -rf /', endpoints: [
        ApiEndpoint(id: 'x', path: '/x', group: 'g\ncurl evil', summary: 'ok\ncurl http://evil.example'),
      ]);
      for (final line in exportCurlScript(evil).split('\n')) {
        expect(line.startsWith('curl ') && !line.startsWith('curl -sS -i -X'), isFalse, reason: line);
        expect(line.startsWith('rm '), isFalse, reason: line);
      }
    });
  });

  group('หน้าจอ', () {
    late WorkspaceController w;
    late MockController m;

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => currentLang = Lang.th);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true)));
      final ctx = tester.element(find.byType(HomePage));
      w = ctx.read<WorkspaceController>();
      m = ctx.read<MockController>();
      w.addDocument(DocType.api, name: 'Shop')!.api!.endpoints.addAll([
        ApiEndpoint(id: 'list', path: '/items', responses: [ApiResponse(status: 200, example: '[1]')]),
      ]);
      w.setMockSettings(const MockSettings(port: 0));
      w.showMock();
      await tester.pumpAndSettle();
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      final f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets('ตั้งลำดับจากกล่อง (ชุดสำเร็จรูป/เพิ่ม/ลบ) → ป้ายลำดับ ; กดปุ่มกลุ่มเลิกใช้ลำดับ ; ย้อนกลับได้', (tester) async {
      await boot(tester);
      expect(find.byKey(const ValueKey('mock-seq-list')), findsOneWidget);
      await tapKey(tester, 'mock-seq-list');
      await tapKey(tester, 'mock-seq-preset-0');
      expect(find.byKey(const ValueKey('mock-seq-pick-2')), findsOneWidget);
      await tapKey(tester, 'mock-seq-del-2'); // เหลือ 200 → 500
      await tapKey(tester, 'mock-seq-add'); // เพิ่มซ้ำขั้นสุดท้าย = 500
      await tapKey(tester, 'mock-seq-ok');
      expect(w.mockSettings.of('list').sequence, [MockScenario.normal, MockScenario.serverError, MockScenario.serverError]);
      expect(w.dirty, isTrue);
      expect(find.byKey(const ValueKey('mock-seq-label-list')), findsOneWidget);
      expect(find.text('ลำดับ 3 ขั้น'), findsOneWidget); // ยังไม่รัน = ไม่มีขั้นถัดไป

      // เปิดกล่องใหม่ : ปุ่มเลิกใช้ลำดับ
      await tapKey(tester, 'mock-seq-list');
      await tapKey(tester, 'mock-seq-clear');
      expect(w.mockSettings.of('list').sequence, isEmpty);
      expect(find.byKey(const ValueKey('mock-seq-label-list')), findsNothing);

      // ตั้งใหม่แล้วกดปุ่มกลุ่ม = เลิกใช้ลำดับ
      await tapKey(tester, 'mock-seq-list');
      await tapKey(tester, 'mock-seq-preset-1');
      await tapKey(tester, 'mock-seq-ok');
      expect(w.mockSettings.of('list').sequence.length, 3);
      await tapKey(tester, 'mock-scenario-list-conflict');
      expect(w.mockSettings.of('list').sequence, isEmpty);
      expect(w.mockSettings.of('list').scenario, MockScenario.conflict);
    });

    testWidgets('เพิ่มขั้นได้ไม่เกิน 10 ; ยกเลิก = ไม่เปลี่ยน', (tester) async {
      await boot(tester);
      await tapKey(tester, 'mock-seq-list');
      for (var i = 0; i < 12; i++) {
        final add = tester.widget<TextButton>(find.byKey(const ValueKey('mock-seq-add')));
        if (add.onPressed == null) break;
        await tapKey(tester, 'mock-seq-add');
      }
      expect(find.byKey(const ValueKey('mock-seq-pick-9')), findsOneWidget);
      expect(find.byKey(const ValueKey('mock-seq-pick-10')), findsNothing);
      expect(tester.widget<TextButton>(find.byKey(const ValueKey('mock-seq-add'))).onPressed, isNull);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(w.mockSettings.of('list').sequence, isEmpty);
    });

    testWidgets('รันอยู่ : ป้ายแสดง "ลำดับ k/N" ตามขั้นถัดไป ; รายละเอียดคำขอบอกลำดับที่', (tester) async {
      await boot(tester);
      w.setMockSettings(w.mockSettings.withEndpoint('list', const MockEndpointSetting(sequence: retry)));
      await tester.pumpAndSettle();
      await tester.runAsync(() => m.start());
      await tester.pumpAndSettle();
      expect(find.text('ลำดับ 1/3'), findsOneWidget);
      await tester.runAsync(() async {
        final c = HttpClient();
        final res = await (await c.getUrl(Uri.parse('${m.url}/items'))).close();
        await res.drain<void>();
        c.close(force: true);
      });
      await tester.pumpAndSettle();
      expect(find.text('ลำดับ 2/3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mock-log-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mock-detail-seq')), findsOneWidget);
      expect(find.text('ลำดับที่ 1/3'), findsOneWidget);
      await tester.runAsync(() => m.stop());
    });

    testWidgets('สวิตช์ "สร้างข้อมูลตัวอย่างให้ตารางที่ไม่มี seed" : ค่าเริ่มต้นเปิด ; กดแล้วเก็บในค่าตั้ง (dirty) ; ย้อนกลับได้', (tester) async {
      await boot(tester);
      expect(w.mockSettings.autoSample, isTrue);
      expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);
      await tapKey(tester, 'mock-autosample');
      expect(w.mockSettings.autoSample, isFalse);
      expect(w.dirty, isTrue);
      expect(find.byIcon(Icons.check_box_outline_blank_rounded), findsOneWidget);
      w.undo();
      expect(w.mockSettings.autoSample, isTrue);
    });

    testWidgets('เมนูส่งออกชุดคำขอ มี Postman และ curl', (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('mock-export')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mock-export-postman')), findsOneWidget);
      expect(find.byKey(const ValueKey('mock-export-curl')), findsOneWidget);
    });
  });
}
