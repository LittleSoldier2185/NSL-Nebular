import '../models/column_model.dart';
import '../models/enums.dart';
import '../models/project.dart';
import '../models/relation_model.dart';
import '../models/api_model.dart';
import 'naming.dart';

/// ไฟล์ที่สร้าง: path (สัมพัทธ์กับโฟลเดอร์ปลายทาง, ใช้ /) + เนื้อหา
typedef GenText = ({String path, String content});

const _phpHeader = '// สร้างโดย NSL Nebular — แก้ไขในโปรแกรมแล้วสร้างใหม่แทนการแก้ไฟล์นี้';

// ======================= Laravel migration (จาก ER) =======================

String _default(ColumnModel c) {
  final v = (c.defaultValue ?? '').trim();
  if (v.isEmpty) return '';
  final up = v.toUpperCase();
  if (up == 'CURRENT_TIMESTAMP' || up == 'NOW()') return '->useCurrent()';
  if (up == 'NULL') return '->default(null)';
  if (up == 'TRUE' || up == 'FALSE') return '->default(${up.toLowerCase()})';
  if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(v)) return '->default($v)';
  final unq = v.length >= 2 && v.startsWith("'") && v.endsWith("'") ? v.substring(1, v.length - 1) : v;
  return '->default(${singleQuoted(unq)})';
}

/// บรรทัด `$table->...` ของคอลัมน์ ; [autoPk] = เป็น PK เดี่ยวที่เพิ่มอัตโนมัติ
String _column(ColumnModel c, {required bool autoPk}) {
  final n = singleQuoted(c.name);
  final String base;
  if (autoPk) {
    base = switch (c.type) {
      DataType.smallint => '\$table->smallIncrements($n)',
      DataType.integer => '\$table->increments($n)',
      _ => c.name == 'id' ? '\$table->id()' : '\$table->bigIncrements($n)',
    };
  } else {
    base = switch (c.type) {
      DataType.integer => '\$table->integer($n)',
      DataType.bigint => '\$table->bigInteger($n)',
      DataType.smallint => '\$table->smallInteger($n)',
      DataType.varchar => '\$table->string($n, ${c.length ?? 255})',
      DataType.text => '\$table->text($n)',
      DataType.decimal => '\$table->decimal($n, ${c.length ?? 10}, ${c.scale ?? 2})',
      DataType.float => '\$table->float($n)',
      DataType.boolean => '\$table->boolean($n)',
      DataType.date => '\$table->date($n)',
      DataType.datetime => '\$table->dateTime($n)',
      DataType.timestamp => '\$table->timestamp($n)',
      DataType.blob => '\$table->binary($n)',
      DataType.uuid => '\$table->uuid($n)',
      DataType.json => '\$table->json($n)',
    };
  }
  final mods = StringBuffer();
  if (!autoPk) {
    if (!c.notNull && !c.isPrimaryKey) mods.write('->nullable()');
    if (c.unique && !c.isPrimaryKey) mods.write('->unique()');
    mods.write(_default(c));
  }
  if (c.comment.trim().isNotEmpty) mods.write('->comment(${singleQuoted(c.comment.trim().replaceAll(RegExp(r'\s+'), ' '))})');
  return '            $base$mods;';
}

String _action(RefAction a) => a.sql.toLowerCase();

/// Laravel migration: ไฟล์ละตาราง (สร้างตารางทั้งหมดก่อน) + ไฟล์สุดท้ายเพิ่ม foreign key ทั้งหมด (ไม่ต้องเรียงตามการอ้างอิง/วนกันได้)
/// ชื่อไฟล์คงที่ ไม่มีวันที่จริง (`0001_01_01_0000NN_create_x_table.php`) — สร้างซ้ำได้ไฟล์เดิม
List<GenText> laravelMigrations(Project p, {String dir = 'database/migrations'}) {
  final out = <GenText>[];
  var n = 1;
  String seq() => '0001_01_01_${(n++).toString().padLeft(6, '0')}';
  for (final t in p.tables) {
    final pks = [for (final c in t.columns) if (c.isPrimaryKey) c];
    final autoPk = pks.length == 1 && pks.single.autoIncrement ? pks.single : null;
    final b = StringBuffer()
      ..writeln('<?php')
      ..writeln()
      ..writeln(_phpHeader)
      ..writeln()
      ..writeln('use Illuminate\\Database\\Migrations\\Migration;')
      ..writeln('use Illuminate\\Database\\Schema\\Blueprint;')
      ..writeln('use Illuminate\\Support\\Facades\\Schema;')
      ..writeln()
      ..writeln('return new class extends Migration')
      ..writeln('{')
      ..writeln('    public function up(): void')
      ..writeln('    {')
      ..writeln('        Schema::create(${singleQuoted(t.name)}, function (Blueprint \$table) {');
    for (final c in t.columns) {
      b.writeln(_column(c, autoPk: identical(c, autoPk)));
    }
    if (autoPk == null && pks.isNotEmpty) {
      b.writeln('            \$table->primary([${pks.map((c) => singleQuoted(c.name)).join(', ')}]);');
    }
    for (final i in t.indexes) {
      final cols = [for (final id in i.columnIds) ?t.columnById(id)?.name];
      if (cols.isEmpty) continue;
      b.writeln('            \$table->${i.unique ? 'unique' : 'index'}([${cols.map(singleQuoted).join(', ')}], ${singleQuoted(i.name)});');
    }
    if (t.comment.trim().isNotEmpty) b.writeln('            \$table->comment(${singleQuoted(t.comment.trim().replaceAll(RegExp(r'\s+'), ' '))});');
    b
      ..writeln('        });')
      ..writeln('    }')
      ..writeln()
      ..writeln('    public function down(): void')
      ..writeln('    {')
      ..writeln('        Schema::dropIfExists(${singleQuoted(t.name)});')
      ..writeln('    }')
      ..writeln('};');
    out.add((path: '$dir/${seq()}_create_${snakeCase(t.name, fallback: 'table')}_table.php', content: b.toString()));
  }
  final fks = [for (final r in p.relations) if (_fkOk(p, r)) r];
  if (fks.isNotEmpty) {
    final byTable = <String, List<RelationModel>>{};
    for (final r in fks) {
      byTable.putIfAbsent(r.fromTableId, () => []).add(r);
    }
    final b = StringBuffer()
      ..writeln('<?php')
      ..writeln()
      ..writeln(_phpHeader)
      ..writeln()
      ..writeln('use Illuminate\\Database\\Migrations\\Migration;')
      ..writeln('use Illuminate\\Database\\Schema\\Blueprint;')
      ..writeln('use Illuminate\\Support\\Facades\\Schema;')
      ..writeln()
      ..writeln('return new class extends Migration')
      ..writeln('{')
      ..writeln('    public function up(): void')
      ..writeln('    {');
    for (final e in byTable.entries) {
      final t = p.tableById(e.key)!;
      b.writeln('        Schema::table(${singleQuoted(t.name)}, function (Blueprint \$table) {');
      for (final r in e.value) {
        final pa = p.tableById(r.toTableId)!;
        b.writeln('            \$table->foreign(${singleQuoted(t.columnById(r.fromColumnId)!.name)})'
            '->references(${singleQuoted(pa.columnById(r.toColumnId)!.name)})->on(${singleQuoted(pa.name)})'
            '->onDelete(${singleQuoted(_action(r.onDelete))})->onUpdate(${singleQuoted(_action(r.onUpdate))});');
      }
      b.writeln('        });');
    }
    b
      ..writeln('    }')
      ..writeln()
      ..writeln('    public function down(): void')
      ..writeln('    {');
    for (final e in byTable.entries) {
      final t = p.tableById(e.key)!;
      b.writeln('        Schema::table(${singleQuoted(t.name)}, function (Blueprint \$table) {');
      for (final r in e.value) {
        b.writeln('            \$table->dropForeign([${singleQuoted(t.columnById(r.fromColumnId)!.name)}]);');
      }
      b.writeln('        });');
    }
    b
      ..writeln('    }')
      ..writeln('};');
    out.add((path: '$dir/${seq()}_add_foreign_keys.php', content: b.toString()));
  }
  return out;
}

bool _fkOk(Project p, RelationModel r) {
  final a = p.tableById(r.fromTableId), b = p.tableById(r.toTableId);
  return a?.columnById(r.fromColumnId) != null && b?.columnById(r.toColumnId) != null;
}

// ======================= Laravel route + controller (จาก API) =======================

/// ชื่อเมธอดของ controller: path แบบ resource (`/x`, `/x/{id}`) ใช้ชื่อของ Laravel (index/store/show/update/destroy) ;
/// path อื่นใช้ส่วนที่เหลือของ path (`POST /auth/login` → `login`, `GET /orders/{id}/items` → `getItems`)
String laravelAction(ApiEndpoint e) {
  final segs = e.path.split('/').where((s) => s.isNotEmpty).toList();
  final params = segs.where((s) => s.startsWith('{')).length;
  final resource = segs.length == 1 || (segs.length == 2 && params == 1 && segs.last.startsWith('{'));
  if (resource) {
    final hasId = segs.length == 2;
    final r = switch ((e.method, hasId)) {
      (ApiMethod.get, false) => 'index',
      (ApiMethod.post, false) => 'store',
      (ApiMethod.get, true) => 'show',
      (ApiMethod.put || ApiMethod.patch, true) => 'update',
      (ApiMethod.delete, true) => 'destroy',
      _ => null,
    };
    if (r != null) return r;
  }
  final rest = [for (final s in segs.skip(1)) if (!s.startsWith('{')) s].join(' ');
  final verb = e.method == ApiMethod.post && rest.isNotEmpty ? '' : e.method.name;
  return camelCase('$verb $rest', fallback: e.method.name);
}

/// `routes/api.php` + controller เปล่าต่อกลุ่ม (`app/Http/Controllers/XController.php`) ของเอกสาร API [api]
List<GenText> laravelApiStubs(ApiDocument api, {String routesPath = 'routes/api.php'}) {
  final groups = <String, List<ApiEndpoint>>{};
  for (final e in api.endpoints) {
    groups.putIfAbsent(e.effectiveGroup.isEmpty ? 'api' : e.effectiveGroup, () => []).add(e);
  }
  String ctl(String g) => '${pascalCase(singular(g), fallback: 'Api')}Controller';
  final routes = StringBuffer()
    ..writeln('<?php')
    ..writeln()
    ..writeln(_phpHeader)
    ..writeln()
    ..writeln('use Illuminate\\Support\\Facades\\Route;');
  for (final g in groups.keys) {
    routes.writeln('use App\\Http\\Controllers\\${ctl(g)};');
  }
  routes.writeln();
  final out = <GenText>[];
  for (final g in groups.entries) {
    final used = <String>{};
    final c = StringBuffer()
      ..writeln('<?php')
      ..writeln()
      ..writeln(_phpHeader)
      ..writeln()
      ..writeln('namespace App\\Http\\Controllers;')
      ..writeln()
      ..writeln('use Illuminate\\Http\\JsonResponse;')
      ..writeln('use Illuminate\\Http\\Request;')
      ..writeln()
      ..writeln('class ${ctl(g.key)} extends Controller')
      ..writeln('{');
    for (final e in g.value) {
      var action = laravelAction(e);
      for (var i = 2; !used.add(action); i++) {
        action = '${laravelAction(e)}$i';
      }
      final route = "Route::${e.method.name}(${singleQuoted(e.path)}, [${ctl(g.key)}::class, ${singleQuoted(action)}])";
      routes.writeln('$route${e.auth ? "->middleware('auth:sanctum')" : ''};');
      final params = ['Request \$request', for (final p in e.pathParams) 'string \$${camelCase(p, fallback: 'id')}'];
      final status = e.responses.isEmpty ? 200 : e.responses.first.status;
      c
        ..writeln('    /** ${e.title}${e.summary.isEmpty ? '' : ' — ${e.summary.replaceAll('*/', '* /')}'} */')
        ..writeln('    public function $action(${params.join(', ')}): JsonResponse')
        ..writeln('    {');
      if (e.fields.isNotEmpty) {
        c.writeln('        \$data = \$request->validate([');
        for (final f in e.fields.where((f) => f.name.trim().isNotEmpty)) {
          final rule = [f.required ? 'required' : 'sometimes', switch (f.type) {
            ApiType.integer => 'integer',
            ApiType.number => 'numeric',
            ApiType.boolean => 'boolean',
            ApiType.array => 'array',
            ApiType.object => 'array',
            ApiType.string => 'string',
          }].join('|');
          c.writeln('            ${singleQuoted(f.name.trim())} => ${singleQuoted(rule)},');
        }
        c.writeln('        ]);');
      }
      c
        ..writeln('        // TODO: ทำงานจริง')
        ..writeln('        return response()->json([], $status);')
        ..writeln('    }')
        ..writeln();
    }
    c.writeln('}');
    out.add((path: 'app/Http/Controllers/${ctl(g.key)}.php', content: c.toString()));
  }
  return [(path: routesPath, content: routes.toString()), ...out];
}
