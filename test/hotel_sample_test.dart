import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_nebular/cli/nebular_api.dart';
import 'package:nsl_nebular/core/codegen/gen_targets.dart';
import 'package:nsl_nebular/core/export/dfd_svg.dart';
import 'package:nsl_nebular/core/export/flowchart_svg.dart';
import 'package:nsl_nebular/core/export/screenflow_svg.dart';
import 'package:nsl_nebular/core/export/wireframe_svg.dart';
import 'package:nsl_nebular/core/l10n/l10n.dart';
import 'package:nsl_nebular/core/models/traceability.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/storage/project_file.dart';
import 'package:nsl_nebular/main.dart';
import 'package:nsl_nebular/state/app_settings.dart';
import 'package:nsl_nebular/state/workspace_controller.dart';
import 'package:nsl_nebular/ui/home_page.dart';
import 'package:provider/provider.dart';

/// โปรเจกต์ตัวอย่าง "ระบบจองห้องพัก" (samples/hotel_booking.nsln — สร้างด้วย `dart run tool/gen_hotel_sample.dart`)
/// ใช้ครบทุกชนิดเอกสาร : เปิดในแอป ตรวจ ส่งออก สร้างโค้ด ต้องไม่มีข้อผิดพลาด
void main() {
  const path = 'samples/hotel_booking.nsln';
  late Workspace w;

  setUp(() async {
    currentLang = Lang.th;
    w = await loadProject(path);
  });
  tearDown(() => currentLang = Lang.th);

  group('ข้อมูล', () {
    test('มีครบทุกชนิดเอกสาร และผูกกันข้ามเอกสารครบ (ตรวจแล้วไม่มีปัญหาเลย)', () {
      expect({for (final d in w.documents) d.type}, DocType.values.toSet());
      expect(w.documents.length, 13);
      expect(w.documentsOf(DocType.wireframe).length, 7);
      expect(w.documentsOf(DocType.er).single.er!.tables.length, 9);
      expect(w.requirements.length, 10);
      final r = validateReport(w);
      expect(r['errors'], 0);
      expect(r['warnings'], 0);
      expect(r['issues'], isEmpty, reason: '${r['issues']}');
    });

    test('ไป-กลับไฟล์ไม่เสียข้อมูล (เขียนซ้ำแล้วอ่านใหม่ได้เนื้อหาเดิม)', () {
      final again = ProjectFile.decode(ProjectFile.encode(w));
      expect(ProjectFile.encode(again), ProjectFile.encode(w));
    });

    test('ใช้ชิ้นส่วน Wireframe หลากหลายครบเกือบทุกชนิด ; ฟีเจอร์เลเยอร์ (กลุ่ม ซ่อน หมุน) อยู่ในไฟล์', () {
      final kinds = {for (final d in w.documentsOf(DocType.wireframe)) for (final c in d.wireframe!.components) c.kind};
      expect(kinds.length, greaterThanOrEqualTo(40), reason: 'ใช้ ${kinds.length} จาก 45 ชนิด');
      final all = [for (final d in w.documentsOf(DocType.wireframe)) ...d.wireframe!.components];
      expect(all.any((c) => c.group != null), isTrue);
      expect(all.any((c) => c.hidden), isTrue);
      expect(all.any((c) => c.rotation != 0), isTrue);
      expect(all.where((c) => c.ref != null).length, greaterThan(30), reason: 'ผูกข้อมูล ER');
      expect(all.where((c) => c.api != null).length, greaterThan(10), reason: 'ผูก endpoint');
    });

    test('ไล่ตามความต้องการ: ข้อที่ครบ 6 คอลัมน์ ; REQ-09/10 เว้นช่องไว้ให้ทดสอบเมทริกซ์ช่องว่าง', () {
      bool covered(String code) => requirementCovered(w, w.requirements.firstWhere((r) => r.code == code));
      for (final code in ['REQ-01', 'REQ-02', 'REQ-03', 'REQ-04', 'REQ-05', 'REQ-06', 'REQ-07', 'REQ-08']) {
        expect(covered(code), isTrue, reason: code);
      }
      expect(covered('REQ-09'), isFalse);
      expect(covered('REQ-10'), isFalse);
      final s = traceSummary(w);
      expect(s.total, 10);
      expect(s.covered, 8);
      // ลิงก์ทุกข้อชี้วัตถุที่มีอยู่จริง (ไม่มีลิงก์ขาด)
      for (final r in w.requirements) {
        for (final t in kTraceColumns) {
          final raw = r.cells[t]?.links.length ?? 0;
          expect(validLinks(w, r, t).length, raw, reason: '${r.code}/${t.name} มีลิงก์ขาด');
        }
      }
    });
  });

  group('ส่งออกและสร้างโค้ด', () {
    test('ส่งออกครบ 4 รูปแบบ (ภาษาไทยและอังกฤษ)', () {
      for (final lang in [Lang.th, Lang.en]) {
        currentLang = lang;
        expect(exportProject(w, 'markdown'), contains('bookings'));
        expect(exportProject(w, 'html'), contains('<svg'), reason: 'แผนภาพฝังในเอกสาร');
        final sql = exportProject(w, 'sql');
        expect(sql, contains('CREATE TABLE `bookings`'));
        expect(sql, contains('FOREIGN KEY'));
        final api = exportProject(w, 'openapi');
        expect(api, contains('/bookings'));
        expect(api, contains('bearerAuth'));
      }
    });

    test('สร้างโค้ดทุกเป้าหมาย: ไม่มีคำเตือน ไฟล์ไม่ซ้ำ และผลคงที่ (สร้างซ้ำได้ไฟล์เดิมทุกตัวอักษร)', () {
      final all = parseTargets(w, ['all']);
      expect(all.length, 13);
      final a = generateFiles(w, all);
      final b = generateFiles(w, all);
      expect(a.warnings, isEmpty);
      expect(a.files.length, greaterThan(30));
      expect(a.files.map((f) => f.path).toSet().length, a.files.length);
      expect([for (final f in a.files) f.content], [for (final f in b.files) f.content]);
      final paths = a.files.map((f) => f.path).toSet();
      expect(paths, containsAll(['database/schema.sql', 'database/seed.sql', 'routes/api.php', 'types/models.ts', 'api/api.openapi.json']));
      expect(a.files.where((f) => f.path.startsWith('lib/screens/')).length, 7, reason: 'หนึ่ง Wireframe = หนึ่งหน้า Flutter');
    });

    test('ชุดตั้งค่าในไฟล์ (codegen / mock) อ่านได้', () {
      final preset = w.meta.extra['codegen'] as Map;
      expect(preset['targets'], contains('laravelMigration'));
      expect(preset['folder'], 'generated/hotel');
      expect((w.meta.extra['mock'] as Map)['port'], 8787);
    });

    test('วาดภาพทุกแผนภาพได้: SVG ของ DFD/Wireframe/Screen Flow ไม่มี NaN และ PNG ของทุกหน้าจอไม่ว่าง', () async {
      for (final d in w.documents) {
        final String? svg = switch (d.type!) {
          DocType.dfd => exportDfdSvg(d.dfd!),
          DocType.flowchart => exportFlowchartSvg(d.flowchart!),
          DocType.wireframe => exportWireframeSvg(d.wireframe!),
          DocType.screenflow => exportScreenFlowSvg(d.screenflow!, wireframeOf: (id) => w.documentById(id)?.wireframe),
          _ => '<svg/>',
        };
        expect(svg, isNotNull, reason: d.name);
        expect(svg!.contains('NaN') || svg.contains('Infinity'), isFalse, reason: d.name);
        expect(svg, startsWith('<svg'), reason: d.name);
      }
    });
  });

  group('เปิดในแอปจริง', () {
    testWidgets('เปิดทุกเอกสารเป็นแท็บและทุกหน้าของโปรเจกต์ (Home, พจนานุกรม, ไล่ตาม, สร้างโค้ด, Mock Server) โดยไม่มีข้อผิดพลาด ทั้งธีมสว่างและมืด', (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final dark in [false, true]) {
        await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, dark: dark, showExplorer: true), initialProject: w, initialPath: path));
        await tester.pumpAndSettle();
        final wc = tester.element(find.byType(HomePage)).read<WorkspaceController>();
        expect(wc.workspace.documents.length, 13);

        for (final d in w.documents) {
          wc.openDocument(d.id);
          await tester.pumpAndSettle();
          expect(wc.activeId, d.id);
          expect(tester.takeException(), isNull, reason: 'เปิด ${d.name} (${d.typeName}) ธีม${dark ? 'มืด' : 'สว่าง'}');
        }
        for (final show in <void Function()>[wc.showHome, wc.showDictionary, wc.showHistory, wc.showTrace, wc.showCodegen, wc.showMock]) {
          show();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'หน้าระดับโปรเจกต์ ${wc.page}');
        }
        wc.showHome(false);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('ไม่มีปัญหาในหน้า "ปัญหาทั้งโปรเจกต์" และ Project Home บอกจำนวนเอกสารถูก', (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NslDevApp(settings: AppSettings(lang: Lang.th, showExplorer: true), initialProject: w, initialPath: path));
      await tester.pumpAndSettle();
      final wc = tester.element(find.byType(HomePage)).read<WorkspaceController>();
      expect(wc.workspaceIssues, isEmpty);
      wc.showHome();
      await tester.pumpAndSettle();
      expect(find.textContaining('13'), findsWidgets);
      expect(wc.dirty, isFalse, reason: 'การเปิดไฟล์ไม่ทำให้ไฟล์ถูกแก้');
    });

    test('ไฟล์ตัวอย่างยังอยู่ในสภาพเดิมหลังเปิด/ตรวจ (เทสต์ไม่แก้ไฟล์ตัวอย่าง)', () async {
      final before = await File(path).readAsBytes();
      await loadProject(path);
      expect(await File(path).readAsBytes(), before);
    });
  });
}
