import '../models/wf_icons.dart';
import '../models/wireframe_model.dart';
import '../models/workspace.dart';
import 'naming.dart';
import 'wireframe_html.dart';

/// ชิ้นส่วนตามลำดับอ่าน (บนลงล่าง แล้วซ้ายไปขวา ; แถวเดียวกันถ้าห่างกันไม่เกิน 8 px) — โครงหน้าแบบไหลตามลำดับ ไม่ใช่ตำแหน่งตายตัว
List<WfComponent> readingOrder(WireframeDiagram d) {
  final list = [...d.components];
  list.sort((a, b) {
    if ((a.y - b.y).abs() > 8) return a.y.compareTo(b.y);
    return a.x.compareTo(b.x);
  });
  return list;
}

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
    WfKind.radio => 'RadioListTile<int>(value: 0, groupValue: ${c.checked ? 0 : -1}, onChanged: (_) {}, title: Text($t))',
    WfKind.toggle => 'SwitchListTile(value: ${c.checked}, onChanged: (_) {}, title: Text($t))',
    WfKind.select => 'DropdownButtonFormField<String>(items: [${items.map((i) => 'DropdownMenuItem(value: ${_dartStr(i)}, child: Text(${_dartStr(i)}))').join(', ')}], onChanged: (_) {})',
    WfKind.slider => 'Slider(value: 0.5, onChanged: (_) {})',
    WfKind.image || WfKind.map || WfKind.chart => 'Container(height: ${c.h.round()}, color: Colors.black12, alignment: Alignment.center, child: Text($t))',
    WfKind.icon => 'const Icon(Icons.${wfIconById(c.symbol)?.flutter ?? 'star_outline'})',
    WfKind.avatar => 'const CircleAvatar(child: Icon(Icons.person))',
    WfKind.table => 'DataTable(columns: [${(c.columns.isEmpty ? ['Column'] : c.columns).map((h) => 'DataColumn(label: Text(${_dartStr(h)}))').join(', ')}], rows: const [])',
    WfKind.list => 'Column(children: [${items.map((i) => 'ListTile(title: Text(${_dartStr(i)}))').join(', ')}])',
    WfKind.card || WfKind.container || WfKind.modal => 'Card(child: Padding(padding: const EdgeInsets.all(16), child: Text($t)))',
    WfKind.tabs => 'DefaultTabController(length: ${items.length}, child: TabBar(tabs: [${items.map((i) => 'Tab(text: ${_dartStr(i)})').join(', ')}]))',
    WfKind.navbar => 'AppBar(title: Text($t), automaticallyImplyLeading: false)',
    WfKind.sidebar => 'NavigationRail(selectedIndex: 0, destinations: [${items.take(5).map((i) => 'NavigationRailDestination(icon: const Icon(Icons.circle_outlined), label: Text(${_dartStr(i)}))').join(', ')}${items.length < 2 ? ', const NavigationRailDestination(icon: Icon(Icons.circle_outlined), label: Text(\'\'))' : ''}])',
    WfKind.divider => 'const Divider()',
    WfKind.badge => 'Chip(label: Text($t))',
    WfKind.pagination => 'Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(onPressed: () {}, icon: const Icon(Icons.chevron_left)), const Text(\'1\'), IconButton(onPressed: () {}, icon: const Icon(Icons.chevron_right))])',
    WfKind.breadcrumb => 'Text(${_dartStr(items.join(' / '))})',
    WfKind.link => 'TextButton(onPressed: () {}, child: Text($t))',
    WfKind.chip => 'InputChip(label: Text($t), onDeleted: () {})',
    WfKind.progress => 'LinearProgressIndicator(value: ${_progressOf(c)})',
    WfKind.alert => 'MaterialBanner(content: Text($t), actions: [TextButton(onPressed: () {}, child: const Text("OK"))])',
    WfKind.datepicker => 'TextField(readOnly: true, decoration: InputDecoration(labelText: $t, suffixIcon: const Icon(Icons.calendar_today_outlined)), onTap: () {})',
    WfKind.upload => 'OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.upload_file), label: Text($t))',
    WfKind.stepper => 'Stepper(currentStep: 0, controlsBuilder: (_, _) => const SizedBox.shrink(), steps: [${items.map((i) => "Step(title: Text(${_dartStr(i)}), content: const SizedBox.shrink())").join(", ")}])',
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
    WfKind.optionGroup => 'Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(${_dartStr(items.first)}, style: Theme.of(context).textTheme.titleSmall)${items.skip(1).toList().indexed.map((e) => c.secondary ? ', CheckboxListTile(value: ${e.$1 == 0}, onChanged: (_) {}, title: Text(${_dartStr(e.$2)}))' : ', RadioListTile<int>(value: ${e.$1}, groupValue: 0, onChanged: (_) {}, title: Text(${_dartStr(e.$2)}))').join()}])',
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

/// โครงหน้า Flutter (`StatelessWidget`) ของหน้าจอ [name] จาก Wireframe [d] — ชิ้นส่วนเรียงตามลำดับอ่านใน `Column`
String flutterScreen(String name, WireframeDiagram d) {
  final cls = '${pascalCase(name, fallback: 'Screen')}Screen';
  final b = StringBuffer()
    ..writeln('// สร้างโดย NSL Nebular จาก Wireframe "${name.replaceAll('\n', ' ')}" — โครงหน้า แก้ต่อได้ตามต้องการ')
    ..writeln("import 'package:flutter/material.dart';")
    ..writeln()
    ..writeln('class $cls extends StatelessWidget {')
    ..writeln('  const $cls({super.key});')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  Widget build(BuildContext context) {')
    ..writeln('    return Scaffold(')
    ..writeln('      body: SingleChildScrollView(')
    ..writeln('        padding: const EdgeInsets.all(16),')
    ..writeln('        child: Column(')
    ..writeln('          crossAxisAlignment: CrossAxisAlignment.stretch,')
    ..writeln('          children: [');
  final comps = readingOrder(d);
  for (var i = 0; i < comps.length; i++) {
    if (i > 0) b.writeln('            const SizedBox(height: 12),');
    b.writeln('            ${_flutterWidget(comps[i])},');
  }
  b
    ..writeln('          ],')
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
