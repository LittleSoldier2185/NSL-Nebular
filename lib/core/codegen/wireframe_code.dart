import 'dart:math' as math;

import '../models/wf_icons.dart';
import '../models/wireframe_model.dart';
import '../models/workspace.dart';
import 'naming.dart';
import 'wireframe_html.dart';
import 'wireframe_layout.dart';

String _dartStr(String s) => dartQuoted(s.replaceAll('\n', ' '));

/// สัดส่วนของแถบความคืบหน้าจากข้อความ ("60%" = 0.6 ; อ่านไม่ได้ = 0.6)
double _progressOf(WfComponent c) {
  final m = RegExp(r'\d+(\.\d+)?').firstMatch(c.text)?.group(0);
  return ((double.tryParse(m ?? '') ?? 60).clamp(0, 100)) / 100;
}

/// บรรทัดของต้นไม้: (ระดับ, ข้อความ) — ระดับนับจากการเยื้อง 2 ช่องต่อระดับ
List<(int, String)> _treeLines(WfComponent c) => [
      for (final l in c.text.split('\n'))
        if (l.trim().isNotEmpty) ((l.length - l.trimLeft().length) ~/ 2, l.trim()),
    ];
/// "ชื่อ | รายละเอียด" ของบรรทัดไทม์ไลน์ (ไม่มี | = ไม่มีรายละเอียด)(String, String) _pipe(String s) {  final parts = s.split('|');  return (parts.first.trim(), parts.length > 1 ? parts.sublist(1).join('|').trim() : '');}

String _one(WfComponent c, String fallback) {
  final t = c.text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.isEmpty ? fallback : t;
}

/// ขั้นตอนแนวนอน: วงเลขลำดับ + ชื่อ คั่นด้วยเส้น (`Stepper` ของ Flutter สูงเกินกรอบแถบขั้นตอนในแบบ)
String _horizontalSteps(List<String> items) => 'Row(children: [${items.indexed.map((e) => '${e.$1 == 0 ? '' : 'const Expanded(child: Divider(indent: 8, endIndent: 8)), '}CircleAvatar(radius: 12, child: Text(\'${e.$1 + 1}\')), const SizedBox(width: 6), Flexible(child: Text(${_dartStr(e.$2)}, overflow: TextOverflow.ellipsis))').join(', ')}])';

/// วิดเจ็ต Flutter ของชิ้นส่วนหนึ่งชิ้น (ย่อหน้า 10 ช่อง)
String _flutterWidget(WfComponent c) {
  final t = _dartStr(_one(c, c.kind.name));
  final items = c.items.isEmpty ? [c.kind.name] : c.items;
  return switch (c.kind) {
    WfKind.heading => 'Text($t, style: Theme.of(context).textTheme.headlineSmall)',
    WfKind.label || WfKind.paragraph => 'Text($t)',
    WfKind.button => c.secondary ? 'OutlinedButton(onPressed: () {}, child: Text($t))' : 'FilledButton(onPressed: () {}, child: Text($t))',
    WfKind.input || WfKind.search => 'TextField(decoration: InputDecoration(labelText: $t${c.kind == WfKind.search ? ', prefixIcon: const Icon(Icons.search)' : ''}))',
    WfKind.textarea => 'TextField(maxLines: 4, decoration: InputDecoration(labelText: $t))',
    WfKind.checkbox => 'CheckboxListTile(value: ${c.checked}, onChanged: (_) {}, title: Text($t))',
    WfKind.radio => 'RadioGroup<int>(groupValue: ${c.checked ? 0 : -1}, onChanged: (_) {}, child: RadioListTile<int>(value: 0, title: Text($t)))',
    WfKind.toggle => 'SwitchListTile(value: ${c.checked}, onChanged: (_) {}, title: Text($t))',
    WfKind.select => 'DropdownButtonFormField<String>(isExpanded: true, hint: Text($t, overflow: TextOverflow.ellipsis), items: [${items.map((i) => 'DropdownMenuItem(value: ${_dartStr(i)}, child: Text(${_dartStr(i)}))').join(', ')}], onChanged: (_) {})',
    WfKind.slider => 'Slider(value: 0.5, onChanged: (_) {})',
    WfKind.image || WfKind.map || WfKind.chart => 'Container(height: ${c.h.round()}, color: Colors.black12, alignment: Alignment.center, child: Text($t))',
    WfKind.icon => 'const Icon(Icons.${wfIconById(c.symbol)?.flutter ?? 'star_outline'})',
    WfKind.avatar => 'const CircleAvatar(child: Icon(Icons.person))',
    WfKind.table => 'DataTable(columns: [${(c.columns.isEmpty ? ['Column'] : c.columns).map((h) => 'DataColumn(label: Text(${_dartStr(h)}))').join(', ')}], rows: const [])',
    WfKind.list => 'Column(children: [${items.map((i) => 'ListTile(title: Text(${_dartStr(i)}))').join(', ')}])',
    WfKind.card || WfKind.container || WfKind.modal => 'Card(child: Padding(padding: const EdgeInsets.all(16), child: Text($t)))',
    WfKind.tabs => 'DefaultTabController(length: ${items.length}, child: TabBar(tabs: [${items.map((i) => 'Tab(text: ${_dartStr(i)}${c.h < 48 ? ', height: ${math.max(20, c.h.round() - 2)}' : ''})').join(', ')}]))',
    WfKind.navbar => 'AppBar(title: Text($t), automaticallyImplyLeading: false)',
    WfKind.sidebar => 'NavigationRail(selectedIndex: 0, destinations: [${items.take(5).map((i) => 'NavigationRailDestination(icon: const Icon(Icons.circle_outlined), label: Text(${_dartStr(i)}))').join(', ')}${items.length < 2 ? ', const NavigationRailDestination(icon: Icon(Icons.circle_outlined), label: Text(\'\'))' : ''}])',
    WfKind.divider => 'const Divider()',
    WfKind.badge => 'Chip(label: Text($t))',
    WfKind.pagination => 'Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(onPressed: () {}, icon: const Icon(Icons.chevron_left)), const Text(\'1\'), IconButton(onPressed: () {}, icon: const Icon(Icons.chevron_right))])',
    WfKind.breadcrumb => 'Text(${_dartStr(items.join(' / '))})',
    WfKind.link => 'TextButton(onPressed: () {}, ${c.h < 40 ? 'style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap), ' : ''}child: Text($t))',
    WfKind.chip => 'InputChip(label: Text($t), onDeleted: () {})',
    WfKind.progress => 'LinearProgressIndicator(value: ${_progressOf(c)})',
    WfKind.alert => 'MaterialBanner(content: Text($t), actions: [TextButton(onPressed: () {}, child: const Text("OK"))])',
    WfKind.datepicker => 'TextField(readOnly: true, decoration: InputDecoration(labelText: $t, suffixIcon: const Icon(Icons.calendar_today_outlined)), onTap: () {})',
    WfKind.upload => 'OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.upload_file), label: Text($t))',
    WfKind.stepper => c.w > c.h ? _horizontalSteps(items) : 'Stepper(currentStep: 0, controlsBuilder: (_, _) => const SizedBox.shrink(), steps: [${items.map((i) => "Step(title: Text(${_dartStr(i)}), content: const SizedBox.shrink())").join(", ")}])',
    WfKind.rating => 'Row(children: List.generate(5, (i) => Icon(i < 3 ? Icons.star : Icons.star_border)))',
    WfKind.video => 'AspectRatio(aspectRatio: 16 / 9, child: Container(color: Colors.black87, child: const Icon(Icons.play_circle_outline, color: Colors.white, size: 48)))',
    WfKind.accordion => 'Column(children: [${items.map((i) => "ExpansionTile(title: Text(${_dartStr(i)}), children: const [])").join(", ")}])',
    WfKind.footer => 'Container(padding: const EdgeInsets.all(16), color: Colors.black12, child: Text($t, textAlign: TextAlign.center))',
    WfKind.tooltip => 'Tooltip(message: $t, child: const Icon(Icons.info_outline))',
    WfKind.skeleton => 'Container(height: ${c.h.round()}, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)))',
    WfKind.calendar => 'CalendarDatePicker(initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100), onDateChanged: (_) {})',
    WfKind.stat => 'Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(${_dartStr(items.length > 1 ? items.first : "")}), Text(${_dartStr(items.length > 1 ? items[1] : items.first)}, style: Theme.of(context).textTheme.headlineMedium)])))',
    WfKind.tree => 'Column(children: [${_treeLines(c).map((l) => "Padding(padding: EdgeInsets.only(left: ${l.$1 * 16.0}), child: ListTile(dense: true, title: Text(${_dartStr(l.$2)})))").join(", ")}])',
    WfKind.statusBar => 'Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text($t), const Row(children: [Icon(Icons.signal_cellular_alt, size: 16), Icon(Icons.wifi, size: 16), Icon(Icons.battery_full, size: 16)])]))',
    WfKind.appBar => 'AppBar(leading: const BackButton(), title: Text($t), actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.search)), IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert))])',
    WfKind.bottomNav => 'NavigationBar(selectedIndex: 0, onDestinationSelected: (_) {}, destinations: [${(items.length < 2 ? [...items, c.kind.name] : items.take(5)).map((i) => 'NavigationDestination(icon: const Icon(Icons.circle_outlined), label: ${_dartStr(i)})').join(', ')}])',
    WfKind.fab => 'FloatingActionButton(onPressed: () {}, child: const Icon(Icons.add))',
    WfKind.bottomSheet => 'Card(child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(title: Text(${_dartStr(items.first)}, style: Theme.of(context).textTheme.titleMedium))${items.skip(1).map((i) => ', ListTile(title: Text(${_dartStr(i)}), onTap: () {})').join()}]))',
    WfKind.drawer => 'SizedBox(height: ${c.h.round()}, child: Drawer(child: ListView(children: [UserAccountsDrawerHeader(accountName: Text(${_dartStr(items.first)}), accountEmail: Text(${_dartStr(items.length > 1 ? items[1] : '')}))${items.skip(2).map((i) => ', ListTile(leading: const Icon(Icons.circle_outlined), title: Text(${_dartStr(i)}), onTap: () {})').join()}])))',
    WfKind.segmented => 'SegmentedButton<int>(segments: [${items.take(5).indexed.map((e) => 'ButtonSegment(value: ${e.$1}, label: Text(${_dartStr(e.$2)}))').join(', ')}], selected: const {0}, onSelectionChanged: (_) {})',
    WfKind.optionGroup => () {
        final rows = items.skip(1).toList().indexed.map((e) => c.secondary ? ', CheckboxListTile(value: ${e.$1 == 0}, onChanged: (_) {}, title: Text(${_dartStr(e.$2)}))' : ', RadioListTile<int>(value: ${e.$1}, title: Text(${_dartStr(e.$2)}))').join();
        final column = 'Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(${_dartStr(items.first)}, style: Theme.of(context).textTheme.titleSmall)$rows])';
        return c.secondary ? column : 'RadioGroup<int>(groupValue: 0, onChanged: (_) {}, child: $column)';
      }(),
    WfKind.password => 'TextField(obscureText: true, decoration: InputDecoration(labelText: ${_dartStr(c.text.trim().isEmpty ? 'Password' : _one(c, 'Password'))}, suffixIcon: const Icon(Icons.visibility_outlined)))',
    WfKind.numberInput => 'Row(mainAxisSize: MainAxisSize.min, children: [IconButton(onPressed: () {}, icon: const Icon(Icons.remove)), Text($t), IconButton(onPressed: () {}, icon: const Icon(Icons.add))])',
    WfKind.timepicker => 'TextField(readOnly: true, decoration: InputDecoration(labelText: $t, suffixIcon: const Icon(Icons.access_time)), onTap: () {})',
    WfKind.emptyState => 'Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.inbox_outlined, size: 64)${items.isNotEmpty ? ', Text(${_dartStr(items[0])}, style: Theme.of(context).textTheme.titleLarge)' : ''}${items.length > 1 ? ', Text(${_dartStr(items[1])}, textAlign: TextAlign.center)' : ''}${items.length > 2 ? ', FilledButton(onPressed: () {}, child: Text(${_dartStr(items[2])}))' : ''}])',
    WfKind.toast => 'Card(color: Colors.black87, child: ListTile(leading: const Icon(Icons.check_circle_outline, color: Colors.white), title: Text(${_dartStr(items.first)}, style: const TextStyle(color: Colors.white))${items.length > 1 ? ', trailing: TextButton(onPressed: () {}, child: Text(${_dartStr(items[1])}))' : ''}))',
    WfKind.kanban => 'SizedBox(height: ${c.h.round()}, child: ListView(scrollDirection: Axis.horizontal, children: [${items.take(6).map((i) => 'SizedBox(width: 200, child: Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.all(12), child: Text(${_dartStr(i)}, style: const TextStyle(fontWeight: FontWeight.bold))), const ListTile(title: Text(\'Task\'))])))').join(', ')}]))',
    WfKind.timeline => 'Column(children: [${items.map((i) {
          final (title, sub) = wfSplitPipe(i);
          return 'ListTile(leading: const Icon(Icons.check_circle_outline), title: Text(${_dartStr(title)})${sub.isEmpty ? '' : ', subtitle: Text(${_dartStr(sub)})'})';
        }).join(', ')}])',
  };
}

/// ชนิดที่เนื้อหาสูงเกินกรอบในแบบได้ — ให้เลื่อนดูได้ ไม่ล้น
const Set<WfKind> _scrollKinds = {
  WfKind.list, WfKind.tree, WfKind.accordion, WfKind.optionGroup, WfKind.timeline, WfKind.emptyState,
  WfKind.bottomSheet, WfKind.card, WfKind.container, WfKind.modal, WfKind.stat, WfKind.stepper,
};

/// ชนิดที่มีขนาดตามเนื้อหา — กรอบในแบบเล็กกว่า = ย่อลงให้พอดี
const Set<WfKind> _shrinkKinds = {WfKind.rating, WfKind.pagination, WfKind.numberInput, WfKind.segmented};

/// วิดเจ็ตของชิ้น [c] พร้อมตัวกันล้นเมื่ออยู่ในกรอบขนาดตายตัว ; [background] = มีชิ้นอื่นวางอยู่ข้างใน
String _boxed(WfComponent c, {bool background = false}) {
  // ภาชนะที่มีชิ้นข้างในและไม่ได้พิมพ์ข้อความ: ไม่ใส่ชื่อชนิดซ้อนใต้ชิ้นข้างใน
  if (background && c.text.trim().isEmpty && const {WfKind.card, WfKind.container, WfKind.modal}.contains(c.kind)) {
    return 'const Card(margin: EdgeInsets.zero)';
  }
  final w = _flutterWidget(c);
  if (background) return w;
  if (_scrollKinds.contains(c.kind)) return 'SingleChildScrollView(child: $w)';
  if (_shrinkKinds.contains(c.kind)) return 'FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: $w)';
  return w;
}

/// เขียนผังหน้าจอเป็นโค้ดวิดเจ็ต — บรรทัดแรกไม่ย่อหน้า บรรทัดถัดไปย่อหน้าตาม `pad`
class _FlutterWriter {
  bool usesMath = false;

  String _sized(WfRect r, String child, String pad) => 'SizedBox(\n'
      '$pad  width: ${r.width},\n'
      '$pad  height: ${r.height},\n'
      '$pad  child: $child,\n'
      '$pad)';

  String node(WfNode n, String pad) => switch (n) {
        WfLeafNode() => leaf(n, pad),
        WfLineNode() => _sized(n.rect, _line(n, '$pad  '), pad),
        WfStackNode() => _sized(n.rect, _stack(n, '$pad  '), pad),
      };

  String _line(WfLineNode n, String pad) {
    final b = StringBuffer('${n.vertical ? 'Column' : 'Row'}(\n')
      ..writeln('$pad  crossAxisAlignment: CrossAxisAlignment.start,')
      ..writeln('$pad  children: [');
    var at = n.vertical ? n.rect.top : n.rect.left;
    for (final k in n.children) {
      final gap = (n.vertical ? k.rect.top : k.rect.left) - at;
      if (gap > 0) b.writeln('$pad    const SizedBox(${n.vertical ? 'height' : 'width'}: $gap),');
      at = n.vertical ? k.rect.bottom : k.rect.right;
      // ระยะเยื้องในแกนขวาง (ซ้ายของแถว / บนของคอลัมน์)
      final shift = n.vertical ? k.rect.left - n.rect.left : k.rect.top - n.rect.top;
      final child = shift == 0
          ? node(k, '$pad    ')
          : 'Padding(\n'
              '$pad      padding: const EdgeInsets.only(${n.vertical ? 'left' : 'top'}: $shift),\n'
              '$pad      child: ${node(k, '$pad      ')},\n'
              '$pad    )';
      b.writeln('$pad    $child,');
    }
    b
      ..writeln('$pad  ],')
      ..write('$pad)');
    return b.toString();
  }

  String _stack(WfStackNode n, String pad) {
    final b = StringBuffer('Stack(\n')..writeln('$pad  children: [');
    for (final k in n.children) {
      b
        ..writeln('$pad    Positioned(')
        ..writeln('$pad      left: ${k.rect.left - n.rect.left},')
        ..writeln('$pad      top: ${k.rect.top - n.rect.top},')
        ..writeln('$pad      child: ${node(k, '$pad      ')},')
        ..writeln('$pad    ),');
    }
    b
      ..writeln('$pad  ],')
      ..write('$pad)');
    return b.toString();
  }

  String leaf(WfLeafNode n, String pad) {
    final c = n.component;
    final rotated = c.rotation != 0;
    final deep = rotated ? '$pad      ' : '$pad  ';
    final inner = n.inner;
    var body = _boxed(c, background: inner != null);
    if (inner != null) {
      body = 'Stack(\n'
          '$deep  children: [\n'
          '$deep    Positioned.fill(child: $body),\n'
          '$deep    ${node(inner, '$deep    ')},\n'
          '$deep  ],\n'
          '$deep)';
    }
    if (!rotated) return _sized(n.rect, body, pad);
    usesMath = true;
    final plain = wfPlainRect(c);
    final turned = 'OverflowBox(\n'
        '$pad    minWidth: ${plain.width},\n'
        '$pad    maxWidth: ${plain.width},\n'
        '$pad    minHeight: ${plain.height},\n'
        '$pad    maxHeight: ${plain.height},\n'
        '$pad    child: Transform.rotate(\n'
        '$pad      angle: ${c.rotation} * math.pi / 180,\n'
        '$pad      child: $body,\n'
        '$pad    ),\n'
        '$pad  )';
    return _sized(n.rect, turned, pad);
  }
}

/// โครงหน้า Flutter (`StatelessWidget`) ของหน้าจอ [name] จาก Wireframe [d] — วางใกล้เคียงแบบด้วย `Column`/`Row`
/// (ชิ้นที่ทับกันใช้ `Stack`+`Positioned`) ตามขนาดในแบบ แล้วย่อทั้งหน้าเมื่อหน้าต่างแคบกว่า
/// ข้อจำกัด: ขนาดตายตัว (ไม่ responsive), ใช้หน้าตาของธีม Material ไม่ใช่สี/ตัวอักษรของแบบ ; ชิ้นที่ซ่อนใส่ไว้แบบมองไม่เห็น
String flutterScreen(String name, WireframeDiagram d) {
  final cls = '${pascalCase(name, fallback: 'Screen')}Screen';
  final writer = _FlutterWriter();
  final width = d.width.round(), height = d.height.round();
  const pad = '            ';
  final tree = wfLayoutTree(d);
  final hiddenIds = wfHiddenIds(d);
  final hidden = [for (final c in d.components) if (hiddenIds.contains(c.id)) c];
  // ผังชั้นนอกสุดมีขนาดเท่าหน้าจอเสมอ ; ไม่มีชิ้นให้วาง = กล่องเปล่าขนาดหน้าจอ
  String base(String indent) => tree == null ? 'const SizedBox(width: $width, height: $height)' : writer.node(tree, indent);
  final String content;
  if (hidden.isEmpty) {
    content = base(pad);
  } else {
    final s = StringBuffer('Stack(\n')
      ..writeln('$pad  children: [')
      ..writeln('$pad    ${base('$pad    ')},');
    for (final c in hidden) {
      s
        ..writeln('$pad    // ซ่อนในแบบ')
        ..writeln('$pad    Visibility(')
        ..writeln('$pad      visible: false,')
        ..writeln('$pad      child: ${writer.leaf(WfLeafNode(c, wfLayoutRect(c)), '$pad      ')},')
        ..writeln('$pad    ),');
    }
    s
      ..writeln('$pad  ],')
      ..write('$pad)');
    content = s.toString();
  }
  final b = StringBuffer()..writeln('// สร้างโดย NSL Nebular จาก Wireframe "${name.replaceAll('\n', ' ')}" — โครงหน้า แก้ต่อได้ตามต้องการ');
  if (writer.usesMath) b.writeln("import 'dart:math' as math;\n");
  b
    ..writeln("import 'package:flutter/material.dart';")
    ..writeln()
    ..writeln('class $cls extends StatelessWidget {')
    ..writeln('  const $cls({super.key});')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  Widget build(BuildContext context) {')
    ..writeln('    return Scaffold(')
    ..writeln('      body: SingleChildScrollView(')
    ..writeln('        child: Center(')
    ..writeln('          // ออกแบบไว้ที่ $width×$height — หน้าต่างแคบกว่า = ย่อทั้งหน้าให้พอดี')
    ..writeln('          child: FittedBox(')
    ..writeln('            fit: BoxFit.scaleDown,')
    ..writeln('            child: $content,')
    ..writeln('          ),')
    ..writeln('        ),')
    ..writeln('      ),')
    ..writeln('    );')
    ..writeln('  }')
    ..writeln('}');
  return b.toString();
}

/// หน้า HTML (+ Tailwind CDN) ของหน้าจอ [name] จาก Wireframe [d] — วางตามแบบทุกชิ้น (ดู [wireframeHtmlPage])
/// [workspace] = ใช้ข้อมูลตั้งต้นของ ER ที่ผูกไว้ และชื่อ endpoint
String htmlTailwindScreen(String name, WireframeDiagram d, {String lang = 'th', Workspace? workspace}) =>
    wireframeHtmlPage(name, d, lang: lang, workspace: workspace);
