import '../export/codegen.dart';
import '../export/openapi_export.dart';
import '../export/seed_data.dart';
import '../ddl/ddl_generator.dart';
import '../l10n/l10n.dart';
import '../models/workspace.dart';
import 'laravel.dart';
import 'naming.dart';
import 'wireframe_code.dart';

/// แหล่งของเป้าหมาย (หัวข้อกลุ่มในหน้าสร้างโค้ด)
enum GenSource { database, models, api, screens }

/// เป้าหมายที่สร้างได้ — ตัวที่มีอยู่แล้วเรียกตัวสร้างเดิม (ddl_generator / codegen.dart / seed_data / openapi_export) ไม่เขียนซ้ำ
enum GenTarget {
  sqlDdl(GenSource.database, DocType.er),
  laravelMigration(GenSource.database, DocType.er),
  prisma(GenSource.database, DocType.er),
  seedSql(GenSource.database, DocType.er),
  typescript(GenSource.models, DocType.er),
  dart(GenSource.models, DocType.er),
  java(GenSource.models, DocType.er),
  csharp(GenSource.models, DocType.er),
  openApi(GenSource.api, DocType.api),
  laravelRoutes(GenSource.api, DocType.api),
  flutterScreen(GenSource.screens, DocType.wireframe),
  htmlTailwind(GenSource.screens, DocType.wireframe);

  const GenTarget(this.source, this.from);
  final GenSource source;

  /// ชนิดเอกสารที่ใช้เป็นข้อมูล (ไม่มีเอกสารชนิดนี้ = เลือกไม่ได้)
  final DocType from;
}

/// ไฟล์ที่จะสร้าง: [path] สัมพัทธ์กับโฟลเดอร์ปลายทาง (ใช้ /) ; [origin] = เอกสารต้นทาง (แสดงในพรีวิว)
class GenFile {
  const GenFile(this.path, this.content, {required this.target, required this.origin});
  final String path;
  final String content;
  final GenTarget target;
  final String origin;
}

/// ชื่อโฟลเดอร์/ไฟล์ของเอกสาร: snake_case (ไม่มีอักษรละติน = ชนิด+ลำดับ) ไม่ซ้ำกันในชนิดเดียวกัน
Map<String, String> _slugs(List<ProjectDocument> docs, String kind) {
  final used = <String>{};
  final out = <String, String>{};
  for (final (i, d) in docs.indexed) {
    var s = snakeCase(d.name, fallback: '${kind}_${i + 1}');
    if (!used.add(s)) {
      var n = 2;
      while (!used.add('${s}_$n')) {
        n++;
      }
      s = '${s}_$n';
    }
    out[d.id] = s;
  }
  return out;
}

/// ผลการสร้าง: ไฟล์ (เรียงตาม path) + คำเตือน (เป้าหมายที่ข้ามเพราะข้อมูลไม่ถูกต้อง)
typedef GenResult = ({List<GenFile> files, List<String> warnings});

/// สร้างไฟล์ทั้งหมดของ [targets] จากโปรเจกต์ [w] — ผลคงที่ (ข้อมูลเดิม → ไฟล์เดิม) ไม่มีวันที่
/// ER หลายอัน = แยกโฟลเดอร์/ชื่อไฟล์ตาม ER ; เอกสารไม่มีเนื้อหา (ER ไม่มีตาราง ฯลฯ) ถูกข้าม
GenResult generateFiles(Workspace w, Set<GenTarget> targets) {
  final files = <GenFile>[];
  final warnings = <String>[];
  final ers = [for (final d in w.documentsOf(DocType.er)) if (d.er!.tables.isNotEmpty) d];
  final apis = [for (final d in w.documentsOf(DocType.api)) if (d.api!.endpoints.isNotEmpty) d];
  final wfs = [for (final d in w.documentsOf(DocType.wireframe)) if (d.wireframe!.components.isNotEmpty) d];
  final erSlug = _slugs(ers, 'er'), apiSlug = _slugs(apis, 'api'), wfSlug = _slugs(wfs, 'screen');
  final multiEr = ers.length > 1, multiApi = apis.length > 1;

  void add(GenTarget t, ProjectDocument d, String path, String content) => files.add(GenFile(path, content, target: t, origin: d.name));

  for (final d in ers) {
    final p = d.er!;
    final db = multiEr ? 'database/${erSlug[d.id]}' : 'database';
    final suffix = multiEr ? '_${erSlug[d.id]}' : '';
    for (final t in targets) {
      switch (t) {
        case GenTarget.sqlDdl:
          add(t, d, '$db/schema.sql', DdlGenerator.forDialect(p.dialect).generate(p));
        case GenTarget.laravelMigration:
          for (final f in laravelMigrations(p, dir: '$db/migrations')) {
            add(t, d, f.path, f.content);
          }
        case GenTarget.prisma:
          add(t, d, '$db/schema.prisma', generateCode(p, CodegenTarget.prisma));
        case GenTarget.seedSql:
          try {
            final s = generateSeedSql(p);
            if (s.isNotEmpty) add(t, d, '$db/seed.sql', s);
          } on SeedException catch (e) {
            warnings.add(tr('ข้ามข้อมูลตั้งต้นของ {0}: ข้อมูลไม่ถูกต้อง {1} จุด', [d.name, e.problems.length]));
          }
        case GenTarget.typescript:
          add(t, d, 'types/models$suffix.ts', generateCode(p, CodegenTarget.typescript));
        case GenTarget.dart:
          add(t, d, 'lib/models/models$suffix.dart', generateCode(p, CodegenTarget.dart));
        case GenTarget.java:
          add(t, d, 'java/Models${pascalCase(suffix, fallback: '')}.java', generateCode(p, CodegenTarget.java));
        case GenTarget.csharp:
          add(t, d, 'csharp/Models${pascalCase(suffix, fallback: '')}.cs', generateCode(p, CodegenTarget.csharp));
        default:
          break;
      }
    }
  }
  for (final d in apis) {
    if (targets.contains(GenTarget.openApi)) {
      add(GenTarget.openApi, d, 'api/${apiSlug[d.id]}.openapi.json', exportOpenApiJson(d.api!, w: w, fallbackTitle: d.name));
    }
    if (targets.contains(GenTarget.laravelRoutes)) {
      for (final f in laravelApiStubs(d.api!, routesPath: multiApi ? 'routes/${apiSlug[d.id]}.php' : 'routes/api.php')) {
        add(GenTarget.laravelRoutes, d, f.path, f.content);
      }
    }
  }
  for (final d in wfs) {
    if (targets.contains(GenTarget.flutterScreen)) {
      add(GenTarget.flutterScreen, d, 'lib/screens/${wfSlug[d.id]}_screen.dart', flutterScreen(d.name, d.wireframe!));
    }
    if (targets.contains(GenTarget.htmlTailwind)) {
      add(GenTarget.htmlTailwind, d, 'web/${wfSlug[d.id]}.html', htmlTailwindScreen(d.name, d.wireframe!, lang: currentLang.code));
    }
  }
  // controller ชื่อเดียวกันจากหลายเอกสาร API: ใช้ตัวแรก แจ้งเตือน
  final seen = <String>{};
  final unique = <GenFile>[];
  for (final f in files) {
    if (seen.add(f.path)) {
      unique.add(f);
    } else {
      warnings.add(tr('ไฟล์ {0} ซ้ำกันจากหลายเอกสาร — ใช้จาก {1}', [f.path, unique.firstWhere((x) => x.path == f.path).origin]));
    }
  }
  unique.sort((a, b) => a.path.compareTo(b.path));
  return (files: unique, warnings: warnings);
}

/// เป้าหมายที่เลือกได้ในโปรเจกต์นี้ (มีเอกสารต้นทางที่มีเนื้อหา)
bool targetAvailable(Workspace w, GenTarget t) => switch (t.from) {
      DocType.er => w.documentsOf(DocType.er).any((d) => d.er!.tables.isNotEmpty),
      DocType.api => w.documentsOf(DocType.api).any((d) => d.api!.endpoints.isNotEmpty),
      DocType.wireframe => w.documentsOf(DocType.wireframe).any((d) => d.wireframe!.components.isNotEmpty),
      _ => false,
    };
