import 'package:flutter/material.dart';

import 'shortcuts.dart';
import 'whats_new_dialog.dart';
import 'theme.dart';
import '../core/l10n/l10n.dart';

/// หน้า "ดูคีย์ลัดทั้งหมด" (F1 หรือ ?) — อ่านจาก [kShortcuts] ชุดเดียวกับตัวดักปุ่มจริง จึงไม่หลุดจากความจริง
Future<void> showShortcutsHelp(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const ShortcutsHelpDialog(),
    );

class ShortcutsHelpDialog extends StatelessWidget {
  const ShortcutsHelpDialog({super.key});

  static const groupOrder = ['ไฟล์', 'แก้ไข', 'Canvas', 'DFD', 'Flowchart', 'Wireframe', 'Screen Flow', 'มุมมอง', 'เครื่องมือ', 'ทั่วไป'];

  @override
  Widget build(BuildContext context) {
    final items = visibleShortcuts;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const HelpTabs(current: 0),
            const SizedBox(height: 10),
            Text(tr('คีย์ลัดทั้งหมด'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(tr('คีย์ที่เป็นตัวอักษรเดี่ยว/ลูกศร/Delete จะไม่ทำงานขณะพิมพ์ในช่องข้อความ'),
                style: TextStyle(fontSize: 12.5, color: C.muted)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(spacing: 28, runSpacing: 16, children: [
                  for (final g in groupOrder)
                    SizedBox(
                      width: 360,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr(g), style: TextStyle(fontWeight: FontWeight.w600, color: C.primaryDark)),
                        const SizedBox(height: 6),
                        for (final s in items.where((x) => x.group == g)) _row(s),
                      ]),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('ปิด'))),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(ShortcutDef s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(tr(s.label), style: const TextStyle(fontSize: 13))),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(5)),
            child: Text(tr(s.keys), style: monoStyle.copyWith(fontSize: 11.5, color: C.text)),
          ),
        ]),
      );
}

/// แถบสลับ "ศูนย์ช่วยเหลือ" (คีย์ลัด / มีอะไรใหม่ / เกี่ยวกับ) — Phase 21 ข้อ 8 ; กดแล้วปิดกล่องนี้และเปิดแท็บที่เลือก
class HelpTabs extends StatelessWidget {
  const HelpTabs({super.key, required this.current});

  /// 0 = คีย์ลัด, 1 = มีอะไรใหม่, 2 = เกี่ยวกับ
  final int current;

  @override
  Widget build(BuildContext context) {
    final names = [tr('คีย์ลัด'), tr('มีอะไรใหม่'), tr('เกี่ยวกับ')];
    return Wrap(runSpacing: 6, children: [
      for (var i = 0; i < names.length; i++)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InkWell(
            key: ValueKey('help-tab-$i'),
            borderRadius: BorderRadius.circular(99),
            onTap: i == current
                ? null
                : () {
                    final nav = Navigator.of(context);
                    final host = nav.context;
                    nav.pop();
                    switch (i) {
                      case 0:
                        showShortcutsHelp(host);
                      case 1:
                        showWhatsNew(host);
                      default:
                        showAbout(host);
                    }
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: i == current ? C.primaryTint : null,
                border: Border.all(color: i == current ? C.primary : C.border),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(names[i], style: TextStyle(fontSize: 12.5, fontWeight: i == current ? FontWeight.w600 : FontWeight.w400, color: i == current ? C.primaryDark : C.text)),
            ),
          ),
        ),
    ]);
  }
}
