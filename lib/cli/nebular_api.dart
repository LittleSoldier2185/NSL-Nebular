import 'dart:convert';
import 'dart:io';

import '../core/app_info.dart';
import '../core/codegen/gen_targets.dart';
import '../core/codegen/gen_writer.dart';
import '../core/export/html_doc_export.dart';
import '../core/export/markdown_export.dart';
import '../core/export/openapi_export.dart';
import '../core/export/sql_export.dart';
import '../core/export/workspace_summary.dart';
import '../core/l10n/l10n.dart';
import '../core/models/workspace.dart';
import '../core/storage/project_file.dart';
import '../core/validate/issue.dart';
import '../core/validate/usecase_validator.dart';
import '../core/validate/workspace_validator.dart';

/// แกนของ CLI และ MCP server (Dart ล้วน ไม่แตะ Flutter) — เรียกตัวตรวจ/ตัวส่งออก/ตัวสร้างโค้ดของโปรแกรมโดยตรง
///
/// **อ่านไฟล์โปรเจกต์อย่างเดียว ไม่เขียนทับ** (กันชนกับโปรแกรมที่เปิดไฟล์เดียวกันอยู่) ; เขียนได้เฉพาะโฟลเดอร์/ไฟล์ปลายทางที่ผู้เรียกระบุ
class NebularError implements Exception {
  NebularError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// ตั้งภาษาของข้อความที่ได้จากตัวตรวจ (`th` / `en`)
void setCliLanguage(String? code) {
  currentLang = Lang.fromCode(code) ?? Lang.th;
}

/// อ่านไฟล์โปรเจกต์ (`.nsln` และสกุลเก่าที่เปิดได้) — path ที่ไม่ใช่สกุลโปรเจกต์ถูกปฏิเสธ (ไม่ให้ใช้เครื่องมือนี้อ่านไฟล์อื่น)
Future<Workspace> loadProject(String path) async {
  final lower = path.toLowerCase();
  if (!kOpenableExts.any((e) => lower.endsWith('.$e'))) {
    throw NebularError('ไม่ใช่ไฟล์โปรเจกต์ Nebular (ต้องลงท้าย ${kOpenableExts.map((e) => '.$e').join(' / ')}): $path');
  }
  final f = File(path);
  if (!await f.exists()) throw NebularError('ไม่พบไฟล์: $path');
  try {
    return ProjectFile.decode(await f.readAsString());
  } on ProjectFormatException catch (e) {
    throw NebularError('อ่านไฟล์โปรเจกต์ไม่ได้: ${e.message}');
  } on FileSystemException catch (e) {
    throw NebularError('อ่านไฟล์ไม่ได้: ${e.message}');
  }
}

/// ชื่อชนิดเอกสารที่ใช้ในผลลัพธ์ (ชนิดที่รุ่นนี้ไม่รู้จัก = ชื่อในไฟล์)
String docTypeName(ProjectDocument d) => d.type?.name ?? d.typeName;

/// ภาพรวมของโปรเจกต์: ชื่อ, จำนวนเอกสารแยกชนิด, ตัวเลขสรุป, จำนวนปัญหา
Map<String, dynamic> projectInfo(Workspace w, {String? path}) {
  final c = workspaceCounts(w);
  final byType = <String, int>{};
  for (final d in w.documents) {
    byType.update(docTypeName(d), (n) => n + 1, ifAbsent: () => 1);
  }
  final issues = [...validateWorkspace(w).map((i) => i.issue), ...validateUseCases(w).map((i) => i.toIssue())];
  int count(Severity s) => issues.where((i) => i.severity == s).length;
  return {
    'name': w.name,
    'path': ?path,
    'app': '$kAppName $kAppVersion',
    'documents': w.documents.length,
    'documentsByType': byType,
    'tables': c.tables,
    'relations': c.relations,
    'dfdObjects': c.objects,
    'flowchartSymbols': c.symbols,
    'wireframeComponents': c.components,
    'screens': c.screens,
    'endpoints': [for (final d in w.documents) d.api?.endpoints.length ?? 0].fold<int>(0, (a, b) => a + b),
    'requirements': w.requirements.length,
    'useCases': w.useCases.length,
    'issues': {'errors': count(Severity.error), 'warnings': count(Severity.warning), 'info': count(Severity.info)},
  };
}

/// รายการเอกสาร (id, ชนิด, ชื่อ)
List<Map<String, dynamic>> listDocuments(Workspace w) => [
      for (final d in w.documents) {'id': d.id, 'type': docTypeName(d), 'name': d.name, 'known': d.type != null},
    ];

/// หาเอกสารจาก id หรือชื่อ (ไม่สนตัวพิมพ์) — ไม่เจอ/ชื่อซ้ำหลายเอกสาร = [NebularError] พร้อมรายการให้เลือก
ProjectDocument findDocument(Workspace w, String ref) {
  final byId = w.documentById(ref);
  if (byId != null) return byId;
  final r = ref.trim().toLowerCase();
  final byName = [for (final d in w.documents) if (d.name.toLowerCase() == r) d];
  if (byName.length == 1) return byName.first;
  final list = [for (final d in w.documents) '${d.id} (${docTypeName(d)}: ${d.name})'].join(', ');
  if (byName.length > 1) throw NebularError('ชื่อเอกสาร "$ref" ซ้ำกันหลายชิ้น — ระบุเป็น id แทน: $list');
  throw NebularError('ไม่พบเอกสาร "$ref" — เอกสารที่มี: ${list.isEmpty ? '(ไม่มี)' : list}');
}

/// เนื้อหาของเอกสารเป็น JSON (รูปแบบเดียวกับในไฟล์โปรเจกต์)
Map<String, dynamic> readDocument(Workspace w, String ref) {
  final d = findDocument(w, ref);
  return {'id': d.id, 'type': docTypeName(d), 'name': d.name, 'content': d.content.toContentJson()};
}

Severity? parseSeverity(String? s) => switch (s?.toLowerCase()) {
      null || '' || 'info' => null,
      'error' => Severity.error,
      'warning' => Severity.warning,
      _ => throw NebularError('ระดับต้องเป็น error / warning / info (ได้ "$s")'),
    };

/// ผลตรวจทั้งโปรเจกต์ — [minSeverity] = แสดงเฉพาะระดับนี้ขึ้นไป (ไม่ระบุ = ทุกระดับ) ; [language] ตั้งภาษาของข้อความ
Map<String, dynamic> validateReport(Workspace w, {Severity? minSeverity}) {
  final all = validateWorkspace(w);
  final uc = validateUseCases(w); // Use Case ไม่ผูกกับเอกสาร จึงรายงานแยก (type = usecase)
  int rank(Severity s) => switch (s) { Severity.error => 0, Severity.warning => 1, Severity.info => 2 };
  final shown = [for (final i in all) if (minSeverity == null || rank(i.issue.severity) <= rank(minSeverity)) i];
  final ucShown = [for (final i in uc) if (minSeverity == null || rank(i.severity) <= rank(minSeverity)) i];
  int count(Severity s) => all.where((i) => i.issue.severity == s).length + uc.where((i) => i.severity == s).length;
  return {
    'errors': count(Severity.error),
    'warnings': count(Severity.warning),
    'info': count(Severity.info),
    'issues': [
      for (final i in shown)
        {
          'documentId': i.docId,
          'document': i.docName,
          'type': i.docType.name,
          'severity': i.issue.severity.name,
          'code': i.issue.code,
          'title': i.issue.title,
          'message': i.issue.message,
          if (i.issue.tableId != null) 'elementId': i.issue.tableId,
        },
      for (final i in ucShown)
        {
          'documentId': '',
          'document': 'Use Case',
          'type': 'usecase',
          'severity': i.severity.name,
          'code': i.code,
          'title': i.title,
          'message': i.detail,
          if (i.ucId != null) 'elementId': i.ucId,
          if (i.stepId != null) 'stepId': i.stepId,
        },
    ],
  };
}

/// รูปแบบที่ส่งออกเป็นข้อความได้
const kExportFormats = ['markdown', 'html', 'sql', 'openapi'];

/// ส่งออกทั้งโปรเจกต์เป็นข้อความ — `openapi` ใช้เอกสาร API [document] (ไม่ระบุ = เอกสาร API ตัวแรก)
String exportProject(Workspace w, String format, {String? document}) {
  switch (format) {
    case 'markdown' || 'md':
      return exportWorkspaceDictionary(w);
    case 'html':
      return exportHtmlDocument(w);
    case 'sql':
      if (w.documentsOf(DocType.er).isEmpty) throw NebularError('โปรเจกต์นี้ไม่มีเอกสาร ER จึงสร้าง SQL ไม่ได้');
      return buildWorkspaceSql(w);
    case 'openapi':
      final ProjectDocument? d;
      if (document != null) {
        d = findDocument(w, document);
        if (d.api == null) throw NebularError('เอกสาร "${d.name}" ไม่ใช่เอกสาร API');
      } else {
        d = w.documentsOf(DocType.api).firstOrNull;
      }
      if (d == null) throw NebularError('โปรเจกต์นี้ไม่มีเอกสาร API');
      return exportOpenApiJson(d.api!, w: w, fallbackTitle: d.name);
    default:
      throw NebularError('ไม่รู้จักรูปแบบ "$format" — ใช้ได้: ${kExportFormats.join(', ')}');
  }
}

/// เป้าหมายการสร้างโค้ดทั้งหมด พร้อมบอกว่าโปรเจกต์นี้สร้างได้ไหม
List<Map<String, dynamic>> listTargets([Workspace? w]) => [
      for (final t in GenTarget.values)
        {'name': t.name, 'source': t.source.name, 'from': t.from.name, if (w != null) 'available': targetAvailable(w, t)},
    ];

/// แปลงรายชื่อเป้าหมาย (`all` = ทุกตัวที่โปรเจกต์นี้สร้างได้)
Set<GenTarget> parseTargets(Workspace w, Iterable<String> names) {
  final byName = GenTarget.values.asNameMap();
  final out = <GenTarget>{};
  for (final n in names) {
    final name = n.trim();
    if (name.isEmpty) continue;
    if (name == 'all') {
      out.addAll(GenTarget.values.where((t) => targetAvailable(w, t)));
      continue;
    }
    final t = byName[name];
    if (t == null) throw NebularError('ไม่รู้จักเป้าหมาย "$name" — ใช้ได้: all, ${byName.keys.join(', ')}');
    out.add(t);
  }
  if (out.isEmpty) {
    throw NebularError(names.any((n) => n.trim() == 'all')
        ? 'โปรเจกต์นี้ยังไม่มีอะไรให้สร้างโค้ด (ER ที่มีตาราง / API ที่มี endpoint / Wireframe ที่มีชิ้นส่วน)'
        : 'ยังไม่ได้ระบุเป้าหมาย (เช่น sqlDdl,typescript หรือ all)');
  }
  return out;
}

/// ไฟล์ที่จะสร้าง (ยังไม่เขียน) + คำเตือน
Map<String, dynamic> codegenPreview(Workspace w, Set<GenTarget> targets) {
  final r = generateFiles(w, targets);
  return {
    'files': [
      for (final f in r.files) {'path': f.path, 'target': f.target.name, 'origin': f.origin, 'bytes': utf8.encode(f.content).length},
    ],
    'warnings': r.warnings,
  };
}

/// สร้างไฟล์ลงโฟลเดอร์ [outDir] — **ไม่ทับไฟล์ที่ถูกแก้ด้วยมือ** (ข้ามและรายงาน) เว้นแต่ [overwriteEdited]
Future<Map<String, dynamic>> codegenWrite(Workspace w, Set<GenTarget> targets, String outDir, {bool overwriteEdited = false}) async {
  final r = generateFiles(w, targets);
  final plan = await planWrite(Directory(outDir), r.files);
  final written = await applyWrite(plan, overwriteEdited: overwriteEdited);
  return {
    'outDir': Directory(outDir).absolute.path,
    'written': written,
    'created': [for (final f in plan.create) f.path],
    'overwritten': [for (final f in plan.overwrite) f.path],
    'unchanged': [for (final f in plan.unchanged) f.path],
    'editedByHand': [for (final f in plan.edited) f.path],
    'skippedEditedByHand': overwriteEdited ? <String>[] : [for (final f in plan.edited) f.path],
    'warnings': r.warnings,
  };
}
