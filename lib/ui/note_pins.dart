import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n/l10n.dart';
import '../core/models/review_note.dart';
import '../state/doc_controller.dart';
import '../state/workspace_controller.dart';
import 'notes_panel.dart' show NoteText, noteKindLabel, notePinNumber;
import 'theme.dart';

/// เส้นผ่านศูนย์กลางของหมุดโน้ต (พิกเซลจอ — ไม่ย่อ/ขยายตามซูม)
const double kNotePinSize = 22;

/// สีของหมุดตามชนิด (เสร็จแล้ว = สีจาง)
Color notePinColor(ReviewNote n) {
  if (n.done) return C.muted;
  return switch (n.kind) {
    NoteKind.todo => C.primary,
    NoteKind.question => C.warnText,
    NoteKind.memo => C.muted,
  };
}

/// ชั้นหมุดโน้ตบนแคนวาส — ใช้ร่วมกันทุกชนิดเอกสาร (ER / DFD / Flowchart / Wireframe / Screen Flow)
/// วางเป็นลูกของ Stack ของแคนวาส ต่อจากพื้นที่วาด (ก่อนแถบเครื่องมือ) ; พื้นที่ว่างไม่รับการคลิก (แคนวาสใต้ยังใช้ได้)
/// - หมุดแต่ละอัน: คลิก = เปิด/ปิดการ์ดโน้ต, ลาก = ย้าย (undo ขั้นเดียว)
/// - ขณะมีคำขอปักหมุด ([WorkspaceController.pinRequest]): คลิกที่ใดบนแคนวาส = ปักหมุดตรงนั้น ; Esc/ปุ่มยกเลิก = เลิก
class NotePinsLayer extends StatefulWidget {
  const NotePinsLayer({super.key, required this.doc, required this.view, required this.scale, required this.offset});

  final DocController doc;

  /// แจ้งเมื่อมุมมอง (เลื่อน/ซูม) เปลี่ยน
  final Listenable view;
  final double Function() scale;
  final Offset Function() offset;

  @override
  State<NotePinsLayer> createState() => _NotePinsLayerState();
}

class _NotePinsLayerState extends State<NotePinsLayer> {
  String? _openId;
  Offset? _dragStart;
  Offset? _dragWorld;

  Offset _toScreen(double x, double y) => Offset(x, y) * widget.scale() + widget.offset();
  Offset _toWorld(Offset s) => (s - widget.offset()) / widget.scale();

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    return ListenableBuilder(
      listenable: Listenable.merge([widget.doc, widget.view]),
      builder: (context, _) {
        final req = w.pinRequest;
        final children = <Widget>[];
        if (req != null && req.docId == widget.doc.docId) {
          children.add(
            Positioned.fill(
              // Esc ยกเลิกผ่านคีย์ลัดระดับแอป (Cmd.escape ใน AppActions) — โฟกัสคีย์บอร์ดอยู่ที่หน้าหลัก
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                child: GestureDetector(
                  key: const ValueKey('note-pin-target'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final p = _toWorld(d.localPosition);
                    w.completePinRequest(widget.doc, p.dx, p.dy);
                  },
                  child: ColoredBox(color: C.primary.withValues(alpha: 0.04)),
                ),
              ),
            ),
          );
          children.add(
            Positioned(
              top: 64,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: C.palette.text,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tr('คลิกบนแคนวาสเพื่อปักหมุดโน้ต · Esc ยกเลิก'), style: TextStyle(fontSize: 12.5, color: C.surface)),
                        const SizedBox(width: 6),
                        TextButton(
                          key: const ValueKey('note-pin-cancel'),
                          style: TextButton.styleFrom(foregroundColor: C.surface, visualDensity: VisualDensity.compact),
                          onPressed: w.cancelPinRequest,
                          child: Text(tr('ยกเลิก')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        if (w.notePinsVisible) {
          for (final n in widget.doc.reviewNotes) {
            if (!n.pinned) continue;
            final p = _toScreen(n.x!, n.y!);
            children.add(Positioned(left: p.dx - kNotePinSize / 2, top: p.dy - kNotePinSize / 2, child: _pin(n)));
            if (_openId == n.id) {
              children.add(Positioned(left: p.dx + kNotePinSize / 2 + 6, top: p.dy - 10, child: _card(n)));
            }
          }
        }
        return Stack(clipBehavior: Clip.none, children: children);
      },
    );
  }

  Widget _pin(ReviewNote n) {
    final num = notePinNumber(widget.doc.doc, n.id) ?? 0;
    final color = notePinColor(n);
    return Tooltip(
      message: n.text,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: GestureDetector(
          key: ValueKey('note-pin-${n.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _openId = _openId == n.id ? null : n.id),
          onPanStart: (d) {
            _dragStart = d.globalPosition;
            _dragWorld = Offset(n.x!, n.y!);
            widget.doc.beginGesture();
          },
          onPanUpdate: (d) {
            final start = _dragStart, origin = _dragWorld;
            if (start == null || origin == null) return;
            final p = origin + (d.globalPosition - start) / widget.scale();
            widget.doc.moveReviewNote(n.id, p.dx, p.dy);
          },
          onPanEnd: (_) => _endDrag(),
          onPanCancel: _endDrag,
          child: Container(
            width: kNotePinSize,
            height: kNotePinSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: C.surface, width: 2),
              boxShadow: C.shadowSm,
            ),
            child: n.done
                ? Icon(Icons.check_rounded, size: 13, color: C.surface)
                : Text(
                    '$num',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.surface),
                  ),
          ),
        ),
      ),
    );
  }

  void _endDrag() {
    _dragStart = null;
    _dragWorld = null;
    widget.doc.endGesture();
  }

  Widget _card(ReviewNote n) {
    final c = widget.doc;
    return Material(
      key: ValueKey('note-card-${n.id}'),
      color: C.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 240,
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: notePinColor(n), width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  noteKindLabel(n.kind),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: notePinColor(n)),
                ),
                const Spacer(),
                if (n.kind != NoteKind.memo)
                  Tooltip(
                    message: tr('ทำเสร็จแล้ว'),
                    child: Checkbox(
                      key: ValueKey('note-card-done-${n.id}'),
                      value: n.done,
                      visualDensity: VisualDensity.compact,
                      onChanged: (_) => c.toggleReviewNoteDone(n.id),
                    ),
                  ),
                IconButton(
                  key: ValueKey('note-card-close-${n.id}'),
                  tooltip: tr('ปิด'),
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: () => setState(() => _openId = null),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            NoteText(note: n, docId: c.docId),
            const SizedBox(height: 6),
            Wrap(
              children: [
                TextButton(
                  key: ValueKey('note-card-unpin-${n.id}'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: () {
                    setState(() => _openId = null);
                    c.moveReviewNote(n.id, null, null);
                  },
                  child: Text(tr('ถอดหมุด'), style: const TextStyle(fontSize: 12)),
                ),
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: () => context.read<WorkspaceController>().showNotesPanel(true),
                  child: Text(tr('เปิดแผงโน้ต'), style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
