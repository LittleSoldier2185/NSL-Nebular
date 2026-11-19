import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/mock/mock_settings.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/mock_controller.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
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

    await tester.tap(find.byKey(const ValueKey('mock-scenario-list')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('409 ซ้ำ').last);
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

    await tester.tap(find.byKey(const ValueKey('mock-add-endpoint')));
    await tester.pumpAndSettle();
    expect(w.mockApiDocument!.api!.endpoints.any((e) => e.path == '/missing'), isTrue);
    expect(find.text('Endpoint · 3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mock-clear-log')));
    await tester.pumpAndSettle();
    expect(find.text('บันทึกคำขอ · 0'), findsOneWidget);

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
