import 'package:flutter/material.dart';

import '../core/export/usecase_export.dart' show ucWhoLabel;
import '../core/export/usecase_testcases.dart';
import '../core/l10n/l10n.dart';
import '../core/models/use_case.dart';
import '../core/models/workspace.dart';
import '../state/workspace_controller.dart';
import 'file_actions.dart';
import 'theme.dart';
import 'widgets.dart';

/// แท็บ "กรณีทดสอบ" ของหน้า Use Case (แบบ A ของ `design/use-case-phase30-32`) : ตารางพรีวิว กดแถวขยายขั้นตอน
/// กรองตามชนิด/Use Case ; ส่งออก Markdown (ตาราง / Given-When-Then) และ CSV — สร้างจากสเปกเสมอ ไม่แก้ที่นี่
class UcTestsTab extends StatefulWidget {
  const UcTestsTab({super.key, required this.w});
  final WorkspaceController w;

  @override
  State<UcTestsTab> createState() => _UcTestsTabState();
}

class _UcTestsTabState extends State<UcTestsTab> {
  final Set<String> _open = {};
  TcKind? _kind;
  String? _ucId;

  Color _kindFg(TcKind k) => switch (k) {
        TcKind.main => C.primaryDark,
        TcKind.alternative => C.warnText,
        TcKind.exception => C.dangerText,
      };
  Color _kindBg(TcKind k) => switch (k) {
        TcKind.main => C.primaryTint,
        TcKind.alternative => C.warnBg,
        TcKind.exception => C.dangerBg,
      };

  String get _base => FileActions.safeName(widget.w.workspace.name);

  Future<void> _export(BuildContext context, String what, List<TestCase> all) async {
    final ws = widget.w.workspace;
    final title = tr('ส่งออกกรณีทดสอบ');
    switch (what) {
      case 'table':
        await FileActions.saveText(context, exportTestCasesMarkdown(ws, cases: all), '$_base-testcases.md', title);
      case 'gwt':
        await FileActions.saveText(context, exportTestCasesMarkdown(ws, style: TcMarkdownStyle.givenWhenThen, cases: all), '$_base-testcases-gwt.md', title);
      case 'csv':
        await FileActions.saveText(context, exportTestCasesCsv(ws, cases: all), '$_base-testcases.csv', title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    if (w.useCases.isEmpty) {
      return Center(child: Text(tr('ยังไม่มี Use Case จึงยังไม่มีกรณีทดสอบ'), key: const ValueKey('uc-tc-empty'), style: TextStyle(color: C.muted)));
    }
    final all = generateTestCases(w.workspace);
    final s = testCaseSummary(w.workspace, all);
    final ucId = w.useCaseById(_ucId ?? '') == null ? null : _ucId;
    final shown = [
      for (final c in all)
        if ((_kind == null || c.kind == _kind) && (ucId == null || c.ucId == ucId)) c,
    ];
    Widget chip(String key, String text, {bool good = false}) => Container(
          key: ValueKey(key),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: good ? C.primaryTint : C.surfaceHi, borderRadius: BorderRadius.circular(6), border: Border.all(color: good ? C.primary : C.border)),
          child: Text(text, style: TextStyle(fontSize: 12, color: good ? C.primaryDark : C.text)),
        );
    final head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: C.muted);
    Widget row(List<Widget> cells, {Color? bg}) => Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells),
        );

    final bar = Container(
      decoration: BoxDecoration(color: C.surface, border: Border(bottom: BorderSide(color: C.border))),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(tr('กรณีทดสอบ'), style: TextStyle(fontWeight: FontWeight.w700, color: C.text)),
        chip('uc-tc-total', tr('{0} กรณี', [s.total])),
        chip('uc-tc-main', '${tr('หลัก')} ${s.main}'),
        chip('uc-tc-alt', '${tr('ทางเลือก')} ${s.alternative}'),
        chip('uc-tc-exc', '${tr('ข้อผิดพลาด')} ${s.exception}'),
        if (s.reqTotal > 0) chip('uc-tc-req', tr('ความต้องการที่มีกรณีทดสอบ {0} / {1} ข้อ', [s.reqCovered, s.reqTotal]), good: s.reqCovered == s.reqTotal),
        SizedBox(
          width: 150,
          child: Dropdown<TcKind?>(
            key: const ValueKey('uc-tc-filter-kind'),
            value: _kind,
            items: [null, ...TcKind.values],
            labelOf: (k) => k == null ? tr('ทุกชนิด') : tcKindLabel(k),
            onChanged: (k) => setState(() => _kind = k),
          ),
        ),
        SizedBox(
          width: 210,
          child: Dropdown<String?>(
            key: const ValueKey('uc-tc-filter-uc'),
            value: ucId,
            items: [null, for (final u in w.useCases) u.id],
            labelOf: (id) => id == null ? tr('ทุก Use Case') : '${w.useCaseById(id)!.code} ${w.useCaseById(id)!.name}'.trim(),
            onChanged: (id) => setState(() => _ucId = id),
          ),
        ),
        PopupMenuButton<String>(
          key: const ValueKey('uc-tc-export'),
          tooltip: tr('ส่งออกกรณีทดสอบ'),
          onSelected: (v) => _export(context, v, all),
          itemBuilder: (_) => [
            PopupMenuItem(key: const ValueKey('uc-tc-export-table'), value: 'table', child: Text(tr('Markdown · ตาราง (ขั้นตอน / ผลที่คาดหวัง)'))),
            PopupMenuItem(key: const ValueKey('uc-tc-export-gwt'), value: 'gwt', child: Text(tr('Markdown · Given / When / Then'))),
            PopupMenuItem(key: const ValueKey('uc-tc-export-csv'), value: 'csv', child: Text(tr('CSV · เปิดใน Excel / Sheets'))),
          ],
          child: IgnorePointer(child: FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.ios_share_rounded, size: 16), label: Text(tr('ส่งออก')))),
        ),
      ]),
    );

    final table = LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth < 980 ? 980.0 : box.maxWidth;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          height: box.maxHeight,
          child: Column(children: [
            row([
              SizedBox(width: 150, child: Text(tr('รหัส'), style: head)),
              SizedBox(width: 170, child: Text('Use Case', style: head)),
              SizedBox(width: 110, child: Text(tr('ประเภท'), style: head)),
              Expanded(flex: 4, child: Text('${tr('เงื่อนไขก่อนเริ่ม')} / ${tr('ขั้นตอน')}', style: head)),
              Expanded(flex: 3, child: Text(tr('ผลที่คาดหวัง'), style: head)),
              Expanded(flex: 3, child: Text(tr('อ้างอิง'), style: head)),
            ], bg: C.surfaceHi),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Text(tr('ไม่พบกรณีที่ตรงตัวกรอง'), key: const ValueKey('uc-tc-none'), style: TextStyle(color: C.muted)))
                  : ListView(children: [for (final c in shown) _caseRow(c, row)]),
            ),
          ]),
        ),
      );
    });

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      bar,
      Expanded(child: Container(color: C.surface, child: table)),
      Container(
        color: C.surfaceHi,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Text(tr('แสดง {0} จาก {1} กรณี · กดแถวเพื่อขยายขั้นตอน', [shown.length, all.length]), key: const ValueKey('uc-tc-footer'), style: TextStyle(fontSize: 12, color: C.muted)),
      ),
    ]);
  }

  Widget _caseRow(TestCase c, Widget Function(List<Widget>, {Color? bg}) row) {
    final open = _open.contains(c.id);
    final refs = [if (c.reqCodes.isNotEmpty) c.reqCodes.join(', '), for (final r in c.refs) '${_short(r.type)}: ${r.label}'].join(' · ');
    return InkWell(
      key: ValueKey('uc-tc-${c.id}'),
      onTap: () => setState(() => open ? _open.remove(c.id) : _open.add(c.id)),
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: C.borderSoft))),
        child: row([
          SizedBox(
            width: 150,
            child: Row(children: [
              Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 16, color: C.muted),
              Flexible(child: Text(c.id, style: monoStyle.copyWith(fontSize: 12, color: C.text), overflow: TextOverflow.ellipsis)),
            ]),
          ),
          SizedBox(width: 170, child: Text('${c.ucCode} ${c.ucName}', maxLines: 2, overflow: TextOverflow.ellipsis)),
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(color: _kindBg(c.kind), borderRadius: BorderRadius.circular(999)),
                child: Text('${tcKindLabel(c.kind)}${c.branchLabel == null ? '' : ' ${c.branchLabel}'}',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _kindFg(c.kind))),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                c.precondition.isEmpty ? tr('(ไม่มีเงื่อนไขก่อนเริ่ม)') : c.precondition,
                style: TextStyle(color: C.muted),
              ),
              if (open)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final (i, st) in c.steps.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: '${i + 1}. ', style: monoStyle.copyWith(color: C.muted)),
                          TextSpan(
                            text: '${ucWhoLabel(st.who)}  ',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: st.who == UcWho.user ? C.primaryDark : C.muted),
                          ),
                          TextSpan(text: st.text, style: TextStyle(color: st.isCondition ? C.warnText : C.text)),
                        ])),
                      ),
                  ]),
                )
              else
                Text(tr('{0} ขั้นตอน', [c.steps.length]), style: TextStyle(fontSize: 12, color: C.muted)),
            ]),
          ),
          Expanded(flex: 3, child: Text(c.expected.isEmpty ? '-' : c.expected)),
          Expanded(flex: 3, child: Text(refs.isEmpty ? '-' : refs, style: TextStyle(fontSize: 12, color: C.muted))),
        ]),
      ),
    );
  }

  String _short(DocType t) => switch (t) {
        DocType.er => 'ER',
        DocType.dfd => 'DFD',
        DocType.flowchart => 'Flowchart',
        DocType.wireframe => 'Wireframe',
        DocType.screenflow => 'Screen Flow',
        DocType.api => 'API',
      };
}
