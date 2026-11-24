import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/export/usecase_export.dart';
import '../core/l10n/l10n.dart';
import '../core/models/requirement.dart' show TraceLink;
import '../core/models/traceability.dart';
import '../core/models/use_case.dart';
import '../core/validate/issue.dart' show Severity;
import '../core/validate/usecase_validator.dart';
import '../state/workspace_controller.dart';
import 'file_actions.dart';
import 'issue_widgets.dart' show IssueCard;
import 'notes_panel.dart' show gotoNoteTarget;
import 'project_home.dart' show homeTypeLabel;
import 'theme.dart';
import 'usecase_diagram.dart';
import 'usecase_tests.dart';
import 'widgets.dart';

enum UcTab { spec, diagram, tests, doc }

/// key ของแถวขั้นตอน (ไว้เลื่อนไปที่ขั้นที่มีปัญหาเมื่อมาจากหน้าต่างปัญหาทั้งโปรเจกต์)
final Map<String, GlobalKey> _ucStepKeys = {};

/// หน้า Use Case (Phase 27): แท็บ "สเปก" แก้ไข · แท็บ "เอกสาร" อ่านต่อเนื่องและส่งออก Markdown
/// ข้อมูลชุดเดียว (`Workspace.useCases`) แก้ที่แท็บสเปกเท่านั้น ; แสดงแทนแคนวาสขณะ [WorkspacePage.useCases]
class UseCaseView extends StatefulWidget {
  const UseCaseView({super.key});

  @override
  State<UseCaseView> createState() => _UseCaseViewState();
}

class _UseCaseViewState extends State<UseCaseView> {
  UcTab _tab = UcTab.spec;
  String? _selectedId;
  String _query = '';

  UseCase? _current(WorkspaceController w) {
    final list = w.useCases;
    if (list.isEmpty) return null;
    for (final u in list) {
      if (u.id == _selectedId) return u;
    }
    return list.first;
  }

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WorkspaceController>();
    // คำขอ "ไปที่ Use Case/ขั้นตอนนี้" (จากหน้าต่างปัญหาทั้งโปรเจกต์) : เลือกข้อนั้น กลับแท็บสเปก แล้วเลื่อนไปที่ขั้น
    final focus = w.takeUseCaseFocus();
    if (focus != null && w.useCaseById(focus.id) != null) {
      _selectedId = focus.id;
      _tab = UcTab.spec;
      final stepId = focus.stepId;
      if (stepId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _ucStepKeys[stepId]?.currentContext;
          if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 200), alignment: 0.3);
        });
      }
    }
    final u = _current(w);
    final cover = useCaseCoverage(w.workspace);
    return Container(
      key: const ValueKey('usecase-view'),
      color: C.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, w, cover),
          Expanded(
            child: w.useCases.isEmpty
                ? _Empty(onAdd: () => _add(w))
                : _tab == UcTab.spec
                ? _SpecTab(
                    w: w,
                    current: u!,
                    query: _query,
                    onQuery: (q) => setState(() => _query = q),
                    onSelect: (id) => setState(() => _selectedId = id),
                  )
                : _tab == UcTab.diagram
                ? UcDiagramView(
                    w: w,
                    initialUcId: u?.id,
                    onOpenSpec: (id) => setState(() {
                      _selectedId = id;
                      _tab = UcTab.spec;
                    }),
                  )
                : _tab == UcTab.tests
                ? UcTestsTab(w: w)
                : _DocTab(w: w),
          ),
        ],
      ),
    );
  }

  void _add(WorkspaceController w) {
    final u = w.addUseCase();
    setState(() {
      _selectedId = u.id;
      _tab = UcTab.spec;
    });
  }

  Widget _header(
    BuildContext context,
    WorkspaceController w,
    ({int covered, int total}) cover,
  ) {
    Widget tab(UcTab t, String label) => InkWell(
      key: ValueKey('uc-tab-${t.name}'),
      onTap: () => setState(() => _tab = t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: _tab == t ? C.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: _tab == t ? FontWeight.w600 : FontWeight.w400,
            color: _tab == t ? C.primaryDark : C.muted,
          ),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: C.surface,
        border: Border(bottom: BorderSide(color: C.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Use Case',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: C.text,
                ),
              ),
              Text(
                tr('{0} รายการ', [w.useCases.length]),
                key: const ValueKey('uc-count'),
                style: TextStyle(color: C.muted),
              ),
              if (cover.total > 0)
                Text(
                  tr('ครอบคลุมความต้องการ {0} / {1} ข้อ', [
                    cover.covered,
                    cover.total,
                  ]),
                  key: const ValueKey('uc-cover-head'),
                  style: TextStyle(
                    color: cover.covered == cover.total
                        ? C.primaryDark
                        : C.warnText,
                  ),
                ),
              OutlinedButton(
                key: const ValueKey('uc-export'),
                onPressed: w.useCases.isEmpty
                    ? null
                    : () => FileActions.saveText(
                        context,
                        exportUseCaseMarkdown(w.workspace),
                        '${FileActions.safeName(w.workspace.name)}-usecases.md',
                        tr('ส่งออก Use Case เป็นเอกสาร'),
                      ),
                child: Text(tr('ส่งออกเป็นเอกสาร')),
              ),
              FilledButton(
                key: const ValueKey('uc-add'),
                onPressed: () => _add(w),
                child: Text(tr('+ Use Case')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              tab(UcTab.spec, tr('สเปก')),
              tab(UcTab.diagram, tr('แผนภาพ')),
              tab(UcTab.tests, tr('กรณีทดสอบ')),
              tab(UcTab.doc, tr('เอกสาร')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('ยังไม่มี Use Case'),
            key: const ValueKey('uc-empty'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: C.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'เขียนว่าใครใช้ระบบเพื่อทำอะไร ทีละขั้นตอน แล้วผูกกับความต้องการ หน้าจอ และ endpoint ที่เกี่ยวข้อง',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: C.muted),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('uc-empty-add'),
            onPressed: onAdd,
            child: Text(tr('+ Use Case แรก')),
          ),
        ],
      ),
    ),
  );
}

// ===================================================================== แท็บสเปก

class _SpecTab extends StatelessWidget {
  const _SpecTab({
    required this.w,
    required this.current,
    required this.query,
    required this.onQuery,
    required this.onSelect,
  });
  final WorkspaceController w;
  final UseCase current;
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final issues = validateUseCases(w.workspace);
    final list = _ListColumn(
      w: w,
      current: current,
      query: query,
      onQuery: onQuery,
      onSelect: onSelect,
      issues: issues,
    );
    final editor = _Editor(
      key: ValueKey('uc-editor-${current.id}'),
      w: w,
      u: current,
      onSelect: onSelect,
    );
    final side = _SideColumn(w: w, u: current, issues: issues);
    // คอลัมน์ข้างในเลย์เอาต์กว้างต้องเลื่อนได้ (เนื้อหายาวกว่าความสูงหน้าจอ = ล้น) ; ความสูงขั้นต่ำเต็มพื้นที่ เพื่อให้พื้นหลัง/เส้นขอบเต็มความสูงเหมือนเดิม
    Widget scrolling(BoxConstraints c, Widget child) =>
        SingleChildScrollView(child: ConstrainedBox(constraints: BoxConstraints(minHeight: c.maxHeight), child: child));
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 1000) {
          return ListView(
            children: [
              list,
              Padding(padding: const EdgeInsets.all(20), child: editor),
              side,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 244, child: scrolling(c, list)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                child: editor,
              ),
            ),
            SizedBox(width: 272, child: scrolling(c, side)),
          ],
        );
      },
    );
  }
}

class _ListColumn extends StatelessWidget {
  const _ListColumn({
    required this.w,
    required this.current,
    required this.query,
    required this.onQuery,
    required this.onSelect,
    required this.issues,
  });
  final WorkspaceController w;
  final UseCase current;
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onSelect;
  final List<UcIssue> issues;

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final shown = [
      for (final u in w.useCases)
        if (q.isEmpty ||
            u.name.toLowerCase().contains(q) ||
            u.code.toLowerCase().contains(q) ||
            u.actor.toLowerCase().contains(q))
          u,
    ];
    final groups = <String, List<UseCase>>{};
    for (final u in shown) {
      (groups[u.actor.trim().isEmpty
                  ? tr('ไม่ระบุผู้กระทำ')
                  : u.actor.trim()] ??=
              [])
          .add(u);
    }
    return Container(
      decoration: BoxDecoration(
        color: C.surface,
        border: Border(right: BorderSide(color: C.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: CommitField(
              key: const ValueKey('uc-search'),
              value: query,
              hint: tr('ค้นหา Use Case'),
              onCommit: onQuery,
            ),
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(tr('ไม่พบ'), style: TextStyle(color: C.muted)),
            ),
          for (final e in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Text(
                '${e.key} · ${e.value.length}',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.4,
                  color: C.muted,
                ),
              ),
            ),
            for (final u in e.value)
              InkWell(
                key: ValueKey('uc-item-${u.id}'),
                onTap: () => onSelect(u.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: u.id == current.id ? C.primaryTint : null,
                    border: Border(
                      left: BorderSide(
                        color: u.id == current.id
                            ? C.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 46,
                        child: Text(
                          u.code,
                          style: monoStyle.copyWith(
                            fontSize: 11.5,
                            color: C.muted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          u.name.trim().isEmpty
                              ? tr('(ไม่มีชื่อ)')
                              : u.name.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: C.text),
                        ),
                      ),
                      _IssueDot(
                        issues: [
                          for (final i in issues)
                            if (i.ucId == u.id) i,
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _IssueDot extends StatelessWidget {
  const _IssueDot({required this.issues});
  final List<UcIssue> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    final err = issues.any((i) => i.severity == Severity.error);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: err ? C.dangerBg : C.warnBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${issues.length}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: err ? C.dangerText : C.warnText,
        ),
      ),
    );
  }
}

/// ป้ายลิงก์ของขั้นตอน (กดไปที่เอกสาร ; × เอาออก) — ลิงก์ที่ขาดเป็นสีเตือน
class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.w, required this.link, this.onRemove});
  final WorkspaceController w;
  final TraceLink link;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final label = traceLinkLabel(w.workspace, link);
    final ok = ucLinkValid(w.workspace, link);
    final t = w.workspace.documentById(link.docId)?.type;
    final col = t == null ? null : C.doc(t);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: ok
          ? () => gotoNoteTarget(context, link.docId, elementId: link.elementId)
          : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(7, 2, 4, 2),
        decoration: BoxDecoration(
          color: ok ? (col?.tint ?? C.surfaceHi) : C.warnBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: ok ? C.border : C.warnText),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (t != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: col!.main,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                ok
                    ? '${homeTypeLabel(t!)} · ${label ?? '?'}'
                    : tr('(ลิงก์ที่ขาด)'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: ok ? C.text : C.warnText,
                ),
              ),
            ),
            if (onRemove != null)
              InkWell(
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, size: 13, color: C.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// เมนูเลือกลิงก์ของขั้นตอน : แยกหัวตามชนิดเอกสาร (ใช้ตัวเลือกเดียวกับเมทริกซ์ความต้องการ)
Future<void> showUcLinkMenu(
  BuildContext context,
  WorkspaceController w,
  UcStep step,
  void Function(TraceLink) onToggle,
) async {
  final box = context.findRenderObject()! as RenderBox;
  final pos = box.localToGlobal(Offset(0, box.size.height));
  final items = <PopupMenuEntry<TraceLink>>[];
  for (final t in kTraceColumns) {
    final cands = traceCandidates(w.workspace, t);
    if (cands.isEmpty) continue;
    items.add(
      PopupMenuItem<TraceLink>(
        enabled: false,
        height: 28,
        child: Text(
          homeTypeLabel(t),
          style: TextStyle(fontSize: 11.5, color: C.muted),
        ),
      ),
    );
    for (final c in cands) {
      items.add(
        CheckedPopupMenuItem<TraceLink>(
          value: c.link,
          checked: step.links.contains(c.link),
          height: 34,
          child: Text(c.label, style: const TextStyle(fontSize: 13)),
        ),
      );
    }
  }
  if (items.isEmpty) {
    items.add(
      PopupMenuItem<TraceLink>(
        enabled: false,
        child: Text(
          tr('ยังไม่มีเอกสารให้ผูก'),
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
  final choice = await showMenu<TraceLink>(
    context: context,
    position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
    items: items,
  );
  if (choice != null) onToggle(choice);
}

class _Editor extends StatelessWidget {
  const _Editor({
    super.key,
    required this.w,
    required this.u,
    required this.onSelect,
  });
  final WorkspaceController w;
  final UseCase u;
  final ValueChanged<String> onSelect;

  void _edit(void Function(UseCase x) f) => w.updateUseCase(u.id, f);

  @override
  Widget build(BuildContext context) {
    Widget text(
      String key,
      String label,
      String value,
      void Function(UseCase x, String v) set, {
      bool multi = true,
      bool mono = false,
    }) => CommitField(
      key: ValueKey('uc-$key-${u.id}'),
      label: label,
      value: value,
      mono: mono,
      minLines: multi ? 2 : null,
      maxLines: multi ? 5 : null,
      onCommit: (v) => _edit((x) => set(x, v.trim())),
    );
    Widget two(Widget a, Widget b) => LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [a, const SizedBox(height: 12), b],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b),
          ],
        );
      },
    );
    final head = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: C.muted,
      letterSpacing: 0.5,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            SizedBox(
              width: 96,
              child: text(
                'code',
                tr('รหัส'),
                u.code,
                (x, v) => x.code = v,
                multi: false,
                mono: true,
              ),
            ),
            SizedBox(
              width: 360,
              child: text(
                'name',
                tr('ชื่อ (ขึ้นต้นด้วยคำกริยา)'),
                u.name,
                (x, v) => x.name = v,
                multi: false,
              ),
            ),
            SizedBox(
              width: 130,
              child: LabeledField(
                label: tr('สถานะ'),
                child: Dropdown<UcStatus>(
                  key: ValueKey('uc-status-${u.id}'),
                  value: u.status,
                  items: UcStatus.values,
                  labelOf: ucStatusLabel,
                  onChanged: (s) => _edit((x) => x.status = s),
                ),
              ),
            ),
            SizedBox(
              width: 110,
              child: LabeledField(
                label: tr('ความสำคัญ'),
                child: Dropdown<UcPriority>(
                  key: ValueKey('uc-priority-${u.id}'),
                  value: u.priority,
                  items: UcPriority.values,
                  labelOf: ucPriorityLabel,
                  onChanged: (p) => _edit((x) => x.priority = p),
                ),
              ),
            ),
            IconButton(
              key: ValueKey('uc-delete-${u.id}'),
              tooltip: tr('ลบ Use Case'),
              icon: Icon(Icons.delete_outline, color: C.danger),
              onPressed: () => w.deleteUseCase(u.id),
            ),
          ],
        ),
        const SizedBox(height: 12),
        two(
          text(
            'actor',
            tr('ผู้กระทำหลัก'),
            u.actor,
            (x, v) => x.actor = v,
            multi: false,
          ),
          text(
            'actor2',
            tr('ผู้กระทำรอง (คั่นด้วยจุลภาค)'),
            u.secondaryActor,
            (x, v) => x.secondaryActor = v,
            multi: false,
          ),
        ),
        const SizedBox(height: 12),
        two(
          text('goal', tr('เป้าหมาย'), u.goal, (x, v) => x.goal = v),
          text(
            'trigger',
            tr('ตัวเริ่มต้น'),
            u.trigger,
            (x, v) => x.trigger = v,
          ),
        ),
        const SizedBox(height: 12),
        two(
          text(
            'pre',
            tr('เงื่อนไขก่อนเริ่ม'),
            u.preconditions,
            (x, v) => x.preconditions = v,
          ),
          text(
            'post',
            tr('ผลลัพธ์เมื่อสำเร็จ'),
            u.postconditions,
            (x, v) => x.postconditions = v,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          '${tr('ขั้นตอนหลัก').toUpperCase()} · ${u.steps.length}',
          style: head,
        ),
        const SizedBox(height: 8),
        _Steps(w: w, u: u),
        const SizedBox(height: 22),
        Text(tr('ทางเลือกและข้อผิดพลาด').toUpperCase(), style: head),
        const SizedBox(height: 8),
        _Branches(w: w, u: u),
      ],
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.w, required this.u});
  final WorkspaceController w;
  final UseCase u;

  @override
  Widget build(BuildContext context) {
    void edit(void Function(UseCase x) f) => w.updateUseCase(u.id, f);
    return Container(
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ลากเรียงด้วยมือจับด้านซ้าย (ปุ่ม ▲▼ ยังอยู่ไว้ใช้ด้วยคีย์บอร์ด) ; ทางเลือกอ้างขั้นด้วย id จึงไม่พังเมื่อเรียงใหม่
          ReorderableListView(
            key: const ValueKey('uc-steps-list'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) {
              if (to != from) edit((x) => x.steps.insert(to, x.steps.removeAt(from)));
            },
            children: [
          for (final (i, s) in u.steps.indexed)
            Container(
              key: ValueKey('uc-step-${s.id}'),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: i == 0 ? Colors.transparent : C.borderSoft,
                  ),
                ),
              ),
              child: Row(
                key: _ucStepKeys.putIfAbsent(s.id, () => GlobalKey()),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, right: 4),
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          key: ValueKey('uc-step-drag-${s.id}'),
                          size: 18,
                          color: C.muted,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 26,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Text(
                        '${i + 1}',
                        style: monoStyle.copyWith(color: C.muted),
                      ),
                    ),
                  ),
                  InkWell(
                    key: ValueKey('uc-step-who-${s.id}'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => edit(
                      (x) => x.stepById(s.id)?.who = s.who == UcWho.user
                          ? UcWho.system
                          : UcWho.user,
                    ),
                    child: Container(
                      width: 56,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: s.who == UcWho.user
                            ? C.primaryTint
                            : C.surfaceHi,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: C.border),
                      ),
                      child: Text(
                        ucWhoLabel(s.who),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: s.who == UcWho.user ? C.primaryDark : C.muted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CommitField(
                          key: ValueKey('uc-step-text-${s.id}'),
                          value: s.text,
                          hint: tr('ใครทำอะไร'),
                          onCommit: (v) =>
                              edit((x) => x.stepById(s.id)?.text = v.trim()),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final l in s.links)
                              _LinkChip(
                                w: w,
                                link: l,
                                onRemove: () => edit(
                                  (x) => x.stepById(s.id)?.links.remove(l),
                                ),
                              ),
                            Builder(
                              builder: (ctx) => OutlinedButton(
                                key: ValueKey('uc-step-link-${s.id}'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 26),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  foregroundColor: C.muted,
                                  side: BorderSide(color: C.border),
                                ),
                                onPressed: () => showUcLinkMenu(
                                  ctx,
                                  w,
                                  s,
                                  (l) => edit((x) {
                                    final links = x.stepById(s.id)?.links;
                                    if (links != null && !links.remove(l)) {
                                      links.add(l);
                                      }
                                  }),
                                ),
                                child: Text(
                                  tr('+ ผูก'),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _IconBtn(
                        key: ValueKey('uc-step-up-${s.id}'),
                        icon: Icons.keyboard_arrow_up_rounded,
                        tip: tr('เลื่อนขึ้น'),
                        onTap: i == 0
                            ? null
                            : () => edit(
                                (x) =>
                                    x.steps.insert(i - 1, x.steps.removeAt(i)),
                              ),
                      ),
                      _IconBtn(
                        key: ValueKey('uc-step-down-${s.id}'),
                        icon: Icons.keyboard_arrow_down_rounded,
                        tip: tr('เลื่อนลง'),
                        onTap: i == u.steps.length - 1
                            ? null
                            : () => edit(
                                (x) =>
                                    x.steps.insert(i + 1, x.steps.removeAt(i)),
                              ),
                      ),
                      _IconBtn(
                        key: ValueKey('uc-step-del-${s.id}'),
                        icon: Icons.close_rounded,
                        tip: tr('ลบขั้นตอน'),
                        onTap: () => edit(
                          (x) => x.steps.removeWhere((e) => e.id == s.id),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ],
          ),
          Container(
            color: C.surfaceHi,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('uc-add-step'),
                onPressed: () => edit(
                  (x) => x.steps.add(
                    UcStep(
                      id: w.newId('us'),
                      who: x.steps.isNotEmpty && x.steps.last.who == UcWho.user
                          ? UcWho.system
                          : UcWho.user,
                    ),
                  ),
                ),
                child: Text(tr('+ เพิ่มขั้นตอน')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    super.key,
    required this.icon,
    required this.tip,
    required this.onTap,
  });
  final IconData icon;
  final String tip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    height: 28,
    child: IconButton(
      padding: EdgeInsets.zero,
      iconSize: 17,
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(icon),
    ),
  );
}

class _Branches extends StatelessWidget {
  const _Branches({required this.w, required this.u});
  final WorkspaceController w;
  final UseCase u;

  static const _end = '#end';

  @override
  Widget build(BuildContext context) {
    void edit(void Function(UseCase x) f) => w.updateUseCase(u.id, f);
    final stepIds = [for (final s in u.steps) s.id];
    String stepLabel(String? id) => id == null
        ? tr('(ไม่ระบุ)')
        : (u.stepNumber(id) == 0
              ? tr('(ไม่พบขั้นตอน)')
              : tr('ขั้นที่ {0}', [u.stepNumber(id)]));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (u.branches.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: C.border),
            ),
            child: Text(
              tr('ยังไม่มีทางเลือกหรือข้อผิดพลาด'),
              style: TextStyle(color: C.muted),
            ),
          ),
        ReorderableListView(
          key: const ValueKey('uc-branches-list'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) {
            if (to != from) edit((x) => x.branches.insert(to, x.branches.removeAt(from)));
          },
          children: [
        for (final (bi, b) in u.branches.indexed)
          Container(
            key: ValueKey('uc-branch-${b.id}'),
            margin: const EdgeInsets.only(bottom: 8),
            // กรอบเส้นเดียวกันทุกด้าน (borderRadius ใช้กับเส้นขอบที่ด้านต่างกันไม่ได้) ; แถบสีด้านซ้ายเป็นวิดเจ็ตแยก
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: C.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 3,
                    color: b.exception ? C.danger : C.warnText,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ReorderableDragStartListener(
                                index: bi,
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.grab,
                                  child: Icon(
                                    Icons.drag_indicator_rounded,
                                    key: ValueKey('uc-branch-drag-${b.id}'),
                                    size: 18,
                                    color: C.muted,
                                  ),
                                ),
                              ),
                              Text(
                                u.branchLabel(b),
                                key: ValueKey('uc-branch-label-${b.id}'),
                                style: monoStyle.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: C.text,
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: Dropdown<bool>(
                                  key: ValueKey('uc-branch-kind-${b.id}'),
                                  value: b.exception,
                                  items: const [false, true],
                                  labelOf: (v) =>
                                      v ? tr('ข้อผิดพลาด') : tr('ทางเลือก'),
                                  onChanged: (v) => edit(
                                    (x) =>
                                        x.branches
                                                .firstWhere((e) => e.id == b.id)
                                                .exception =
                                            v,
                                  ),
                                ),
                              ),
                              Text(tr('ที่'), style: TextStyle(color: C.muted)),
                              SizedBox(
                                width: 130,
                                child: Dropdown<String?>(
                                  key: ValueKey('uc-branch-at-${b.id}'),
                                  value:
                                      b.atStepId != null &&
                                          stepIds.contains(b.atStepId)
                                      ? b.atStepId
                                      : null,
                                  items: [null, ...stepIds],
                                  labelOf: stepLabel,
                                  onChanged: (v) => edit(
                                    (x) =>
                                        x.branches
                                                .firstWhere((e) => e.id == b.id)
                                                .atStepId =
                                            v,
                                  ),
                                ),
                              ),
                              IconButton(
                                key: ValueKey('uc-branch-del-${b.id}'),
                                tooltip: tr('ลบ'),
                                iconSize: 17,
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => edit(
                                  (x) => x.branches.removeWhere(
                                    (e) => e.id == b.id,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          CommitField(
                            key: ValueKey('uc-branch-cond-${b.id}'),
                            value: b.condition,
                            hint: tr('เกิดเมื่อ... (เช่น ห้องเต็มแล้ว)'),
                            onCommit: (v) => edit(
                              (x) =>
                                  x.branches
                                      .firstWhere((e) => e.id == b.id)
                                      .condition = v
                                      .trim(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          CommitField(
                            key: ValueKey('uc-branch-out-${b.id}'),
                            value: b.outcome,
                            hint: tr('แล้วทำอะไรต่อ'),
                            onCommit: (v) => edit(
                              (x) =>
                                  x.branches
                                      .firstWhere((e) => e.id == b.id)
                                      .outcome = v
                                      .trim(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                tr('จากนั้น'),
                                style: TextStyle(color: C.muted),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 190,
                                child: Dropdown<String?>(
                                  key: ValueKey('uc-branch-target-${b.id}'),
                                  value: b.ends
                                      ? _end
                                      : (b.returnStepId != null &&
                                                stepIds.contains(b.returnStepId)
                                            ? b.returnStepId
                                            : null),
                                  items: [null, _end, ...stepIds],
                                  labelOf: (v) => v == null
                                      ? tr('(ยังไม่ระบุ)')
                                      : (v == _end
                                            ? tr('จบ Use Case')
                                            : tr('กลับไป{0}', [stepLabel(v)])),
                                  onChanged: (v) => edit((x) {
                                    final e = x.branches.firstWhere(
                                      (e) => e.id == b.id,
                                    );
                                    e.ends = v == _end;
                                    e.returnStepId = (v == null || v == _end)
                                        ? null
                                        : v;
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              key: const ValueKey('uc-add-alt'),
              onPressed: u.steps.isEmpty
                  ? null
                  : () => edit(
                      (x) => x.branches.add(
                        UcBranch(id: w.newId('ub'), atStepId: x.steps.last.id),
                      ),
                    ),
              child: Text(tr('+ ทางเลือก')),
            ),
            OutlinedButton(
              key: const ValueKey('uc-add-ex'),
              onPressed: u.steps.isEmpty
                  ? null
                  : () => edit(
                      (x) => x.branches.add(
                        UcBranch(
                          id: w.newId('ub'),
                          atStepId: x.steps.last.id,
                          exception: true,
                        ),
                      ),
                    ),
              child: Text(tr('+ ข้อผิดพลาด')),
            ),
          ],
        ),
      ],
    );
  }
}

// ===================================================================== แผงขวา

class _SideColumn extends StatelessWidget {
  const _SideColumn({required this.w, required this.u, required this.issues});
  final WorkspaceController w;
  final UseCase u;
  final List<UcIssue> issues;

  @override
  Widget build(BuildContext context) {
    final mine = [
      for (final i in issues)
        if (i.ucId == u.id) i,
    ];
    final project = [
      for (final i in issues)
        if (i.ucId == null) i,
    ];
    final cover = useCaseCoverage(w.workspace);
    final head = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: C.muted,
      letterSpacing: 0.5,
    );
    final docs = <TraceLink>[];
    for (final s in u.steps) {
      for (final l in s.links) {
        if (!docs.contains(l)) docs.add(l);
      }
    }
    Widget chipBtn(
      String key,
      String label,
      Future<void> Function(BuildContext) onTap,
    ) => Builder(
      builder: (ctx) => OutlinedButton(
        key: ValueKey(key),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 26),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: C.muted,
          side: BorderSide(color: C.border),
        ),
        onPressed: () => onTap(ctx),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
    Widget pill(String text, VoidCallback onRemove, {Key? key}) => Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
      decoration: BoxDecoration(
        color: C.primaryTint,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: C.primary),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ข้อความยาว (เช่น เงื่อนไขของ extend) หดด้วย … แทนที่จะล้นคอลัมน์
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle.copyWith(fontSize: 11.5, color: C.primaryDark),
            ),
          ),
          InkWell(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: 13, color: C.muted),
            ),
          ),
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: C.surface,
        border: Border(left: BorderSide(color: C.border)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('ความต้องการ').toUpperCase(), style: head),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in w.requirements)
                if (u.reqIds.contains(r.id))
                  pill(
                    r.code,
                    () => w.updateUseCase(u.id, (x) => x.reqIds.remove(r.id)),
                    key: ValueKey('uc-req-${r.id}'),
                  ),
              chipBtn('uc-req-add', tr('+ ผูก REQ'), (ctx) async {
                final box = ctx.findRenderObject()! as RenderBox;
                final pos = box.localToGlobal(Offset(0, box.size.height));
                final choice = await showMenu<String>(
                  context: ctx,
                  position: RelativeRect.fromLTRB(
                    pos.dx,
                    pos.dy,
                    pos.dx + 1,
                    pos.dy + 1,
                  ),
                  items: [
                    for (final r in w.requirements)
                      CheckedPopupMenuItem<String>(
                        value: r.id,
                        checked: u.reqIds.contains(r.id),
                        height: 34,
                        child: Text(
                          '${r.code}  ${r.text}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    if (w.requirements.isEmpty)
                      PopupMenuItem<String>(
                        enabled: false,
                        child: Text(
                          tr('ยังไม่มีความต้องการ'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                );
                if (choice != null) {
                  w.updateUseCase(
                    u.id,
                    (x) => x.reqIds.contains(choice) ? x.reqIds.remove(choice) : x.reqIds.add(choice),
                  );
                }
              }),
            ],
          ),
          const SizedBox(height: 18),
          Text(tr('เรียกใช้ Use Case อื่น').toUpperCase(), style: head),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in w.useCases)
                if (u.includes.contains(o.id))
                  pill(
                    o.code,
                    () => w.updateUseCase(u.id, (x) => x.includes.remove(o.id)),
                    key: ValueKey('uc-inc-${o.id}'),
                  ),
              chipBtn('uc-inc-add', tr('+ เรียกใช้'), (ctx) async {
                final box = ctx.findRenderObject()! as RenderBox;
                final pos = box.localToGlobal(Offset(0, box.size.height));
                final others = [
                  for (final o in w.useCases)
                    if (o.id != u.id) o,
                ];
                final choice = await showMenu<String>(
                  context: ctx,
                  position: RelativeRect.fromLTRB(
                    pos.dx,
                    pos.dy,
                    pos.dx + 1,
                    pos.dy + 1,
                  ),
                  items: [
                    for (final o in others)
                      CheckedPopupMenuItem<String>(
                        value: o.id,
                        checked: u.includes.contains(o.id),
                        height: 34,
                        child: Text(
                          '${o.code}  ${o.name}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    if (others.isEmpty)
                      PopupMenuItem<String>(
                        enabled: false,
                        child: Text(
                          tr('ยังไม่มี Use Case อื่น'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                );
                if (choice != null) {
                  w.updateUseCase(
                    u.id,
                    (x) => x.includes.contains(choice) ? x.includes.remove(choice) : x.includes.add(choice),
                  );
                }
              }),
            ],
          ),
          const SizedBox(height: 18),
          Text(tr('ขยายจาก Use Case อื่น').toUpperCase(), style: head),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in u.extendsFrom)
                InkWell(
                  key: ValueKey('uc-ext-${e.baseId}'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _editExtendCondition(context, w, u, e),
                  child: pill(
                    _extendLabel(w, e),
                    () => w.updateUseCase(u.id, (x) => x.extendsFrom.removeWhere((y) => y.baseId == e.baseId)),
                  ),
                ),
              chipBtn('uc-ext-add', tr('+ ขยายจาก'), (ctx) async {
                final box = ctx.findRenderObject()! as RenderBox;
                final pos = box.localToGlobal(Offset(0, box.size.height));
                final others = [
                  for (final o in w.useCases)
                    if (o.id != u.id) o,
                ];
                final choice = await showMenu<String>(
                  context: ctx,
                  position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
                  items: [
                    for (final o in others)
                      CheckedPopupMenuItem<String>(
                        value: o.id,
                        checked: u.extendsFrom.any((e) => e.baseId == o.id),
                        height: 34,
                        child: Text('${o.code}  ${o.name}', style: const TextStyle(fontSize: 13)),
                      ),
                    if (others.isEmpty)
                      PopupMenuItem<String>(enabled: false, child: Text(tr('ยังไม่มี Use Case อื่น'), style: const TextStyle(fontSize: 13))),
                  ],
                );
                if (choice != null) {
                  w.updateUseCase(u.id, (x) {
                    if (!x.extendsFrom.any((e) => e.baseId == choice)) {
                      x.extendsFrom.add(UcExtend(baseId: choice));
                    } else {
                      x.extendsFrom.removeWhere((e) => e.baseId == choice);
                    }
                  });
                }
              }),
            ],
          ),
          const SizedBox(height: 18),
          Text(tr('เอกสารที่ถูกอ้างถึง').toUpperCase(), style: head),
          const SizedBox(height: 8),
          if (docs.isEmpty)
            Text(
              tr('ยังไม่มี — ผูกขั้นตอนกับหน้าจอ endpoint หรือตาราง'),
              style: TextStyle(fontSize: 12.5, color: C.muted),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final l in docs) _LinkChip(w: w, link: l)],
            ),
          const SizedBox(height: 18),
          Text('${tr('ตรวจ').toUpperCase()} · ${mine.length}', style: head),
          const SizedBox(height: 8),
          if (mine.isEmpty)
            Text(
              tr('✓ ไม่พบปัญหา'),
              key: const ValueKey('uc-no-issues'),
              style: TextStyle(fontSize: 12.5, color: C.primaryDark),
            )
          else
            for (final i in mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: UcIssueTile(
                  key: ValueKey('uc-issue-${i.code}'),
                  issue: i,
                ),
              ),
          const SizedBox(height: 18),
          Text(tr('ความครอบคลุมของความต้องการ').toUpperCase(), style: head),
          const SizedBox(height: 6),
          Text(
            cover.total == 0
                ? tr('ยังไม่มีความต้องการ')
                : tr('{0} จาก {1} ข้อมี Use Case', [
                    cover.covered,
                    cover.total,
                  ]),
            key: const ValueKey('uc-cover-side'),
          ),
          if (cover.total > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: cover.covered / cover.total,
                minHeight: 6,
                backgroundColor: C.borderSoft,
                color: C.primary,
              ),
            ),
          ],
          for (final i in project)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: UcIssueTile(key: ValueKey('uc-proj-${i.reqId}'), issue: i),
            ),
        ],
      ),
    );
  }
}

class UcIssueTile extends StatelessWidget {
  const UcIssueTile({super.key, required this.issue});
  final UcIssue issue;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = IssueCard.style(issue.severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                if (issue.detail.isNotEmpty)
                  Text(
                    issue.detail,
                    style: TextStyle(fontSize: 11.5, color: fg),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===================================================================== แท็บเอกสาร

class _DocTab extends StatelessWidget {
  const _DocTab({required this.w});
  final WorkspaceController w;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: C.muted);
    Widget para(String label, String v) => v.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label  ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: v.trim()),
                ],
              ),
            ),
          );
    return ListView(
      key: const ValueKey('uc-doc'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final u in w.useCases)
                  Container(
                    key: ValueKey('uc-doc-${u.id}'),
                    margin: const EdgeInsets.only(bottom: 28),
                    padding: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: C.borderSoft)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.code,
                          style: monoStyle.copyWith(
                            fontSize: 12,
                            color: C.muted,
                          ),
                        ),
                        Text(
                          u.name.trim().isEmpty
                              ? tr('(ไม่มีชื่อ)')
                              : u.name.trim(),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: C.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _Tag(
                              '${tr('ผู้กระทำ')}: ${u.actor.trim().isEmpty ? '-' : u.actor.trim()}${u.secondaryActors.isEmpty ? '' : ' + ${u.secondaryActors.join(', ')}'}',
                            ),
                            _Tag(ucStatusLabel(u.status)),
                            _Tag(
                              '${tr('ความสำคัญ')}: ${ucPriorityLabel(u.priority)}',
                            ),
                            for (final r in w.requirements)
                              if (u.reqIds.contains(r.id))
                                _Tag(r.code, mono: true),
                          ],
                        ),
                        const SizedBox(height: 12),
                        para(tr('เป้าหมาย'), u.goal),
                        para(tr('ตัวเริ่มต้น'), u.trigger),
                        para(tr('เงื่อนไขก่อนเริ่ม'), u.preconditions),
                        if (u.steps.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            tr('ขั้นตอนหลัก'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          for (final (i, s) in u.steps.indexed)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 26,
                                    child: Text(
                                      '${i + 1}.',
                                      style: monoStyle.copyWith(color: C.muted),
                                    ),
                                  ),
                                  Expanded(
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        _Tag(ucWhoLabel(s.who)),
                                        Text(s.text.trim()),
                                        for (final l in s.links)
                                          _LinkChip(w: w, link: l),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        if (u.branches.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            tr('ทางเลือกและข้อผิดพลาด'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          for (final b in u.branches)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '${u.branchLabel(b)}  ',
                                      style: monoStyle.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: b.exception
                                            ? C.danger
                                            : C.warnText,
                                      ),
                                    ),
                                    TextSpan(text: b.condition.trim()),
                                    TextSpan(
                                      text:
                                          ' → ${b.outcome.trim().isEmpty ? '' : '${b.outcome.trim()} · '}${ucBranchTarget(u, b)}',
                                      style: muted,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                        const SizedBox(height: 8),
                        para(tr('ผลลัพธ์เมื่อสำเร็จ'), u.postconditions),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.mono = false});
  final String text;
  final bool mono;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: C.surfaceHi,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: C.border),
    ),
    child: Text(
      text,
      style: (mono ? monoStyle : const TextStyle()).copyWith(
        fontSize: 11.5,
        color: C.text,
      ),
    ),
  );
}

/// ป้ายของ extend : รหัสของ Use Case ฐาน + เงื่อนไข (ฐานที่ไม่มีแล้ว = ?)
String _extendLabel(WorkspaceController w, UcExtend e) {
  final base = w.useCaseById(e.baseId);
  final c = e.condition.trim();
  return '${base?.code ?? '?'}${c.isEmpty ? '' : ' · [$c]'}';
}

/// กล่องแก้เงื่อนไขของ extend (ว่าง = ไม่มีเงื่อนไข)
Future<void> _editExtendCondition(BuildContext context, WorkspaceController w, UseCase u, UcExtend e) async {
  final base = w.useCaseById(e.baseId);
  final v = await showDialog<String>(
    context: context,
    builder: (_) => _ExtendConditionDialog(title: tr('เงื่อนไขของการขยาย {0}', [base?.code ?? '?']), initial: e.condition),
  );
  if (v == null) return;
  w.updateUseCase(u.id, (x) {
    for (final t in x.extendsFrom) {
      if (t.baseId == e.baseId) t.condition = v.trim();
    }
  });
}

/// กล่องพิมพ์เงื่อนไข : ถือ controller เอง (dispose ตอนกล่องถูกถอดจริง ไม่ใช่ตอนเริ่มปิด จึงไม่ชนกับแอนิเมชันปิด)
class _ExtendConditionDialog extends StatefulWidget {
  const _ExtendConditionDialog({required this.title, required this.initial});
  final String title, initial;

  @override
  State<_ExtendConditionDialog> createState() => _ExtendConditionDialogState();
}

class _ExtendConditionDialogState extends State<_ExtendConditionDialog> {
  late final TextEditingController _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const ValueKey('uc-ext-dialog'),
        title: Text(widget.title),
        content: SizedBox(
          width: 360,
          child: TextField(
            key: const ValueKey('uc-ext-condition'),
            controller: _ctl,
            autofocus: true,
            decoration: InputDecoration(hintText: tr('เช่น มีโค้ดส่วนลด (เว้นว่าง = ไม่มีเงื่อนไข)')),
            onSubmitted: (t) => Navigator.pop(context, t),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
          FilledButton(key: const ValueKey('uc-ext-ok'), onPressed: () => Navigator.pop(context, _ctl.text), child: Text(tr('ตกลง'))),
        ],
      );
}
