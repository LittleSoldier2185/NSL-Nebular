import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/storage/project_file.dart';
import 'package:nsl_nebular/core/storage/recent_files.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/ui/start_page.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

/// หน้า Start + กล่องสร้างโปรเจกต์ใหม่ + ไฟล์ล่าสุด (Phase 2)
void main() {
  test('relativeTimeLabel: ช่วงเวลาต่าง ๆ', () {
    final now = DateTime(2026, 11, 18, 12, 0);
    expect(relativeTimeLabel(now, now), 'เมื่อสักครู่');
    expect(relativeTimeLabel(now.subtract(const Duration(minutes: 10)), now), '10 นาทีที่แล้ว');
    expect(relativeTimeLabel(now.subtract(const Duration(hours: 3)), now), '3 ชั่วโมงที่แล้ว');
    expect(relativeTimeLabel(DateTime(2026, 11, 17, 8, 0), now), 'เมื่อวาน');
    expect(relativeTimeLabel(DateTime(2026, 11, 15, 23, 0), now), '3 วันที่แล้ว');
    expect(relativeTimeLabel(DateTime(2026, 9, 1), now), '2026-09-01');
    expect(relativeTimeLabel(now.add(const Duration(hours: 1)), now), 'เมื่อสักครู่'); // เวลาในอนาคต (นาฬิกาเพี้ยน)
  });

  group('บนจอ', () {
    late Directory dir;
    late AppSettings settings;
    late WorkspaceController w;

    setUp(() => dir = Directory.systemTemp.createTempSync('nsl_start'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> boot(WidgetTester tester, {Lang lang = Lang.th, RecentFiles? recent}) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      settings = AppSettings(lang: lang, recent: recent);
      await tester.pumpWidget(NslDevApp(settings: settings, showStart: true));
      w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      await tester.pump();
    }

    /// สร้างไฟล์โปรเจกต์จริงในโฟลเดอร์ชั่วคราว (ต้องใช้ runAsync เพราะเป็น I/O จริง)
    Future<String> makeFile(WidgetTester tester, String name) async {
      final path = '${dir.path}${Platform.pathSeparator}$name.nsln';
      await tester.runAsync(() async {
        final ws = Workspace.single(base())..name = name;
        await ProjectFile.save(ws, path);
      });
      return path;
    }

    testWidgets('เปิดแอปแบบ showStart: เห็นหน้า Start ไม่เห็นแถบไอคอน/แถบสถานะ', (tester) async {
      await boot(tester);
      expect(w.startView, true);
      expect(find.byKey(const ValueKey('start-page')), findsOneWidget);
      expect(find.byKey(const ValueKey('activity-rail')), findsNothing);
      expect(find.text('สวัสดี ออกแบบอะไรดีวันนี้'), findsOneWidget);
      expect(find.byKey(const ValueKey('recent-empty')), findsOneWidget);
    });

    testWidgets('กดสร้างด่วน Flowchart: ออกจาก Start ได้ ER + Flowchart เปิด Flowchart', (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('start-quick-flowchart')));
      await tester.pumpAndSettle();
      expect(w.startView, false);
      expect(find.byKey(const ValueKey('start-page')), findsNothing);
      expect(find.byKey(const ValueKey('activity-rail')), findsOneWidget);
      expect(w.documents.map((d) => d.type), [DocType.er, DocType.flowchart]);
      expect(w.activeDocument.type, DocType.flowchart);
    });

    testWidgets('กดสร้างด่วน ER: ได้ ER อย่างเดียว', (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('start-quick-er')));
      await tester.pumpAndSettle();
      expect(w.documents.map((d) => d.type), [DocType.er]);
    });

    testWidgets('กล่องสร้างโปรเจกต์: เลือกจุดเริ่มต้นแล้วติ๊กตาม ; ER ปิดไม่ได้ ; ติ๊กเพิ่มได้ ; ตั้งชื่อ ; สร้าง', (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('start-new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('newproject-create')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('newproject-preset-analysis')));
      await tester.pump();
      bool checked(String t) => tester.widget<CheckboxListTile>(find.byKey(ValueKey('newproject-doc-$t'))).value == true;
      expect([checked('er'), checked('dfd'), checked('flowchart'), checked('wireframe'), checked('screenflow')], [true, true, true, false, false]);
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('newproject-doc-er'))).onChanged, isNull);

      await tester.tap(find.byKey(const ValueKey('newproject-doc-wireframe')));
      await tester.pump();
      expect(checked('wireframe'), true);

      await tester.enterText(find.byKey(const ValueKey('newproject-name')), 'ระบบเบิกวัสดุ');
      await tester.tap(find.byKey(const ValueKey('newproject-create')));
      await tester.pumpAndSettle();
      expect(w.startView, false);
      expect(w.documents.map((d) => d.type), [DocType.er, DocType.dfd, DocType.flowchart, DocType.wireframe]);
      expect(w.workspace.name, 'ระบบเบิกวัสดุ');
    });

    testWidgets('ยกเลิกกล่องสร้างโปรเจกต์: ยังอยู่หน้า Start', (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const ValueKey('start-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(w.startView, true);
    });

    testWidgets('เริ่มจากจุดเริ่มต้นสำเร็จรูป: การ์ด "ออกแบบแอป"', (tester) async {
      await boot(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('start-template-appDesign')));
      await tester.tap(find.byKey(const ValueKey('start-template-appDesign')));
      await tester.pumpAndSettle();
      expect(w.documents.map((d) => d.type), [DocType.er, DocType.wireframe, DocType.screenflow]);
    });

    testWidgets('ไฟล์ล่าสุด: แสดงการ์ด กดแล้วเปิดไฟล์จริง ออกจาก Start และอัปเดตรายการ', (tester) async {
      final path = await makeFile(tester, 'shop');
      await boot(tester, recent: RecentFiles().touch(path, name: 'ร้านขายของ', now: DateTime.now(), docCount: 3, docTypes: ['er', 'dfd']));
      expect(find.text('ร้านขายของ'), findsOneWidget);
      expect(find.byKey(const ValueKey('recent-empty')), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(ValueKey('recent-${recentKey(path)}')));
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(w.startView, false);
      expect(w.filePath, path);
      // เปิดแล้วชื่อ/จำนวนเอกสารในรายการล่าสุดอัปเดตตามไฟล์จริง
      expect(settings.recentFiles.single.name, 'shop');
      expect(settings.recentFiles.single.docCount, 1);
    });

    testWidgets('ไฟล์ล่าสุดที่หายไปแล้ว: กดแล้วแจ้งเตือนและเอาออกจากรายการ ไม่ออกจาก Start', (tester) async {
      final gone = '${dir.path}${Platform.pathSeparator}gone.nsln';
      await boot(tester, recent: RecentFiles().touch(gone, name: 'gone', now: DateTime.now()));
      // ตอนเริ่มหน้า Start จะตัดไฟล์ที่ไม่มีออกเอง — ใส่กลับแล้วกดทันที เพื่อทดสอบเส้นทางกดโดยตรง
      await tester.pump();
      expect(settings.recentFiles, isEmpty);
      settings.addRecent(gone, name: 'gone', now: DateTime.now());
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('recent-${recentKey(gone)}')));
      await tester.pumpAndSettle();
      expect(w.startView, true);
      expect(settings.recentFiles, isEmpty);
      expect(find.textContaining('ไม่พบไฟล์'), findsOneWidget);
    });

    testWidgets('เริ่มหน้า Start: ตัดไฟล์ที่ไม่มีอยู่ออกจากรายการล่าสุดเอง', (tester) async {
      final path = await makeFile(tester, 'keep');
      final gone = '${dir.path}${Platform.pathSeparator}gone.nsln';
      await boot(tester, recent: RecentFiles().touch(path, name: 'keep', now: DateTime.now()).touch(gone, name: 'gone', now: DateTime.now()));
      await tester.pump();
      expect(settings.recentFiles.map((f) => f.name), ['keep']);
    });

    testWidgets('ปักหมุด/เอาออกจากรายการล่าสุด', (tester) async {
      final a = await makeFile(tester, 'a');
      final b = await makeFile(tester, 'b');
      await boot(tester, recent: RecentFiles().touch(a, name: 'a', now: DateTime(2026, 11, 1)).touch(b, name: 'b', now: DateTime(2026, 11, 2)));
      expect(settings.recentFiles.map((f) => f.name), ['b', 'a']);
      await tester.tap(find.byKey(ValueKey('recent-pin-${recentKey(a)}')));
      await tester.pump();
      expect(settings.recentFiles.map((f) => (f.name, f.pinned)), [('a', true), ('b', false)]);
      await tester.tap(find.byKey(ValueKey('recent-remove-${recentKey(b)}')));
      await tester.pump();
      expect(settings.recentFiles.map((f) => f.name), ['a']);
    });

    testWidgets('ภาษาอังกฤษ: หน้า Start และกล่องสร้างโปรเจกต์ไม่มีไทยหลุด', (tester) async {
      final path = await makeFile(tester, 'shop');
      await boot(tester, lang: Lang.en, recent: RecentFiles().touch(path, name: 'shop', now: clock.now(), docCount: 2));
      final thai = RegExp(r'[฀-๿]');
      void expectNoThai(Finder scope) {
        for (final t in tester.widgetList<Text>(find.descendant(of: scope, matching: find.byType(Text)))) {
          expect(thai.hasMatch(t.data ?? ''), false, reason: t.data);
        }
      }

      expectNoThai(find.byKey(const ValueKey('start-page')));
      await tester.tap(find.byKey(const ValueKey('start-new')));
      await tester.pumpAndSettle();
      expectNoThai(find.byType(Dialog));
    });
  });
}
