import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/models/api_model.dart';
import '../core/models/table_model.dart';
import '../core/models/workspace.dart';
import 'doc_controller.dart';
import 'workspace_controller.dart';

/// controller ของเอกสาร API หนึ่งชิ้น: เนื้อหา + undo/redo + endpoint ที่เลือก
class ApiController extends DocController {
  ApiController.forDoc(super.doc, this.workspace) : assert(doc.content is ApiDocument);

  /// ตัวแทนตอนไม่มีเอกสาร API ที่ใช้งานอยู่ (ว่าง แก้ไขไม่ได้)
  ApiController.detached(this.workspace) : super(ProjectDocument.api(id: '', name: '', content: ApiDocument()));

  final WorkspaceController workspace;

  /// เอกสารนี้ยังอยู่ในโปรเจกต์ (ตัวแทน/เอกสารที่ถูกลบ = false แก้ไขไม่ได้)
  bool get active => !disposed && identical(workspace.documentById(docId), doc);

  ApiDocument get api => doc.content as ApiDocument;

  @override
  @protected
  String snapshot() => jsonEncode(api.toJson());

  @override
  @protected
  void restoreSnapshot(String snap) => doc.content = ApiDocument.fromJson(jsonDecode(snap));

  @override
  @protected
  void afterRestore() {
    if (_selected != null && api.endpointById(_selected!) == null) _selected = null;
  }

  int _seq = 0;
  String _newId(String p) => '$p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_seq++}';

  /// แก้แบบมีประวัติ เฉพาะเมื่อเนื้อหาเปลี่ยนจริง (ลองกับสำเนาก่อน) ; คืน true ถ้าเปลี่ยน
  bool _edit(void Function(ApiDocument a) change) {
    if (!active) return false;
    final before = snapshot();
    final probe = ApiDocument.fromJson(jsonDecode(before));
    change(probe);
    if (jsonEncode(probe.toJson()) == before) return false;
    editWithHistory(() => change(api));
    return true;
  }

  // ---------- การเลือก ----------

  String? _selected;
  String? get selectedId => _selected;
  ApiEndpoint? get selected => _selected == null ? null : api.endpointById(_selected!);

  void select(String? id) {
    if (_selected == id) return;
    _selected = id;
    notifyListeners();
  }

  // ---------- เอกสาร ----------

  void setInfo({String? title, String? version, String? baseUrl}) => _edit((a) {
        if (title != null) a.title = title.trim();
        if (version != null) a.version = version.trim();
        if (baseUrl != null) a.baseUrl = baseUrl.trim();
      });

  // ---------- endpoint ----------

  /// เพิ่ม endpoint แล้วเลือก ; path ไม่ขึ้นต้นด้วย / = เติมให้
  ApiEndpoint? addEndpoint({ApiMethod method = ApiMethod.get, String path = '/', String group = '', ApiTableRef? table}) {
    if (!active) return null;
    final e = ApiEndpoint(id: _newId('ep'), method: method, path: normalizePath(path), group: group, table: table);
    e.responses.add(ApiResponse(status: method == ApiMethod.post ? 201 : (method == ApiMethod.delete ? 204 : 200)));
    _edit((a) => a.endpoints.add(_copy(e)));
    _selected = e.id;
    notifyListeners();
    return api.endpointById(e.id);
  }

  static ApiEndpoint _copy(ApiEndpoint e) => ApiEndpoint.tryFromJson(jsonDecode(jsonEncode(e.toJson())))!;

  /// path มาตรฐาน: ขึ้นต้นด้วย / ไม่มีช่องว่าง ไม่มี / ซ้ำ ไม่ลงท้าย / (ยกเว้น "/")
  static String normalizePath(String p) {
    var s = p.trim().replaceAll(RegExp(r'\s+'), '');
    if (!s.startsWith('/')) s = '/$s';
    s = s.replaceAll(RegExp(r'/{2,}'), '/');
    if (s.length > 1 && s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }

  /// แก้ endpoint [id] (undo ขั้นเดียว ; ไม่เปลี่ยน = ไม่เข้าประวัติ)
  bool updateEndpoint(String id, void Function(ApiEndpoint e) change) => _edit((a) {
        final e = a.endpointById(id);
        if (e == null) return;
        change(e);
        e.path = normalizePath(e.path);
      });

  bool deleteEndpoint(String id) {
    final ok = _edit((a) => a.endpoints.removeWhere((e) => e.id == id));
    if (ok && _selected == id) {
      _selected = null;
      notifyListeners();
    }
    return ok;
  }

  ApiEndpoint? duplicateEndpoint(String id) {
    final src = api.endpointById(id);
    if (src == null || !active) return null;
    final j = src.toJson()..['id'] = _newId('ep');
    final copy = ApiEndpoint.tryFromJson(j)!;
    _edit((a) => a.endpoints.insert(a.endpoints.indexWhere((e) => e.id == id) + 1, _copy(copy)));
    _selected = copy.id;
    notifyListeners();
    return api.endpointById(copy.id);
  }

  // ---------- ฟิลด์ / response ----------

  ApiField? addField(String endpointId, {String name = '', ApiType type = ApiType.string, bool required = false, ApiTableRef? column}) {
    final f = ApiField(id: _newId('f'), name: name, type: type, required: required, column: column);
    final ok = _edit((a) => a.endpointById(endpointId)?.fields.add(ApiField.tryFromJson(f.toJson())!));
    return ok ? api.endpointById(endpointId)?.fields.last : null;
  }

  bool updateField(String endpointId, String fieldId, void Function(ApiField f) change) => _edit((a) {
        for (final f in a.endpointById(endpointId)?.fields ?? const <ApiField>[]) {
          if (f.id == fieldId) change(f);
        }
      });

  bool removeField(String endpointId, String fieldId) =>
      _edit((a) => a.endpointById(endpointId)?.fields.removeWhere((f) => f.id == fieldId));

  bool addResponse(String endpointId, int status) => _edit((a) {
        final e = a.endpointById(endpointId);
        if (e == null || e.responses.any((r) => r.status == status)) return;
        e.responses
          ..add(ApiResponse(status: status))
          ..sort((x, y) => x.status.compareTo(y.status));
      });

  bool updateResponse(String endpointId, int status, void Function(ApiResponse r) change) => _edit((a) {
        for (final r in a.endpointById(endpointId)?.responses ?? const <ApiResponse>[]) {
          if (r.status == status) change(r);
        }
      });

  bool removeResponse(String endpointId, int status) =>
      _edit((a) => a.endpointById(endpointId)?.responses.removeWhere((r) => r.status == status));

  // ---------- ผูกกับ ER ----------

  /// ฟิลด์ request จากคอลัมน์ของตาราง (ข้าม PK ที่เพิ่มอัตโนมัติ) — บังคับตาม NOT NULL ที่ไม่มีค่าเริ่มต้น
  static List<ApiField> fieldsFromTable(String docId, TableModel t, String Function() newId) => [
        for (final c in t.columns)
          if (!(c.isPrimaryKey && c.autoIncrement))
            ApiField(
              id: newId(),
              name: c.name,
              type: apiTypeOfColumn(c),
              required: (c.notNull || c.isPrimaryKey) && (c.defaultValue ?? '').trim().isEmpty,
              column: ApiTableRef(docId: docId, tableId: t.id, columnId: c.id),
              description: c.comment,
            ),
      ];

  /// ดึงฟิลด์จากคอลัมน์ของตารางที่ endpoint ผูกไว้ (เพิ่มเฉพาะคอลัมน์ที่ยังไม่มีฟิลด์ชื่อเดียวกัน) ; คืนจำนวนที่เพิ่ม
  int pullFieldsFromTable(String endpointId) {
    final e = api.endpointById(endpointId);
    final ref = e?.table;
    final t = ref == null ? null : workspace.workspace.documentById(ref.docId)?.er?.tableById(ref.tableId);
    if (e == null || t == null) return 0;
    final have = {for (final f in e.fields) f.name.toLowerCase()};
    final add = [for (final f in fieldsFromTable(ref!.docId, t, () => _newId('f'))) if (!have.contains(f.name.toLowerCase())) f];
    if (add.isEmpty) return 0;
    _edit((a) => a.endpointById(endpointId)!.fields.addAll([for (final f in add) ApiField.tryFromJson(f.toJson())!]));
    return add.length;
  }

  /// สร้าง CRUD 5 endpoint ของตาราง (`GET/POST /t`, `GET/PATCH/DELETE /t/{id}`) — undo ขั้นเดียว ; ข้าม method+path ที่มีอยู่แล้ว
  /// คืนจำนวนที่สร้าง
  int generateCrud(String erDocId, TableModel t) {
    if (!active) return 0;
    final base = '/${t.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_')}';
    final ref = ApiTableRef(docId: erDocId, tableId: t.id);
    final made = <ApiEndpoint>[
      ApiEndpoint(id: _newId('ep'), method: ApiMethod.get, path: base, summary: 'List ${t.name}', table: ref, responses: [ApiResponse(status: 200)]),
      ApiEndpoint(
        id: _newId('ep'),
        method: ApiMethod.post,
        path: base,
        summary: 'Create ${t.name}',
        table: ref,
        fields: fieldsFromTable(erDocId, t, () => _newId('f')),
        responses: [ApiResponse(status: 201), ApiResponse(status: 400)],
      ),
      ApiEndpoint(
        id: _newId('ep'),
        method: ApiMethod.get,
        path: '$base/{id}',
        summary: 'Get ${t.name}',
        table: ref,
        responses: [ApiResponse(status: 200), ApiResponse(status: 404)],
      ),
      ApiEndpoint(
        id: _newId('ep'),
        method: ApiMethod.patch,
        path: '$base/{id}',
        summary: 'Update ${t.name}',
        table: ref,
        fields: [for (final f in fieldsFromTable(erDocId, t, () => _newId('f'))) f..required = false],
        responses: [ApiResponse(status: 200), ApiResponse(status: 404)],
      ),
      ApiEndpoint(
        id: _newId('ep'),
        method: ApiMethod.delete,
        path: '$base/{id}',
        summary: 'Delete ${t.name}',
        table: ref,
        responses: [ApiResponse(status: 204), ApiResponse(status: 404)],
      ),
    ];
    final existing = {for (final e in api.endpoints) e.title};
    final fresh = [for (final e in made) if (!existing.contains(e.title)) e];
    if (fresh.isEmpty) return 0;
    _edit((a) => a.endpoints.addAll([for (final e in fresh) _copy(e)]));
    _selected = fresh.first.id;
    notifyListeners();
    return fresh.length;
  }
}
