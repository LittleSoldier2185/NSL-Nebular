// สร้างโปรเจกต์ตัวอย่าง "ระบบจองห้องพัก" (samples/hotel_booking.nsln) ด้วยโมเดลเดียวกับโปรแกรม
// ใช้ทดสอบโปรแกรมแบบครบทุกชนิดเอกสาร: ER · DFD (2 ระดับ) · Flowchart · Wireframe (7 หน้า) · Screen Flow · API · ความต้องการ · โน้ต
//
// รัน: dart run tool/gen_hotel_sample.dart samples/hotel_booking.nsln
import 'dart:io';

import 'package:nsl_nebular/core/layout/screenflow_geometry.dart';
import 'package:nsl_nebular/core/mock/mock_settings.dart';
import 'package:nsl_nebular/core/models/api_ref.dart';
import 'package:nsl_nebular/core/models/requirement.dart';
import 'package:nsl_nebular/core/models/review_note.dart';
import 'package:nsl_nebular/core/models/screenflow_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/storage/project_file.dart';

import 'gen_hotel_sample/api.dart';
import 'gen_hotel_sample/er.dart';
import 'gen_hotel_sample/process.dart';
import 'gen_hotel_sample/wireframes.dart';

ScreenFlowDiagram buildScreenFlow() {
  SfNode screen(String id, String title, String wf) => SfNode(id: id, kind: SfKind.screen, title: title, wireframeId: wf);
  final d = ScreenFlowDiagram(nodes: [
    SfNode(id: 'sf_start', kind: SfKind.start, title: 'ผู้ใช้เข้าเว็บ'),
    screen('sf_home', 'หน้าแรก', 'wf_home'),
    screen('sf_rooms', 'รายการห้อง', 'wf_rooms'),
    screen('sf_detail', 'รายละเอียดห้อง', 'wf_detail'),
    screen('sf_checkout', 'จองและชำระเงิน', 'wf_checkout'),
    SfNode(id: 'sf_gateway', kind: SfKind.external, title: 'หน้าชำระเงินของธนาคาร'),
    screen('sf_mybookings', 'การจองของฉัน', 'wf_mybookings'),
    screen('sf_admin', 'แดชบอร์ดแอดมิน', 'wf_admin'),
    screen('sf_adminroom', 'เพิ่ม/แก้ไขห้อง', 'wf_adminroom'),
    SfNode(id: 'sf_end', kind: SfKind.end, title: 'ออกจากระบบ'),
  ], edges: [
    SfEdge(id: 's1', fromId: 'sf_start', toId: 'sf_home'),
    SfEdge(id: 's2', fromId: 'sf_home', toId: 'sf_rooms', label: 'ค้นหาห้องว่าง')..api = const ApiRef(docId: kApiDocId, endpointId: 'e_rooms_available'),
    SfEdge(id: 's3', fromId: 'sf_home', toId: 'sf_detail', label: 'ดูรายละเอียดประเภทห้อง')..api = const ApiRef(docId: kApiDocId, endpointId: 'e_types_get'),
    SfEdge(id: 's4', fromId: 'sf_rooms', toId: 'sf_detail', label: 'เลือกห้อง'),
    SfEdge(id: 's5', fromId: 'sf_detail', toId: 'sf_checkout', label: 'จองเลย', condition: 'เข้าสู่ระบบแล้ว')..api = const ApiRef(docId: kApiDocId, endpointId: 'e_booking_create'),
    SfEdge(id: 's6', fromId: 'sf_checkout', toId: 'sf_gateway', label: 'ชำระเงิน')..api = const ApiRef(docId: kApiDocId, endpointId: 'e_pay_create'),
    SfEdge(id: 's7', fromId: 'sf_gateway', toId: 'sf_mybookings', label: 'ชำระสำเร็จ'),
    SfEdge(id: 's8', fromId: 'sf_gateway', toId: 'sf_checkout', label: 'ชำระไม่สำเร็จ'),
    SfEdge(id: 's9', fromId: 'sf_mybookings', toId: 'sf_end', label: 'ออกจากระบบ'),
    SfEdge(id: 's10', fromId: 'sf_home', toId: 'sf_admin', label: 'เมนูแอดมิน', condition: 'role = admin'),
    SfEdge(id: 's11', fromId: 'sf_admin', toId: 'sf_adminroom', label: 'เพิ่ม/แก้ไขห้อง'),
    SfEdge(id: 's12', fromId: 'sf_adminroom', toId: 'sf_admin', label: 'บันทึก')..api = const ApiRef(docId: kApiDocId, endpointId: 'e_rooms_create'),
    SfEdge(id: 's13', fromId: 'sf_admin', toId: 'sf_end', label: 'ออกจากระบบ'),
  ]);
  final pos = sfAutoLayout(d);
  for (final n in d.nodes) {
    final p = pos[n.id];
    if (p != null) {
      n.x = p.x + 60;
      n.y = p.y + 60;
    }
  }
  return d;
}

Requirement req(String id, String code, String text, ReqPriority pr, Map<DocType, TraceCell> cells) =>
    Requirement(id: id, code: code, text: text, priority: pr, cells: cells);

TraceCell links(List<TraceLink> l) => TraceCell(links: l);
final na = TraceCell(notNeeded: true);

List<Requirement> buildRequirements() => [
      req('r1', 'REQ-01', 'ผู้เข้าพักค้นหาห้องว่างตามวันที่และจำนวนผู้เข้าพักได้', ReqPriority.high, {
        DocType.er: links([const TraceLink('er_main', 'rooms'), const TraceLink('er_main', 'bookings')]),
        DocType.dfd: links([const TraceLink(kDfdLevel1Id, 'p1')]),
        DocType.flowchart: links([const TraceLink('fc_booking', 'search')]),
        DocType.wireframe: links([const TraceLink('wf_home', 'h_btn_search')]),
        DocType.screenflow: links([const TraceLink('sf_main', 'sf_rooms')]),
        DocType.api: links([const TraceLink(kApiDocId, 'e_rooms_available')]),
      }),
      req('r2', 'REQ-02', 'สมัครสมาชิกและเข้าสู่ระบบด้วยอีเมล', ReqPriority.high, {
        DocType.er: links([const TraceLink('er_main', 'users')]),
        DocType.dfd: links([const TraceLink(kDfdLevel1Id, 'd1')]),
        DocType.flowchart: links([const TraceLink('fc_booking', 'auth')]),
        DocType.wireframe: links([const TraceLink('wf_home', 'h_nav')]),
        DocType.screenflow: links([const TraceLink('sf_main', 'sf_home')]),
        DocType.api: links([const TraceLink(kApiDocId, 'e_register'), const TraceLink(kApiDocId, 'e_login')]),
      }),
      req('r3', 'REQ-03', 'จองห้องโดยไม่ให้จองซ้อนในช่วงวันเดียวกัน', ReqPriority.high, {
        DocType.er: links([const TraceLink('er_main', 'bookings')]),
        DocType.dfd: links([const TraceLink(kDfdLevel1Id, 'p2')]),
        DocType.flowchart: links([const TraceLink('fc_booking', 'create')]),
        DocType.wireframe: links([const TraceLink('wf_detail', 'd_btn_book')]),
        DocType.screenflow: links([const TraceLink('sf_main', 'sf_checkout')]),
        DocType.api: links([const TraceLink(kApiDocId, 'e_booking_create')]),
      }),
      req('r4', 'REQ-04', 'ชำระเงินออนไลน์ (บัตร / PromptPay / โอน)', ReqPriority.high, {
        DocType.er: links([const TraceLink('er_main', 'payments')]),
        DocType.dfd: links([const TraceLink(kDfdLevel1Id, 'p3')]),
        DocType.flowchart: links([const TraceLink('fc_booking', 'pay')]),
        DocType.wireframe: links([const TraceLink('wf_checkout', 'c_btn_pay')]),
        DocType.screenflow: links([const TraceLink('sf_main', 'sf_gateway')]),
        DocType.api: links([const TraceLink(kApiDocId, 'e_pay_create')]),
      }),
      req('r5', 'REQ-05', 'ดูและยกเลิกการจองของตัวเอง', ReqPriority.medium, {
        DocType.er: links([const TraceLink('er_main', 'bookings')]),
        DocType.dfd: links([const TraceLink(kDfdLevel1Id, 'd3')]),
        DocType.flowchart: links([const TraceLink('fc_booking', 'cancel')]),
        DocType.wireframe: links([const TraceLink('wf_mybookings')]),
        DocType.screenflow: links([const TraceLink('sf_main', 'sf_mybookings')]),
        DocType.api: links([const TraceLink(kApiDocId, 'e_booking_list'), const TraceLink(kApiDocId, 'e_booking_cancel')]),
      }),
      req('r6', 'REQ-06', 'เขียนรีวิวและให้คะแนนหลังเข้าพัก', ReqPriority.medium, {
        DocType.er: links([const TraceLink('er_main', 'reviews')]),
        DocType.dfd: links([const TraceLink(kDfdLevel1Id, 'p5')]),
        DocType.flowchart: na,
        DocType.wireframe: links([const TraceLink('wf_mybookings', 'm_review')]),
        DocType.screenflow: na,
        DocType.api: links([const TraceLink(kApiDocId, 'e_review_create')]),
      }),
      req('r7', 'REQ-07', 'แอดมินเพิ่ม/แก้ไข/ลบห้องและตั้งราคา', ReqPriority.high, {
        DocType.er: links([const TraceLink('er_main', 'rooms'), const TraceLink('er_main', 'seasonal_prices')]),
        DocType.dfd: links([const TraceLink(kDfdLevel1Id, 'p4')]),
        DocType.flowchart: na,
        DocType.wireframe: links([const TraceLink('wf_adminroom', 'x_form')]),
        DocType.screenflow: links([const TraceLink('sf_main', 'sf_adminroom')]),
        DocType.api: links([const TraceLink(kApiDocId, 'e_rooms_create'), const TraceLink(kApiDocId, 'e_rooms_update')]),
      }),
      req('r8', 'REQ-08', 'แดชบอร์ดแอดมิน: อัตราเข้าพัก เช็คอิน/เอาท์ รายได้', ReqPriority.medium, {
        DocType.er: links([const TraceLink('er_main', 'bookings')]),
        DocType.dfd: links([const TraceLink(kDfdLevel1Id, 'p5')]),
        DocType.flowchart: na,
        DocType.wireframe: links([const TraceLink('wf_admin', 'a_side')]),
        DocType.screenflow: links([const TraceLink('sf_main', 'sf_admin')]),
        DocType.api: links([const TraceLink(kApiDocId, 'e_dashboard')]),
      }),
      // ตั้งใจเว้นบางช่อง — เอาไว้ทดสอบเมทริกซ์ช่องว่างและ "สร้างเอกสารจากช่องว่าง"
      req('r9', 'REQ-09', 'ส่งอีเมลยืนยันการจองให้ผู้เข้าพัก', ReqPriority.low, {
        DocType.er: na,
        DocType.flowchart: links([const TraceLink('fc_booking', 'confirm')]),
        DocType.wireframe: na,
        DocType.screenflow: na,
      }),
      req('r10', 'REQ-10', 'รองรับสองภาษา (ไทย/อังกฤษ)', ReqPriority.low, {
        DocType.er: na,
        DocType.dfd: na,
        DocType.flowchart: na,
      }),
    ];

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('ใช้: dart run tool/gen_hotel_sample.dart <ไฟล์ปลายทาง.nsln>');
    exit(2);
  }
  final w = Workspace(name: 'ระบบจองห้องพัก Siam Residence');
  w.meta.description = 'เว็บจองห้องพักโรงแรม — ตัวอย่างโปรเจกต์ที่ใช้ครบทุกชนิดเอกสารของ NSL Nebular';
  w.meta.createdAt = DateTime.now().toUtc().toIso8601String();

  w.folders.addAll([
    DocFolder(id: 'f_data', name: 'ข้อมูล'),
    DocFolder(id: 'f_process', name: 'กระบวนการ'),
    DocFolder(id: 'f_ui', name: 'หน้าจอ'),
    DocFolder(id: 'f_api', name: 'API'),
  ]);

  ReviewNote note(String id, NoteKind k, String text, {bool done = false, double? x, double? y, String? anchor}) =>
      ReviewNote(id: id, kind: k, text: text, done: done, x: x, y: y, anchorId: anchor, created: DateTime.utc(2026, 11, 19));

  ProjectDocument withNotes(ProjectDocument d, List<ReviewNote> n) => d..reviewNotes = n;

  w.documents.addAll([
    withNotes(ProjectDocument.er(id: kErDocId, name: 'ER — ระบบจองห้องพัก', content: buildEr(), folderId: 'f_data'), [
      note('n1', NoteKind.todo, 'เพิ่มตารางคูปอง/โปรโมชัน (รอข้อสรุปจากฝ่ายการตลาด)', x: 1180, y: 330),
      note('n2', NoteKind.question, 'ต้องเก็บเลขบัตรประชาชน/พาสปอร์ตของผู้เข้าพักต่างชาติหรือไม่? (PDPA)', anchor: 'users', x: 90, y: 60),
      note('n3', NoteKind.memo, 'ราคารวม = base_price × multiplier ของ seasonal_prices ที่ช่วงวันครอบคลุมแต่ละคืน', anchor: 'seasonal_prices'),
      note('n4', NoteKind.todo, 'ตั้งชื่อ index ให้ตรงมาตรฐานทีม', done: true),
    ]),
    ProjectDocument.dfd(id: 'dfd_ctx', name: 'DFD ระดับ 0 — ภาพรวมระบบ', content: buildDfdContext(), folderId: 'f_process'),
    withNotes(ProjectDocument.dfd(id: kDfdLevel1Id, name: 'DFD ระดับ 1 — จองห้องพัก', content: buildDfdLevel1(), folderId: 'f_process'), [
      note('n5', NoteKind.question, 'ควรแยกกระบวนการ "ยกเลิกการจอง" ออกจาก 2.0 หรือไม่?', anchor: 'p2'),
    ]),
    ProjectDocument.flowchart(id: 'fc_booking', name: 'Flowchart — ขั้นตอนการจอง', content: buildFlowchart(), folderId: 'f_process'),
    withNotes(ProjectDocument.wireframe(id: 'wf_home', name: 'Home — หน้าแรก', content: buildHome(), folderId: 'f_ui'), [
      note('n6', NoteKind.todo, 'ใส่รูปจริงของโรงแรมแทนภาพตัวอย่าง', anchor: 'h_hero', x: 1300, y: 100),
      note('n7', NoteKind.memo, 'ปุ่มค้นหาเรียก GET /rooms/available ด้วยวันที่และจำนวนผู้เข้าพัก', anchor: 'h_btn_search'),
    ]),
    ProjectDocument.wireframe(id: 'wf_rooms', name: 'Rooms — รายการห้อง', content: buildRooms(), folderId: 'f_ui'),
    ProjectDocument.wireframe(id: 'wf_detail', name: 'Room Detail — รายละเอียดห้อง', content: buildDetail(), folderId: 'f_ui'),
    withNotes(ProjectDocument.wireframe(id: 'wf_checkout', name: 'Checkout — จองและชำระเงิน', content: buildCheckout(), folderId: 'f_ui'), [
      note('n8', NoteKind.question, 'ต้องมี 3D Secure สำหรับบัตรหรือให้เกตเวย์จัดการ?', anchor: 'c_btn_pay'),
    ]),
    ProjectDocument.wireframe(id: 'wf_mybookings', name: 'My Bookings — การจองของฉัน', content: buildMyBookings(), folderId: 'f_ui'),
    ProjectDocument.wireframe(id: 'wf_admin', name: 'Admin Dashboard — แดชบอร์ด', content: buildAdmin(), folderId: 'f_ui'),
    ProjectDocument.wireframe(id: 'wf_adminroom', name: 'Admin Room — เพิ่มห้อง', content: buildAdminRoom(), folderId: 'f_ui'),
    ProjectDocument.screenflow(id: 'sf_main', name: 'Screen Flow — เว็บจองห้องพัก', content: buildScreenFlow(), folderId: 'f_ui'),
    withNotes(ProjectDocument.api(id: kApiDocId, name: 'API — ระบบจองห้องพัก', content: buildApi(), folderId: 'f_api'), [
      note('n9', NoteKind.question, 'ใช้ JWT หรือ session cookie? (โมบายล์แอปในอนาคตควรใช้ JWT)'),
      note('n10', NoteKind.todo, 'เพิ่ม query สำหรับ /rooms/available (check_in, check_out, guests) เป็นพารามิเตอร์ตามสัญญา'),
    ]),
  ]);

  w.requirements.addAll(buildRequirements());

  // ชุดตั้งค่า: การสร้างโค้ดและ Mock Server (เก็บในไฟล์โปรเจกต์)
  w.meta.extra['codegen'] = {
    'targets': ['sqlDdl', 'seedSql', 'laravelMigration', 'prisma', 'typescript', 'dart', 'openApi', 'laravelRoutes', 'flutterScreen', 'htmlTailwind'],
    'folder': 'generated/hotel',
  };
  w.meta.extra['mock'] = const MockSettings(apiDocId: kApiDocId, port: 8787)
      .withEndpoint('e_pay_create', const MockEndpointSetting(delayMs: 600))
      .withEndpoint('e_dashboard', const MockEndpointSetting(delayMs: 300))
      .toJson();

  await File(args.first).parent.create(recursive: true);
  await File(args.first).writeAsString(ProjectFile.encode(w));
  stdout.writeln('เขียนแล้ว: ${args.first} (เอกสาร ${w.documents.length} ชิ้น · ความต้องการ ${w.requirements.length} ข้อ)');
}
