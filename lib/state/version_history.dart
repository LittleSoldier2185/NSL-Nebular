import 'package:flutter/foundation.dart';

import '../core/models/workspace.dart';
import '../core/storage/history_store.dart';
import '../core/storage/project_codec.dart';
import 'workspace_controller.dart';

/// รายการหนึ่งในหน้าประวัติ: สำเนา + ชื่อที่แสดง (เวอร์ชันที่ตั้งชื่อได้เลข v1, v2… ตามลำดับเวลา)
class VersionEntry {
  const VersionEntry(this.info, this.number);
  final SnapshotInfo info;

  /// เลขเวอร์ชัน (เฉพาะที่ผู้ใช้บันทึกเอง) ; null = บันทึกอัตโนมัติ
  final int? number;

  bool get named => number != null;
}

/// ประวัติเวอร์ชันของโปรเจกต์ที่เปิดอยู่ (Phase 7) บน [HistoryStore] — เก็บนอกไฟล์ `.nsln` ในโฟลเดอร์ข้อมูลของแอป
/// - บันทึกเวอร์ชันเอง (ตั้งชื่อ) = [SnapshotKind.manual]
/// - บันทึกไฟล์แต่ละครั้ง = สำเนาอัตโนมัติ ([SnapshotKind.save] ; เหมือนสำเนาล่าสุด = ไม่เก็บซ้ำ)
/// [store] = null (หาที่เก็บไม่ได้) = ปิดความสามารถนี้ ([enabled] false)
class VersionHistory extends ChangeNotifier {
  VersionHistory(this.store, this.workspace);

  final HistoryStore? store;
  final WorkspaceController workspace;

  bool get enabled => store != null;

  List<VersionEntry> _entries = const [];
  List<VersionEntry> get entries => _entries;

  /// เวอร์ชันที่ตั้งชื่อ ใหม่สุดก่อน
  List<VersionEntry> get named => [for (final e in _entries) if (e.named) e];

  /// สำเนาอัตโนมัติ ใหม่สุดก่อน
  List<VersionEntry> get automatic => [for (final e in _entries) if (!e.named) e];

  String get key => HistoryStore.keyFor(workspace.filePath);

  /// อ่านรายการใหม่จากที่เก็บ
  Future<void> refresh() async {
    final s = store;
    if (s == null) return;
    final all = await s.list(key);
    // เลขเวอร์ชันนับจากเก่าไปใหม่ (เฉพาะ manual)
    final manualOldFirst = [for (final i in all.reversed) if (i.kind == SnapshotKind.manual) i.id];
    _entries = [
      for (final i in all) VersionEntry(i, i.kind == SnapshotKind.manual ? manualOldFirst.indexOf(i.id) + 1 : null),
    ];
    notifyListeners();
  }

  /// บันทึกเวอร์ชันปัจจุบันพร้อมชื่อ (เก็บเสมอ แม้เนื้อหาเหมือนสำเนาล่าสุด) ; คืนรายการใหม่ (null = ปิดอยู่)
  Future<VersionEntry?> saveVersion(String label, {DateTime? now}) async {
    final s = store;
    if (s == null) return null;
    final info = await s.add(key, copyWorkspace(workspace.workspace), kind: SnapshotKind.manual, label: label.trim(), now: now, force: true);
    await refresh();
    return info == null ? null : _entries.firstWhere((e) => e.info.id == info.id);
  }

  /// เรียกหลังบันทึกไฟล์สำเร็จ: [previousPath] = path ก่อนบันทึก (บันทึกครั้งแรก/บันทึกเป็น = ย้ายประวัติตามไฟล์ใหม่)
  Future<void> onSaved(String? previousPath, {DateTime? now}) async {
    final s = store;
    if (s == null) return;
    final from = HistoryStore.keyFor(previousPath);
    if (from == 'unsaved' && from != key) await s.adopt(from, key);
    await s.add(key, copyWorkspace(workspace.workspace), kind: SnapshotKind.save, now: now);
    await refresh();
  }

  /// เนื้อหาโปรเจกต์ของสำเนา [id] ; null = ไม่พบ/ไฟล์เสีย
  Future<Workspace?> load(String id) async => store?.load(key, id);

  /// เก็บสำเนาของปัจจุบันไว้ก่อนย้อนกลับ (ย้อนการย้อนได้จากหน้าประวัติ แม้ undo หมดแล้ว)
  Future<void> beforeRestore(String label, {DateTime? now}) async {
    final s = store;
    if (s == null) return;
    await s.add(key, copyWorkspace(workspace.workspace), kind: SnapshotKind.beforeRestore, label: label, now: now);
    await refresh();
  }
}
