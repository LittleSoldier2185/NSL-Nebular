import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/core/diff/schema_diff.dart';
import 'package:nsl_nebular/core/diff/visual_diff.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/storage/history_store.dart';
import 'package:nsl_nebular/core/storage/project_codec.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/version_history.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// ที่เก็บประวัติในหน่วยความจำ (เทสต์หน้าจอ: งานไฟล์จริงไม่จบในนาฬิกาจำลองของ widget test)
class _MemoryHistoryStore extends HistoryStore {
  _MemoryHistoryStore() : super(Directory('unused'));
  final Map<String, List<(SnapshotInfo, Workspace)>> _data = {};
  var _n = 0;

  @override
  Future<SnapshotInfo?> add(String key, Workspace w,
      {SnapshotKind kind = SnapshotKind.save, String label = '', DateTime? now, bool force = false}) async {
    final list = _data.putIfAbsent(key, () => []);
    final digest = HistoryStore.digestOf(w);
    if (!force && list.isNotEmpty && list.first.$1.digest == digest) return null;
    final info = SnapshotInfo(
      id: 's${(_n++).toString().padLeft(4, '0')}',
      savedAt: (now ?? DateTime.now()).add(Duration(milliseconds: _n)),
      kind: kind,
      label: label,
      tables: w.tableCount,
      relations: w.relationCount,
      digest: digest,
    );
    list.insert(0, (info, copyWorkspace(w)));
    return info;
  }

  @override
  Future<List<SnapshotInfo>> list(String key) async => [for (final e in _data[key] ?? const []) e.$1];

  @override
  Future<Workspace?> load(String key, String id) async {
    for (final e in _data[key] ?? const <(SnapshotInfo, Workspace)>[]) {
      if (e.$1.id == id) return copyWorkspace(e.$2);
    }
    return null;
  }

  @override
  Future<void> adopt(String fromKey, String toKey) async {
    final from = _data.remove(fromKey);
    if (from != null) _data.putIfAbsent(toKey, () => []).insertAll(0, from);
  }
}

/// Phase 7: ประวัติเวอร์ชันและ Diff
void main() {
  Project base() => Project(name: 'shop', tables: [
        TableModel(id: 'c', name: 'customers', columns: [ColumnModel(id: 'c1', name: 'id', isPrimaryKey: true), ColumnModel(id: 'c2', name: 'name')]),
        TableModel(id: 'o', name: 'orders', columns: [
          ColumnModel(id: 'o1', name: 'id', isPrimaryKey: true),
          ColumnModel(id: 'o2', name: 'status', type: DataType.varchar, length: 10),
          ColumnModel(id: 'o3', name: 'discount'),
        ]),
        TableModel(id: 'k', name: 'coupons', columns: [ColumnModel(id: 'k1', name: 'id')]),
      ]);

  Project changed() {
    final p = Project.fromContentJson(base().toContentJson());
    p.tables.removeWhere((t) => t.id == 'k'); // ลบตาราง
    final o = p.tableById('o')!;
    o.columns.removeWhere((c) => c.id == 'o3'); // ลบคอลัมน์
    o.columnById('o2')!.length = 20; // เปลี่ยนชนิด
    o.columns.add(ColumnModel(id: 'o4', name: 'note')); // เพิ่มคอลัมน์
    p.tables.add(TableModel(id: 'p', name: 'payments', columns: [ColumnModel(id: 'p1', name: 'id')])); // เพิ่มตาราง
    return p;
  }

  group('ภาพ diff ตรงกับ schema_diff', () {
    test('สถานะตาราง/คอลัมน์ ตรงกับรายการใน SchemaDiff', () {
      final old = base(), neu = changed();
      final d = diffProjects(old, neu);
      final v = visualDiff(old, neu, d);
      VisualTable t(String n) => v.firstWhere((x) => x.name == n);
      expect(t('customers').mark, DiffMark.same);
      expect(t('payments').mark, DiffMark.added);
      expect(t('coupons').mark, DiffMark.dropped);
      expect(t('orders').mark, DiffMark.changed);
      final cols = {for (final c in t('orders').columns) c.name: c};
      expect(cols['note']!.mark, DiffMark.added);
      expect(cols['discount']!.mark, DiffMark.dropped);
      expect(cols['status']!.mark, DiffMark.changed);
      expect(cols['status']!.detail, contains('→'));
      expect(cols['id']!.mark, DiffMark.same);
      // นับให้ตรงกับ SchemaDiff
      expect(v.where((x) => x.mark == DiffMark.added).length, d.addedTables.length);
      expect(v.where((x) => x.mark == DiffMark.dropped).length, d.droppedTables.length);
      expect(v.where((x) => x.mark == DiffMark.changed).length, d.modified.where((m) => m.hasChanges).length);
      // ตารางที่ลบอยู่ท้ายสุด
      expect(v.last.name, 'coupons');
    });

    test('เปลี่ยนชื่อตาราง: แสดงชื่อเดิม ; ไม่มีความต่าง = ทุกอย่าง same', () {
      final old = base();
      final neu = Project.fromContentJson(old.toContentJson())..tableById('c')!.name = 'clients';
      final v = visualDiff(old, neu, diffProjects(old, neu));
      expect(v.first.oldName, 'customers');
      final same = visualDiff(old, old, diffProjects(old, old));
      expect(same.every((t) => t.mark == DiffMark.same && t.columns.every((c) => c.mark == DiffMark.same)), isTrue);
    });

    test('ความเปลี่ยนแปลงของเอกสารอื่น: เพิ่ม/แก้/ลบ (การลบนับว่าอันตราย)', () {
      final w = WorkspaceController();
      addTearDown(w.dispose);
      final keep = w.addDocument(DocType.flowchart, name: 'A')!;
      final gone = w.addDocument(DocType.dfd, name: 'B')!;
      final old = copyWorkspace(w.workspace);
      w.deleteDocument(gone.id);
      keep.name = 'A2';
      w.addDocument(DocType.wireframe, name: 'C');
      final lines = documentChanges(old, w.workspace);
      expect(lines.map((l) => l.kind), containsAll([ChangeKind.add, ChangeKind.change, ChangeKind.drop]));
      expect(lines.firstWhere((l) => l.kind == ChangeKind.drop).destructive, isTrue);
    });
  });

  group('VersionHistory', () {
    late Directory dir;
    late WorkspaceController w;
    late VersionHistory v;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('nsl_hist_');
      w = WorkspaceController();
      v = VersionHistory(HistoryStore(dir), w);
    });
    tearDown(() async {
      v.dispose();
      w.dispose();
      await dir.delete(recursive: true);
    });

    test('เวอร์ชันที่ตั้งชื่อได้เลข v1, v2 ตามเวลา ; แยกจากสำเนาอัตโนมัติ', () async {
      final t0 = DateTime(2026, 11, 1, 9);
      await v.saveVersion('โครง ER แรก', now: t0);
      w.mainEr.project.tables.add(TableModel(id: 'x', name: 'x'));
      await v.onSaved(null, now: t0.add(const Duration(hours: 1)));
      await v.saveVersion('ส่งให้ลูกค้าดู', now: t0.add(const Duration(days: 1)));
      expect(v.named.map((e) => (e.number, e.info.label)), [(2, 'ส่งให้ลูกค้าดู'), (1, 'โครง ER แรก')]);
      expect(v.automatic, hasLength(1));
      final loaded = await v.load(v.named.last.info.id);
      expect(loaded!.firstEr!.er!.tables, isEmpty);
    });

    test('บันทึกไฟล์ครั้งแรก: ย้ายประวัติของโปรเจกต์ที่ยังไม่บันทึกไปอยู่กับไฟล์', () async {
      await v.saveVersion('ก่อนบันทึก');
      expect(v.key, 'unsaved');
      w.markSaved('${dir.path}${Platform.pathSeparator}shop.nsln');
      await v.onSaved(null); // เนื้อหาเหมือนสำเนาล่าสุด = ไม่เก็บซ้ำ
      expect(v.key, isNot('unsaved'));
      expect(v.named.single.info.label, 'ก่อนบันทึก');
      expect(v.automatic, isEmpty);
      w.mainEr.project.tables.add(TableModel(id: 'y', name: 'y'));
      await v.onSaved(w.filePath);
      expect(v.automatic, hasLength(1));
    });

    test('ไม่มีที่เก็บ: ปิดความสามารถโดยไม่พัง', () async {
      final off = VersionHistory(null, w);
      addTearDown(off.dispose);
      expect(off.enabled, isFalse);
      expect(await off.saveVersion('x'), isNull);
      await off.onSaved(null);
      expect(off.entries, isEmpty);
    });
  });

  test('ย้อน ER ทั้งชุด (replaceContent) undo ได้ ; ชื่อ ER คงเดิม ; เหมือนเดิม = ไม่เข้าประวัติ', () {
    final w = WorkspaceController();
    addTearDown(w.dispose);
    w.mainEr.project.name = 'ปัจจุบัน';
    w.mainEr.project.tables.add(TableModel(id: 'a', name: 'a'));
    final old = base()..name = 'ชื่อเก่า';
    w.mainEr.replaceContent(old);
    expect(w.mainEr.project.tables.map((t) => t.name), ['customers', 'orders', 'coupons']);
    expect(w.mainEr.project.name, 'ปัจจุบัน');
    old.tables.clear(); // สำเนาแยกขาด
    expect(w.mainEr.project.tables, hasLength(3));
    final canUndo = w.mainEr.canUndo;
    w.mainEr.replaceContent(Project.fromContentJson(w.mainEr.project.toContentJson()));
    expect(w.mainEr.canUndo, canUndo);
    w.mainEr.undo();
    expect(w.mainEr.project.tables.map((t) => t.name), ['a']);
  });

  group('หน้าประวัติ', () {
    late WorkspaceController w;
    final view = find.byKey(const ValueKey('history-view'));

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true), history: _MemoryHistoryStore()));
      w = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      w.mainEr.project.tables.addAll(base().tables);
      await tester.pump();
    }

    Future<void> settleIo(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.pumpAndSettle();
      }
    }

    testWidgets('ยังไม่มีเวอร์ชัน = ข้อความแนะนำ ; บันทึกเวอร์ชัน แก้ ER แล้วเห็นภาพ diff และรายการความเปลี่ยนแปลง', (tester) async {
      await boot(tester);
      w.showHistory();
      await settleIo(tester);
      expect(view, findsOneWidget);
      expect(find.byKey(const ValueKey('history-message')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('history-save-version')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('history-version-name')), 'โครงแรก');
      await tester.tap(find.byKey(const ValueKey('history-version-ok')));
      await settleIo(tester);
      expect(find.text('v1 · โครงแรก'), findsOneWidget);
      expect(find.byKey(const ValueKey('history-same')), findsOneWidget);

      // แก้ ER ให้เหมือน changed()
      w.mainEr.replaceContent(changed());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-table-payments')), findsOneWidget);
      expect(find.byKey(const ValueKey('history-table-coupons')), findsOneWidget);
      final d = diffProjects(base(), changed());
      expect(find.text('ความเปลี่ยนแปลง · ${d.summary(base(), changed()).length}'), findsOneWidget);
      expect(find.byKey(const ValueKey('history-destructive')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('สร้าง migration เปิดหน้าต่างเดิม ; ย้อน ER กลับ แล้ว undo ได้ และมีสำเนาก่อนย้อน', (tester) async {
      await boot(tester);
      final v = tester.element(find.byType(HomePage)).read<VersionHistory>();
      await v.saveVersion('ฐาน');
      w.mainEr.replaceContent(changed());
      w.showHistory();
      await settleIo(tester);

      await tester.tap(find.byKey(const ValueKey('history-migration')));
      await tester.pumpAndSettle();
      expect(find.textContaining('DROP TABLE'), findsWidgets);
      await tester.tapAt(const Offset(5, 5)); // ปิดหน้าต่าง
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('history-restore')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history-restore-ok')));
      await settleIo(tester);
      expect(w.mainEr.project.tables.map((t) => t.name), ['customers', 'orders', 'coupons']);
      expect(v.automatic.any((e) => e.info.kind == SnapshotKind.beforeRestore), isTrue);
      w.mainEr.undo();
      expect(w.mainEr.project.tableById('p'), isNotNull); // กลับมาเป็นก่อนย้อน
    });

    testWidgets('เข้าได้จากปุ่มบน Project Home', (tester) async {
      await boot(tester);
      w.showHome();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-history')));
      await settleIo(tester);
      expect(view, findsOneWidget);
    });
  });
}
