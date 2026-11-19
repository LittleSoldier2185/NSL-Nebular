import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/export/workspace_summary.dart' show screensLinkingTo;
import '../../core/l10n/l10n.dart';
import '../../core/layout/box_ops.dart';
import '../../core/models/wireframe_model.dart';
import '../../core/validate/wireframe_validator.dart';
import '../../state/wireframe_controller.dart';
import '../../state/workspace_controller.dart';
import '../canvas/canvas_chrome.dart';
import '../issue_widgets.dart';
import '../prompt_dialog.dart';
import '../theme.dart';
import '../widgets.dart';
import 'wf_actions.dart';
import 'wf_painter.dart';
import 'wf_view.dart';
import '../api/api_ref_picker.dart';

/// แผงซ้ายของแท็บ Wireframe: คลังชิ้นส่วน (ค้นได้ คลิก = เลือกเครื่องมือ / ลากไปวาง) ; รายการชิ้นส่วนบนหน้าจอ (เลเยอร์) อยู่ล่างสุดของแผงขวา
class WireframeLeftPanel extends StatefulWidget {
  const WireframeLeftPanel({super.key});

  @override
  State<WireframeLeftPanel> createState() => _WireframeLeftPanelState();
}

class _WireframeLeftPanelState extends State<WireframeLeftPanel> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    context.watch<WireframeController>(); // วาดใหม่เมื่อคลังเปลี่ยน
    final w = context.watch<WorkspaceController>();
    final q = _q.trim().toLowerCase();
    bool match(String s) => q.isEmpty || s.toLowerCase().contains(q);
    final kinds = [for (final k in kWfLibraryKinds) if (match('${wfKindLabel(k)} ${k.name}')) k];
    Widget section(String title, int n) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
            TextSpan(text: ' ($n)', style: TextStyle(color: C.muted, fontSize: 12.5)),
          ])),
        );

    return Container(
      decoration: BoxDecoration(border: Border(right: BorderSide(color: C.border))),
      child: Material(
        color: C.surface,
        child: ListView(padding: EdgeInsets.zero, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Text(w.activeDocument.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: SizedBox(
              height: kFieldHeight,
              child: TextField(
                key: const ValueKey('wf-search'),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr('ค้นหาชิ้นส่วน'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 16),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          ),
          section(tr('คลังชิ้นส่วน'), kinds.length),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
            child: Wrap(spacing: 6, runSpacing: 6, children: [for (final k in kinds) _KindTile(kind: k)]),
          ),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

/// ช่องหนึ่งในคลังชิ้นส่วน: ไอคอน + ชื่อ — คลิก = เลือกเครื่องมือ, ลากไปวางบนแคนวาสได้
class _KindTile extends StatelessWidget {
  const _KindTile({required this.kind});
  final WfKind kind;

  @override
  Widget build(BuildContext context) {
    final f = context.watch<WireframeController>();
    final on = f.tool == WfTool.place && f.toolKind == kind;
    final k = wfKindShortcut(kind);
    final tile = Container(
      width: 74,
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      decoration: BoxDecoration(
        color: on ? C.primaryTint : C.bg,
        border: Border.all(color: on ? C.primary : C.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(wfKindIcon(kind), size: 18, color: on ? C.primaryDark : C.muted),
        const SizedBox(height: 3),
        Text(wfKindLabel(kind),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: on ? C.primaryDark : C.text)),
      ]),
    );
    return Tooltip(
      message: k.isEmpty ? wfKindLabel(kind) : '${wfKindLabel(kind)} ($k)',
      child: Draggable<Object>(
        data: kind,
        feedback: Material(color: Colors.transparent, child: Opacity(opacity: 0.8, child: tile)),
        child: InkWell(
          key: ValueKey('wf-kind-${kind.name}'),
          borderRadius: BorderRadius.circular(6),
          onTap: () => f.setPlaceTool(kind),
          child: tile,
        ),
      ),
    );
  }
}

/// แผงขวาของแท็บ Wireframe: คุณสมบัติชิ้นที่เลือก / จัดแนวหลายชิ้น / ตั้งค่าหน้าจอ + ผลตรวจเมื่อไม่ได้เลือกอะไร
class WireframeRightPanel extends StatelessWidget {
  const WireframeRightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final f = context.watch<WireframeController>();
    context.watch<WorkspaceController>();
    final sel = f.selectedBox;
    final Widget body;
    if (sel != null) {
      body = Padding(padding: const EdgeInsets.all(16), child: _ComponentProps(c: sel));
    } else if (f.selectedIds.length > 1) {
      body = Padding(padding: const EdgeInsets.all(16), child: _MultiProps(ids: f.selectedIds));
    } else {
      body = const _PageProps();
    }
    // สูงเต็มคอลัมน์เสมอ (ไม่ใช่แค่ความสูงเนื้อหา) ; เลเยอร์อยู่ล่างสุดทุกสถานะ
    return SizedBox.expand(
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: C.border))),
        child: Material(
          color: C.surface,
          // ส่วนบน (หัว+คุณสมบัติ) เลื่อนเอง ; เลเยอร์ติดอยู่ล่างแผงและเลื่อนแยก — เลือกชิ้นแล้วรายการเลเยอร์ไม่กระโดด
          child: LayoutBuilder(
            builder: (context, box) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const _PanelHeader(), body]),
                ),
              ),
              _LayersFold(key: const ValueKey('wf-layers'), maxHeight: box.maxHeight),
            ]),
          ),
        ),
      ),
    );
  }
}

Widget _toggle(String key, IconData icon, String tip, bool on, VoidCallback tap) => IconButton(
      key: ValueKey(key),
      tooltip: tip,
      isSelected: on,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(backgroundColor: on ? C.primaryTint : null),
      icon: Icon(icon, size: 18, color: on ? C.primaryDark : C.muted),
      onPressed: tap,
    );

Widget _check(String key, String label, bool value, ValueChanged<bool> onChanged) => CheckboxListTile(
      key: ValueKey(key),
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: VisualDensity.compact,
      controlAffinity: ListTileControlAffinity.leading,
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      title: Text(label, style: const TextStyle(fontSize: 13)),
    );

/// ช่องตัวเลข (บันทึกตอน Enter/ออกจากช่อง) ; ค่าที่อ่านไม่ได้ถูกเมิน
Widget _numField(String key, String label, double value, ValueChanged<double> onCommit) => Expanded(
      child: CommitField(
        key: ValueKey('$key-${value.round()}'),
        label: label,
        value: '${value.round()}',
        onCommit: (v) {
          final n = double.tryParse(v.trim());
          if (n != null && n.isFinite) onCommit(n);
        },
      ),
    );

class _StyleSection extends StatelessWidget {
  const _StyleSection({required this.ids, required this.sample});
  final Set<String> ids;
  final WfComponent sample;

  @override
  Widget build(BuildContext context) {
    final f = context.read<WireframeController>();
    final a = WireframeActions(context);
    const sizes = [10.0, 11.0, 12.0, 13.0, 14.0, 16.0, 18.0, 20.0, 22.0, 24.0, 28.0, 32.0, 40.0];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LabeledField(
        label: tr('ตัวอักษร'),
        child: Row(children: [
          SizedBox(
            width: 92,
            child: KeyedSubtree(
              key: const ValueKey('wf-font-size'),
              child: Dropdown<double>(
                value: sample.fontSize != null && sizes.contains(sample.fontSize) ? sample.fontSize! : 0,
                items: const [0, ...sizes],
                labelOf: (v) => v == 0 ? tr('อัตโนมัติ') : v.toStringAsFixed(0),
                onChanged: (v) => f.updateComponents(ids, (c) => c.fontSize = v == 0 ? null : v),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _toggle('wf-bold', Icons.format_bold_rounded, tr('ตัวหนา'), sample.bold, () => f.updateComponents(ids, (c) => c.bold = !sample.bold)),
          _toggle('wf-align-left', Icons.format_align_left_rounded, tr('ชิดซ้าย'), sample.align == WfAlign.left,
              () => f.updateComponents(ids, (c) => c.align = WfAlign.left)),
          _toggle('wf-align-center', Icons.format_align_center_rounded, tr('กึ่งกลาง'), sample.align == WfAlign.center,
              () => f.updateComponents(ids, (c) => c.align = WfAlign.center)),
          _toggle('wf-align-right', Icons.format_align_right_rounded, tr('ชิดขวา'), sample.align == WfAlign.right,
              () => f.updateComponents(ids, (c) => c.align = WfAlign.right)),
        ]),
      ),
      const SizedBox(height: 12),
      LabeledField(
        label: tr('สีพื้น'),
        child: ColorSwatchRow(
          keyPrefix: 'wf-fill',
          palette: kWfPalette,
          current: sample.fill,
          onPick: (v) => f.updateComponents(ids, (c) => c.fill = v),
          onCustom: () => a.pickColor(ids, which: 'fill', current: sample.fill),
        ),
      ),
      const SizedBox(height: 12),
      LabeledField(
        label: tr('สีเส้นขอบ'),
        child: ColorSwatchRow(
          keyPrefix: 'wf-stroke',
          palette: kWfPalette,
          current: sample.stroke,
          onPick: (v) => f.updateComponents(ids, (c) => c.stroke = v),
          onCustom: () => a.pickColor(ids, which: 'stroke', current: sample.stroke),
        ),
      ),
      const SizedBox(height: 12),
      LabeledField(
        label: tr('สีตัวอักษร'),
        child: ColorSwatchRow(
          keyPrefix: 'wf-text',
          palette: kWfPalette,
          current: sample.textColor,
          onPick: (v) => f.updateComponents(ids, (c) => c.textColor = v),
          onCustom: () => a.pickColor(ids, which: 'text', current: sample.textColor),
        ),
      ),
      if (f.diagram.style == WfStyle.sketch) ...[
        const SizedBox(height: 6),
        Text(tr('แบบร่างแสดงสีเป็นโทนเทา'), style: TextStyle(fontSize: 11.5, color: C.muted)),
      ],
      const SizedBox(height: 10),
      _check('wf-disabled', tr('ใช้งานไม่ได้ (disabled)'), sample.disabled, (v) => f.updateComponents(ids, (c) => c.disabled = v)),
    ]);
  }
}

class _ComponentProps extends StatelessWidget {
  const _ComponentProps({required this.c});
  final WfComponent c;

  @override
  Widget build(BuildContext context) {
    final f = context.read<WireframeController>();
    final w = context.read<WorkspaceController>().workspace;
    final a = WireframeActions(context);
    final ref = c.ref;
    final refProblem = ref == null ? null : wfRefProblem(w, ref);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(wfKindIcon(c.kind), size: 18, color: C.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(wfKindLabel(c.kind), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
        IconButton(
          key: const ValueKey('wf-delete'),
          tooltip: tr('ลบชิ้นส่วน'),
          icon: Icon(Icons.delete_outline, color: C.danger, size: 20),
          onPressed: f.deleteSelection,
        ),
      ]),
      const SizedBox(height: 10),
      LabeledField(
        label: tr('ชนิด'),
        child: KeyedSubtree(
          key: const ValueKey('wf-kind'),
          child: Dropdown<WfKind>(
            value: c.kind,
            items: WfKind.values,
            labelOf: wfKindLabel,
            onChanged: (k) => f.updateComponents([c.id], (x) => x.kind = k),
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (c.kind == WfKind.table) ...[
        CommitField(
          key: ValueKey('wf-columns-${c.id}-${c.columns.join('|')}'),
          label: tr('หัวคอลัมน์ (บรรทัดละคอลัมน์)'),
          value: c.columns.join('\n'),
          minLines: 3,
          maxLines: 8,
          onCommit: (v) => f.setColumns(c.id, [for (final l in v.split('\n')) if (l.trim().isNotEmpty) l.trim()]),
        ),
        const SizedBox(height: 12),
      ] else ...[
        CommitField(
          key: ValueKey('wf-text-${c.id}-${c.text}'),
          label: wfMultiline(c.kind) ? tr('ข้อความ (บรรทัดละรายการ)') : tr('ข้อความ'),
          value: c.text,
          minLines: wfMultiline(c.kind) ? 3 : null,
          maxLines: wfMultiline(c.kind) ? 8 : null,
          onCommit: (v) => f.setText(c.id, v),
        ),
        const SizedBox(height: 12),
      ],
      if (c.kind == WfKind.table || c.kind == WfKind.list) ...[
        LabeledField(
          label: tr('จำนวนแถวตัวอย่าง'),
          child: KeyedSubtree(
            key: const ValueKey('wf-rows'),
            child: Dropdown<int>(
              value: c.rows.clamp(0, 12),
              items: const [0, 1, 2, 3, 4, 5, 6, 8, 10, 12],
              labelOf: (v) => '$v',
              onChanged: (v) => f.updateComponents([c.id], (x) => x.rows = v),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
      if (c.kind == WfKind.button) _check('wf-secondary', tr('ปุ่มรอง (secondary)'), c.secondary, (v) => f.updateComponents([c.id], (x) => x.secondary = v)),
      if (kWfCheckableKinds.contains(c.kind)) _check('wf-checked', tr('เลือกอยู่ (checked / on)'), c.checked, (v) => f.updateComponents([c.id], (x) => x.checked = v)),
      if (kWfBindableKinds.contains(c.kind)) ...[
        const SizedBox(height: 6),
        LabeledField(
          label: tr('ข้อมูลจาก ER'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (ref == null)
              Text(tr('ยังไม่ได้ผูก'), style: TextStyle(fontSize: 12.5, color: C.muted))
            else
              Container(
                key: const ValueKey('wf-ref-chip'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (refProblem == null ? const Color(0xFF0D9488) : C.danger).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  refProblem == null ? '⛁ ${wfRefLabel(w, ref, withDoc: true)}' : '⛁ ${wfRefLabel(w, ref, withDoc: true)} — $refProblem',
                  style: TextStyle(fontSize: 12.5, color: refProblem == null ? const Color(0xFF0F766E) : C.danger),
                ),
              ),
            const SizedBox(height: 4),
            Wrap(spacing: 4, children: [
              TextButton.icon(
                key: const ValueKey('wf-bind'),
                onPressed: () => a.bindData(c.id),
                icon: const Icon(Icons.storage_rounded, size: 15),
                label: Text(ref == null ? tr('ผูกกับข้อมูลใน ER…') : tr('เปลี่ยน…')),
              ),
              if (ref != null)
                TextButton(key: const ValueKey('wf-unbind'), onPressed: () => f.setRef(c.id, null), child: Text(tr('เลิกผูก'))),
              if (ref != null && refProblem == null)
                TextButton(key: const ValueKey('wf-goto-table'), onPressed: () => f.gotoBoundTable(c.id), child: Text(tr('ไปที่ตาราง'))),
            ]),
          ]),
        ),
      ],
      const SizedBox(height: 10),
      Row(children: [
        _numField('wf-x', 'X', c.x, (v) => f.updateComponents([c.id], (x) => x.x = v)),
        const SizedBox(width: 6),
        _numField('wf-y', 'Y', c.y, (v) => f.updateComponents([c.id], (x) => x.y = v)),
        const SizedBox(width: 6),
        _numField('wf-w', tr('กว้าง'), c.w, (v) => f.updateComponents([c.id], (x) => x.w = v.clamp(kWfMinSide, kWfMaxSide).toDouble())),
        const SizedBox(width: 6),
        _numField('wf-h', tr('สูง'), c.h, (v) => f.updateComponents([c.id], (x) => x.h = v.clamp(kWfMinSide, kWfMaxSide).toDouble())),
      ]),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _numField('wf-rotation', tr('หมุน (องศา)'), c.rotation, (v) => f.setRotation([c.id], v)),
        const SizedBox(width: 4),
        _toggle('wf-rot-ccw', Icons.rotate_left_rounded, tr('หมุน 90° ทวนเข็ม'), false, () => f.setRotation([c.id], -90, relative: true)),
        _toggle('wf-rot-cw', Icons.rotate_right_rounded, tr('หมุน 90° ตามเข็ม'), false, () => f.setRotation([c.id], 90, relative: true)),
        _toggle('wf-rot-reset', Icons.restart_alt_rounded, tr('ไม่หมุน (0°)'), false, () => f.setRotation([c.id], 0)),
      ]),
      if (c.locked) ...[
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.lock_rounded, size: 14, color: C.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(tr('ล็อกอยู่ — ย้าย/ปรับขนาด/หมุน/ลบบนแคนวาสไม่ได้'), style: TextStyle(fontSize: 12, color: C.muted))),
          TextButton(key: const ValueKey('wf-unlock'), onPressed: () => f.setLocked([c.id], false), child: Text(tr('ปลดล็อก'))),
        ]),
      ],
      const SizedBox(height: 14),
      _StyleSection(ids: {c.id}, sample: c),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        OutlinedButton.icon(
          key: const ValueKey('wf-duplicate'),
          onPressed: f.duplicateSelection,
          icon: const Icon(Icons.file_copy_outlined, size: 16),
          label: Text(tr('ทำสำเนา')),
        ),
        _toggle('wf-front', Icons.flip_to_front_rounded, tr('นำขึ้นบนสุด'), false, () => f.reorder(front: true)),
        _toggle('wf-back', Icons.flip_to_back_rounded, tr('นำลงล่างสุด'), false, () => f.reorder(front: false)),
      ]),
      const SizedBox(height: 14),
      ApiRefPicker(value: c.api, onChanged: (r) => f.updateComponents([c.id], (x) => x.api = r)),
    ]);
  }
}

class _MultiProps extends StatelessWidget {
  const _MultiProps({required this.ids});
  final Set<String> ids;

  @override
  Widget build(BuildContext context) {
    final f = context.read<WireframeController>();
    final sample = f.diagram.componentById(ids.first) ?? WfComponent(id: '', kind: WfKind.label);
    Widget btn(String key, IconData icon, String tip, VoidCallback tap) =>
        IconButton(key: ValueKey(key), tooltip: tip, visualDensity: VisualDensity.compact, icon: Icon(icon, size: 18, color: C.muted), onPressed: tap);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(tr('เลือก {0} ชิ้นส่วน', [ids.length]), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
        IconButton(
          key: const ValueKey('wf-delete'),
          tooltip: tr('ลบชิ้นส่วน'),
          icon: Icon(Icons.delete_outline, color: C.danger, size: 20),
          onPressed: f.deleteSelection,
        ),
      ]),
      const SizedBox(height: 8),
      LabeledField(
        label: tr('จัดแนว'),
        child: Wrap(children: [
          btn('wf-al-left', Icons.align_horizontal_left_rounded, tr('จัดชิดซ้าย'), () => f.align(BoxAlign.left)),
          btn('wf-al-center', Icons.align_horizontal_center_rounded, tr('จัดกึ่งกลางแนวตั้ง'), () => f.align(BoxAlign.centerH)),
          btn('wf-al-right', Icons.align_horizontal_right_rounded, tr('จัดชิดขวา'), () => f.align(BoxAlign.right)),
          btn('wf-al-top', Icons.align_vertical_top_rounded, tr('จัดชิดบน'), () => f.align(BoxAlign.top)),
          btn('wf-al-middle', Icons.align_vertical_center_rounded, tr('จัดกึ่งกลางแนวนอน'), () => f.align(BoxAlign.middle)),
          btn('wf-al-bottom', Icons.align_vertical_bottom_rounded, tr('จัดชิดล่าง'), () => f.align(BoxAlign.bottom)),
        ]),
      ),
      const SizedBox(height: 6),
      LabeledField(
        label: tr('กระจาย / ขนาด'),
        child: Wrap(children: [
          btn('wf-dist-h', Icons.horizontal_distribute_rounded, tr('กระจายแนวนอน (3 ชิ้นขึ้นไป)'), () => f.distribute(horizontal: true)),
          btn('wf-dist-v', Icons.vertical_distribute_rounded, tr('กระจายแนวตั้ง (3 ชิ้นขึ้นไป)'), () => f.distribute(horizontal: false)),
          btn('wf-same-size', Icons.photo_size_select_small_rounded, tr('ขนาดเท่ากับชิ้นแรกที่เลือก'), f.sameSize),
        ]),
      ),
      const SizedBox(height: 10),
      _StyleSection(ids: ids, sample: sample),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const ValueKey('wf-duplicate'),
        onPressed: f.duplicateSelection,
        icon: const Icon(Icons.file_copy_outlined, size: 16),
        label: Text(tr('ทำสำเนา')),
      ),
    ]);
  }
}

/// ส่วนที่พับได้ของแผงขวา: หัว (ลูกศร + ชื่อ + สรุปค่าปัจจุบัน) คลิกแล้วกาง/พับ ; สถานะกาง/พับจำไว้ตลอดรอบที่เปิดโปรแกรม (สถานะมุมมอง ไม่บันทึกในไฟล์)
class _Fold extends StatefulWidget {
  const _Fold({
    required this.id,
    required this.title,
    required this.child,
    this.summary,
    this.summaryColor,
    this.initiallyOpen = false,
  });
  final String id;
  final String title;
  final String? summary;
  final Color? summaryColor;
  final bool initiallyOpen;
  final Widget child;

  static final Map<String, bool> _open = {};

  @override
  State<_Fold> createState() => _FoldState();
}

class _FoldState extends State<_Fold> {
  bool get _isOpen => _Fold._open[widget.id] ?? widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final open = _isOpen;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          key: ValueKey('${widget.id}-head'),
          onTap: () => setState(() => _Fold._open[widget.id] = !open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(children: [
              Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 18, color: C.muted),
              const SizedBox(width: 8),
              Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(width: 10),
              if (widget.summary != null)
                Expanded(
                  child: Text(widget.summary!,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: widget.summaryColor ?? C.muted)),
                )
              else
                const Spacer(),
            ]),
          ),
        ),
        if (open) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: widget.child),
      ]),
    );
  }
}

String _styleShort(WfStyle s) => s == WfStyle.sketch ? tr('ร่าง') : tr('เรียบร้อย');

/// หัวแผง (แสดงตลอด ไม่ว่าจะเลือกชิ้นส่วนหรือไม่): ชื่อหน้าจอ · จำนวนชิ้น · ภาพย่อ · ขนาด/รูปแบบ
class _PanelHeader extends StatelessWidget {
  const _PanelHeader();

  @override
  Widget build(BuildContext context) {
    final f = context.watch<WireframeController>();
    final name = context.select<WorkspaceController, String>((w) => w.activeDocument.name);
    final d = f.diagram;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: C.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ),
          Text(tr('{0} ชิ้นส่วน', [d.components.length]), style: TextStyle(fontSize: 12.5, color: C.muted)),
        ]),
        const SizedBox(height: 10),
        Container(
          key: const ValueKey('wf-page-thumb'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.border)),
          // ระหว่างลากไม่วาดภาพย่อใหม่ทุกเฟรม (วาดใหม่ตอนปล่อยเมาส์)
          child: RepaintBoundary(child: WireframeThumbnail(diagram: d, height: 130, version: f.gestureActive ? -1 : f.revision)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text(wfFrameLabel(d), key: const ValueKey('wf-page-size'), style: TextStyle(fontSize: 11.5, color: C.muted), overflow: TextOverflow.ellipsis),
          ),
          Text(_styleShort(d.style), style: TextStyle(fontSize: 11.5, color: C.primaryDark)),
        ]),
      ]),
    );
  }
}

/// กลุ่มที่พับไว้ในแผงเลเยอร์ (สถานะมุมมอง ไม่บันทึกในไฟล์)
final Set<String> _collapsedGroups = {};

/// สัดส่วนความสูงของแผงเลเยอร์ต่อแผงขวา (ลากปรับได้) และพับอยู่หรือไม่ — สถานะมุมมอง ไม่บันทึกในไฟล์
double _layersFrac = 0.42;
bool _layersCollapsed = false;

/// เลเยอร์ (แบบ Adobe): บนสุดก่อน ; กลุ่มเป็นแถวพับได้ ; ลูกในภาชนะเยื้องเข้า ; ทุกแถวมีตา (ซ่อน/แสดง) และกุญแจ (ล็อก)
/// คลิกแถว = เลือกชิ้นนั้น (Ctrl/Shift = เพิ่ม/เอาออก) ; คลิกแถวกลุ่ม = เลือกทั้งกลุ่ม
class _LayersFold extends StatefulWidget {
  const _LayersFold({super.key, required this.maxHeight});

  /// ความสูงของแผงขวาทั้งแผง (ใช้คิดความสูงของแผงเลเยอร์)
  final double maxHeight;

  @override
  State<_LayersFold> createState() => _LayersFoldState();
}

class _LayersFoldState extends State<_LayersFold> {
  bool get _additive => HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed;

  @override
  Widget build(BuildContext context) {
    final f = context.watch<WireframeController>();
    final d = f.diagram;
    final parents = f.parents;
    final hidden = f.hiddenIds;
    final sel = f.selectedIds;
    int depth(String id) {
      var n = 0;
      for (var p = parents[id]; p != null && n < 20; p = parents[p]) {
        n++;
      }
      return n;
    }

    // แถว (บนสุดก่อน) — ลากแถวเพื่อเปลี่ยนลำดับการซ้อน ; ลากหัวกลุ่ม = ย้ายทั้งกลุ่ม ; ลากชิ้นเข้า/ออกจากกลุ่มได้
    final layerRows = f.layerRows(_collapsedGroups);
    final kidCount = <String, int>{};
    for (final p in parents.values) {
      kidCount[p] = (kidCount[p] ?? 0) + 1;
    }
    final rows = <Widget>[
      for (final (i, r) in layerRows.indexed)
        ReorderableDragStartListener(
          key: ValueKey(r.header ? 'wf-layer-row-g-${r.group}' : 'wf-layer-row-${r.id}'),
          index: i,
          child: r.header
              ? _groupRow(f, r.group!, wfGroupMembers(d, r.group!).reversed.toList(), r.open, sel)
              : _layerRow(f, d.componentById(r.id!)!, depth(r.id!), r.group != null, kidCount[r.id!] ?? 0, hidden, sel),
        ),
    ];

    final canGroup = sel.length >= 2;
    final maxH = widget.maxHeight;
    final header = InkWell(
      key: const ValueKey('wf-fold-layers-head'),
      onTap: () => setState(() => _layersCollapsed = !_layersCollapsed),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Row(children: [
          Icon(_layersCollapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded, size: 18, color: C.muted),
          const SizedBox(width: 8),
          Text(tr('เลเยอร์'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const Spacer(),
          Text('${d.components.length}', style: TextStyle(fontSize: 12, color: C.muted)),
        ]),
      ),
    );
    if (_layersCollapsed) {
      return Container(decoration: BoxDecoration(border: Border(top: BorderSide(color: C.border))), child: header);
    }
    final double h = (maxH * _layersFrac).clamp(math.min(160.0, maxH * 0.5), math.max(160.0, maxH - 180)).toDouble();
    return Container(
      height: h,
      decoration: BoxDecoration(border: Border(top: BorderSide(color: C.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ลากขอบบนเพื่อปรับความสูงของแผงเลเยอร์
        MouseRegion(
          cursor: SystemMouseCursors.resizeRow,
          child: GestureDetector(
            key: const ValueKey('wf-layers-resize'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (u) => setState(() => _layersFrac = ((h - u.delta.dy) / maxH).clamp(0.15, 0.85)),
            child: const SizedBox(height: 6),
          ),
        ),
        header,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            _layerTool('wf-layer-new-group', Icons.create_new_folder_outlined, tr('กลุ่มใหม่ (ว่าง)'), f.addEmptyGroup),
            _layerTool('wf-layer-group', Icons.folder_copy_outlined, '${tr('จัดกลุ่ม')} (Ctrl+G)', canGroup ? f.groupSelection : null),
            _layerTool('wf-layer-ungroup', Icons.folder_off_outlined, '${tr('เลิกจัดกลุ่ม')} (Ctrl+Shift+G)', f.selectionHasGroup ? f.ungroupSelection : null),
            _layerTool('wf-layer-front', Icons.flip_to_front_rounded, tr('นำขึ้นบนสุด'), sel.isEmpty ? null : () => f.reorder(front: true)),
            _layerTool('wf-layer-back', Icons.flip_to_back_rounded, tr('นำลงล่างสุด'), sel.isEmpty ? null : () => f.reorder(front: false)),
          ]),
        ),
        Expanded(
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Text(tr('ยังไม่มีชิ้นส่วนบนหน้าจอ'), key: const ValueKey('wf-layers-empty'), style: TextStyle(fontSize: 12.5, color: C.muted)),
                )
              : ReorderableListView(
                  key: const ValueKey('wf-layers-list'),
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, _, _) => Material(elevation: 4, color: C.surface, borderRadius: BorderRadius.circular(6), child: child),
                  onReorderItem: (from, to) => f.moveLayerRow(_collapsedGroups, from, to),
                  children: rows,
                ),
        ),
      ]),
    );
  }

  Widget _layerTool(String key, IconData icon, String tip, VoidCallback? onTap) => IconButton(
        key: ValueKey(key),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        color: C.muted,
        onPressed: onTap,
        icon: Icon(icon),
      );

  Widget _eyeLock(String key, {required bool hidden, required bool locked, required VoidCallback onEye, required VoidCallback onLock, bool dimEye = false}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        _miniToggle('wf-eye-$key', hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, hidden ? tr('แสดง') : tr('ซ่อน'),
            hidden || dimEye ? C.muted.withValues(alpha: 0.6) : C.muted, onEye),
        _miniToggle('wf-lock-$key', locked ? Icons.lock_rounded : Icons.lock_open_rounded, locked ? tr('ปลดล็อก') : tr('ล็อก'),
            locked ? C.primaryDark : C.muted.withValues(alpha: 0.45), onLock),
      ]);

  Widget _miniToggle(String key, IconData icon, String tip, Color color, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(5), child: Icon(icon, size: 16, color: color)),
        ),
      );

  Future<void> _rename(WireframeController f, String g) async {
    final r = await showDialog<PromptResult>(
      context: context,
      builder: (_) => TextPromptDialog(title: tr('เปลี่ยนชื่อกลุ่ม'), initial: f.diagram.groupById(g)?.name ?? '', label: tr('ชื่อกลุ่ม')),
    );
    if (r != null) f.renameGroup(g, r.text);
  }

  /// ที่จับลาก (บอกว่าแถวนี้ลากเรียงได้) — เมาส์ชี้แล้วเป็นรูปมือจับ
  Widget _grip() => const MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Padding(padding: EdgeInsets.only(left: 2), child: Icon(Icons.drag_indicator_rounded, size: 16, color: Color(0x998A94A6))),
      );

  /// ช่องติ๊กเลือกของแถว: ติ๊ก = เพิ่มเข้า/เอาออกจากที่เลือก (เลือกหลายชิ้นได้โดยไม่ต้องกด Ctrl) ; [value] null = เลือกบางส่วน (กลุ่ม)
  Widget _pick(String key, bool? value, VoidCallback onTap) => SizedBox(
        width: 24,
        height: 24,
        child: Checkbox(
          key: ValueKey(key),
          value: value,
          tristate: true,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (_) => onTap(),
        ),
      );

  DateTime _lastHeaderTap = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastHeaderId;

  Widget _groupRow(WireframeController f, String g, List<WfComponent> members, bool open, Set<String> sel) {
    final empty = members.isEmpty;
    final allSel = !empty && members.every((m) => sel.contains(m.id));
    final allHidden = !empty && members.every((m) => m.hidden);
    final allLocked = !empty && members.every((m) => m.locked);
    final ids = [for (final m in members) m.id];
    return Material(
      color: allSel ? C.primaryTint : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        key: ValueKey('wf-group-$g'),
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          // ดับเบิลคลิก = เปลี่ยนชื่อ (จับเวลาเอง ไม่ให้คลิกเดียวช้า)
          final now = clock.now();
          final dbl = _lastHeaderId == g && now.difference(_lastHeaderTap).inMilliseconds < 400;
          _lastHeaderTap = now;
          _lastHeaderId = g;
          if (dbl) {
            _rename(f, g);
            return;
          }
          if (!empty) f.setSelection(_additive ? {...sel, ...ids} : ids, exact: true);
        },
        child: SizedBox(
          height: 32,
          child: Row(children: [
            _grip(),
            InkWell(
              key: ValueKey('wf-group-toggle-$g'),
              onTap: () => setState(() => open ? _collapsedGroups.add(g) : _collapsedGroups.remove(g)),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 18, color: C.muted),
              ),
            ),
            _pick('wf-pick-group-$g', empty ? false : (allSel ? true : (members.any((m) => sel.contains(m.id)) ? null : false)), () {
              if (empty) return;
              f.setSelection(allSel ? {for (final s in sel) if (!ids.contains(s)) s} : {...sel, ...ids}, exact: true);
            }),
            Icon(open ? Icons.folder_open_outlined : Icons.folder_outlined, size: 16, color: C.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: f.groupLabel(g), style: TextStyle(fontWeight: FontWeight.w600, color: allHidden ? C.muted : C.text)),
                  TextSpan(
                      text: empty ? '  ${tr('ว่าง — ลากชิ้นส่วนมาวางใต้แถวนี้')}' : '  ${members.length}',
                      style: TextStyle(fontSize: 11.5, color: C.muted)),
                ]),
                key: ValueKey('wf-group-label-$g'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            _miniToggle('wf-group-remove-$g', Icons.folder_off_outlined, tr('ลบกลุ่ม (ชิ้นส่วนยังอยู่)'), C.muted.withValues(alpha: 0.6), () => f.removeGroup(g)),
            if (!empty)
              _eyeLock(g,
                  hidden: allHidden,
                  locked: allLocked,
                  onEye: () => f.setHidden(ids, !allHidden),
                  onLock: () => f.setLocked(ids, !allLocked)),
          ]),
        ),
      ),
    );
  }

  /// เส้นนำทางแนวตั้งของลำดับชั้น: ระดับ "กลุ่ม" เป็นสีเน้น ระดับ "อยู่ในกล่อง" เป็นสีเทา (ต่อ 1 ระดับ = 1 ช่องกว้าง 16)
  Widget _guides(bool inGroup, int boxDepth) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (inGroup)
          SizedBox(
            width: 16,
            height: 32,
            child: Center(child: Container(width: 2, color: C.primary.withValues(alpha: 0.55))),
          ),
        for (var i = 0; i < boxDepth; i++)
          SizedBox(
            width: 16,
            height: 32,
            child: Center(child: Container(width: 1.5, color: C.muted.withValues(alpha: 0.45))),
          ),
      ]);

  Widget _layerRow(WireframeController f, WfComponent c, int depth, bool inGroup, int kids, Set<String> hidden, Set<String> sel) {
    final selected = sel.contains(c.id);
    final invisible = hidden.contains(c.id);
    final name = c.text.trim().isEmpty ? wfKindLabel(c.kind) : c.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return Material(
      key: ValueKey('wf-item-${c.id}'),
      color: selected ? C.primaryTint : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          f.selectBox(c.id, add: _additive, exact: true);
          if (!_additive) f.reveal(c.id, f.viewport);
        },
        child: SizedBox(
          height: 32,
          child: Row(children: [
            _grip(),
            _guides(inGroup, depth),
            _pick('wf-pick-${c.id}', selected, () => f.selectBox(c.id, add: true, exact: true)),
            const SizedBox(width: 4),
            Icon(wfKindIcon(c.kind), size: 16, color: invisible ? C.muted.withValues(alpha: 0.5) : C.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: invisible ? C.muted : C.text, fontStyle: invisible ? FontStyle.italic : null)),
            ),
            if (kids > 0)
              Tooltip(
                message: tr('มี {0} ชิ้นข้างใน', [kids]),
                child: Container(
                  key: ValueKey('wf-kids-${c.id}'),
                  margin: const EdgeInsets.only(right: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: C.muted.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.subdirectory_arrow_right_rounded, size: 11, color: C.muted),
                    Text('$kids', style: TextStyle(fontSize: 10.5, color: C.muted)),
                  ]),
                ),
              ),
            if (c.rotation != 0)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Text('${c.rotation.round()}°', style: TextStyle(fontSize: 11, color: C.muted)),
              ),
            if (c.ref != null) Padding(padding: const EdgeInsets.only(right: 2), child: Icon(Icons.storage_rounded, size: 13, color: C.muted)),
            _eyeLock(c.id,
                hidden: c.hidden,
                locked: c.locked,
                dimEye: invisible && !c.hidden,
                onEye: () => f.setHidden([c.id], !c.hidden),
                onLock: () => f.setLocked([c.id], !c.locked)),
          ]),
        ),
      ),
    );
  }
}

/// ตั้งค่าหน้าจอ (ไม่ได้เลือกชิ้นส่วน): ภาพย่อ + ส่วนที่พับได้ (การแสดงผล / ขนาด / ตรวจสอบ / Screen Flow)
class _PageProps extends StatelessWidget {
  const _PageProps();

  @override
  Widget build(BuildContext context) {
    final f = context.watch<WireframeController>();
    final w = context.watch<WorkspaceController>();
    final a = WireframeActions(context);
    final d = f.diagram;
    final issues = f.issues;
    final linked = screensLinkingTo(w.workspace, f.docId);
    final size = '${d.width.round()} × ${d.height.round()}';
    final device = d.device == WfDevice.custom ? size : wfDeviceLabel(d.device);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Fold(
        id: 'wf-fold-look',
        title: tr('การแสดงผล'),
        summary: _styleShort(d.style),
        initiallyOpen: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<WfStyle>(
              key: const ValueKey('wf-panel-style'),
              showSelectedIcon: false,
              segments: [
                for (final s in WfStyle.values) ButtonSegment(value: s, label: Text(_styleShort(s), style: const TextStyle(fontSize: 12.5))),
              ],
              selected: {d.style},
              onSelectionChanged: (s) => f.setStyle(s.first),
            ),
          ),
          const SizedBox(height: 6),
          Text(d.style == WfStyle.sketch ? tr('ขาวดำ เส้นวาดมือ') : tr('UI สีสว่าง ใช้สีเน้น'), style: TextStyle(fontSize: 11.5, color: C.muted)),
          const SizedBox(height: 12),
          LabeledField(
            label: tr('สีเน้น (accent)'),
            child: ColorSwatchRow(
              keyPrefix: 'wf-accent',
              palette: kWfPalette.take(8).toList(),
              current: d.accent,
              allowDefault: false,
              onPick: (v) {
                if (v != null) f.setAccent(v);
              },
              onCustom: a.pickAccent,
            ),
          ),
          if (d.style == WfStyle.sketch) ...[
            const SizedBox(height: 4),
            Text(tr('สีเน้นใช้เมื่อแสดงแบบเรียบร้อย'), style: TextStyle(fontSize: 11.5, color: C.muted)),
          ],
        ]),
      ),
      _Fold(
        id: 'wf-fold-size',
        title: tr('ขนาดหน้าจอ'),
        summary: device,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          KeyedSubtree(
            key: const ValueKey('wf-device'),
            child: Dropdown<WfDevice>(value: d.device, items: WfDevice.values, labelOf: wfDeviceLabel, onChanged: f.setDevice),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _numField('wf-frame-w', tr('กว้าง'), d.width, (v) => f.setFrameSize(v, d.height)),
            const SizedBox(width: 8),
            _numField('wf-frame-h', tr('สูง'), d.height, (v) => f.setFrameSize(d.width, v)),
          ]),
        ]),
      ),
      _Fold(
        id: 'wf-fold-checks',
        title: tr('ตรวจสอบ'),
        summary: issues.isEmpty ? tr('✓ ไม่พบปัญหา') : '${issues.length}',
        summaryColor: issues.isEmpty ? C.primaryDark : C.warnText,
        initiallyOpen: issues.isNotEmpty,
        child: issues.isEmpty
            ? Text(tr('✓ ไม่พบปัญหา'), key: const ValueKey('wf-no-issues'), style: TextStyle(fontSize: 12.5, color: C.primaryDark))
            : Column(children: [
                for (final i in issues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: IssueCard(
                      key: ValueKey('wf-issue-${i.code}-${i.tableId}'),
                      issue: i,
                      onTap: () {
                        if (i.tableId == null) return;
                        f.selectBox(i.tableId!);
                        f.reveal(i.tableId!, f.viewport);
                      },
                    ),
                  ),
              ]),
      ),
      if (linked.isNotEmpty)
        _Fold(
          id: 'wf-fold-flow',
          title: tr('ใช้ใน Screen Flow'),
          summary: tr('{0} หน้าจอ', [linked.length]),
          child: Align(alignment: Alignment.centerLeft, child: Text(linked.join(', '), style: TextStyle(fontSize: 12.5, color: C.muted))),
        ),
    ]);
  }
}

/// ภาพย่อหน้าจอ Wireframe (ใช้ในแผงของ Screen Flow / Project Home)
class WireframeThumbnail extends StatelessWidget {
  const WireframeThumbnail({super.key, required this.diagram, this.height = 90, this.version});
  final WireframeDiagram diagram;
  final double height;

  /// รุ่นของเนื้อหา: ระบุแล้ววาดใหม่เฉพาะเมื่อรุ่นเปลี่ยน (null = วาดใหม่ทุกครั้ง)
  final Object? version;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: CustomPaint(painter: _ThumbPainter(diagram, version), child: const SizedBox.expand()),
      );
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.d, this.version);
  final WireframeDiagram d;
  final Object? version;

  @override
  void paint(Canvas canvas, Size size) {
    final s = (size.width / d.width) < (size.height / d.height) ? size.width / d.width : size.height / d.height;
    canvas.save();
    canvas.translate((size.width - d.width * s) / 2, (size.height - d.height * s) / 2);
    canvas.scale(s);
    canvas.clipRect(Rect.fromLTWH(0, 0, d.width, d.height));
    paintWireframe(canvas, d);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => version == null || old.version != version || !identical(old.d, d);
}
