import 'dart:math' as math;

import '../layout/wireframe_render.dart' show wfGray, wfPalette, WfPalette;
import '../models/api_model.dart';
import '../models/project.dart';
import '../models/table_model.dart';
import '../models/wireframe_model.dart';
import '../models/workspace.dart';

/// หน้า HTML ของ Wireframe ที่ "หน้าตาตรงกับแบบ": ทุกชิ้นวางตามตำแหน่ง/ขนาด/การหมุนในแบบ (พิกัดสัมพัทธ์กับภาชนะที่ครอบ),
/// สีและรูปทรงตามรูปแบบการแสดงผลของเอกสาร (เรียบร้อย/ร่าง — ชุดสีเดียวกับแคนวาส [wfPalette]), ชิ้นที่ซ่อน = `hidden`
/// ชิ้นที่ผูก ER ได้ข้อมูลตั้งต้นจริง (ตัวเลือกใน select, แถวในตาราง) ; ผูกข้อมูล/endpoint บอกไว้ใน `data-bind` / `data-api`
/// หน้าจอกว้างกว่าหน้าต่าง = ย่อทั้งหน้าให้พอดี (สคริปต์ท้ายไฟล์) — โครงหน้าใช้เป็นจุดเริ่มเขียนเว็บจริงต่อได้
String wireframeHtmlPage(String name, WireframeDiagram d, {String lang = 'th', Workspace? workspace}) =>
    _WfHtml(d, workspace).page(name, lang);

String _h(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

String _n(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? '${r.round()}' : r.toStringAsFixed(1);
}

String _px(double v) => '${_n(v)}px';

class _WfHtml {
  _WfHtml(this.d, this.ws)
      : p = wfPalette(d),
        parents = wfParentMap(d);

  final WireframeDiagram d;
  final Workspace? ws;
  final WfPalette p;
  final Map<String, String> parents;
  final out = StringBuffer();

  bool get sketch => p.sketch;

  // ---------------------------------------------------------------- ข้อมูลจาก ER / API

  TableModel? _table(WfDataRef? r) {
    if (r == null) return null;
    final er = ws?.documentById(r.docId)?.er;
    return er?.tableById(r.tableId);
  }

  Project? _project(WfDataRef? r) => r == null ? null : ws?.documentById(r.docId)?.er;

  String? _bind(WfComponent c) {
    final r = c.ref;
    if (r == null) return null;
    final t = _table(r);
    if (t == null) return r.columnId == null ? r.tableId : '${r.tableId}.${r.columnId}';
    if (r.columnId == null) return t.name;
    final col = t.columns.where((x) => x.id == r.columnId).firstOrNull;
    return col == null ? t.name : '${t.name}.${col.name}';
  }

  String? _api(WfComponent c) {
    final a = c.api;
    if (a == null) return null;
    final e = ws?.documentById(a.docId)?.api?.endpointById(a.endpointId);
    return e == null ? a.endpointId : '${e.method.label} ${e.path}';
  }

  /// ค่าตั้งต้นของคอลัมน์ที่ผูก (ไม่ซ้ำ ไม่ว่าง ตามลำดับ)
  List<String> _seedValues(WfComponent c) {
    final t = _table(c.ref);
    final colId = c.ref?.columnId;
    if (t == null || colId == null) return const [];
    final seen = <String>{};
    return [
      for (final r in t.seedRows)
        if ((r[colId] ?? '').trim().isNotEmpty && seen.add(r[colId]!.trim())) r[colId]!.trim(),
    ];
  }

  /// แถวตัวอย่างของตารางที่ผูก ER: จับหัวคอลัมน์กับคอลัมน์ (ชื่อ / คำอธิบาย / ตารางปลายทางของ FK) ; จับไม่ได้ = null (แถบเทา)
  List<List<String?>> _tableRows(WfComponent c, List<String> headers) {
    final t = _table(c.ref);
    final pr = _project(c.ref);
    if (t == null || pr == null || t.seedRows.isEmpty) return const [];
    bool match(String name, String comment, String h) {
      final hl = h.trim().toLowerCase();
      if (hl.isEmpty) return false;
      final nl = name.toLowerCase(), cl = comment.trim().toLowerCase();
      return nl == hl || cl == hl || (cl.isNotEmpty && cl.startsWith(hl)) || nl.startsWith(hl) || nl.replaceAll('_', ' ') == hl;
    }

    // แต่ละหัวคอลัมน์ -> ฟังก์ชันอ่านค่าจากแถว
    final readers = <String? Function(Map<String, String?>)?>[];
    for (final h in headers) {
      final direct = t.columns.where((col) => match(col.name, col.comment, h)).firstOrNull;
      if (direct != null) {
        readers.add((r) => r[direct.id]);
        continue;
      }
      // FK ที่ตารางปลายทางชื่อ/คำอธิบายตรงหัวคอลัมน์ -> แสดงคอลัมน์ข้อความแรกของแถวปลายทาง
      String? Function(Map<String, String?>)? via;
      for (final rel in pr.relations.where((x) => x.fromTableId == t.id)) {
        final to = pr.tableById(rel.toTableId);
        if (to == null || !match(to.name, to.comment, h)) continue;
        final label = to.columns.where((x) => !x.isPrimaryKey && x.id != rel.toColumnId).firstOrNull;
        if (label == null) continue;
        via = (r) {
          final key = r[rel.fromColumnId];
          final hit = to.seedRows.where((x) => x[rel.toColumnId] == key).firstOrNull;
          return hit?[label.id] ?? key;
        };
        break;
      }
      readers.add(via);
    }
    return [
      for (final r in t.seedRows) [for (final f in readers) f?.call(r)],
    ];
  }

  // ---------------------------------------------------------------- หน้า

  String page(String name, String lang) {
    final font = sketch ? 'Itim' : 'Noto Sans Thai';
    final fontUrl = sketch
        ? 'https://fonts.googleapis.com/css2?family=Itim&display=swap'
        : 'https://fonts.googleapis.com/css2?family=Noto+Sans+Thai:wght@400;600;700&display=swap';
    out
      ..writeln('<!DOCTYPE html>')
      ..writeln('<!-- สร้างโดย NSL Nebular จาก Wireframe "${_h(name.replaceAll('\n', ' ')).replaceAll('--', '- -')}" '
          '(${_n(d.width)}×${_n(d.height)} ${sketch ? 'ร่าง' : 'เรียบร้อย'}) — วางตามแบบทุกชิ้น ; data-bind = ผูกข้อมูล ER, data-api = endpoint -->')
      ..writeln('<html lang="$lang">')
      ..writeln('<head>')
      ..writeln('<meta charset="utf-8">')
      ..writeln('<meta name="viewport" content="width=device-width, initial-scale=1">')
      ..writeln('<title>${_h(name)}</title>')
      ..writeln('<link rel="preconnect" href="https://fonts.googleapis.com">')
      ..writeln('<link rel="stylesheet" href="$fontUrl">')
      ..writeln('<script src="https://cdn.tailwindcss.com"></script>')
      ..writeln('<style>')
      ..write(_css(font))
      ..writeln('</style>')
      ..writeln('</head>')
      ..writeln('<body class="${sketch ? 'wf-sketch' : 'wf-clean'}">')
      ..writeln('<div id="wf-stage" class="wf-stage" style="width:${_px(d.width)};height:${_px(d.height)}">')
      ..writeln('<main id="wf-page" class="wf-page" style="width:${_px(d.width)};height:${_px(d.height)}">');
    final hiddenOwn = {for (final c in d.components) if (c.hidden) c.id};
    for (final c in d.components.where((c) => !parents.containsKey(c.id))) {
      _emit(c, 0, 0, 1, hiddenOwn);
    }
    out
      ..writeln('</main>')
      ..writeln('</div>')
      ..writeln('<script>')
      ..writeln('// หน้าต่างแคบกว่าแบบ = ย่อทั้งหน้าให้พอดีความกว้าง (คงสัดส่วนตามแบบ)')
      ..writeln('(function () {')
      ..writeln('  var stage = document.getElementById("wf-stage"), page = document.getElementById("wf-page");')
      ..writeln('  var W = ${_n(d.width)}, H = ${_n(d.height)};')
      ..writeln('  function fit() {')
      ..writeln('    var k = Math.min(1, (document.documentElement.clientWidth - 32) / W);')
      ..writeln('    page.style.transform = k < 1 ? "scale(" + k + ")" : "";')
      ..writeln('    stage.style.width = W * k + "px";')
      ..writeln('    stage.style.height = H * k + "px";')
      ..writeln('  }')
      ..writeln('  window.addEventListener("resize", fit);')
      ..writeln('  fit();')
      ..writeln('})();')
      ..writeln('</script>')
      ..writeln('</body>')
      ..writeln('</html>');
    return out.toString();
  }

  String _css(String font) {
    final accentPrimaryFill = sketch ? '#DADADA' : 'var(--wf-accent)';
    final bw = sketch ? '1.4px' : '1px';
    return '''
:root {
  --wf-surface: ${_hex(p.surface)}; --wf-subtle: ${_hex(p.subtle)}; --wf-border: ${_hex(p.border)};
  --wf-text: ${_hex(p.text)}; --wf-muted: ${_hex(p.muted)}; --wf-accent: ${_hex(p.accent)};
  --wf-on-accent: ${_hex(p.onAccent)}; --wf-tint: ${_hex(p.accentTint)}; --wf-bw: $bw;
  --wf-bar: ${sketch ? '#C8C8C8' : '#E4E7EC'}; --wf-line: ${sketch ? '#BDBDBD' : _hex(p.border)};
}
* { box-sizing: border-box; }
body { margin: 0; padding: 16px; background: ${sketch ? '#F4F4F2' : '#EEF1F5'}; color: var(--wf-text); font-family: '$font', system-ui, sans-serif; }
.wf-stage { margin: 0 auto; }
.wf-page { position: relative; overflow: hidden; transform-origin: 0 0; background: var(--wf-surface); outline: var(--wf-bw) solid ${sketch ? 'var(--wf-border)' : '#98A2B3'}; }
.wf { position: absolute; margin: 0; padding: 0; line-height: 1.3; font: inherit; font-size: 14px; color: inherit; }
.wf[hidden] { display: none; }
.wf-off { opacity: .45; }
.wf-para { white-space: pre-line; overflow: hidden; }
.wf-t { display: flex; align-items: center; min-width: 0; }
.wf-1 { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; min-width: 0; }
.wf-bar { display: inline-block; height: 6px; border-radius: 3px; background: var(--wf-bar); vertical-align: middle; }
.wf-box { border: var(--wf-bw) solid var(--wf-border); border-radius: 4px; background: var(--wf-surface); }
.wf-r6, .wf-acc { border-radius: 6px; }
.wf-dashed { border-style: dashed; background: transparent; }
.wf-cap { position: absolute; left: 8px; top: 4px; right: 8px; font-size: .85em; color: var(--wf-muted); }
.wf-card { border: var(--wf-bw) solid var(--wf-border); border-radius: 8px; background: var(--wf-surface); }
.wf-card > .wf-card-h { position: absolute; left: 12px; top: 8px; right: 12px; margin: 0; font-size: 1em; font-weight: 700; }
.wf-btn { justify-content: center; padding: 0 6px; border: var(--wf-bw) solid var(--wf-accent); border-radius: 6px; background: $accentPrimaryFill; color: var(--wf-on-accent); font-weight: 700; cursor: pointer; }
.wf-btn-2 { background: var(--wf-surface); color: var(--wf-accent); }
.wf-sketch .wf-btn { border: 2px solid var(--wf-border); color: var(--wf-text); }
.wf-sketch .wf-btn-2 { border-width: var(--wf-bw); background: #FFFFFF; }
.wf-field { border: var(--wf-bw) solid var(--wf-border); border-radius: 4px; background: var(--wf-surface); padding: 0 10px; color: var(--wf-text); }
.wf-field::placeholder, .wf-field input::placeholder { color: var(--wf-muted); }
textarea.wf-field { padding: 8px 10px; resize: none; }
select.wf-field { appearance: none; padding-right: 28px; background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='6'%3E%3Cpath d='M.5.5l4.5 4.5L9.5.5' fill='none' stroke='%23${_hex(p.text).substring(1)}' stroke-width='1.5'/%3E%3C/svg%3E"); background-repeat: no-repeat; background-position: right 11px center; }
.wf-search { display: flex; align-items: center; gap: 8px; }
.wf-search input { flex: 1; min-width: 0; border: 0; outline: 0; background: transparent; font: inherit; color: inherit; }
.wf-check { gap: 8px; cursor: pointer; }
.wf-check input { width: 16px; height: 16px; margin: 0; flex: none; accent-color: var(--wf-accent); }
.wf-check input[type=checkbox]:not(.wf-switch) { appearance: none; border: var(--wf-bw) solid var(--wf-border); border-radius: 3px; background: var(--wf-surface); display: grid; place-content: center; }
.wf-check input[type=checkbox]:not(.wf-switch):checked { background: ${sketch ? 'var(--wf-surface)' : 'var(--wf-accent)'}; border-color: ${sketch ? 'var(--wf-border)' : 'var(--wf-accent)'}; }
.wf-check input[type=checkbox]:not(.wf-switch):checked::after { content: ""; width: 8px; height: 4px; border: solid ${sketch ? 'var(--wf-text)' : 'var(--wf-on-accent)'}; border-width: 0 0 2px 2px; transform: translateY(-1px) rotate(-45deg); }
.wf-date { color: var(--wf-text); }
.wf-date input { order: 0; }
.wf-switch { appearance: none; width: 36px !important; height: 20px !important; border-radius: 10px; background: var(--wf-subtle); border: var(--wf-bw) solid var(--wf-border); position: relative; }
.wf-switch::after { content: ""; position: absolute; left: 2px; top: 2px; width: 14px; height: 14px; border-radius: 50%; background: #FFFFFF; transition: left .15s; }
.wf-switch:checked { background: ${sketch ? '#9A9A9A' : 'var(--wf-accent)'}; border-color: ${sketch ? 'var(--wf-border)' : 'var(--wf-accent)'}; }
.wf-switch:checked::after { left: 18px; }
.wf-range { accent-color: var(--wf-accent); }
.wf-img { border: var(--wf-bw) solid var(--wf-border); background: ${sketch ? '#FFFFFF' : '#E4E7EC'}; overflow: hidden; }
.wf-img svg, .wf-avatar svg, .wf-icon svg, .wf-video svg { position: absolute; inset: 0; width: 100%; height: 100%; }
.wf-avatar { border: var(--wf-bw) solid var(--wf-border); border-radius: 50%; background: var(--wf-subtle); overflow: hidden; }
.wf-icon { border-radius: 20%; background: var(--wf-subtle); }
.wf-table-box { border: var(--wf-bw) solid var(--wf-border); border-radius: 4px; background: var(--wf-surface); overflow: hidden; }
.wf-table { width: 100%; border-collapse: collapse; table-layout: fixed; }
.wf-table th { background: ${sketch ? '#EDEDED' : 'var(--wf-subtle)'}; text-align: left; font-weight: 700; padding: 0 8px; border-bottom: 1px solid var(--wf-border); }
.wf-table td { padding: 0 8px; border-top: .8px solid var(--wf-line); }
.wf-table tr > :not(:first-child) { border-left: .8px solid var(--wf-line); }
.wf-table th, .wf-table td { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.wf-list { list-style: none; margin: 0; padding: 0; }
.wf-list li { display: flex; align-items: center; gap: 10px; padding: 0 8px 0 11px; border-top: .8px solid var(--wf-line); }
.wf-list li:first-child { border-top: 0; }
.wf-list li::before { content: ""; width: 6px; height: 6px; border-radius: 50%; background: var(--wf-muted); flex: none; }
.wf-tabs { display: flex; border-bottom: 1px solid var(--wf-border); }
.wf-tabs a { flex: 1; display: flex; align-items: center; justify-content: center; color: var(--wf-muted); text-decoration: none; border-bottom: 2.5px solid transparent; }
.wf-tabs a.on { color: ${sketch ? 'var(--wf-text)' : 'var(--wf-accent)'}; font-weight: 700; border-bottom-color: ${sketch ? 'var(--wf-text)' : 'var(--wf-accent)'}; }
.wf-nav, .wf-foot { border: var(--wf-bw) solid var(--wf-border); background: var(--wf-surface); }
.wf-foot { background: var(--wf-subtle); color: var(--wf-muted); }
.wf-brand { position: absolute; left: 16px; top: 0; bottom: 0; display: flex; align-items: center; font-weight: 700; max-width: 50%; }
.wf-foot .wf-brand { font-weight: 400; }
.wf-fake { position: absolute; top: 0; bottom: 0; right: 24px; display: flex; align-items: center; gap: 16px; }
.wf-side { border: var(--wf-bw) solid var(--wf-border); background: var(--wf-subtle); padding: 12px 8px; }
.wf-side a { display: flex; align-items: center; height: 30px; margin-bottom: 6px; padding: 0 10px; border-radius: 6px; color: inherit; text-decoration: none; }
.wf-side a.on { background: ${sketch ? '#E0E0E0' : 'var(--wf-tint)'}; color: ${sketch ? 'inherit' : 'var(--wf-accent)'}; font-weight: 700; }
.wf-modal { border: ${sketch ? '1.8px' : '1.2px'} solid var(--wf-border); border-radius: 10px; background: var(--wf-surface); box-shadow: 3px 4px 0 rgba(0,0,0,.08); }
.wf-modal-h { display: flex; align-items: center; justify-content: space-between; padding: 0 12px 0 16px; border-bottom: .8px solid var(--wf-border); font-weight: 700; }
.wf-modal-h button { border: 0; background: none; color: var(--wf-muted); font-size: 18px; cursor: pointer; }
.wf-badge { justify-content: center; padding: 0 4px; border-radius: 999px; background: ${sketch ? '#FFFFFF' : 'var(--wf-tint)'}; color: ${sketch ? 'var(--wf-text)' : 'var(--wf-accent)'}; font-weight: 700; ${sketch ? 'border: var(--wf-bw) solid var(--wf-border);' : ''} }
.wf-pages { display: flex; align-items: center; gap: 4px; }
.wf-pages a { display: flex; align-items: center; justify-content: center; border: var(--wf-bw) solid var(--wf-border); border-radius: 4px; color: inherit; text-decoration: none; background: var(--wf-surface); }
.wf-pages a.on { background: ${sketch ? '#DADADA' : 'var(--wf-accent)'}; border-color: ${sketch ? 'var(--wf-border)' : 'var(--wf-accent)'}; color: ${sketch ? 'inherit' : 'var(--wf-on-accent)'}; }
.wf-muted { color: var(--wf-muted); }
.wf-link { color: ${sketch ? 'var(--wf-text)' : 'var(--wf-accent)'}; text-decoration: underline; text-underline-offset: 3px; }
.wf-chip { justify-content: space-between; gap: 4px; padding: 0 6px 0 10px; border: var(--wf-bw) solid var(--wf-border); border-radius: 999px; background: ${sketch ? '#FFFFFF' : 'var(--wf-subtle)'}; }
.wf-chip button { border: 0; background: none; color: var(--wf-muted); cursor: pointer; padding: 0 4px; font-size: 1.1em; line-height: 1; }
.wf-progress { display: flex; align-items: center; gap: 8px; }
.wf-progress .track { flex: 1; height: 10px; border-radius: 5px; background: var(--wf-subtle); overflow: hidden; ${sketch ? 'border: var(--wf-bw) solid var(--wf-border); background: #FFFFFF;' : ''} }
.wf-progress .fill { height: 100%; border-radius: 5px; background: ${sketch ? '#9A9A9A' : 'var(--wf-accent)'}; }
.wf-alert { gap: 10px; padding: 0 12px 0 14px; border: var(--wf-bw) solid var(--wf-border); border-left: 5px solid ${sketch ? 'var(--wf-border)' : 'var(--wf-accent)'}; border-radius: 6px; background: ${sketch ? '#FFFFFF' : 'var(--wf-tint)'}; }
.wf-alert-i { flex: none; width: 20px; height: 20px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-weight: 700; font-size: 13px; background: ${sketch ? 'transparent' : 'var(--wf-accent)'}; color: ${sketch ? 'var(--wf-text)' : 'var(--wf-on-accent)'}; ${sketch ? 'border: 1.4px solid var(--wf-border);' : ''} }
.wf-upload { flex-direction: column; justify-content: center; gap: 8px; border: var(--wf-bw) dashed var(--wf-border); border-radius: 8px; background: ${sketch ? 'transparent' : 'var(--wf-subtle)'}; color: var(--wf-muted); text-align: center; cursor: pointer; padding: 0 12px; }
.wf-steps { display: flex; list-style: none; margin: 0; padding: 0; }
.wf-steps li { flex: 1; display: flex; flex-direction: column; align-items: center; gap: 4px; text-align: center; color: var(--wf-muted); font-size: .93em; }
.wf-steps li span { width: 22px; height: 22px; border-radius: 50%; border: var(--wf-bw) solid var(--wf-border); display: flex; align-items: center; justify-content: center; font-weight: 700; font-size: 12px; background: var(--wf-surface); }
.wf-steps li.on { color: inherit; font-weight: 700; }
.wf-steps li.on span { background: ${sketch ? '#9A9A9A' : 'var(--wf-accent)'}; border-color: ${sketch ? 'var(--wf-border)' : 'var(--wf-accent)'}; color: ${sketch ? 'inherit' : 'var(--wf-on-accent)'}; }
.wf-stars { justify-content: space-around; color: ${sketch ? '#BDBDBD' : '#F5B301'}; }
.wf-stars .off { color: transparent; -webkit-text-stroke: 1px var(--wf-border); }
.wf-video { border: var(--wf-bw) solid var(--wf-border); border-radius: 4px; background: ${sketch ? '#FFFFFF' : '#1D2939'}; overflow: hidden; }
.wf-acc details { border-top: .8px solid var(--wf-border); }
.wf-acc details:first-child { border-top: 0; }
.wf-acc summary { height: 36px; display: flex; align-items: center; justify-content: space-between; padding: 0 14px; cursor: pointer; list-style: none; }
.wf-acc details[open] summary { font-weight: 700; }
.wf-acc summary::after { content: ""; width: 6px; height: 6px; border: solid var(--wf-text); border-width: 0 1.5px 1.5px 0; transform: rotate(-45deg); margin-right: 4px; }
.wf-acc details[open] summary::after { transform: translateY(-2px) rotate(45deg); }
.wf-acc .body { padding: 6px 14px 10px; display: flex; flex-direction: column; gap: 8px; }
.wf-tip { justify-content: center; text-align: center; padding: 0 8px; border-radius: 6px; background: ${sketch ? '#FFFFFF' : '#1D2939'}; color: ${sketch ? 'var(--wf-text)' : '#FFFFFF'}; ${sketch ? 'border: var(--wf-bw) solid var(--wf-border);' : ''} }
.wf-tip::after { content: ""; position: absolute; left: 50%; bottom: -7px; margin-left: -6px; border: 6px solid transparent; border-top-color: ${sketch ? 'var(--wf-border)' : '#1D2939'}; border-bottom: 0; }
.wf-skel { display: grid; grid-template-columns: auto 1fr; gap: 6px 12px; align-content: start; }
.wf-skel .c { border-radius: 50%; background: var(--wf-bar); grid-row: span 2; }
.wf-skel .full { grid-column: 1 / -1; }
.wf-cal { border: var(--wf-bw) solid var(--wf-border); border-radius: 8px; background: var(--wf-surface); padding: 0 8px; }
.wf-cal-h { display: flex; align-items: center; justify-content: space-between; padding: 0 8px; font-weight: 700; }
.wf-cal-g { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); text-align: center; }
.wf-cal-g .d { color: var(--wf-muted); font-size: .85em; }
.wf-cal-g .today { font-weight: 700; color: ${sketch ? 'inherit' : 'var(--wf-on-accent)'}; background: ${sketch ? '#DADADA' : 'var(--wf-accent)'}; border-radius: 50%; }
.wf-stat .l { position: absolute; left: 14px; top: 10px; right: 14px; color: var(--wf-muted); font-size: .85em; }
.wf-stat .v { position: absolute; left: 14px; right: 14px; bottom: 8px; font-size: 2.1em; font-weight: 700; }
.wf-tree { list-style: none; margin: 0; padding: 0; }
.wf-tree li { display: flex; align-items: center; gap: 6px; }
.wf-status { justify-content: space-between; padding: 0 20px; font-weight: 700; }
.wf-appbar { display: flex; align-items: center; gap: 12px; padding: 0 16px 0 14px; border: var(--wf-bw) solid var(--wf-border); background: var(--wf-surface); }
.wf-appbar .wf-back { font-size: 28px; line-height: 1; }
.wf-appbar .wf-ttl { flex: 1; font-weight: 700; }
.wf-icons { display: flex; gap: 20px; }
.wf-icons i { width: 24px; height: 24px; border: 1.3px solid var(--wf-muted); border-radius: 7px; }
.wf-bnav { display: flex; border: var(--wf-bw) solid var(--wf-border); background: var(--wf-surface); }
.wf-bnav a { flex: 1; min-width: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px; color: var(--wf-muted); text-decoration: none; font-size: .92em; }
.wf-bnav .ic { width: 22px; height: 22px; border: 1.3px solid var(--wf-muted); border-radius: 6px; }
.wf-bnav a.on { color: ${sketch ? 'inherit' : 'var(--wf-accent)'}; font-weight: 700; }
.wf-bnav a.on .ic { background: ${sketch ? '#DADADA' : 'var(--wf-accent)'}; border-color: ${sketch ? 'var(--wf-border)' : 'var(--wf-accent)'}; }
.wf-fab { justify-content: center; border-radius: 50%; border: var(--wf-bw) solid ${sketch ? 'var(--wf-border)' : 'var(--wf-accent)'}; background: $accentPrimaryFill; color: ${sketch ? 'var(--wf-text)' : 'var(--wf-on-accent)'}; font-size: 28px; line-height: 1; cursor: pointer; ${sketch ? '' : 'box-shadow: 0 3px 8px rgba(0,0,0,.22);'} }
.wf-sheet { border: var(--wf-bw) solid var(--wf-border); border-radius: 16px; background: var(--wf-surface); padding-top: 24px; overflow: hidden; }
.wf-sheet .grab { position: absolute; top: 10px; left: 50%; width: 36px; height: 4px; margin-left: -18px; border-radius: 2px; background: var(--wf-bar); }
.wf-sheet h2 { margin: 0 24px 10px; height: 30px; display: flex; align-items: center; font-size: 1.15em; }
.wf-sheet a { display: flex; align-items: center; gap: 12px; height: 58px; margin: 0 24px; border-top: .8px solid var(--wf-line); color: inherit; text-decoration: none; }
.wf-sheet a i { width: 18px; height: 18px; border-radius: 50%; border: 1.4px solid var(--wf-muted); flex: none; }
.wf-sheet a.on { font-weight: 700; }
.wf-sheet a.on i { background: ${sketch ? '#DADADA' : 'var(--wf-accent)'}; border-color: ${sketch ? 'var(--wf-border)' : 'var(--wf-accent)'}; }
.wf-drawer { border: var(--wf-bw) solid var(--wf-border); background: var(--wf-surface); overflow: hidden; }
.wf-drawer .hd { position: relative; background: var(--wf-subtle); }
.wf-drawer .av { position: absolute; left: 24px; top: 28%; width: 52px; height: 52px; border-radius: 50%; border: 1.4px solid var(--wf-muted); background: var(--wf-surface); }
.wf-drawer .hd b { position: absolute; left: 24px; right: 24px; bottom: 26px; font-size: 1.15em; }
.wf-drawer .hd small { position: absolute; left: 24px; right: 24px; bottom: 8px; color: var(--wf-muted); font-size: .85em; }
.wf-drawer nav { padding: 20px 10px 0; }
.wf-drawer nav a { display: flex; align-items: center; gap: 12px; height: 44px; margin-bottom: 10px; padding: 0 14px; border-radius: 8px; color: inherit; text-decoration: none; }
.wf-drawer nav a i { width: 22px; height: 22px; border: 1.3px solid var(--wf-muted); border-radius: 6px; flex: none; }
.wf-drawer nav a.on { background: ${sketch ? '#E2E2E2' : 'var(--wf-tint)'}; color: ${sketch ? 'inherit' : 'var(--wf-accent)'}; font-weight: 700; }
.wf-seg { display: flex; padding: 4px; border: var(--wf-bw) solid var(--wf-border); border-radius: 9px; background: var(--wf-subtle); }
.wf-seg a { flex: 1; min-width: 0; display: flex; align-items: center; justify-content: center; border-radius: 6px; color: var(--wf-muted); text-decoration: none; font-size: .92em; }
.wf-seg a.on { background: var(--wf-surface); border: 1.1px solid var(--wf-border); color: inherit; font-weight: 700; }
.wf-opts { border: 0; margin: 0; padding: 0; min-width: 0; }
.wf-opts legend { padding: 0; font-weight: 700; height: 30px; line-height: 24px; }
.wf-opts .wf-check { height: 36px; position: static; }
.wf-pw { display: flex; align-items: center; gap: 8px; }
.wf-pw input { flex: 1; min-width: 0; border: 0; outline: 0; background: transparent; font: inherit; color: inherit; }
.wf-eye { width: 18px; height: 11px; border: 1.4px solid var(--wf-muted); border-radius: 50%; position: relative; flex: none; }
.wf-eye::after { content: ""; position: absolute; left: 50%; top: 50%; width: 4px; height: 4px; margin: -2px 0 0 -2px; border-radius: 50%; background: var(--wf-muted); }
.wf-num { display: flex; align-items: stretch; border: var(--wf-bw) solid var(--wf-border); border-radius: 6px; background: var(--wf-surface); overflow: hidden; }
.wf-num button { width: 40px; border: 0; background: none; font: inherit; font-size: 18px; cursor: pointer; color: inherit; }
.wf-num .v { flex: 1; display: flex; align-items: center; justify-content: center; font-weight: 700; border-left: .8px solid var(--wf-border); border-right: .8px solid var(--wf-border); }
.wf-time { display: flex; align-items: center; gap: 10px; }
.wf-time input { flex: 1; min-width: 0; border: 0; outline: 0; background: transparent; font: inherit; color: inherit; }
.wf-clock { width: 18px; height: 18px; border: 1.4px solid var(--wf-muted); border-radius: 50%; position: relative; flex: none; }
.wf-clock::after { content: ""; position: absolute; left: 7px; top: 3px; width: 4px; height: 6px; border: solid var(--wf-muted); border-width: 0 0 1.4px 1.4px; }
.wf-chev { width: 7px; height: 7px; border: solid var(--wf-muted); border-width: 0 1.5px 1.5px 0; transform: rotate(45deg); margin: -3px 2px 0 0; flex: none; }
.wf-empty { display: flex; flex-direction: column; align-items: center; text-align: center; padding-top: 8px; }
.wf-empty .ill { width: 72px; height: 72px; border-radius: 50%; border: var(--wf-bw) solid var(--wf-border); background: var(--wf-subtle); flex: none; }
.wf-empty h3 { margin: 16px 16px 0; max-width: 100%; font-size: 1.2em; }
.wf-empty p { margin: 6px 24px 0; color: var(--wf-muted); font-size: .92em; }
.wf-empty .wf-btn { margin-top: auto; margin-bottom: 16px; width: 160px; max-width: 80%; height: 40px; }
.wf-toast { gap: 12px; padding: 0 16px; border-radius: 10px; background: ${sketch ? '#4A4A4A' : '#1D2939'}; color: #FFFFFF; }
.wf-toast .ok { flex: none; width: 18px; height: 18px; border: 1.4px solid #FFFFFF; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 11px; }
.wf-toast .msg { flex: 1; }
.wf-toast .act { flex: none; margin-left: auto; color: ${sketch ? '#D5DBE3' : '#8FB4FF'}; }
.wf-kan { display: flex; gap: 15px; }
.wf-kan section { flex: 1; min-width: 0; padding: 0 10px; border: var(--wf-bw) solid var(--wf-border); border-radius: 10px; background: var(--wf-subtle); overflow: hidden; }
.wf-kan header { display: flex; align-items: center; justify-content: space-between; height: 44px; padding: 0 4px; }
.wf-kan header span { color: var(--wf-muted); font-size: .9em; }
.wf-kan .cd { height: 72px; margin-bottom: 12px; padding: 19px 12px 0; display: flex; flex-direction: column; gap: 12px; border: var(--wf-bw) solid var(--wf-border); border-radius: 8px; background: var(--wf-surface); }
.wf-tl { list-style: none; margin: 0; padding: 0; position: relative; }
.wf-tl::before { content: ""; position: absolute; left: 15px; top: 12px; bottom: 14px; width: 2px; background: var(--wf-border); }
.wf-tl li { position: relative; padding-left: 40px; display: flex; flex-direction: column; justify-content: flex-start; padding-top: 6px; color: var(--wf-muted); }
.wf-tl li.on { color: inherit; }
.wf-tl .dot { position: absolute; left: 8px; top: 14px; width: 16px; height: 16px; border-radius: 50%; border: 1.6px solid var(--wf-border); background: var(--wf-surface); }
.wf-tl li.on .dot { background: ${sketch ? '#BDBDBD' : 'var(--wf-accent)'}; border-color: ${sketch ? 'var(--wf-border)' : 'var(--wf-accent)'}; }
.wf-tl small { color: var(--wf-muted); font-size: .85em; }
''';
  }

  // ---------------------------------------------------------------- ชิ้นส่วน

  void _emit(WfComponent c, double ox, double oy, int depth, Set<String> hiddenOwn) {
    final ind = '  ' * depth;
    final kids = [for (final k in d.components) if (parents[k.id] == c.id) k];
    final (tag, cls, attrs, inner, isVoid) = _el(c, hasKids: kids.isNotEmpty);
    final style = StringBuffer()..write(_box(c, ox, oy));
    _overrides(c, style);
    final a = StringBuffer(' class="wf $cls${c.disabled ? ' wf-off' : ''}" style="$style"');
    a.write(' data-wf="${_h(c.id)}"');
    if (c.group != null) a.write(' data-group="${_h(c.group!)}"');
    final bind = _bind(c);
    if (bind != null) a.write(' data-bind="${_h(bind)}"');
    final api = _api(c);
    if (api != null) a.write(' data-api="${_h(api)}"');
    if (hiddenOwn.contains(c.id)) a.write(' hidden');
    a.write(attrs);
    if (isVoid) {
      out.writeln('$ind<$tag$a>');
      return;
    }
    if (kids.isEmpty) {
      out.writeln('$ind<$tag$a>$inner</$tag>');
      return;
    }
    out.writeln('$ind<$tag$a>$inner');
    for (final k in kids) {
      _emit(k, c.x, c.y, depth + 1, hiddenOwn);
    }
    out.writeln('$ind</$tag>');
  }

  /// ตำแหน่ง/ขนาด (สัมพัทธ์กับภาชนะที่ครอบ) + การหมุน
  String _box(WfComponent c, double ox, double oy) {
    if (c.kind == WfKind.divider) {
      // เส้นคั่น: เส้นเดียวกึ่งกลางกรอบ
      return c.h > c.w
          ? 'left:${_px(c.x - ox + c.w / 2)};top:${_px(c.y - oy)};width:0;height:${_px(c.h)};border-left:1px solid var(--wf-border);'
          : 'left:${_px(c.x - ox)};top:${_px(c.y - oy + c.h / 2)};width:${_px(c.w)};height:0;border-top:1px solid var(--wf-border);';
    }
    final s = 'left:${_px(c.x - ox)};top:${_px(c.y - oy)};width:${_px(c.w)};height:${_px(c.h)};';
    return c.rotation == 0 ? s : '${s}transform:rotate(${_n(c.rotation)}deg);';
  }

  /// สี/ตัวอักษรที่ผู้ใช้กำหนดในแบบ (ร่าง = เทา เหมือนบนแคนวาส)
  void _overrides(WfComponent c, StringBuffer s) {
    int g(int v) => sketch ? wfGray(v) : v;
    if (c.fill != null) s.write('background:${_hex(g(c.fill!))};');
    if (c.stroke != null) s.write('border-color:${_hex(g(c.stroke!))};');
    if (c.textColor != null) s.write('color:${_hex(g(c.textColor!))};');
    final fs = c.effectiveFontSize;
    if (fs != 14) s.write('font-size:${_px(fs)};');
    if (c.bold || c.kind == WfKind.heading) s.write('font-weight:700;');
    const aligned = {
      WfKind.heading, WfKind.label, WfKind.paragraph, WfKind.button, WfKind.badge, WfKind.link,
      WfKind.alert, WfKind.breadcrumb, WfKind.input, WfKind.search, WfKind.textarea, WfKind.select,
    };
    if (aligned.contains(c.kind)) {
      final (ta, jc) = switch (c.align) {
        WfAlign.left => ('left', 'flex-start'),
        WfAlign.center => ('center', 'center'),
        WfAlign.right => ('right', 'flex-end'),
      };
      s.write('text-align:$ta;');
      if (c.kind != WfKind.input && c.kind != WfKind.textarea && c.kind != WfKind.select) s.write('justify-content:$jc;');
    }
  }

  String _t(WfComponent c, [String fallback = '']) {
    final t = c.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return _h(t.isEmpty ? fallback : t);
  }

  String _bars(List<double> widths) => widths.map((w) => '<span class="wf-bar" style="width:${_px(w)}"></span>').join();

  String _nameAttr(WfComponent c) {
    final b = _bind(c);
    if (b == null || !b.contains('.')) return '';
    return ' name="${_h(b.split('.').last)}"';
  }

  /// (แท็ก, คลาส, แอตทริบิวต์เพิ่ม, เนื้อหาข้างใน, แท็กว่าง)
  (String, String, String, String, bool) _el(WfComponent c, {required bool hasKids}) {
    final t = _t(c);
    final dis = c.disabled ? ' disabled' : '';
    switch (c.kind) {
      case WfKind.container:
        return ('div', 'wf-box wf-r6${c.fill == null && !sketch ? ' wf-dashed' : ''}', '', t.isEmpty ? '' : '<span class="wf-cap wf-1">$t</span>', false);
      case WfKind.heading:
        return ('h1', 'wf-t', '', '<span class="wf-1">$t</span>', false);
      case WfKind.label:
        return ('p', 'wf-t', '', '<span class="wf-1">$t</span>', false);
      case WfKind.paragraph:
        return ('p', 'wf-para', '', _h(c.text.trim()), false);
      case WfKind.button:
        return ('button', 'wf-t wf-btn${c.secondary ? ' wf-btn-2' : ''}', ' type="button"$dis', '<span class="wf-1">$t</span>', false);
      case WfKind.input:
        final email = (_bind(c) ?? '').toLowerCase().contains('email');
        return ('input', 'wf-field', ' type="${email ? 'email' : 'text'}" placeholder="$t"${_nameAttr(c)}$dis', '', true);
      case WfKind.textarea:
        return ('textarea', 'wf-field', ' placeholder="$t"${_nameAttr(c)}$dis', '', false);
      case WfKind.search:
        final r = math.min(6.0, c.h / 4);
        final icon = '<svg width="${_n(r * 2.6)}" height="${_n(r * 2.6)}" viewBox="0 0 16 16" aria-hidden="true" fill="none" '
            'stroke="var(--wf-muted)" stroke-width="1.6"><circle cx="6.5" cy="6.5" r="5"/><path d="M10.5 10.5L15 15"/></svg>';
        return ('label', 'wf-field wf-search', '', '$icon<input type="search" placeholder="$t"${_nameAttr(c)}$dis>', false);
      case WfKind.select:
        final opts = <String>[if (c.text.trim().isNotEmpty) c.text.trim()];
        for (final v in [...c.items.skip(1), ..._seedValues(c)]) {
          if (!opts.contains(v)) opts.add(v);
        }
        if (opts.isEmpty) opts.add('');
        return ('select', 'wf-field', '${_nameAttr(c)}$dis', opts.map((o) => '<option>${_h(o)}</option>').join(), false);
      case WfKind.datepicker:
        const cal = '<svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.3">'
            '<rect x="0.7" y="2.2" width="14.6" height="13" rx="2"/><path d="M.7 7h14.6M4.5.5v3M11.5.5v3"/></svg>';
        return ('label', 'wf-field wf-search wf-date', '',
            '<input type="text" placeholder="$t" aria-label="$t"${_nameAttr(c)}$dis '
                "onfocus=\"this.type='date'\" onblur=\"if(!this.value)this.type='text'\">$cal",
            false);
      case WfKind.checkbox || WfKind.radio:
        final type = c.kind == WfKind.radio ? 'radio' : 'checkbox';
        return ('label', 'wf-t wf-check', '', '<input type="$type"${c.checked ? ' checked' : ''}$dis><span class="wf-1">$t</span>', false);
      case WfKind.toggle:
        return ('label', 'wf-t wf-check', '', '<input type="checkbox" role="switch" class="wf-switch"${c.checked ? ' checked' : ''}$dis><span class="wf-1">$t</span>', false);
      case WfKind.slider:
        return ('input', 'wf-range', ' type="range" value="40"$dis', '', true);
      case WfKind.image:
        // พิกัดจริงของชิ้น (viewBox = ขนาดชิ้น) — ภาพเหมือนบนแคนวาส ไม่ยืดวงกลม
        final w = c.w, h = c.h, m = math.min(w, h);
        final art = sketch
            ? '<svg viewBox="0 0 ${_n(w)} ${_n(h)}" aria-hidden="true"><path d="M0 0L${_n(w)} ${_n(h)}M${_n(w)} 0L0 ${_n(h)}" stroke="var(--wf-border)" stroke-width="1"/></svg>'
            : '<svg viewBox="0 0 ${_n(w)} ${_n(h)}" aria-hidden="true"><path d="M${_n(w * .15)} ${_n(h * .8)}L${_n(w * .4)} ${_n(h * .45)} ${_n(w * .58)} ${_n(h * .65)} '
                '${_n(w * .7)} ${_n(h * .52)} ${_n(w * .88)} ${_n(h * .8)}Z" fill="#C4CAD4"/><circle cx="${_n(w * .7)}" cy="${_n(h * .3)}" r="${_n(m * .08)}" fill="#C4CAD4"/></svg>';
        return ('div', 'wf-img', ' role="img" aria-label="${t.isEmpty ? 'image' : t}"', art, false);
      case WfKind.icon:
        final art = sketch
            ? '<svg viewBox="0 0 100 100" aria-hidden="true"><path d="M25 25L75 75M75 25L25 75" stroke="var(--wf-border)" stroke-width="4"/></svg>'
            : '<svg viewBox="0 0 100 100" aria-hidden="true"><circle cx="50" cy="50" r="22" fill="none" stroke="var(--wf-muted)" stroke-width="7"/></svg>';
        return ('span', 'wf-icon', ' aria-hidden="true"', art, false);
      case WfKind.avatar:
        final f = sketch ? 'none' : '#C4CAD4';
        final st = sketch ? ' stroke="var(--wf-border)" stroke-width="3"' : '';
        return (
          'span',
          'wf-avatar',
          ' role="img" aria-label="${t.isEmpty ? 'avatar' : t}"',
          '<svg viewBox="0 0 100 100" aria-hidden="true"><circle cx="50" cy="41" r="16" fill="$f"$st/><path d="M20 86L27 65h46l7 21" fill="$f"$st/></svg>',
          false,
        );
      case WfKind.table:
        final cols = c.columns.isEmpty ? ['', '', ''] : c.columns;
        final rh = math.min(40.0, c.h / (c.rows + 1));
        final shown = math.max(0, math.min(c.rows, (c.h / rh).floor() - 1));
        final data = _tableRows(c, cols);
        final cw = c.w / cols.length;
        final b = StringBuffer('<table class="wf-table"><thead><tr style="height:${_px(rh)}">');
        for (final h in cols) {
          b.write('<th>${_h(h)}</th>');
        }
        b.write('</tr></thead><tbody>');
        for (var r = 0; r < shown; r++) {
          b.write('<tr style="height:${_px(rh)}">');
          for (var i = 0; i < cols.length; i++) {
            final v = r < data.length ? data[r][i] : null;
            if (v != null) {
              b.write('<td>${_h(v)}</td>');
            } else {
              final len = (cw - 16) * (0.45 + 0.35 * ((((r + 1) * 7 + i * 3) % 5) / 4));
              b.write('<td>${_bars([math.max(8, len)])}</td>');
            }
          }
          b.write('</tr>');
        }
        b.write('</tbody></table>');
        return ('div', 'wf-table-box', '', b.toString(), false);
      case WfKind.list:
        final items = c.items;
        final n = math.max(items.length, c.rows);
        final rh = n == 0 ? 0.0 : math.min(44.0, c.h / n);
        final b = StringBuffer('<ul class="wf-list">');
        for (var i = 0; i < n && (i + 1) * rh <= c.h + 0.5; i++) {
          b.write('<li style="height:${_px(rh)}">${i < items.length ? '<span class="wf-1">${_h(items[i])}</span>' : _bars([math.min(c.w * 0.5, c.w - 40)])}</li>');
        }
        b.write('</ul>');
        return ('div', 'wf-box', '', b.toString(), false);
      case WfKind.card:
        return ('section', 'wf-card', '', t.isEmpty ? '' : '<h3 class="wf-card-h wf-1">$t</h3>', false);
      case WfKind.tabs:
        final items = c.items.isEmpty ? [''] : c.items;
        return ('nav', 'wf-tabs', '', items.indexed.map((e) => '<a href="#"${e.$1 == 0 ? ' class="on"' : ''}>${_h(e.$2)}</a>').join(), false);
      case WfKind.navbar:
        final fake = '<span class="wf-fake" aria-hidden="true">${_bars([48, 48, 48])}</span>';
        return ('header', 'wf-nav', '', '<strong class="wf-brand wf-1">$t</strong>$fake', false);
      case WfKind.sidebar:
        final items = c.items;
        return ('aside', 'wf-side', '', items.indexed.map((e) => '<a href="#"${e.$1 == 0 ? ' class="on"' : ''}><span class="wf-1">${_h(e.$2)}</span></a>').join(), false);
      case WfKind.modal:
        final th = math.min(48.0, c.h * 0.3);
        return ('div', 'wf-modal', ' role="dialog" aria-label="$t"',
            '<div class="wf-modal-h" style="height:${_px(th)}"><span class="wf-1">$t</span><button type="button" aria-label="close">×</button></div>', false);
      case WfKind.divider:
        return ('div', '', ' role="separator"', '', false);
      case WfKind.badge:
        return ('span', 'wf-t wf-badge', '', '<span class="wf-1">$t</span>', false);
      case WfKind.pagination:
        final s = math.min(c.h, c.w / 5 - 4);
        final cells = ['‹', '1', '2', '3', '›'];
        return ('nav', 'wf-pages', ' aria-label="pagination"',
            cells.indexed.map((e) => '<a href="#" style="width:${_px(s)};height:${_px(s)}"${e.$1 == 1 ? ' class="on" aria-current="page"' : ''}>${e.$2}</a>').join(), false);
      case WfKind.breadcrumb:
        return ('nav', 'wf-t wf-muted', ' aria-label="breadcrumb"', '<span class="wf-1">${c.items.map(_h).join('&nbsp; / &nbsp;')}</span>', false);
      case WfKind.map:
        final road = sketch ? '#BDBDBD' : '#FFFFFF';
        final pin = sketch ? 'none' : '#E5484D';
        return (
          'div',
          'wf-img',
          ' role="img" aria-label="${t.isEmpty ? 'map' : t}"',
          () {
            final w = c.w, h = c.h;
            final px = w * .62, py = h * .42, r = math.min(10.0, math.min(w, h) * .08);
            final ps = sketch ? 'var(--wf-border)' : 'none';
            return '<svg viewBox="0 0 ${_n(w)} ${_n(h)}" aria-hidden="true"><rect width="${_n(w)}" height="${_n(h)}" fill="${sketch ? '#FFFFFF' : '#E6EFE3'}"/>'
                '<path d="M0 ${_n(h * .35)}L${_n(w)} ${_n(h * .55)}M${_n(w * .3)} 0L${_n(w * .45)} ${_n(h)}" stroke="$road" stroke-width="${sketch ? 1.2 : 5}" fill="none"/>'
                '<path d="M${_n(px - r * .8)} ${_n(py + r * .4)}L${_n(px)} ${_n(py + r * 2.2)} ${_n(px + r * .8)} ${_n(py + r * .4)}Z" fill="$pin" stroke="$ps"/>'
                '<circle cx="${_n(px)}" cy="${_n(py)}" r="${_n(r)}" fill="${sketch ? '#FFFFFF' : pin}" stroke="$ps"/></svg>';
          }(),
          false,
        );
      case WfKind.chart:
        const vals = [0.45, 0.75, 0.55, 0.9, 0.65];
        final w = c.w, h = c.h;
        final l = 24.0, bt = h - 20, tp = 16.0, r = w - 16;
        final bw = (r - l) / (vals.length * 1.6);
        final bars = StringBuffer();
        for (var i = 0; i < vals.length; i++) {
          final bx = l + bw * 0.6 + i * bw * 1.6, bh = (bt - tp) * vals[i];
          bars.write('<rect x="${_n(bx)}" y="${_n(bt - bh)}" width="${_n(bw)}" height="${_n(bh)}" '
              '${sketch ? 'fill="none" stroke="var(--wf-border)" stroke-width="1.2"' : 'fill="var(--wf-accent)" fill-opacity="${i.isEven ? 0.85 : 0.55}"'}/>');
        }
        return ('div', 'wf-box', ' role="img" aria-label="${t.isEmpty ? 'chart' : t}"',
            '<svg viewBox="0 0 ${_n(w)} ${_n(h)}" style="position:absolute;inset:0;width:100%;height:100%" aria-hidden="true">'
                '<path d="M${_n(l)} ${_n(tp)}V${_n(bt)}H${_n(r)}" fill="none" stroke="var(--wf-muted)"/>$bars</svg>',
            false);
      case WfKind.link:
        return ('a', 'wf-t wf-link', ' href="#"', '<span class="wf-1">$t</span>', false);
      case WfKind.chip:
        return ('span', 'wf-t wf-chip', '', '<span class="wf-1">$t</span><button type="button" aria-label="remove">×</button>', false);
      case WfKind.progress:
        final digits = RegExp(r'\d+(\.\d+)?').firstMatch(c.text)?.group(0);
        final pct = ((double.tryParse(digits ?? '') ?? 60).clamp(0, 100)).round();
        final label = c.text.trim().isNotEmpty && c.w > 110 ? '<span>${_h(c.text.trim())}</span>' : '';
        return ('div', 'wf-progress', ' role="progressbar" aria-valuenow="$pct" aria-valuemin="0" aria-valuemax="100"',
            '<span class="track"><span class="fill" style="display:block;width:$pct%"></span></span>$label', false);
      case WfKind.alert:
        return ('div', 'wf-t wf-alert', ' role="alert"', '<span class="wf-alert-i" aria-hidden="true">!</span><span>$t</span>', false);
      case WfKind.upload:
        return ('label', 'wf-t wf-upload', '',
            '<svg width="20" height="22" viewBox="0 0 20 22" aria-hidden="true" fill="none" stroke="var(--wf-muted)" stroke-width="2"><path d="M10 21V3M3 9l7-7 7 7"/></svg>'
                '<span>$t</span><input type="file" hidden$dis>',
            false);
      case WfKind.stepper:
        final items = c.items.isEmpty ? ['', '', ''] : c.items;
        return ('ol', 'wf-steps', '',
            items.indexed.map((e) => '<li${e.$1 == 0 ? ' class="on"' : ''}><span>${e.$1 + 1}</span>${_h(e.$2)}</li>').join(), false);
      case WfKind.rating:
        final s = math.max(8.0, math.min(c.h, c.w / 5) - 2);
        return ('div', 'wf-t wf-stars', ' role="img" aria-label="3/5"',
            '<span style="font-size:${_px(s)}">★</span><span style="font-size:${_px(s)}">★</span><span style="font-size:${_px(s)}">★</span>'
                '<span class="off" style="font-size:${_px(s)}">★</span><span class="off" style="font-size:${_px(s)}">★</span>',
            false);
      case WfKind.video:
        final fg = sketch ? 'var(--wf-border)' : '#FFFFFF';
        return ('div', 'wf-video', ' role="img" aria-label="${t.isEmpty ? 'video' : t}"',
            () {
              final w = c.w, h = c.h;
              final cx = w / 2, cy = h / 2 - 8, r = math.min(w, h) * .13;
              final track = sketch ? 'var(--wf-border)' : '#667085', done = sketch ? 'var(--wf-text)' : 'var(--wf-accent)';
              return '<svg viewBox="0 0 ${_n(w)} ${_n(h)}" aria-hidden="true"><circle cx="${_n(cx)}" cy="${_n(cy)}" r="${_n(r)}" fill="none" stroke="$fg" stroke-width="2"/>'
                  '<path d="M${_n(cx - r * .3)} ${_n(cy - r * .45)}L${_n(cx + r * .5)} ${_n(cy)} ${_n(cx - r * .3)} ${_n(cy + r * .45)}Z" fill="${sketch ? 'none' : fg}" stroke="${sketch ? fg : 'none'}"/>'
                  '<path d="M14 ${_n(h - 16)}H${_n(w - 14)}" stroke="$track" stroke-width="3"/><path d="M14 ${_n(h - 16)}H${_n(14 + (w - 28) * .35)}" stroke="$done" stroke-width="3"/></svg>';
            }(),
            false);
      case WfKind.accordion:
        final items = c.items.isEmpty ? [''] : c.items;
        final b = StringBuffer();
        for (final (i, it) in items.indexed) {
          b.write('<details${i == 0 ? ' open' : ''}><summary>${_h(it)}</summary>'
              '${i == 0 ? '<div class="body">${_bars([c.w - 40])}${_bars([(c.w - 40) * 0.7])}</div>' : ''}</details>');
        }
        return ('div', 'wf-box wf-acc', '', b.toString(), false);
      case WfKind.footer:
        final fake = '<span class="wf-fake" aria-hidden="true">${_bars([56, 56, 56])}</span>';
        return ('footer', 'wf-foot', '', '<span class="wf-brand wf-1">$t</span>$fake', false);
      case WfKind.tooltip:
        return ('div', 'wf-t wf-tip', ' role="tooltip"', '<span>$t</span>', false);
      case WfKind.skeleton:
        final r = math.min(c.h * 0.28, 22.0);
        final rest = c.w - r * 2 - 12;
        return ('div', 'wf-skel animate-pulse', ' aria-hidden="true"',
            '<span class="c" style="width:${_px(r * 2)};height:${_px(r * 2)}"></span>${_bars([rest * 0.7])}${_bars([rest * 0.45])}'
                '${[1.0, 0.92, 0.6].where((_) => r * 2 + 30 <= c.h).map((f) => '<span class="full">${_bars([c.w * f])}</span>').join()}',
            false);
      case WfKind.calendar:
        final hh = math.min(40.0, c.h * 0.15);
        final rh = math.max(1.0, (c.h - hh - 28) / 6);
        const days = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];
        final g = StringBuffer('<div class="wf-cal-g">');
        for (final dd in days) {
          g.write('<span class="d" style="height:22px;line-height:22px">$dd</span>');
        }
        for (var i = 0; i < 3; i++) {
          g.write('<span></span>');
        }
        for (var n = 1; n <= 30; n++) {
          final today = n == 15;
          g.write('<span${today ? ' class="today"' : ''} style="height:${_px(rh)};line-height:${_px(rh)}">$n</span>');
        }
        g.write('</div>');
        return ('div', 'wf-cal', '',
            '<div class="wf-cal-h" style="height:${_px(hh)}"><span class="wf-muted">‹</span><span class="wf-1">$t</span><span class="wf-muted">›</span></div>$g', false);
      case WfKind.stat:
        final parts = c.items;
        final label = parts.length > 1 ? parts.first : '';
        final value = parts.isEmpty ? '' : (parts.length > 1 ? parts[1] : parts.first);
        return ('div', 'wf-card wf-stat', '',
            '${label.isEmpty ? '' : '<span class="l wf-1">${_h(label)}</span>'}<span class="v wf-1">${_h(value)}</span>', false);
      case WfKind.tree:
        final raw = [for (final l in c.text.split('\n')) if (l.trim().isNotEmpty) l];
        final rh = math.min(28.0, c.h / math.max(1, raw.length));
        int ind(String l) => (l.length - l.trimLeft().length) ~/ 2;
        final b = StringBuffer('<ul class="wf-tree">');
        for (var i = 0; i < raw.length && (i + 1) * rh <= c.h + 0.5; i++) {
          final parent = i + 1 < raw.length && ind(raw[i + 1]) > ind(raw[i]);
          b.write('<li style="height:${_px(rh)};padding-left:${_px(6 + ind(raw[i]) * 18.0)}${parent ? ';font-weight:700' : ''}">'
              '<span aria-hidden="true" class="wf-muted">${parent ? '⌄' : '•'}</span><span class="wf-1">${_h(raw[i].trim())}</span></li>');
        }
        b.write('</ul>');
        return ('div', '', '', b.toString(), false);
      // ---- Phase 18b: มือถือ ----
      case WfKind.statusBar:
        return ('div', 'wf-t wf-status', '',
            '<span class="wf-1">$t</span><svg width="64" height="14" viewBox="0 0 64 14" aria-hidden="true" fill="currentColor">'
                '<rect x="0" y="9" width="3" height="4" rx=".8"/><rect x="5" y="7" width="3" height="6" rx=".8"/><rect x="10" y="5" width="3" height="8" rx=".8"/><rect x="15" y="2" width="3" height="11" rx=".8"/>'
                '<path d="M26 8a6 6 0 018 0M23.5 5.5a9.5 9.5 0 0113 0M28.5 10.5a3 3 0 013 0" fill="none" stroke="currentColor" stroke-width="1.3"/>'
                '<rect x="40" y="2.5" width="22" height="9" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.2"/><rect x="42" y="4.5" width="14" height="5" rx="1" /></svg>',
            false);
      case WfKind.appBar:
        return ('header', 'wf-appbar', '',
            '<span class="wf-back" aria-hidden="true">‹</span><span class="wf-ttl wf-1">$t</span><span class="wf-icons" aria-hidden="true"><i></i><i></i></span>', false);
      case WfKind.bottomNav:
        final tabs = c.items.isEmpty ? [''] : c.items.take(5).toList();
        return ('nav', 'wf-bnav', '',
            tabs.indexed.map((e) => '<a href="#"${e.$1 == 0 ? ' class="on"' : ''}><span class="ic"></span><span class="wf-1">${_h(e.$2)}</span></a>').join(), false);
      case WfKind.fab:
        final glyph = c.text.trim().isEmpty || c.text.trim() == '+' ? '+' : _h(c.text.trim());
        return ('button', 'wf-t wf-fab', ' type="button" aria-label="${glyph == '+' ? 'add' : glyph}"$dis', '<span aria-hidden="true">$glyph</span>', false);
      case WfKind.bottomSheet:
        final its = c.items;
        final rows = its.skip(1).indexed.map((e) => '<a href="#"${e.$1 == 0 ? ' class="on"' : ''}><i></i><span class="wf-1">${_h(e.$2)}</span></a>').join();
        return ('div', 'wf-sheet', '', '<span class="grab"></span><h2 class="wf-1">${its.isEmpty ? '' : _h(its.first)}</h2>$rows', false);
      case WfKind.drawer:
        final its = c.items;
        final hh = math.min(150.0, c.h * 0.25);
        final links = its.skip(2).indexed.map((e) => '<a href="#"${e.$1 == 0 ? ' class="on"' : ''}><i></i><span class="wf-1">${_h(e.$2)}</span></a>').join();
        return ('aside', 'wf-drawer', '',
            '<div class="hd" style="height:${_px(hh)}"><span class="av"></span><b class="wf-1">${its.isEmpty ? '' : _h(its[0])}</b>'
                '<small class="wf-1">${its.length > 1 ? _h(its[1]) : ''}</small></div><nav>$links</nav>',
            false);
      // ---- Phase 18b: ฟอร์ม ----
      case WfKind.segmented:
        final its = c.items.isEmpty ? [''] : c.items.take(5).toList();
        return ('div', 'wf-seg', ' role="tablist"', its.indexed.map((e) => '<a href="#"${e.$1 == 0 ? ' class="on"' : ''} role="tab">${_h(e.$2)}</a>').join(), false);
      case WfKind.optionGroup:
        final its = c.items;
        final type = c.secondary ? 'checkbox' : 'radio';
        final opts = its.skip(1).indexed
            .map((e) => '<label class="wf-t wf-check"><input type="$type" name="g-${_h(c.id)}"${e.$1 == 0 ? ' checked' : ''}$dis><span class="wf-1">${_h(e.$2)}</span></label>')
            .join();
        return ('fieldset', 'wf-opts', '', '<legend>${its.isEmpty ? '' : _h(its.first)}</legend>$opts', false);
      case WfKind.password:
        final hasText = c.text.trim().isNotEmpty;
        return ('div', 'wf-field wf-pw', '',
            '<input type="password" ${hasText ? 'placeholder="$t"' : 'value="password"'}${_nameAttr(c)}$dis aria-label="password"><span class="wf-eye" aria-hidden="true"></span>', false);
      case WfKind.numberInput:
        return ('div', 'wf-num', '', '<button type="button" aria-label="-"$dis>−</button><span class="v wf-1">$t</span><button type="button" aria-label="+"$dis>+</button>', false);
      case WfKind.timepicker:
        return ('label', 'wf-t wf-field wf-time', '',
            '<span class="wf-clock" aria-hidden="true"></span><input type="text" value="$t" aria-label="time"${_nameAttr(c)}$dis><span class="wf-chev" aria-hidden="true"></span>', false);
      // ---- Phase 18b: ข้อมูล / สถานะ ----
      case WfKind.emptyState:
        final its = c.items;
        return ('div', 'wf-empty', '',
            '<span class="ill" aria-hidden="true"></span>'
                '${its.isNotEmpty ? '<h3 class="wf-1">${_h(its[0])}</h3>' : ''}${its.length > 1 ? '<p>${_h(its[1])}</p>' : ''}'
                '${its.length > 2 ? '<button type="button" class="wf-t wf-btn">${_h(its[2])}</button>' : ''}',
            false);
      case WfKind.toast:
        final its = c.items;
        return ('div', 'wf-t wf-toast', ' role="status"',
            '<span class="ok" aria-hidden="true">✓</span><span class="msg wf-1">${its.isEmpty ? '' : _h(its.first)}</span>'
                '${its.length > 1 ? '<b class="act">${_h(its[1])}</b>' : ''}',
            false);
      case WfKind.kanban:
        final cols = c.items.isEmpty ? [''] : c.items.take(6).toList();
        final b = StringBuffer();
        for (final (i, title) in cols.indexed) {
          final cards = math.max(1, c.rows - i);
          b.write('<section><header><b class="wf-1">${_h(title)}</b><span>$cards</span></header>');
          for (var j = 0; j < cards && 44 + (j + 1) * 84 - 12 <= c.h + 0.5; j++) {
            b.write('<div class="cd">${_bars([80])}${_bars([50])}</div>');
          }
          b.write('</section>');
        }
        return ('div', 'wf-kan', '', b.toString(), false);
      case WfKind.timeline:
        final its = c.items;
        final step = its.isEmpty ? 62.0 : math.min(62.0, (c.h - 20) / its.length);
        final b = StringBuffer();
        for (final (i, it) in its.indexed) {
          final (title, sub) = wfSplitPipe(it);
          final done = its.length == 1 || i < its.length - 1;
          b.write('<li${done ? ' class="on"' : ''} style="height:${_px(step)}"><span class="dot" aria-hidden="true"></span><b class="wf-1">${_h(title)}</b>'
              '${sub.isEmpty ? '' : '<small class="wf-1">${_h(sub)}</small>'}</li>');
        }
        return ('ol', 'wf-tl', '', b.toString(), false);
    }
  }
}
