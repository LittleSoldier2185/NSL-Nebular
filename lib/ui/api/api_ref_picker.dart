import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/models/api_model.dart';
import '../../core/models/api_ref.dart';
import '../../core/models/workspace.dart';
import '../../core/validate/api_ref_check.dart';
import '../../state/workspace_controller.dart';
import '../theme.dart';
import 'api_view.dart' show ApiMethodChip;

/// endpoint ทุกอันในโปรเจกต์ (ตามลำดับเอกสาร API แล้วลำดับ endpoint)
List<(ProjectDocument doc, ApiEndpoint e)> allEndpoints(Workspace w) => [
      for (final d in w.documentsOf(DocType.api))
        for (final e in d.api!.endpoints) (d, e),
    ];

/// ส่วน "เรียก API" ในแผงขวาของเอกสารอื่น: เลือก endpoint ที่วัตถุนี้เรียก (หรือไม่เรียก) + ปุ่มไปที่ endpoint
/// ลิงก์ที่ขาด (endpoint/เอกสารถูกลบ) แสดงเป็นคำเตือน และเลือกใหม่ได้
class ApiRefPicker extends StatelessWidget {
  const ApiRefPicker({super.key, required this.value, required this.onChanged});

  final ApiRef? value;
  final ValueChanged<ApiRef?> onChanged;

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final eps = allEndpoints(w.workspace);
    final multi = w.workspace.documentsOf(DocType.api).length > 1;
    final problem = value == null ? null : apiRefProblem(w.workspace, value!);
    final head = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.muted);

    return Column(key: const ValueKey('api-ref-picker'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('เรียก API'), style: head),
      const SizedBox(height: 4),
      if (eps.isEmpty && value == null)
        Text(tr('ยังไม่มีเอกสาร API — เพิ่มเอกสาร API ก่อนจึงผูก endpoint ได้'), style: TextStyle(fontSize: 12, color: C.muted))
      else
        DropdownButtonFormField<ApiRef?>(
          key: const ValueKey('api-ref-dropdown'),
          initialValue: problem == null ? value : null,
          isExpanded: true,
          isDense: true,
          decoration: const InputDecoration(isDense: true),
          items: [
            DropdownMenuItem(value: null, child: Text(tr('ไม่เรียก API'), style: const TextStyle(fontSize: 13))),
            for (final (d, e) in eps)
              DropdownMenuItem(
                value: ApiRef(docId: d.id, endpointId: e.id),
                child: Row(children: [
                  ApiMethodChip(e.method, width: 50),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(multi ? '${e.path} · ${d.name}' : e.path,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace')),
                  ),
                ]),
              ),
          ],
          onChanged: onChanged,
        ),
      if (problem != null) ...[
        const SizedBox(height: 4),
        Text(problem, key: const ValueKey('api-ref-broken'), style: TextStyle(fontSize: 12, color: C.dangerText)),
      ] else if (value != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('api-ref-goto'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
            onPressed: () {
              if (w.openDocument(value!.docId)) w.apiController(value!.docId)?.select(value!.endpointId);
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 14),
            label: Text(tr('ไปที่ endpoint'), style: const TextStyle(fontSize: 12)),
          ),
        ),
    ]);
  }
}
