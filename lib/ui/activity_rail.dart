import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../core/models/workspace.dart';
import '../state/workspace_controller.dart';
import 'document_actions.dart' show docTypeIcon;
import 'theme.dart';

/// ความกว้างของแถบไอคอนชนิดเอกสาร (ตามดีไซน์ NSL Nebular)
const double kActivityRailWidth = 52;

/// ชนิดเอกสารที่มีปุ่มในแถบ เรียงตามดีไซน์
const _railTypes = [DocType.er, DocType.dfd, DocType.flowchart, DocType.wireframe, DocType.screenflow];

String _typeLabel(DocType t) => switch (t) {
      DocType.er => tr('ER Diagram (ตารางฐานข้อมูล)'),
      DocType.dfd => tr('DFD (Data Flow Diagram)'),
      DocType.flowchart => tr('Flowchart (ผังงาน)'),
      DocType.wireframe => tr('Wireframe (หน้าจอ)'),
      DocType.screenflow => tr('Screen Flow (ลำดับหน้าจอ)'),
    };

/// แถบไอคอนชนิดเอกสารด้านซ้ายสุด: กด = ไปที่เอกสารชนิดนั้น (เอกสารที่เปิดอยู่ล่าสุดของชนิดนั้น ไม่มี = เอกสารแรกของชนิดนั้น
/// ไม่มีเลย = สร้างใหม่) ; ปุ่มของชนิดที่กำลังเปิดอยู่ไฮไลต์ด้วยสีประจำชนิด
class ActivityRail extends StatelessWidget {
  const ActivityRail({super.key});

  /// เอกสารปลายทางของปุ่มชนิด [t]: ถ้าเอกสารที่เปิดอยู่เป็นชนิดนี้อยู่แล้วคืนตัวนั้น ไม่งั้นแท็บชนิดนี้อันแรกที่เปิดอยู่ ไม่งั้นเอกสารแรกของชนิดนี้
  @visibleForTesting
  static String? targetFor(WorkspaceController w, DocType t) {
    if (w.activeDocument.type == t) return w.activeDocument.id;
    for (final d in w.tabDocuments) {
      if (d.type == t) return d.id;
    }
    for (final d in w.documents) {
      if (d.type == t) return d.id;
    }
    return null;
  }

  static void go(WorkspaceController w, DocType t) {
    final id = targetFor(w, t);
    if (id != null) {
      w.openDocument(id);
    } else {
      w.addDocument(t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    final active = w.homeView ? null : w.activeDocument.type;
    return Container(
      key: const ValueKey('activity-rail'),
      width: kActivityRailWidth,
      decoration: BoxDecoration(
        color: C.surface,
        border: Border(right: BorderSide(color: C.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(children: [
        for (final t in _railTypes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _RailButton(
              key: ValueKey('rail-${t.name}'),
              type: t,
              active: active == t,
              count: w.documents.where((d) => d.type == t).length,
              onTap: () => go(w, t),
            ),
          ),
      ]),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({super.key, required this.type, required this.active, required this.count, required this.onTap});

  final DocType type;
  final bool active;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dc = C.doc(type);
    return Tooltip(
      message: count == 0 ? '${_typeLabel(type)} — ${tr('สร้างใหม่')}' : '${_typeLabel(type)} · $count',
      child: Semantics(
        button: true,
        selected: active,
        label: _typeLabel(type),
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: active ? dc.tint : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              // แถบสีด้านซ้ายของปุ่มที่เปิดอยู่ (ตามดีไซน์)
              border: Border(left: BorderSide(color: active ? dc.main : Colors.transparent, width: 3)),
            ),
            child: Icon(docTypeIcon(type), size: 20, color: active ? dc.ink : dc.ink.withValues(alpha: 0.85)),
          ),
        ),
      ),
    );
  }
}
