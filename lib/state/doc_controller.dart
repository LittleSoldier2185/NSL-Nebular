import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/models/review_note.dart';
import '../core/models/workspace.dart';
import 'snapshot_history.dart';

/// controller ของเอกสารหนึ่งชิ้นใน workspace: ถือ [doc] + ประวัติ undo/redo (แบบ snapshot ของเนื้อหาเอกสารนี้เท่านั้น)
/// + สถานะ "แก้แล้วยังไม่บันทึก" ของเอกสารนี้
///
/// ชนิดย่อยบอกวิธีทำ snapshot ([snapshot]) และวิธีใส่ snapshot กลับ ([restoreSnapshot])
abstract class DocController extends ChangeNotifier {
  DocController(this._doc);

  static const maxHistory = 100;

  ProjectDocument _doc;

  /// เอกสารที่ controller นี้ดูแล (object จริงใน workspace)
  ProjectDocument get doc => _doc;
  String get docId => _doc.id;

  /// ประวัติ undo/redo ของเอกสารนี้
  final SnapshotHistory history = SnapshotHistory(max: maxHistory);

  int _revision = 0;

  /// นับขึ้นทุกครั้งที่เนื้อหาเปลี่ยน (แก้/ลากสด/undo/redo) — ใช้เทียบว่าเนื้อหาเปลี่ยนหรือยัง
  int get revision => _revision;

  bool _docDirty = false;

  /// เอกสารนี้ถูกแก้หลังบันทึก/เปิดครั้งล่าสุด
  bool get docDirty => _docDirty;

  /// แก้แล้วยังไม่บันทึก (ของเอกสารนี้)
  bool get dirty => _docDirty;

  bool _disposed = false;
  bool get disposed => _disposed;

  /// เนื้อหาปัจจุบันเป็นข้อความ (ใช้เก็บในประวัติ)
  @protected
  String snapshot();

  /// ใส่เนื้อหาจาก [snap] กลับเข้า [doc] (object ใหม่)
  @protected
  void restoreSnapshot(String snap);

  /// สิ่งที่เก็บในประวัติ undo: เนื้อหา + โน้ตของเอกสาร
  /// (ไม่มีโน้ต = เท่ากับ [snapshot] ทุกตัวอักษร ; มีโน้ต = `\u0001<โน้ต JSON>\u0001<เนื้อหา>`)
  String historySnapshot() {
    final c = snapshot();
    if (_doc.reviewNotes.isEmpty) return c;
    return '$_notesMark${jsonEncode(encodeNotes(_doc.reviewNotes))}$_notesMark$c';
  }

  static const _notesMark = '\u0001';

  void _restoreHistory(String snap) {
    if (snap.startsWith(_notesMark)) {
      final end = snap.indexOf(_notesMark, 1);
      _doc.reviewNotes = decodeNotes(jsonDecode(snap.substring(1, end)));
      restoreSnapshot(snap.substring(end + 1));
    } else {
      _doc.reviewNotes = [];
      restoreSnapshot(snap);
    }
  }

  /// เรียกหลัง undo/redo ใส่เนื้อหากลับแล้ว (เช่น ล้างการเลือกที่หายไป)
  @protected
  void afterRestore() {}

  /// ผูก controller กับเอกสารใหม่ (เปิดไฟล์ใหม่แต่ใช้ controller ตัวเดิม) — ล้างประวัติและสถานะ dirty
  @protected
  void rebind(ProjectDocument doc) {
    _doc = doc;
    history.clear();
    _docDirty = false;
    _revision++;
  }

  /// เนื้อหาเปลี่ยนและนับว่าแก้แล้ว
  @protected
  void markEdited() {
    _docDirty = true;
    _revision++;
  }

  /// เนื้อหาเปลี่ยนชั่วคราวระหว่างลาก (ยังไม่นับว่าแก้)
  @protected
  void markLive() => _revision++;

  /// บันทึกแล้ว / เปิดใหม่
  void markClean() => _docDirty = false;

  /// แก้เนื้อหาแบบมีประวัติ (undo ขั้นเดียว)
  @protected
  void editWithHistory(void Function() change) {
    history.push(historySnapshot());
    change();
    markEdited();
    notifyListeners();
  }

  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  void undo() {
    if (!history.canUndo) return;
    _apply(history.undo(historySnapshot())!);
  }

  void redo() {
    if (!history.canRedo) return;
    _apply(history.redo(historySnapshot())!);
  }

  void _apply(String snap) {
    _restoreHistory(snap);
    markEdited();
    afterRestore();
    notifyListeners();
  }

  /// กำลังลากอยู่ (ตั้งแต่ [beginGesture] ถึง [endGesture])
  bool get gestureActive => history.gestureActive;

  /// เริ่มลาก: การแก้สดจนถึง [endGesture] นับเป็น undo ขั้นเดียว
  void beginGesture() {
    if (history.gestureActive) return;
    history.beginGesture(historySnapshot());
  }

  /// จบการลาก — คืน true ถ้าเนื้อหาเปลี่ยน (เก็บเข้าประวัติแล้ว)
  bool endGesture() {
    if (!history.gestureActive) return false;
    final changed = history.endGesture(historySnapshot());
    if (changed) markEdited();
    notifyListeners();
    return changed;
  }

  // ---------- โน้ตและงานค้าง (Phase 5) — แก้แบบมี undo ร่วมกับเนื้อหาเอกสาร ----------

  /// โน้ตของเอกสารนี้ (ตามลำดับที่เพิ่ม)
  List<ReviewNote> get reviewNotes => _doc.reviewNotes;

  ReviewNote? reviewNoteById(String id) {
    for (final n in _doc.reviewNotes) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// ตัวนับของทั้งโปรแกรม (ไม่ใช่ต่อเอกสาร) — เพิ่มโน้ตหลายเอกสารในไมโครวินาทีเดียวกันต้องได้ id ไม่ซ้ำ
  static int _reviewNoteSeq = 0;

  /// เพิ่มโน้ต (ข้อความว่างหลังตัดช่องว่าง = ไม่เพิ่ม คืน null) ; [x],[y] = ปักหมุดที่ตำแหน่งนั้นบนแคนวาส
  ReviewNote? addReviewNote(String text, {NoteKind kind = NoteKind.todo, double? x, double? y, String? anchorId}) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final n = ReviewNote(
      id: 'note${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_reviewNoteSeq++}',
      kind: kind,
      text: t,
      x: x,
      y: y,
      anchorId: anchorId,
    );
    editWithHistory(() => _doc.reviewNotes = [..._doc.reviewNotes, n]);
    return n;
  }

  /// แก้โน้ต [id] (ส่งเฉพาะค่าที่จะเปลี่ยน) ; ไม่มีอะไรเปลี่ยน = ไม่เข้าประวัติ ; คืน true ถ้าเปลี่ยน
  bool updateReviewNote(String id, {String? text, NoteKind? kind, bool? done}) {
    final n = reviewNoteById(id);
    if (n == null) return false;
    final t = text?.trim();
    if (t != null && t.isEmpty) return false;
    if ((t == null || t == n.text) && (kind == null || kind == n.kind) && (done == null || done == n.done)) return false;
    editWithHistory(() {
      if (t != null) n.text = t;
      if (kind != null) n.kind = kind;
      if (done != null) n.done = done;
    });
    return true;
  }

  /// สลับสถานะเสร็จ/ยังไม่เสร็จ
  bool toggleReviewNoteDone(String id) {
    final n = reviewNoteById(id);
    return n != null && updateReviewNote(id, done: !n.done);
  }

  /// ย้ายหมุดของโน้ต (ระหว่างลาก — ครอบด้วย [beginGesture]/[endGesture] เพื่อให้ undo ขั้นเดียว) ; null = ถอดหมุด
  void moveReviewNote(String id, double? x, double? y) {
    final n = reviewNoteById(id);
    if (n == null) return;
    if (gestureActive) {
      n
        ..x = x
        ..y = y;
      markLive();
      notifyListeners();
    } else {
      editWithHistory(() => n
        ..x = x
        ..y = y);
    }
  }

  bool deleteReviewNote(String id) {
    if (reviewNoteById(id) == null) return false;
    editWithHistory(() => _doc.reviewNotes = [for (final n in _doc.reviewNotes) if (n.id != id) n]);
    return true;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
