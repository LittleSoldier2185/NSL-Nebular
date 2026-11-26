import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/mock/mock_settings.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/mock_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/ui/left_panel.dart';
import 'package:provider/provider.dart';

/// Phase 11: หน้า Mock Server
void main() {
  late WorkspaceController w;
  late MockController m;
  final view = find.byKey(const ValueKey('mock-view'));

  // เทสต์วิดเจ็ตบล็อกเครือข่ายจริงโดยปริยาย (ตอบ 400) — ที่นี่ต้องยิงเข้า localhost จริง
  setUpAll(() => HttpOverrides.global = null);

  Future<void> boot(WidgetTester tester, {bool api = true, Lang lang = Lang.th}) async {
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang, showExplorer: true)));
    final ctx = tester.element(find.byType(HomePage));
    w = ctx.read<WorkspaceController>();
    m = ctx.read<MockController>();
    if (api) {
      w.addDocument(DocType.api, name: 'Shop')!.api!.endpoints.addAll([
        ApiEndpoint(id: 'list', path: '/items', responses: [ApiResponse(status: 200, example: '[1]')]),
        ApiEndpoint(id: 'make', method: ApiMethod.post, path: '/items'),
      ]);
      w.setMockSettings(const MockSettings(port: 0));
    }
    w.showMock();
    await tester.pumpAndSettle();
  }

  Future<String> get(WidgetTester tester, String path) => tester.runAsync(() async {
        final c = HttpClient();
        try {
          final res = await (await c.getUrl(Uri.parse('${m.url}$path'))).close();
          return '${res.statusCode} ${await utf8.decoder.bind(res).join()}';
        } finally {
          c.close(force: true);
        }
      }).then((v) => v!);

  testWidgets('ไม่มีเอกสาร API: บอกว่ายังเริ่มไม่ได้', (tester) async {
    await boot(tester, api: false);
    expect(view, findsOneWidget);
    expect(find.byKey(const ValueKey('mock-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('mock-toggle')), findsNothing);
  });

  testWidgets('แสดง endpoint ทุกตัว ; เปลี่ยนสถานการณ์/หน่วงแล้วเก็บในค่าตั้งของโปรเจกต์ (dirty)', (tester) async {
    await boot(tester);
    expect(find.text('Endpoint · 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('mock-ep-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('mock-ep-make')), findsOneWidget);
    expect(find.descendant(of: view, matching: find.text('/items')), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('mock-scenario-list-conflict')));
    await tester.pumpAndSettle();
    expect(w.mockSettings.of('list').scenario, MockScenario.conflict);
    expect(w.dirty, isTrue);

    await tester.enterText(find.byKey(const ValueKey('mock-delay-make')), '350');
    await tester.pump();
    expect(w.mockSettings.of('make').delayMs, 350);
    await tester.enterText(find.byKey(const ValueKey('mock-delay-make')), '');
    await tester.pump();
    expect(w.mockSettings.endpoints.containsKey('make'), isFalse, reason: 'ค่าเริ่มต้นไม่เก็บในไฟล์');
  });

  testWidgets('เริ่ม → เห็นที่อยู่ ; เรียกจริงแล้วขึ้นในบันทึก ; path ที่ไม่มี → เพิ่มเข้า API ได้ ; หยุดแล้วที่อยู่หาย', (tester) async {
    await boot(tester);
    expect(find.byKey(const ValueKey('mock-url')), findsNothing);
    await tester.runAsync(() async => m.start());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mock-url')), findsOneWidget);
    expect(find.text(m.url!), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('mock-port'))).enabled, isFalse);

    expect(await get(tester, '/items'), '200 [1]');
    expect((await get(tester, '/missing')).startsWith('404'), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('บันทึกคำขอ · 2'), findsOneWidget);
    expect(find.text('/missing'), findsOneWidget);
    expect(find.text('ไม่มี endpoint นี้ใน API'), findsOneWidget);
    // ตารางนับ "เรียกแล้ว/ล่าสุด" ของ endpoint ที่ถูกเรียก ; ตัวที่ไม่ถูกเรียก = —
    expect(tester.widget<Text>(find.byKey(const ValueKey('mock-hits-list'))).data, '1');
    expect(tester.widget<Text>(find.byKey(const ValueKey('mock-last-list'))).data, '200');
    expect(tester.widget<Text>(find.byKey(const ValueKey('mock-hits-make'))).data, '—');
    // รายละเอียดเริ่มที่คำขอใหม่สุด (/missing = 404) ; กดแถวเก่าสุด (/items) เห็น response จริง
    expect(tester.widget<Text>(find.byKey(const ValueKey('mock-detail-status'))).data, '404');
    await tester.tap(find.byKey(const ValueKey('mock-log-1')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('mock-detail-status'))).data, '200');
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('mock-detail-response'))).data, '[\n  1\n]');
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('mock-detail-request'))).data, '(ไม่มี body)');

    await tester.tap(find.byKey(const ValueKey('mock-add-endpoint')));
    await tester.pumpAndSettle();
    expect(w.mockApiDocument!.api!.endpoints.any((e) => e.path == '/missing'), isTrue);
    expect(find.text('Endpoint · 3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mock-clear-log')));
    await tester.pumpAndSettle();
    expect(find.text('บันทึกคำขอ · 0'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('mock-hits-list'))).data, '—', reason: 'ล้างบันทึก = ล้างตัวนับ');

    await tester.runAsync(() async => m.stop());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mock-url')), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('mock-port'))).enabled, isTrue);
  });

  testWidgets('ปุ่มเริ่ม/หยุดบนหน้าจอ: พอร์ตที่พิมพ์ถูกบันทึกในค่าตั้ง ; พอร์ตถูกใช้อยู่ = ขึ้นข้อความผิดพลาด', (tester) async {
    await boot(tester);
    final taken = (await tester.runAsync(() => ServerSocket.bind(InternetAddress.loopbackIPv4, 0)))!;
    addTearDown(taken.close);
    await tester.enterText(find.byKey(const ValueKey('mock-port')), '${taken.port}');
    await tester.tap(find.byKey(const ValueKey('mock-toggle')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(w.mockSettings.port, taken.port);
    expect(m.running, isFalse);
    expect(find.byKey(const ValueKey('mock-error')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('mock-port')), '0');
    await tester.tap(find.byKey(const ValueKey('mock-toggle')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(m.running, isTrue);
    expect(find.byKey(const ValueKey('mock-error')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mock-toggle')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(m.running, isFalse);
  });

  testWidgets('แถบเซิร์ฟเวอร์: หยุดอยู่ → กำลังทำงาน ; ลิ้นชักบันทึกพับ/แสดงได้', (tester) async {
    await boot(tester);
    expect(find.text('หยุดอยู่'), findsOneWidget);
    expect(find.byKey(const ValueKey('mock-source')), findsOneWidget);
    expect(find.byKey(const ValueKey('mock-detail')), findsNothing, reason: 'ยังไม่มีคำขอ');
    await tester.runAsync(() async => m.start());
    await tester.pumpAndSettle();
    expect(find.text('กำลังทำงาน'), findsOneWidget);
    expect(await get(tester, '/items'), '200 [1]');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mock-log-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mock-drawer-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mock-log-1')), findsNothing, reason: 'พับลิ้นชัก');
    expect(find.byKey(const ValueKey('mock-log-count')), findsOneWidget, reason: 'หัวลิ้นชักยังอยู่');
    await tester.tap(find.byKey(const ValueKey('mock-drawer-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mock-log-1')), findsOneWidget);
    await tester.runAsync(() async => m.stop());
    await tester.pumpAndSettle();
    expect(find.text('หยุดอยู่'), findsOneWidget);
  });

  testWidgets('ปุ่มสถานการณ์: เลือกแล้วเก็บในไฟล์ ; สลับกลับ "ปกติ" = ไม่เก็บ ; เรียกจริงแล้วตอบตามสถานการณ์', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('mock-scenario-list-serverError')));
    await tester.pumpAndSettle();
    expect(w.mockSettings.of('list').scenario, MockScenario.serverError);
    await tester.runAsync(() async => m.start());
    expect((await get(tester, '/items')).startsWith('500'), isTrue);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('mock-last-list'))).data, '500');
    expect(find.text('500 ผิดพลาด'), findsWidgets, reason: 'บันทึกบอกสถานการณ์ที่ใช้');
    await tester.tap(find.byKey(const ValueKey('mock-scenario-list-normal')));
    await tester.pumpAndSettle();
    expect(w.mockSettings.endpoints.containsKey('list'), isFalse);
    await tester.runAsync(() async => m.stop());
  });

  testWidgets('หน้า Mock Server ไม่มีแถบของโหมด ER: แผงซ้าย ปุ่ม Export .sql/Dialect/จัดวางอัตโนมัติ สรุป ER และซูมในแถบสถานะ', (tester) async {
    await boot(tester);
    expect(find.byType(LeftPanel), findsNothing);
    expect(find.text('Export .sql'), findsNothing);
    expect(find.textContaining('Dialect'), findsNothing);
    expect(find.text('จัดวางอัตโนมัติ'), findsNothing);
    expect(find.byKey(const ValueKey('status-zoom')), findsNothing);
    final summary = tester.widget<Text>(find.byKey(const ValueKey('status-summary'))).data!;
    expect(summary.contains('ตาราง'), isFalse, reason: 'ไม่มีสรุป ER : $summary');
    // กลับไปเอกสาร ER = ทุกอย่างกลับมา
    w.openDocument(w.mainEr.docId);
    await tester.pumpAndSettle();
    expect(find.byType(LeftPanel), findsOneWidget);
    expect(find.text('Export .sql'), findsOneWidget);
    expect(find.byKey(const ValueKey('status-zoom')), findsOneWidget);
  });

  testWidgets('รีเซ็ตข้อมูล: ปิดตอนหยุด ; ตอนรันโชว์จำนวนที่เปลี่ยน ; กดแล้วบอกผล ล้างจำนวน และข้อมูลกลับไปเริ่มใหม่', (tester) async {
    await boot(tester);
    // endpoint ที่ผูกตาราง ER (ข้อมูลจำ) : ตาราง items 1 แถวจาก seed
    w.mainEr.project.tables.add(TableModel(id: 'it', name: 'items', columns: [
      ColumnModel(id: 'k1', name: 'id', isPrimaryKey: true, autoIncrement: true),
      ColumnModel(id: 'k2', name: 'name', type: DataType.varchar, length: 20),
    ]));
    final api = w.mockApiDocument!.api!;
    api.endpoints
      ..clear()
      ..addAll([
        ApiEndpoint(id: 'list', path: '/items', table: ApiTableRef(docId: w.mainEr.docId, tableId: 'it'), responses: [ApiResponse(status: 200)]),
        ApiEndpoint(id: 'make', method: ApiMethod.post, path: '/items', table: ApiTableRef(docId: w.mainEr.docId, tableId: 'it'), fields: [ApiField(id: 'f', name: 'name')], responses: [ApiResponse(status: 201)]),
      ]);
    // ปิดข้อมูลตัวอย่างอัตโนมัติ (Phase 33) ให้ตารางที่ไม่มี seed เริ่มจาก 0 แถว
    w.setMockSettings(w.mockSettings.copyWith(autoSample: false));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('mock-reset'))).onPressed, isNull, reason: 'หยุดอยู่ = รีเซ็ตไม่ได้');
    expect(find.byKey(const ValueKey('mock-changes')), findsNothing);

    await tester.runAsync(() async => m.start());
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('mock-reset'))).onPressed, isNotNull);
    // ยังไม่มีอะไรเปลี่ยน = กดแล้วบอกว่าไม่มีอะไรให้รีเซ็ต
    await tester.tap(find.byKey(const ValueKey('mock-reset')));
    await tester.pumpAndSettle();
    expect(find.text('ข้อมูลยังเป็นค่าเริ่มต้นจาก seed ของ ER อยู่แล้ว — ไม่มีอะไรให้รีเซ็ต'), findsOneWidget);

    // POST จริง 2 ครั้ง → แถบบอก "เปลี่ยน 2 ครั้ง"
    await tester.runAsync(() async {
      for (final n in ['a', 'b']) {
        final c = HttpClient();
        try {
          final rq = await c.postUrl(Uri.parse('${m.url}/items'));
          rq.headers.contentType = ContentType.json;
          rq.write('{"name":"$n"}');
          await (await rq.close()).drain<void>();
        } finally {
          c.close(force: true);
        }
      }
    });
    await tester.pumpAndSettle();
    expect(m.changes, 2);
    expect(find.text('ข้อมูลเปลี่ยนจาก seed 2 ครั้ง'), findsOneWidget);
    final before = jsonDecode((await get(tester, '/items')).substring(4)) as List;
    expect(before.length, 2, reason: 'POST เพิ่มแถว (ตาราง items ไม่มี seed)');

    await tester.tap(find.byKey(const ValueKey('mock-reset')));
    await tester.pumpAndSettle();
    expect(find.text('รีเซ็ตข้อมูลแล้ว — ล้างการเปลี่ยน 2 ครั้ง กลับไปเริ่มจาก seed ของ ER'), findsOneWidget);
    expect(find.byKey(const ValueKey('mock-changes')), findsNothing);
    expect(m.changes, 0);
    final after = jsonDecode((await get(tester, '/items')).substring(4)) as List;
    expect(after, isEmpty, reason: 'กลับไปเริ่มจาก seed (ไม่มีแถว)');
    await tester.runAsync(() async => m.stop());
  });

  testWidgets('ทางเข้า: เมนูมุมมอง/Project Home/palette ; ภาษาอังกฤษไม่มีไทยหลุด', (tester) async {
    await boot(tester, lang: Lang.en);
    expect(find.text('Endpoints · 2'), findsOneWidget);
    expect(find.text('Request log · 0'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Reset data'), findsOneWidget);
    final thai = RegExp(r'[฀-๿]');
    final leaks = [
      for (final t in tester.widgetList<Text>(find.descendant(of: view, matching: find.byType(Text))))
        if (thai.hasMatch(t.data ?? '')) t.data,
    ];
    expect(leaks, isEmpty);

    w.showHome();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-mock')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-mock')));
    await tester.pumpAndSettle();
    expect(w.page, WorkspacePage.mock);
    expect(view, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
