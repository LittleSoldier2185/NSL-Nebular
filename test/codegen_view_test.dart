import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/codegen/gen_targets.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// Phase 10: หน้าสร้างโค้ด
void main() {
  late WorkspaceController w;
  final view = find.byKey(const ValueKey('codegen-view'));

  Future<void> boot(WidgetTester tester, {bool tables = true}) async {
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true)));
    w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
    if (tables) {
      w.mainEr.project.tables.add(TableModel(id: 'o', name: 'orders', columns: [ColumnModel(id: 'o1', name: 'id', isPrimaryKey: true)]));
    }
    w.showCodegen();
    await tester.pumpAndSettle();
  }

  testWidgets('ค่าเริ่มต้น SQL + TypeScript ; เป้าหมายที่ไม่มีเอกสารต้นทางกดไม่ได้ ; ติ๊กเพิ่มแล้วรายการไฟล์/พรีวิวเปลี่ยน', (tester) async {
    await boot(tester);
    expect(view, findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('gen-count'))).data, '2');
    expect(find.byKey(const ValueKey('gen-file-database/schema.sql')), findsOneWidget);
    final api = tester.widget<CheckboxListTile>(find.byKey(const ValueKey('gen-target-openApi')));
    expect(api.onChanged, isNull);

    await tester.tap(find.byKey(const ValueKey('gen-target-laravelMigration')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('gen-count'))).data, '3');
    await tester.tap(find.byKey(const ValueKey('gen-file-database/migrations/0001_01_01_000001_create_orders_table.php')));
    await tester.pumpAndSettle();
    final preview = tester.widget<SelectableText>(find.byKey(const ValueKey('gen-preview')));
    expect(preview.data, contains("Schema::create('orders'"));
    expect(tester.takeException(), isNull);
  });

  testWidgets('บันทึกเป็นชุดตั้งค่า: เก็บใน meta ของโปรเจกต์ (dirty) และเปิดหน้าใหม่ได้ค่าเดิม', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('gen-target-typescript'))); // เอาออก
    await tester.tap(find.byKey(const ValueKey('gen-target-prisma')));
    await tester.enterText(find.byKey(const ValueKey('gen-folder')), r'C:\out');
    await tester.tap(find.byKey(const ValueKey('gen-save-preset')));
    await tester.pumpAndSettle();
    expect(w.codegenPreset!.targets, [GenTarget.sqlDdl.name, GenTarget.prisma.name]);
    expect(w.codegenPreset!.folder, r'C:\out');
    expect(w.dirty, isTrue);

    w.showHome();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-codegen')));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('gen-target-prisma'))).value, isTrue);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('gen-target-typescript'))).value, isFalse);
  });

  testWidgets('สร้างไฟล์ลงโฟลเดอร์ ; ครั้งถัดไปไฟล์ที่แก้ด้วยมือ = ถามก่อน เลือกข้ามแล้วไม่ทับ', (tester) async {
    await boot(tester);
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('nsl_genui_')))!;
    addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));
    await tester.enterText(find.byKey(const ValueKey('gen-folder')), dir.path);

    /// กดใน runAsync: งานอ่าน/เขียนไฟล์จริงต้องเดินด้วยเวลาจริง (นาฬิกาจำลองของ widget test ไม่ทำให้ IO เสร็จ)
    Future<void> tapReal(Finder f) async {
      await tester.runAsync(() async {
        await tester.tap(f);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();
    }

    Future<void> write() => tapReal(find.byKey(const ValueKey('gen-write')));

    await write();
    final sql = File('${dir.path}/database/schema.sql');
    expect(await tester.runAsync(sql.exists), isTrue);

    await tester.runAsync(() => sql.writeAsString('-- ของฉัน\n'));
    w.mainEr.project.tables.first.name = 'orders2'; // ให้ไฟล์ที่จะสร้างเปลี่ยน
    w.showHome();
    w.showCodegen();
    await tester.pumpAndSettle();
    await write();
    expect(find.byKey(const ValueKey('gen-edited-dialog')), findsOneWidget);
    await tapReal(find.byKey(const ValueKey('gen-skip-edited')));
    expect(await tester.runAsync(sql.readAsString), '-- ของฉัน\n');
  });

  testWidgets('ไม่มีอะไรให้สร้าง = ข้อความแนะนำ ; ปุ่มสร้างไฟล์ปิด', (tester) async {
    await boot(tester, tables: false);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('gen-write'))).onPressed, isNull);
    expect(find.textContaining('ยังไม่มีเอกสารที่สร้างโค้ดได้'), findsOneWidget);
  });
}
