import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/models/wireframe_model.dart';
import '../../core/models/workspace.dart';
import '../../core/validate/issue.dart';
import '../../state/app_settings.dart';
import '../../state/wireframe_controller.dart';
import '../shortcuts.dart' show Cmd;
import '../theme.dart';
import 'wf_actions.dart';
import 'wf_library.dart';
import 'wf_panels.dart' show WireframeLeftPanel;
import '../../core/validate/wireframe_validator.dart' show wfKindLabel, wfStyleLabel;
import 'wf_view.dart' show wfKindShortcut;
import '../../state/doc_controller.dart';

/// ชิ้นส่วนที่อยู่ในแถบวางด่วนเสมอ (ช่องที่ 5 สลับตามที่ใช้ล่าสุด — ไม่ซ้ำกับสี่ตัวนี้ ; ไม่มีประวัติ = รูปภาพ)
const List<WfKind> kWfQuickKinds = [WfKind.label, WfKind.button, WfKind.input, WfKind.container];

/// ชิ้นส่วนทั้งห้าช่องของแถบวางด่วน (ใช้กับแถบเครื่องมือและเทสต์)
List<WfKind> wfQuickKinds(List<WfKind> recent) => [
      ...kWfQuickKinds,
      recent.firstWhere((k) => !kWfQuickKinds.contains(k), orElse: () => WfKind.image),
    ];

/// แถบเครื่องมือเต็มความกว้างเหนือแคนวาส Wireframe (Phase 18, ตามดีไซน์ "Wireframe Library Panel"):
/// [เลือก] · วางด่วน 5 ชิ้น + เพิ่มเติม · ร่าง/เรียบร้อย ······ ผลตรวจ · Snap · ส่งออกภาพ
/// ขนาดหน้าจอ/สีเน้นอยู่ที่แผงขวา (ตามที่ผู้ใช้เลือก) ; แคบ = ไอคอนอย่างเดียว ; ปานกลาง = ไม่มีป้ายคีย์ลัด
class WireframeToolbar extends StatelessWidget {
  const WireframeToolbar({super.key});

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, box) => _Body(compact: box.maxWidth < 1000, medium: box.maxWidth < 1500));
}

class _Body extends StatelessWidget {
  const _Body({required this.compact, required this.medium});
  final bool compact, medium;

  @override
  Widget build(BuildContext context) {
    final f = context.watchContentIdle<WireframeController>();
    final s = context.watch<AppSettings>();
    final dc = C.doc(DocType.wireframe);
    final problems = f.issues.where((i) => i.severity != Severity.info).length;
    final quick = wfQuickKinds(s.wfRecentKinds);

    Widget seg(String key, String label, Widget icon, bool on, VoidCallback onTap, {String? tip, String? shortcut, bool alwaysIcon = false}) => Tooltip(
          message: tip ?? label,
          child: InkWell(
            key: ValueKey(key),
            borderRadius: BorderRadius.circular(7),
            onTap: onTap,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: on ? C.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                boxShadow: on ? [BoxShadow(color: C.palette.shadow.withValues(alpha: 0.12), blurRadius: 2, offset: const Offset(0, 1))] : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                icon,
                if (!compact && !alwaysIcon) ...[
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w600 : FontWeight.w400, color: on ? dc.ink : C.text)),
                  if (shortcut != null && shortcut.isNotEmpty && !medium) ...[
                    const SizedBox(width: 5),
                    Text(shortcut, style: TextStyle(fontSize: 11, color: C.muted, fontFamily: kMono, fontFamilyFallback: const ['Consolas'])),
                  ],
                ],
              ]),
            ),
          ),
        );

    Widget group(List<Widget> children) => Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: C.field, borderRadius: BorderRadius.circular(9)),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        );

    Widget kindBtn(WfKind k) {
      final on = f.tool == WfTool.place && f.toolBlock == null && f.toolKind == k;
      final sc = wfKindShortcut(k);
      return seg('wf-tool-${k.name}', wfKindLabel(k), WfKindThumb(k, width: 22, height: 14, color: on ? dc.ink : C.muted), on,
          () => f.setPlaceTool(k),
          tip: sc.isEmpty ? wfKindLabel(k) : '${wfKindLabel(k)} ($sc)', shortcut: sc);
    }

    final ok = problems == 0;
    final rules = Tooltip(
      message: ok ? tr('ตรวจหน้าจอแล้วไม่พบปัญหา') : tr('ดูปัญหาในหน้าจอนี้'),
      child: InkWell(
        key: const ValueKey('wf-rules'),
        borderRadius: BorderRadius.circular(11),
        onTap: f.clearSelection, // ไม่ได้เลือกอะไร = แผงขวาแสดงผลตรวจ
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: ok ? C.primaryTint : C.palette.warnBg, borderRadius: BorderRadius.circular(11)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ok ? Icons.check_rounded : Icons.warning_amber_rounded, size: 13, color: ok ? C.primaryDark : C.palette.warnText),
            const SizedBox(width: 4),
            Text(
              ok ? (compact || medium ? tr('ผ่าน') : tr('ไม่พบปัญหา')) : tr('{0} ปัญหา', [problems]),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: ok ? C.primaryDark : C.palette.warnText),
            ),
          ]),
        ),
      ),
    );

    final snap = Tooltip(
      message: tr('จัดแนวตามตาราง (Snap) — กด Alt ค้างตอนลากเพื่อข้ามชั่วคราว'),
      child: InkWell(
        key: const ValueKey('wf-snap'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => s.setSnapToGrid(!s.snapToGrid),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: s.snapToGrid ? C.primaryTint : null, borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.grid_4x4_rounded, size: 15, color: s.snapToGrid ? C.primaryDark : C.muted),
            if (!compact && !medium) ...[
              const SizedBox(width: 5),
              Text('Snap', style: TextStyle(fontSize: 12, color: s.snapToGrid ? C.primaryDark : C.text)),
            ],
          ]),
        ),
      ),
    );

    final export = Tooltip(
      message: tr('Export ภาพ PNG / SVG'),
      child: Material(
        color: dc.main,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: const ValueKey('wf-export'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => WireframeActions(context).run(Cmd.exportImage),
          child: SizedBox(
            height: 30,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.image_outlined, size: 15, color: Colors.white),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(tr('ส่งออกภาพ'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );

    final more = Tooltip(
      message: tr('คลังชิ้นส่วนทั้งหมด — ไปที่ช่องค้นหาทางซ้าย'),
      child: InkWell(
        key: const ValueKey('wf-more'),
        borderRadius: BorderRadius.circular(8),
        onTap: WireframeLeftPanel.focusSearch,
        child: Container(
          height: 30,
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
          decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.widgets_outlined, size: 15, color: C.muted),
            if (!compact) ...[
              const SizedBox(width: 6),
              Text(tr('เพิ่มเติม'), style: const TextStyle(fontSize: 12)),
            ],
          ]),
        ),
      ),
    );

    final style = f.diagram.style;
    return Container(
      key: const ValueKey('wf-toolbar'),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: C.surface, border: Border(bottom: BorderSide(color: C.borderSoft))),
      child: Row(children: [
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              group([
                seg('wf-tool-pointer', tr('เลือก'), Icon(Icons.near_me_outlined, size: 15, color: f.tool == WfTool.select ? dc.ink : C.muted),
                    f.tool == WfTool.select, () => f.setTool(WfTool.select)),
              ]),
              Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 8), color: C.border),
              group([for (final k in quick) kindBtn(k)]),
              const SizedBox(width: 6),
              more,
              Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 8), color: C.border),
              group([
                seg('wf-style-sketch', wfStyleLabel(WfStyle.sketch), Icon(Icons.gesture_rounded, size: 15, color: style == WfStyle.sketch ? dc.ink : C.muted),
                    style == WfStyle.sketch, () => f.setStyle(WfStyle.sketch),
                    alwaysIcon: medium),
                const SizedBox(width: 2),
                seg('wf-style-clean', wfStyleLabel(WfStyle.clean),
                    Icon(Icons.auto_awesome_mosaic_outlined, size: 15, color: style == WfStyle.clean ? dc.ink : C.muted),
                    style == WfStyle.clean, () => f.setStyle(WfStyle.clean),
                    alwaysIcon: medium),
              ]),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        rules,
        const SizedBox(width: 6),
        snap,
        const SizedBox(width: 6),
        export,
      ]),
    );
  }
}
