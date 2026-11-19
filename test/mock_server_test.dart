import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/mock/mock_settings.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/state/mock_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';

/// Phase 11: ยิง HTTP จริงบน localhost
void main() {
  late WorkspaceController w;
  late MockController mock;

  WorkspaceController build() {
    final w = WorkspaceController();
    w.mainEr.project.tables.add(TableModel(id: 'o', name: 'orders', columns: [
      ColumnModel(id: 'c1', name: 'id', isPrimaryKey: true, autoIncrement: true),
      ColumnModel(id: 'c2', name: 'name', type: DataType.varchar, length: 50, notNull: true),
    ], seedRows: [
      {'c2': 'first'},
    ]));
    final ref = ApiTableRef(docId: w.mainEr.docId, tableId: 'o');
    w.addDocument(DocType.api, name: 'Shop')!.api!.endpoints.addAll([
      ApiEndpoint(id: 'list', path: '/orders', table: ref),
      ApiEndpoint(id: 'create', method: ApiMethod.post, path: '/orders', table: ref, fields: [ApiField(id: 'f', name: 'name', required: true)]),
      ApiEndpoint(id: 'slow', path: '/slow', responses: [ApiResponse(status: 200, example: '{"ok":true}')]),
    ]);
    return w;
  }

  setUp(() {
    w = build();
    w.setMockSettings(const MockSettings(port: 0));
    mock = MockController(w);
  });

  tearDown(() async {
    await mock.stop();
    mock.dispose();
  });

  Future<(int, Object?, HttpHeaders)> send(String method, String path, {Object? body, Map<String, String>? headers}) async {
    final c = HttpClient();
    try {
      final req = await c.openUrl(method, Uri.parse('${mock.url}$path'));
      headers?.forEach(req.headers.set);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(body is String ? body : jsonEncode(body));
      }
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      return (res.statusCode, text.isEmpty ? null : jsonDecode(text), res.headers);
    } finally {
      c.close(force: true);
    }
  }

  test('เริ่มแล้วเรียกได้จริง: GET/POST จำข้อมูล, log เก็บทุกคำขอ พร้อมเวลาตอบ', () async {
    expect(await mock.start(), isTrue);
    expect(mock.running, isTrue);
    expect(mock.url, startsWith('http://127.0.0.1:'));

    final (s1, b1, h1) = await send('GET', '/orders');
    expect(s1, 200);
    expect(b1, [
      {'id': 1, 'name': 'first'},
    ]);
    expect(h1.value('access-control-allow-origin'), '*');
    expect(h1.contentType?.mimeType, 'application/json');

    final (s2, b2, _) = await send('POST', '/orders', body: {'name': 'second'});
    expect(s2, 201);
    expect(b2, {'id': 2, 'name': 'second'});
    expect((await send('GET', '/orders')).$2, hasLength(2));

    expect(mock.log.map((e) => '${e.method} ${e.path} ${e.status}'), ['GET /orders 200', 'POST /orders 201', 'GET /orders 200']);
    expect(mock.log.every((e) => e.durationMs >= 0), isTrue);
  });

  test('ตรวจสัญญาบนเครือข่ายจริง: body ผิด = 400 และ log ติดปัญหา ; path ที่ไม่มี = 404 เสนอเพิ่ม endpoint', () async {
    await mock.start();
    final (s, b, _) = await send('POST', '/orders', body: <String, Object?>{});
    expect(s, 400);
    expect((b as Map)['error'], 'validation_failed');
    expect(mock.log.last.issues.single.code, 'required');

    expect((await send('GET', '/customers')).$1, 404);
    final unknown = mock.log.last;
    expect(unknown.unknown, isTrue);
    final api = w.mockApiDocument!.api!;
    expect(api.endpoints.any((e) => e.path == '/customers'), isFalse);
    final made = mock.addEndpointFromLog(unknown);
    expect(made?.title, 'GET /customers');
    expect(api.endpoints.any((e) => e.path == '/customers' && e.method == ApiMethod.get), isTrue);
    expect(mock.addEndpointFromLog(mock.log.first), isNull, reason: 'คำขอที่ endpoint มีอยู่แล้ว ไม่เสนอเพิ่ม');
  });

  test('เปลี่ยนสถานการณ์ขณะรัน (ผ่านค่าตั้งของโปรเจกต์) มีผลกับคำขอถัดไป และหน่วงจริง', () async {
    await mock.start();
    w.setMockSettings(w.mockSettings.withEndpoint('list', const MockEndpointSetting(scenario: MockScenario.serverError)));
    expect((await send('GET', '/orders')).$1, 500);
    w.setMockSettings(w.mockSettings.withEndpoint('slow', const MockEndpointSetting(delayMs: 300)));
    final sw = Stopwatch()..start();
    expect((await send('GET', '/slow')).$2, {'ok': true});
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(280));
    expect(mock.log.last.durationMs, greaterThanOrEqualTo(280));
  });

  test('CORS preflight (OPTIONS) ตอบ 204 ไม่ลง log', () async {
    await mock.start();
    final (s, _, h) = await send('OPTIONS', '/orders');
    expect(s, 204);
    expect(h.value('access-control-allow-methods'), contains('POST'));
    expect(mock.log, isEmpty);
  });

  test('รีเซ็ตข้อมูลกลับไปเริ่มจาก seed', () async {
    await mock.start();
    await send('POST', '/orders', body: {'name': 'x'});
    expect((await send('GET', '/orders')).$2, hasLength(2));
    mock.resetData();
    expect((await send('GET', '/orders')).$2, hasLength(1));
  });

  test('หยุดแล้วปล่อยพอร์ต: เชื่อมต่อไม่ได้อีก และพอร์ตเดิมเปิดซ้ำได้ ; เปิดซ้อน/หยุดซ้ำไม่พัง', () async {
    await mock.start();
    final port = mock.port!;
    expect(await mock.start(), isTrue, reason: 'เริ่มซ้ำ = ยังรันอยู่ ไม่เปิดพอร์ตที่สอง');
    expect(mock.port, port);
    await mock.stop();
    await mock.stop();
    expect(mock.running, isFalse);
    expect(mock.url, isNull);
    await expectLater(Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 1)), throwsA(isA<SocketException>()));

    // พอร์ตนั้นว่างจริง: ตัวอื่นจองได้
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await probe.close();
  });

  test('พอร์ตถูกใช้อยู่ = เริ่มไม่ได้ มีข้อความผิดพลาด ไม่ค้างสถานะ ; หายเมื่อเริ่มสำเร็จ', () async {
    final taken = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(taken.close);
    w.setMockSettings(MockSettings(port: taken.port));
    expect(await mock.start(), isFalse);
    expect(mock.running, isFalse);
    expect(mock.busy, isFalse);
    expect(mock.error, isNotNull);

    w.setMockSettings(const MockSettings(port: 0));
    expect(await mock.start(), isTrue);
    expect(mock.error, isNull);
  });

  test('ฟังเฉพาะ 127.0.0.1: ต่อผ่าน IP อื่นของเครื่องนี้ไม่ได้', () async {
    await mock.start();
    final lan = [
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
        for (final a in i.addresses)
          if (!a.isLoopback) a,
    ];
    if (lan.isEmpty) {
      markTestSkipped('เครื่องนี้ไม่มี IPv4 นอก loopback');
      return;
    }
    await expectLater(Socket.connect(lan.first, mock.port!, timeout: const Duration(seconds: 2)), throwsA(isA<SocketException>()));
    final c = await Socket.connect(InternetAddress.loopbackIPv4, mock.port!);
    await c.close();
  });

  test('เอกสาร API ถูกลบขณะรัน = หยุดเอง ; ไม่มีเอกสาร API = เริ่มไม่ได้', () async {
    await mock.start();
    final id = w.mockApiDocument!.id;
    w.deleteDocument(id);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(mock.running, isFalse);

    expect(await mock.start(), isFalse);
    expect(mock.error, isNotNull);
  });

  test('dispose = ปล่อยพอร์ต (ปิดแอป)', () async {
    await mock.start();
    final port = mock.port!;
    mock.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await probe.close();
    mock = MockController(w); // ให้ tearDown ใช้ได้
  });
}
