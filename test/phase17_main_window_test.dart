import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/project_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:nsl_nebular/ui/project_explorer.dart';
import 'package:nsl_nebular/ui/right_panel.dart';
import 'package:nsl_nebular/ui/theme.dart';
import 'package:provider/provider.dart';

import 'migration_fixtures.dart';

/// Phase 17: แถบบนพื้นเข้ม · แผงขวา ER แยกแท็บ ตาราง/สไตล์/SQL · ตัวสำรวจเป็นคอลัมน์กว้างคงที่
void main() {
  late ProjectController c;

  Future<void> boot(WidgetTester tester, {Lang lang = Lang.th, double width = 1440}) async {
    tester.view.physicalSize = Size(width, 936);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: lang, showExplorer: true)));
    c = tester.element(find.byType(HomePage)).read<ProjectController>();
    c.loadProject(base(), null);
    c.selectTable('to');
    await tester.pumpAndSettle();
  }

  Finder tab(String name) => find.byKey(ValueKey('er-tab-$name'));

  group('แผงขวา ER แยกแท็บ', () {
    testWidgets('เริ่มที่แท็บตาราง: เห็นชื่อ/คอลัมน์ ไม่เห็นสีกับฟอนต์', (tester) async {
      await boot(tester);
      expect(tab('table'), findsOneWidget);
      expect(tab('style'), findsOneWidget);
      expect(tab('sql'), findsOneWidget);
      expect(find.byKey(const ValueKey('seed-open')), findsOneWidget);
      expect(find.byKey(const ValueKey('table-font')), findsNothing);
      expect(find.byKey(const ValueKey('table-color-none')), findsNothing);
    });

    testWidgets('แท็บสไตล์: มีสีกับฟอนต์ ไม่มีรายการคอลัมน์', (tester) async {
      await boot(tester);
      await tester.tap(tab('style'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('table-font')), findsOneWidget);
      expect(find.byKey(const ValueKey('table-color-none')), findsOneWidget);
      expect(find.byKey(const ValueKey('seed-open')), findsNothing);
      expect(find.byKey(const ValueKey('edit-structure')), findsNothing);
    });

    testWidgets('แท็บ SQL: แสดง CREATE TABLE ของตารางที่เลือกตารางเดียว', (tester) async {
      await boot(tester);
      await tester.tap(tab('sql'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('er-table-sql')), findsOneWidget);
      expect(find.byKey(const ValueKey('er-table-sql-copy')), findsOneWidget);
      final sql = tableSql(c.project, c.selectedTable!);
      expect(sql, contains('CREATE TABLE'));
      expect(sql, contains(c.selectedTable!.name));
      for (final t in c.project.tables) {
        if (t.id != c.selectedTable!.id) expect(sql, isNot(contains('CREATE TABLE `${t.name}`')));
      }
    });

    testWidgets('เลือกตารางอื่น แท็บที่เปิดอยู่คงเดิม ; ไม่เลือกตาราง = ข้อความบอกให้เลือก', (tester) async {
      await boot(tester);
      await tester.tap(tab('style'));
      await tester.pumpAndSettle();
      c.selectTable('tu');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('table-font')), findsOneWidget);
      c.selectTable(null);
      await tester.pumpAndSettle();
      expect(find.text('เลือกตารางทางซ้ายเพื่อแก้ไข'), findsOneWidget);
      expect(tab('style'), findsNothing);
    });

    testWidgets('ภาษาอังกฤษ: ป้ายแท็บแปลแล้ว', (tester) async {
      await boot(tester, lang: Lang.en);
      expect(find.descendant(of: find.byType(RightPanel), matching: find.text('Style')), findsOneWidget);
      expect(find.descendant(of: find.byType(RightPanel), matching: find.text('สไตล์')), findsNothing);
    });
  });

  group('ตัวสำรวจเป็นคอลัมน์กว้างคงที่', () {
    testWidgets('กว้าง kExplorerWidth เต็มความสูง และไม่เปลี่ยนเมื่อลากแถบแผงซ้าย', (tester) async {
      await boot(tester);
      final ex = find.byKey(const ValueKey('project-explorer'));
      expect(tester.getSize(ex).width, kExplorerWidth);
      final body = tester.getRect(find.byType(HomePage));
      expect(tester.getSize(ex).height, greaterThan(body.height * 0.6));
      // ลากแถบซ้าย: ตัวสำรวจต้องไม่ขยับขนาด
      await tester.drag(find.byKey(const ValueKey('splitter-left')), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(ex).width, kExplorerWidth);
    });

    testWidgets('ซ่อนตัวสำรวจ = ไม่มีคอลัมน์', (tester) async {
      tester.view.physicalSize = const Size(1440, 936);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: false)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('project-explorer')), findsNothing);
    });
  });

  group('แถบบนพื้นเข้ม', () {
    testWidgets('พื้นแถบบนเป็นสีหัวตาราง และกล่องค้นหา/เมนูใช้สีตัวอักษรอ่อน', (tester) async {
      await boot(tester);
      final bar = tester.widget<Container>(find
          .ancestor(of: find.byKey(const ValueKey('app-logo')), matching: find.byType(Container))
          .first);
      expect((bar.decoration as BoxDecoration).color, C.barBg);
      final menu = tester.widget<Text>(find.text('ไฟล์').first);
      expect(menu.style?.color, C.onBarMuted);
    });
  });
}
