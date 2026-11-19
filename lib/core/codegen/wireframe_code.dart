import '../models/wireframe_model.dart';
import 'naming.dart';

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
    WfKind.icon => 'const Icon(Icons.star_outline)',
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

String _h(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// HTML ของชิ้นส่วนหนึ่งชิ้น (คลาส Tailwind)
String _htmlOf(WfComponent c) {
  final t = _h(_one(c, c.kind.name));
  final items = (c.items.isEmpty ? [c.kind.name] : c.items).map(_h).toList();
  const field = 'w-full rounded-lg border border-slate-300 px-3 py-2';
  return switch (c.kind) {
    WfKind.heading => '<h1 class="text-2xl font-bold">$t</h1>',
    WfKind.label => '<p class="text-sm font-medium text-slate-700">$t</p>',
    WfKind.paragraph => '<p class="text-slate-600">$t</p>',
    WfKind.button => c.secondary
        ? '<button class="rounded-lg border border-slate-300 px-4 py-2 font-semibold">$t</button>'
        : '<button class="rounded-lg bg-teal-700 px-4 py-2 font-semibold text-white">$t</button>',
    WfKind.input => '<input class="$field" placeholder="$t">',
    WfKind.search => '<input type="search" class="$field" placeholder="$t">',
    WfKind.textarea => '<textarea class="$field" rows="4" placeholder="$t"></textarea>',
    WfKind.checkbox => '<label class="flex items-center gap-2"><input type="checkbox"${c.checked ? ' checked' : ''}> $t</label>',
    WfKind.radio => '<label class="flex items-center gap-2"><input type="radio"${c.checked ? ' checked' : ''}> $t</label>',
    WfKind.toggle => '<label class="flex items-center gap-2"><input type="checkbox" role="switch"${c.checked ? ' checked' : ''}> $t</label>',
    WfKind.select => '<select class="$field">${items.map((i) => '<option>$i</option>').join()}</select>',
    WfKind.slider => '<input type="range" class="w-full">',
    WfKind.image || WfKind.map || WfKind.chart =>
      '<div class="flex items-center justify-center rounded-lg bg-slate-200 text-slate-500" style="height:${c.h.round()}px">$t</div>',
    WfKind.icon => '<span class="inline-block h-6 w-6 rounded bg-slate-300"></span>',
    WfKind.avatar => '<span class="inline-block h-10 w-10 rounded-full bg-slate-300"></span>',
    WfKind.table =>
      '<table class="w-full text-left"><thead><tr>${(c.columns.isEmpty ? ['Column'] : c.columns).map((h) => '<th class="border-b p-2">${_h(h)}</th>').join()}</tr></thead><tbody></tbody></table>',
    WfKind.list => '<ul class="divide-y rounded-lg border">${items.map((i) => '<li class="p-3">$i</li>').join()}</ul>',
    WfKind.card || WfKind.container || WfKind.modal => '<div class="rounded-xl border bg-white p-4 shadow-sm">$t</div>',
    WfKind.tabs => '<nav class="flex gap-4 border-b">${items.map((i) => '<a class="py-2" href="#">$i</a>').join()}</nav>',
    WfKind.navbar => '<header class="flex items-center justify-between bg-slate-800 px-4 py-3 text-white"><span class="font-bold">$t</span></header>',
    WfKind.sidebar => '<aside class="w-56 space-y-1 border-r p-3">${items.map((i) => '<a class="block rounded px-2 py-1" href="#">$i</a>').join()}</aside>',
    WfKind.divider => '<hr>',
    WfKind.badge => '<span class="rounded-full bg-slate-200 px-2 py-0.5 text-xs">$t</span>',
    WfKind.pagination => '<nav class="flex justify-center gap-2"><a href="#">‹</a><span>1</span><a href="#">›</a></nav>',
    WfKind.breadcrumb => '<nav class="text-sm text-slate-500">${items.join(' / ')}</nav>',
    WfKind.link => '<a class="text-teal-700 underline" href="#">$t</a>',
    WfKind.chip => '<span class="inline-flex items-center gap-1 rounded-full border px-3 py-1 text-sm">$t <button aria-label="remove">×</button></span>',
    WfKind.progress => '<progress class="w-full" value="${(_progressOf(c) * 100).round()}" max="100"></progress>',
    WfKind.alert => '<div role="alert" class="rounded-lg border-l-4 border-teal-700 bg-teal-50 p-3">$t</div>',
    WfKind.datepicker => '<input type="date" class="$field" aria-label="$t">',
    WfKind.upload => '<label class="flex h-32 cursor-pointer items-center justify-center rounded-xl border-2 border-dashed text-slate-500">$t<input type="file" class="hidden"></label>',
    WfKind.stepper => '<ol class="flex justify-between">${items.indexed.map((e) => "<li class=\"text-center\"><span class=\"mx-auto flex h-7 w-7 items-center justify-center rounded-full ${e.$1 == 0 ? "bg-teal-700 text-white" : "border"}\">${e.$1 + 1}</span>${e.$2}</li>").join()}</ol>',
    WfKind.rating => '<div aria-label="rating 3/5" class="text-amber-400">★★★☆☆</div>',
    WfKind.video => '<video class="w-full rounded-lg bg-black" style="height:${c.h.round()}px" controls></video>',
    WfKind.accordion => '<div class="divide-y rounded-lg border">${items.map((i) => "<details class=\"p-3\"><summary>$i</summary></details>").join()}</div>',
    WfKind.footer => '<footer class="bg-slate-100 p-4 text-center text-sm text-slate-500">$t</footer>',
    WfKind.tooltip => '<span class="rounded bg-slate-800 px-2 py-1 text-xs text-white" role="tooltip">$t</span>',
    WfKind.skeleton => '<div class="animate-pulse rounded-lg bg-slate-200" style="height:${c.h.round()}px"></div>',
    WfKind.calendar => '<input type="date" class="$field" aria-label="$t">',
    WfKind.stat => '<div class="rounded-xl border bg-white p-4"><p class="text-sm text-slate-500">${items.length > 1 ? items.first : ""}</p><p class="text-3xl font-bold">${items.length > 1 ? items[1] : items.first}</p></div>',
    WfKind.tree => '<ul class="text-sm">${_treeLines(c).map((l) => "<li style=\"margin-left:${l.$1 * 16}px\">${_h(l.$2)}</li>").join()}</ul>',
  };
}

/// หน้า HTML + Tailwind (CDN) ของหน้าจอ [name] จาก Wireframe [d]
String htmlTailwindScreen(String name, WireframeDiagram d, {String lang = 'th'}) {
  final b = StringBuffer()
    ..writeln('<!DOCTYPE html>')
    ..writeln('<!-- สร้างโดย NSL Nebular จาก Wireframe "${_h(name.replaceAll('\n', ' ')).replaceAll('--', '- -')}" — โครงหน้า แก้ต่อได้ตามต้องการ -->')
    ..writeln('<html lang="$lang">')
    ..writeln('<head>')
    ..writeln('<meta charset="utf-8">')
    ..writeln('<meta name="viewport" content="width=device-width, initial-scale=1">')
    ..writeln('<title>${_h(name)}</title>')
    ..writeln('<script src="https://cdn.tailwindcss.com"></script>')
    ..writeln('</head>')
    ..writeln('<body class="bg-slate-50 text-slate-900">')
    ..writeln('<main class="mx-auto flex max-w-3xl flex-col gap-3 p-4">');
  for (final c in readingOrder(d)) {
    b.writeln('  ${_htmlOf(c)}');
  }
  b
    ..writeln('</main>')
    ..writeln('</body>')
    ..writeln('</html>');
  return b.toString();
}
