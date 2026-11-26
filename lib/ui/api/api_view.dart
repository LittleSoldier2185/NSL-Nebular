import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/models/api_model.dart';
import '../../core/models/workspace.dart';
import '../../core/validate/api_validator.dart';
import '../../state/api_controller.dart';
import '../../state/workspace_controller.dart';
import '../document_actions.dart' show DocTypeDot, linkOriginTitle;
import '../notes_panel.dart' show gotoNoteTarget;
import '../palette/command_palette.dart' show gotoScreenFlow;
import '../issue_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import '../../core/export/openapi_export.dart';
import '../file_actions.dart';

/// สีของป้าย method (ใช้สีประจำชนิดเอกสารที่มีอยู่ ไม่เพิ่มค่าสีใหม่)
Color apiMethodColor(ApiMethod m) => switch (m) {
  ApiMethod.get => C.doc(DocType.er).ink,
  ApiMethod.post => C.doc(DocType.dfd).ink,
  ApiMethod.put || ApiMethod.patch => C.doc(DocType.wireframe).ink,
  ApiMethod.delete => C.dangerText,
};

class ApiMethodChip extends StatelessWidget {
  const ApiMethodChip(this.method, {super.key, this.width = 54});
  final ApiMethod method;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.symmetric(vertical: 2),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: apiMethodColor(method).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)),
    child: Text(
      method.label,
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: apiMethodColor(method), fontFamily: 'monospace'),
    ),
  );
}

/// ชื่อตาราง ER ที่อ้างถึง ; ไม่พบ = null
String? apiTableName(Workspace w, ApiTableRef? r) => r == null ? null : w.documentById(r.docId)?.er?.tableById(r.tableId)?.name;

/// ตารางที่ยังไม่มี endpoint ผูก (ทุก ER) : (เอกสาร ER, ตาราง)
List<(ProjectDocument, String tableId, String name)> uncoveredTables(Workspace w) {
  final covered = <String>{
    for (final d in w.documentsOf(DocType.api))
      for (final e in d.api!.endpoints)
        if (e.table case final t?) '${t.docId}/${t.tableId}',
  };
  return [
    for (final d in w.documentsOf(DocType.er))
      for (final t in d.er!.tables)
        if (!covered.contains('${d.id}/${t.id}')) (d, t.id, t.name),
  ];
}

// ======================= แผงซ้าย: รายการ endpoint =======================

/// แผงซ้ายของแท็บ API: endpoint จัดกลุ่ม · เพิ่ม · ตารางที่ยังไม่มี endpoint (สร้าง CRUD อัตโนมัติ)
class ApiLeftPanel extends StatelessWidget {
  const ApiLeftPanel({super.key, this.focusNode});

  /// โฟกัสของหน้าหลัก — คลิกในแผงแล้วดึงกลับมา คีย์ลัด (Delete/Ctrl+Z) จึงทำงานกับ endpoint ที่เลือก
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final a = context.watch<ApiController>();
    final w = context.watch<WorkspaceController>();
    final groups = <String, List<ApiEndpoint>>{};
    for (final e in a.api.endpoints) {
      groups.putIfAbsent(e.effectiveGroup, () => []).add(e);
    }
    final uncovered = uncoveredTables(w.workspace);

    return Listener(
      onPointerDown: (_) => focusNode?.requestFocus(),
      child: Material(
        color: C.surface,
        shape: Border(right: BorderSide(color: C.border)),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Endpoints',
                      style: TextStyle(fontWeight: FontWeight.w700, color: C.text),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('api-add'),
                    onPressed: a.active ? () => a.addEndpoint(path: '/') : null,
                    child: Text(tr('+ เพิ่ม')),
                  ),
                ],
              ),
            ),
            if (a.api.endpoints.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Text(tr('ยังไม่มี endpoint'), style: TextStyle(fontSize: 12.5, color: C.muted)),
              ),
            for (final g in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: Text(
                  [
                    if (g.key.isEmpty) tr('(ไม่มีกลุ่ม)') else g.key,
                    if (_groupTable(w.workspace, g.value) case final t?) tr('ผูกกับตาราง {0}', [t]) else tr('ไม่ผูกตาราง'),
                  ].join(' · '),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: C.muted),
                ),
              ),
              for (final e in g.value)
                Material(
                  color: a.selectedId == e.id ? C.primaryTint : Colors.transparent,
                  child: InkWell(
                    key: ValueKey('api-ep-${e.id}'),
                    onTap: () => a.select(e.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          ApiMethodChip(e.method),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              e.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: C.text),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
            if (uncovered.isNotEmpty) ...[
              Divider(height: 24, color: C.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                child: Text(
                  tr('ตารางที่ยังไม่มี endpoint'),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: C.muted),
                ),
              ),
              for (final (doc, tableId, name) in uncovered)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: Row(
                    children: [
                      DocTypeDot(DocType.er, size: 7),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: C.text),
                        ),
                      ),
                      TextButton(
                        key: ValueKey('api-crud-${doc.id}-$tableId'),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: a.active ? () => a.generateCrud(doc.id, doc.er!.tableById(tableId)!) : null,
                        child: Text(tr('สร้าง CRUD'), style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// ชื่อตารางเมื่อทุก endpoint ในกลุ่มผูกตารางเดียวกัน
  static String? _groupTable(Workspace w, List<ApiEndpoint> eps) {
    final refs = {for (final e in eps) e.table};
    if (refs.length != 1 || refs.first == null) return null;
    return apiTableName(w, refs.first);
  }
}

// ======================= กลาง: แก้ endpoint =======================

/// พื้นที่กลางของแท็บ API: แก้ endpoint ที่เลือก (method/path/ตาราง/ล็อกอิน/คำอธิบาย/request body/responses)
class ApiEditor extends StatefulWidget {
  const ApiEditor({super.key, this.focusNode});

  /// โฟกัสของหน้าหลัก — คลิกพื้นที่ว่างแล้วดึงกลับมา (ช่องกรอกยังรับโฟกัสของตัวเองตามปกติ)
  final FocusNode? focusNode;

  @override
  State<ApiEditor> createState() => _ApiEditorState();
}

class _ApiEditorState extends State<ApiEditor> {
  int? _status;

  @override
  Widget build(BuildContext context) {
    final a = context.watch<ApiController>();
    final w = context.watch<WorkspaceController>();
    final e = a.selected;
    if (e == null) {
      return Container(
        key: const ValueKey('api-editor-empty'),
        color: C.bg,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          a.api.endpoints.isEmpty
              ? tr('เพิ่ม endpoint จากแผงซ้าย หรือกด "สร้าง CRUD" ที่ตาราง ER')
              : tr('เลือก endpoint ทางซ้ายเพื่อแก้ไข'),
          textAlign: TextAlign.center,
          style: TextStyle(color: C.muted),
        ),
      );
    }
    final status = e.responses.any((r) => r.status == _status) ? _status : e.responses.firstOrNull?.status;
    final resp = e.responses.where((r) => r.status == status).firstOrNull;
    final ers = w.workspace.documentsOf(DocType.er).toList();
    final tables = [
      for (final d in ers)
        for (final t in d.er!.tables) ApiTableRef(docId: d.id, tableId: t.id),
    ];
    String tableLabel(ApiTableRef? r) {
      if (r == null) return tr('ไม่ผูกตาราง');
      final name = apiTableName(w.workspace, r) ?? '?';
      return ers.length > 1 ? '${w.workspace.documentById(r.docId)?.name ?? '?'} · $name' : name;
    }

    final head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: C.muted);
    return Listener(
      onPointerDown: (_) => widget.focusNode?.requestFocus(),
      child: Container(
        key: ValueKey('api-editor-${e.id}'),
        color: C.bg,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: C.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: C.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Dropdown<ApiMethod>(
                          key: const ValueKey('api-method'),
                          value: e.method,
                          items: ApiMethod.values,
                          labelOf: (m) => m.label,
                          onChanged: (m) => a.updateEndpoint(e.id, (x) => x.method = m),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CommitField(
                          key: ValueKey('api-path-${e.id}'),
                          value: e.path,
                          mono: true,
                          hint: '/orders/{id}',
                          onCommit: (v) => a.updateEndpoint(e.id, (x) => x.path = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 260,
                        child: Dropdown<ApiTableRef?>(
                          key: const ValueKey('api-table'),
                          value: e.table != null && tables.contains(e.table) ? e.table : null,
                          items: [null, ...tables],
                          labelOf: tableLabel,
                          onChanged: (r) => a.updateEndpoint(e.id, (x) => x.table = r),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            key: const ValueKey('api-auth'),
                            value: e.auth,
                            onChanged: (v) => a.updateEndpoint(e.id, (x) => x.auth = v),
                          ),
                          Text(tr('ต้องล็อกอิน'), style: TextStyle(fontSize: 13, color: C.text)),
                        ],
                      ),
                      SizedBox(
                        width: 160,
                        child: CommitField(
                          key: ValueKey('api-group-${e.id}'),
                          value: e.group,
                          hint: tr('กลุ่ม (ว่าง = จาก path)'),
                          onCommit: (v) => a.updateEndpoint(e.id, (x) => x.group = v.trim()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  CommitField(
                    key: ValueKey('api-summary-${e.id}'),
                    value: e.summary,
                    hint: tr('อธิบายว่า endpoint นี้ทำอะไร'),
                    minLines: 2,
                    maxLines: 4,
                    onCommit: (v) => a.updateEndpoint(e.id, (x) => x.summary = v.trim()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ---- Request body ----
            _Section(
              title: 'Request body',
              trailing: Wrap(
                spacing: 4,
                children: [
                  if (e.table != null)
                    TextButton(
                      key: const ValueKey('api-pull-fields'),
                      onPressed: () => a.pullFieldsFromTable(e.id),
                      child: Text(tr('ดึงฟิลด์จากคอลัมน์ ER'), style: const TextStyle(fontSize: 12.5)),
                    ),
                  TextButton(
                    key: const ValueKey('api-add-field'),
                    onPressed: () => a.addField(e.id),
                    child: Text(tr('+ ฟิลด์'), style: const TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
              child: e.fields.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        e.method.hasBody ? tr('ยังไม่มีฟิลด์') : tr('{0} ปกติไม่มี request body', [e.method.label]),
                        style: TextStyle(fontSize: 12.5, color: C.muted),
                      ),
                    )
                  : Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FixedColumnWidth(110),
                        2: FlexColumnWidth(2),
                        3: FixedColumnWidth(56),
                        4: FixedColumnWidth(36),
                      },
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(
                          children: [
                            for (final h in [tr('ฟิลด์'), tr('ชนิด'), tr('มาจาก'), tr('บังคับ'), ''])
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                                child: Text(h, style: head),
                              ),
                          ],
                        ),
                        for (final f in e.fields)
                          TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(2),
                                child: CommitField(
                                  key: ValueKey('api-field-name-${f.id}'),
                                  value: f.name,
                                  mono: true,
                                  onCommit: (v) => a.updateField(e.id, f.id, (x) => x.name = v.trim()),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(2),
                                child: Dropdown<ApiType>(
                                  key: ValueKey('api-field-type-${f.id}'),
                                  value: f.type,
                                  items: ApiType.values,
                                  labelOf: (t) => t.name,
                                  onChanged: (t) => a.updateField(e.id, f.id, (x) => x.type = t),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  _fieldSource(w.workspace, f),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, fontFamily: f.column == null ? null : 'monospace', color: C.muted),
                                ),
                              ),
                              Checkbox(
                                key: ValueKey('api-field-req-${f.id}'),
                                value: f.required,
                                onChanged: (v) => a.updateField(e.id, f.id, (x) => x.required = v ?? false),
                              ),
                              IconButton(
                                key: ValueKey('api-field-del-${f.id}'),
                                tooltip: tr('ลบฟิลด์'),
                                iconSize: 16,
                                visualDensity: VisualDensity.compact,
                                onPressed: () => a.removeField(e.id, f.id),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            // ---- Responses ----
            _Section(
              title: 'Responses',
              trailing: PopupMenuButton<int>(
                key: const ValueKey('api-add-response'),
                tooltip: tr('เพิ่ม response'),
                icon: const Icon(Icons.add_rounded, size: 18),
                onSelected: (s) {
                  a.addResponse(e.id, s);
                  setState(() => _status = s);
                },
                itemBuilder: (_) => [
                  for (final s in const [200, 201, 204, 400, 401, 403, 404, 409, 422, 500])
                    if (!e.responses.any((r) => r.status == s)) PopupMenuItem(value: s, height: 32, child: Text('$s')),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final r in e.responses)
                        ChoiceChip(
                          key: ValueKey('api-status-${r.status}'),
                          label: Text('${r.status}', style: const TextStyle(fontFamily: 'monospace')),
                          selected: r.status == status,
                          onSelected: (_) => setState(() => _status = r.status),
                        ),
                    ],
                  ),
                  if (resp != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: CommitField(
                            key: ValueKey('api-resp-desc-${e.id}-${resp.status}'),
                            value: resp.description,
                            hint: tr('คำอธิบาย response'),
                            onCommit: (v) => a.updateResponse(e.id, resp.status, (x) => x.description = v.trim()),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('api-resp-del'),
                          tooltip: tr('ลบ response นี้'),
                          onPressed: () => a.removeResponse(e.id, resp.status),
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    CommitField(
                      key: ValueKey('api-resp-example-${e.id}-${resp.status}'),
                      value: resp.example,
                      mono: true,
                      hint: tr('ตัวอย่าง body (JSON)'),
                      minLines: 4,
                      maxLines: 14,
                      onCommit: (v) => a.updateResponse(e.id, resp.status, (x) => x.example = v.trim()),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fieldSource(Workspace w, ApiField f) {
    final r = f.column;
    if (r == null) return tr('กำหนดเอง');
    final t = w.documentById(r.docId)?.er?.tableById(r.tableId);
    final c = t?.columnById(r.columnId ?? '');
    return t == null || c == null ? tr('(คอลัมน์ถูกลบ)') : '${t.name}.${c.name}';
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: C.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: C.border),
    ),
    padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w700, color: C.text),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    ),
  );
}

/// ไปที่วัตถุต้นทางที่เรียก endpoint (เส้น Screen Flow ไปที่เส้น ; อื่น ๆ ไปที่วัตถุ)
void _gotoCaller(BuildContext context, ProjectDocument src, String el) {
  if (src.screenflow?.edgeById(el) != null) {
    gotoScreenFlow(context, src.id, edge: el);
  } else {
    gotoNoteTarget(context, src.id, elementId: el);
  }
}

/// บันทึกเอกสาร OpenAPI 3.1 ของ [a] (JSON หรือ YAML) ลงไฟล์ที่ผู้ใช้เลือก
Future<void> exportOpenApiFile(BuildContext context, ApiController a, {bool yaml = false}) {
  final w = context.read<WorkspaceController>();
  final text = (yaml ? exportOpenApiYaml : exportOpenApiJson)(a.api, w: w.workspace, fallbackTitle: a.doc.name);
  final name = '${FileActions.safeName(a.doc.name)}.openapi.${yaml ? 'yaml' : 'json'}';
  return FileActions.saveText(context, text, name, tr('ส่งออก OpenAPI'));
}

// ======================= แผงขวา =======================

/// แผงขวาของแท็บ API: ข้อมูล API · endpoint ที่เลือก (ลบ/ทำสำเนา) · เรียกใช้จาก · ตรวจสอบ
class ApiRightPanel extends StatelessWidget {
  const ApiRightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final a = context.watch<ApiController>();
    final w = context.watch<WorkspaceController>();
    final e = a.selected;
    final all = validateApi(a.api, workspace: w.workspace, docId: a.docId);
    final issues = e == null
        ? [
            for (final i in all)
              if (i.tableId == null || a.api.endpointById(i.tableId!) == null) i,
          ]
        : [
            for (final i in all)
              if (i.tableId == e.id) i,
          ];
    final callers = e == null ? const <(String, String)>[] : [for (final u in w.usagesOf(a.docId, e.id)) (u.$1, u.$2)];
    final head = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.muted);

    return Material(
      color: C.surface,
      shape: Border(left: BorderSide(color: C.border)),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (e == null) ...[
            Text(tr('ข้อมูล API'), style: head),
            const SizedBox(height: 6),
            CommitField(
              key: const ValueKey('api-title'),
              label: tr('ชื่อ API'),
              value: a.api.title,
              onCommit: (v) => a.setInfo(title: v),
            ),
            const SizedBox(height: 6),
            CommitField(
              key: const ValueKey('api-version'),
              label: tr('รุ่น'),
              value: a.api.version,
              onCommit: (v) => a.setInfo(version: v),
            ),
            const SizedBox(height: 6),
            CommitField(
              key: const ValueKey('api-base'),
              label: 'Base URL',
              mono: true,
              value: a.api.baseUrl,
              onCommit: (v) => a.setInfo(baseUrl: v),
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: const ValueKey('api-export-openapi'),
              onPressed: () => exportOpenApiFile(context, a),
              child: Text(tr('ส่งออก OpenAPI…')),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              key: const ValueKey('api-export-openapi-yaml'),
              onPressed: () => exportOpenApiFile(context, a, yaml: true),
              child: Text(tr('ส่งออก OpenAPI แบบ YAML…')),
            ),
          ] else ...[
            Text(
              e.title,
              style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace', color: C.text),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                OutlinedButton(key: const ValueKey('api-dup'), onPressed: () => a.duplicateEndpoint(e.id), child: Text(tr('ทำสำเนา'))),
                OutlinedButton(
                  key: const ValueKey('api-delete'),
                  style: OutlinedButton.styleFrom(foregroundColor: C.danger),
                  onPressed: () => a.deleteEndpoint(e.id),
                  child: Text(tr('ลบ endpoint')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(tr('เรียกใช้จาก'), style: head),
            const SizedBox(height: 4),
            if (callers.isEmpty)
              Text(tr('ยังไม่มีเอกสารอื่นอ้างถึง endpoint นี้'), style: TextStyle(fontSize: 12.5, color: C.muted))
            else
              for (final (fromDoc, fromEl) in callers)
                if (w.workspace.documentById(fromDoc) case final src?)
                  InkWell(
                    key: ValueKey('api-caller-$fromDoc-$fromEl'),
                    onTap: () => _gotoCaller(context, src, fromEl),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          DocTypeDot(src.type, size: 7),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              [src.name, linkOriginTitle(src, fromEl)].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: C.text),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
          const SizedBox(height: 16),
          Text(tr('ตรวจสอบ'), style: head),
          const SizedBox(height: 4),
          if (issues.isEmpty)
            Text(
              tr('ไม่พบปัญหา'),
              key: const ValueKey('api-no-issues'),
              style: TextStyle(fontSize: 12.5, color: C.primaryDark),
            )
          else
            for (final i in issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: IssueCard(
                  issue: i,
                  onTap: i.tableId != null && a.api.endpointById(i.tableId!) != null ? () => a.select(i.tableId) : null,
                ),
              ),
        ],
      ),
    );
  }
}
