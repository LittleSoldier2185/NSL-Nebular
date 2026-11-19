// สร้างโปรเจกต์ตัวอย่างขนาดเล็ก "ห้องสมุดเล็ก" (samples/mini_library.nsln) — ใช้ทุกฟีเจอร์ แต่เนื้อหาน้อย อ่านจบเร็ว
// เหมาะกับการลองใช้แอปด้วยมือทีละฟีเจอร์ (ดูเช็คลิสต์ใน samples/README.md) ; ตัวอย่างเต็มรูปแบบดู gen_hotel_sample.dart
//
// รัน: dart run tool/gen_mini_sample.dart samples/mini_library.nsln
import 'dart:io';

import 'package:nsl_nebular/core/layout/dfd_layout.dart';
import 'package:nsl_nebular/core/layout/flowchart_layout.dart';
import 'package:nsl_nebular/core/layout/screenflow_geometry.dart';
import 'package:nsl_nebular/core/mock/mock_settings.dart';
import 'package:nsl_nebular/core/models/api_model.dart';
import 'package:nsl_nebular/core/models/api_ref.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/dfd_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/flowchart_model.dart';
import 'package:nsl_nebular/core/models/group_model.dart';
import 'package:nsl_nebular/core/models/index_model.dart';
import 'package:nsl_nebular/core/models/note_model.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/relation_model.dart';
import 'package:nsl_nebular/core/models/requirement.dart';
import 'package:nsl_nebular/core/models/review_note.dart';
import 'package:nsl_nebular/core/models/screenflow_model.dart';
import 'package:nsl_nebular/core/models/table_model.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';
import 'package:nsl_nebular/core/models/workspace.dart';
import 'package:nsl_nebular/core/storage/project_file.dart';

const kEr = 'er_lib';
const kApi = 'api_lib';
const kDfd1 = 'dfd_l1';

String c(String table, String col) => '${table}_$col';

// ---------------------------------------------------------------- ER (PostgreSQL, 4 ตาราง)

ColumnModel _col(String t, String name, DataType type,
        {int? len, bool pk = false, bool nn = false, bool uq = false, bool ai = false, String? def, String comment = ''}) =>
    ColumnModel(
      id: c(t, name),
      name: name,
      type: type,
      length: len,
      isPrimaryKey: pk,
      notNull: nn || pk,
      unique: uq,
      autoIncrement: ai,
      defaultValue: def,
      comment: comment,
    );

Map<String, String?> _row(String t, Map<String, String?> v) => {for (final e in v.entries) c(t, e.key): e.value};

Project buildEr() {
  final p = Project(name: 'Mini Library', dialect: Dialect.postgres, boardWidth: 1600, boardHeight: 1000);

  final categories = TableModel(id: 'categories', name: 'categories', comment: 'หมวดหนังสือ (มีหมวดย่อยได้)', x: 80, y: 80, width: 240, colorIndex: 2, columns: [
    _col('categories', 'id', DataType.integer, pk: true, ai: true),
    _col('categories', 'name', DataType.varchar, len: 80, nn: true, uq: true),
    _col('categories', 'parent_id', DataType.integer, comment: 'หมวดแม่ (ว่าง = หมวดบนสุด)'),
  ], seedRows: [
    _row('categories', {'id': '1', 'name': 'นิยาย', 'parent_id': null}),
    _row('categories', {'id': '2', 'name': 'วิทยาศาสตร์', 'parent_id': null}),
    _row('categories', {'id': '3', 'name': 'คอมพิวเตอร์', 'parent_id': '2'}),
  ]);

  final books = TableModel(id: 'books', name: 'books', comment: 'หนังสือในห้องสมุด', x: 420, y: 80, width: 250, colorIndex: 2, columns: [
    _col('books', 'id', DataType.integer, pk: true, ai: true),
    _col('books', 'isbn', DataType.varchar, len: 13, nn: true, uq: true),
    _col('books', 'title', DataType.varchar, len: 200, nn: true, comment: 'ชื่อเรื่อง'),
    _col('books', 'category_id', DataType.integer, nn: true),
    _col('books', 'copies', DataType.smallint, nn: true, def: '1', comment: 'จำนวนเล่มทั้งหมด'),
    _col('books', 'created_at', DataType.timestamp, nn: true, def: 'CURRENT_TIMESTAMP'),
  ], seedRows: [
    _row('books', {'id': '1', 'isbn': '9786160000011', 'title': 'สี่แผ่นดิน', 'category_id': '1', 'copies': '2'}),
    _row('books', {'id': '2', 'isbn': '9786160000028', 'title': 'จักรวาลในเปลือกนัท', 'category_id': '2', 'copies': '1'}),
    _row('books', {'id': '3', 'isbn': '9786160000035', 'title': 'เขียนโปรแกรมด้วย Dart', 'category_id': '3', 'copies': '3'}),
  ]);

  final members = TableModel(id: 'members', name: 'members', comment: 'สมาชิกห้องสมุด', x: 80, y: 420, width: 240, colorIndex: 1, columns: [
    _col('members', 'id', DataType.integer, pk: true, ai: true),
    _col('members', 'full_name', DataType.varchar, len: 120, nn: true),
    _col('members', 'email', DataType.varchar, len: 190, nn: true, uq: true),
    _col('members', 'joined_at', DataType.date, nn: true, def: 'CURRENT_DATE'),
  ], seedRows: [
    _row('members', {'id': '1', 'full_name': 'สมชาย ใจดี', 'email': 'somchai@example.com', 'joined_at': '2026-01-10'}),
    _row('members', {'id': '2', 'full_name': 'สมหญิง รักอ่าน', 'email': 'somying@example.com', 'joined_at': '2026-03-02'}),
  ]);

  final loans = TableModel(id: 'loans', name: 'loans', comment: 'การยืม-คืน (สมาชิก ↔ หนังสือ)', x: 420, y: 420, width: 250, colorIndex: 3, columns: [
    _col('loans', 'id', DataType.integer, pk: true, ai: true),
    _col('loans', 'member_id', DataType.integer, nn: true),
    _col('loans', 'book_id', DataType.integer, nn: true),
    _col('loans', 'borrowed_at', DataType.date, nn: true, def: 'CURRENT_DATE'),
    _col('loans', 'due_at', DataType.date, nn: true, comment: 'กำหนดคืน (ยืม + 14 วัน)'),
    _col('loans', 'returned_at', DataType.date, comment: 'ว่าง = ยังไม่คืน'),
  ]);

  p.tables.addAll([categories, books, members, loans]);

  void idx(TableModel t, List<String> cols) =>
      t.indexes.add(IndexModel(id: 'idx_${t.id}_${cols.join('_')}', name: 'idx_${t.id}_${cols.join('_')}', columnIds: [for (final k in cols) c(t.id, k)]));
  idx(categories, ['parent_id']);
  idx(books, ['category_id']);
  idx(loans, ['member_id']);
  idx(loans, ['book_id', 'returned_at']);

  int n = 0;
  void fk(String from, String col, String to, {RefAction del = RefAction.restrict}) => p.relations.add(RelationModel(
        id: 'fk_${++n}',
        fromTableId: from,
        fromColumnId: c(from, col),
        toTableId: to,
        toColumnId: c(to, 'id'),
        onDelete: del,
      ));
  fk('categories', 'parent_id', 'categories', del: RefAction.setNull); // อ้างตัวเอง
  fk('books', 'category_id', 'categories');
  fk('loans', 'member_id', 'members', del: RefAction.cascade);
  fk('loans', 'book_id', 'books');

  p.groups.add(GroupModel(id: 'g_catalog', name: 'แค็ตตาล็อก', x: 50, y: 40, width: 660, height: 320, colorIndex: 2));
  p.notes.add(NoteModel(id: 'note_due', text: 'ยืมได้คนละไม่เกิน 3 เล่ม · ค้างคืน = due_at < วันนี้ และ returned_at ว่าง', x: 760, y: 440, width: 240));
  return p;
}

// ---------------------------------------------------------------- DFD ระดับ 0 และ 1

void _layoutDfd(DfdDiagram d) {
  final plan = dfdLayoutPlan(d);
  for (final node in d.nodes) {
    final p = plan.positions[node.id];
    if (p != null) {
      node.x = p.x + 60;
      node.y = p.y + 60;
      node.h = plan.heights[node.id] ?? node.h;
    }
  }
}

DfdDiagram buildDfd0() {
  final d = DfdDiagram(nodes: [
    DfdNode(id: 'e_member', kind: DfdKind.entity, name: 'สมาชิก'),
    DfdNode(id: 'e_staff', kind: DfdKind.entity, name: 'บรรณารักษ์'),
    DfdNode(id: 'p0', kind: DfdKind.process, name: 'ระบบห้องสมุด', number: '0', w: 200, h: 90, childId: kDfd1),
  ], flows: [
    DfdFlow(id: 'f1', fromId: 'e_member', toId: 'p0', label: 'คำขอยืม'),
    DfdFlow(id: 'f2', fromId: 'p0', toId: 'e_member', label: 'ผลการยืม'),
    DfdFlow(id: 'f3', fromId: 'e_staff', toId: 'p0', label: 'ข้อมูลหนังสือ'),
    DfdFlow(id: 'f4', fromId: 'p0', toId: 'e_staff', label: 'รายงานค้างคืน'),
  ]);
  _layoutDfd(d);
  return d;
}

DfdDiagram buildDfd1() {
  DfdNode store(String id, String no, String name, String table) =>
      DfdNode(id: id, kind: DfdKind.store, name: name, number: no, tableId: table, tableDocId: kEr);
  final d = DfdDiagram(nodes: [
    DfdNode(id: 'e_member', kind: DfdKind.entity, name: 'สมาชิก'),
    DfdNode(id: 'e_staff', kind: DfdKind.entity, name: 'บรรณารักษ์'),
    DfdNode(id: 'p1', kind: DfdKind.process, name: 'ยืมหนังสือ', number: '1.0')..api = const ApiRef(docId: kApi, endpointId: 'e_loan_create'),
    DfdNode(id: 'p2', kind: DfdKind.process, name: 'คืนและติดตามค้างคืน', number: '2.0')..api = const ApiRef(docId: kApi, endpointId: 'e_overdue'),
    DfdNode(id: 'p3', kind: DfdKind.process, name: 'จัดการหนังสือ', number: '3.0')..api = const ApiRef(docId: kApi, endpointId: 'e_book_create'),
    store('d1', 'D1', 'สมาชิก', 'members'),
    store('d2', 'D2', 'หนังสือ', 'books'),
    store('d3', 'D3', 'การยืม', 'loans'),
  ], flows: [
    DfdFlow(id: 'f1', fromId: 'e_member', toId: 'p1', label: 'คำขอยืม'),
    DfdFlow(id: 'f2', fromId: 'p1', toId: 'e_member', label: 'ผลการยืม'),
    DfdFlow(id: 'f3', fromId: 'd1', toId: 'p1', label: 'ข้อมูลสมาชิก'),
    DfdFlow(id: 'f4', fromId: 'd2', toId: 'p1', label: 'สถานะหนังสือ'),
    DfdFlow(id: 'f5', fromId: 'p1', toId: 'd3', label: 'การยืมใหม่'),
    DfdFlow(id: 'f6', fromId: 'd3', toId: 'p2', label: 'การยืมที่ค้าง'),
    DfdFlow(id: 'f7', fromId: 'p2', toId: 'd3', label: 'วันที่คืน'),
    DfdFlow(id: 'f8', fromId: 'p2', toId: 'e_staff', label: 'รายงานค้างคืน'),
    DfdFlow(id: 'f9', fromId: 'e_staff', toId: 'p3', label: 'ข้อมูลหนังสือ'),
    DfdFlow(id: 'f10', fromId: 'p3', toId: 'd2', label: 'หนังสือใหม่'),
  ]);
  _layoutDfd(d);
  return d;
}

// ---------------------------------------------------------------- Flowchart

FlowchartDiagram buildFlowchart() {
  FcNode n(String id, FcShape s, String text, {String? api}) =>
      FcNode(id: id, shape: s, text: text)..api = api == null ? null : ApiRef(docId: kApi, endpointId: api);
  final d = FlowchartDiagram(nodes: [
    n('start', FcShape.start, 'เริ่ม'),
    n('input', FcShape.io, 'สแกนบัตรสมาชิก\nและ ISBN'),
    n('check', FcShape.process, 'ตรวจข้อมูลสมาชิก', api: 'e_member_get'),
    n('overdue', FcShape.decision, 'มีเล่มค้างคืน?'),
    n('warn', FcShape.io, 'แจ้งให้คืนก่อน'),
    n('avail', FcShape.decision, 'หนังสือว่าง?'),
    n('save', FcShape.subroutine, 'บันทึกการยืม', api: 'e_loan_create'),
    n('due', FcShape.process, 'กำหนดคืน +14 วัน'),
    n('end_ok', FcShape.end, 'จบ: ยืมสำเร็จ'),
    n('end_fail', FcShape.end, 'จบ: ยืมไม่ได้'),
    n('note', FcShape.note, 'ยืมได้คนละไม่เกิน 3 เล่ม'),
  ], edges: [
    FcEdge(id: 'e1', fromId: 'start', toId: 'input'),
    FcEdge(id: 'e2', fromId: 'input', toId: 'check'),
    FcEdge(id: 'e3', fromId: 'check', toId: 'overdue'),
    FcEdge(id: 'e4', fromId: 'overdue', toId: 'warn', label: 'มี'),
    FcEdge(id: 'e5', fromId: 'warn', toId: 'end_fail'),
    FcEdge(id: 'e6', fromId: 'overdue', toId: 'avail', label: 'ไม่มี'),
    FcEdge(id: 'e7', fromId: 'avail', toId: 'save', label: 'ว่าง'),
    FcEdge(id: 'e8', fromId: 'avail', toId: 'end_fail', label: 'ไม่ว่าง'),
    FcEdge(id: 'e9', fromId: 'save', toId: 'due'),
    FcEdge(id: 'e10', fromId: 'due', toId: 'end_ok'),
  ]);
  final pos = fcAutoLayout(d);
  for (final node in d.nodes) {
    final p = pos[node.id];
    if (p != null) {
      node.x = p.x + 60;
      node.y = p.y + 60;
    }
  }
  final check = d.nodeById('check')!;
  d.nodeById('note')!
    ..x = check.x + check.w + 80
    ..y = check.y;
  return d;
}

// ---------------------------------------------------------------- Wireframe 2 หน้า (เดสก์ท็อป + มือถือ)

WfComponent _wf(String id, WfKind k, double x, double y, double w, double h,
    {String text = '', String? table, String? col, String? api, bool secondary = false, String? group, List<String>? columns}) {
  final comp = WfComponent(
    id: id,
    kind: k,
    text: text,
    x: x,
    y: y,
    w: w,
    h: h,
    secondary: secondary,
    align: k == WfKind.button || k == WfKind.badge || k == WfKind.chip ? WfAlign.center : WfAlign.left,
    columns: columns,
    group: group,
    ref: table == null ? null : WfDataRef(docId: kEr, tableId: table, columnId: col == null ? null : c(table, col)),
  );
  if (api != null) comp.api = ApiRef(docId: kApi, endpointId: api);
  return comp;
}

WireframeDiagram buildBooksPage() => WireframeDiagram(device: WfDevice.desktop, width: 1440, height: 900, style: WfStyle.clean, components: [
      _wf('b_nav', WfKind.navbar, 0, 0, 1440, 64, text: 'ห้องสมุดเล็ก'),
      _wf('b_link1', WfKind.link, 300, 20, 90, 24, text: 'หนังสือ', group: 'g_menu'),
      _wf('b_link2', WfKind.link, 400, 20, 110, 24, text: 'การยืมของฉัน', group: 'g_menu'),
      _wf('b_avatar', WfKind.avatar, 1376, 8, 48, 48),
      _wf('b_title', WfKind.heading, 80, 100, 600, 48, text: 'ค้นหาหนังสือ'),
      _wf('b_search', WfKind.search, 80, 170, 520, 44, text: 'ชื่อเรื่องหรือ ISBN', table: 'books', col: 'title', api: 'e_books_list'),
      _wf('b_cat', WfKind.select, 620, 170, 220, 44, text: 'ทุกหมวด', table: 'categories', col: 'name'),
      _wf('b_chip1', WfKind.chip, 80, 230, 90, 30, text: 'นิยาย'),
      _wf('b_chip2', WfKind.chip, 180, 230, 120, 30, text: 'วิทยาศาสตร์'),
      _wf('b_table', WfKind.table, 80, 280, 1000, 360, table: 'books', columns: ['ISBN', 'ชื่อเรื่อง', 'หมวด', 'จำนวน']),
      _wf('b_page', WfKind.pagination, 80, 660, 320, 40),
      _wf('b_btn_borrow', WfKind.button, 940, 660, 140, 44, text: 'ยืมเล่มนี้', api: 'e_loan_create'),
      _wf('b_new', WfKind.badge, 1120, 100, 120, 36, text: 'มาใหม่ 3 เล่ม')..rotation = -6,
      _wf('b_side', WfKind.card, 1120, 280, 260, 200, text: 'สถิติ'),
      _wf('b_stat', WfKind.stat, 1140, 320, 220, 80, text: 'ยืมวันนี้ 12'),
      _wf('b_loading', WfKind.skeleton, 1140, 410, 220, 50)..hidden = true,
      _wf('b_footer', WfKind.footer, 0, 820, 1440, 80, text: '© 2026 ห้องสมุดเล็ก'),
    ]);

WireframeDiagram buildLoanPage() => WireframeDiagram(device: WfDevice.mobile, width: 390, height: 844, style: WfStyle.sketch, components: [
      _wf('l_title', WfKind.heading, 20, 40, 350, 40, text: 'ยืมหนังสือ'),
      _wf('l_lbl_email', WfKind.label, 20, 100, 200, 22, text: 'อีเมลสมาชิก'),
      _wf('l_email', WfKind.input, 20, 126, 350, 44, text: 'name@example.com', table: 'members', col: 'email'),
      _wf('l_lbl_book', WfKind.label, 20, 186, 200, 22, text: 'หนังสือ'),
      _wf('l_book', WfKind.select, 20, 212, 350, 44, text: 'เลือกหนังสือ', table: 'books', col: 'title'),
      _wf('l_lbl_due', WfKind.label, 20, 272, 200, 22, text: 'กำหนดคืน'),
      _wf('l_due', WfKind.datepicker, 20, 298, 350, 44, text: '14 วันจากวันนี้', table: 'loans', col: 'due_at'),
      _wf('l_agree', WfKind.checkbox, 20, 360, 350, 28, text: 'ยอมรับระเบียบการยืม'),
      _wf('l_alert', WfKind.alert, 20, 404, 350, 56, text: 'ยืมได้คนละไม่เกิน 3 เล่ม'),
      _wf('l_btn', WfKind.button, 20, 480, 350, 48, text: 'ยืนยันการยืม', api: 'e_loan_create'),
      _wf('l_back', WfKind.button, 20, 540, 350, 44, text: 'กลับ', secondary: true),
      _wf('l_done', WfKind.modal, 30, 600, 330, 200, text: 'ยืมสำเร็จ!')..hidden = true,
    ]);

// ---------------------------------------------------------------- Screen Flow

ScreenFlowDiagram buildScreenFlow() {
  final d = ScreenFlowDiagram(nodes: [
    SfNode(id: 'sf_start', kind: SfKind.start, title: 'เปิดเว็บ'),
    SfNode(id: 'sf_books', kind: SfKind.screen, title: 'ค้นหาหนังสือ', wireframeId: 'wf_books'),
    SfNode(id: 'sf_loan', kind: SfKind.screen, title: 'ยืมหนังสือ', wireframeId: 'wf_loan'),
    SfNode(id: 'sf_mail', kind: SfKind.external, title: 'อีเมลยืนยันการยืม'),
    SfNode(id: 'sf_end', kind: SfKind.end, title: 'ออก'),
  ], edges: [
    SfEdge(id: 's1', fromId: 'sf_start', toId: 'sf_books'),
    SfEdge(id: 's2', fromId: 'sf_books', toId: 'sf_loan', label: 'ยืมเล่มนี้', condition: 'หนังสือว่าง'),
    SfEdge(id: 's3', fromId: 'sf_loan', toId: 'sf_mail', label: 'ยืนยันการยืม')..api = const ApiRef(docId: kApi, endpointId: 'e_loan_create'),
    SfEdge(id: 's4', fromId: 'sf_loan', toId: 'sf_books', label: 'กลับ'),
    SfEdge(id: 's5', fromId: 'sf_books', toId: 'sf_end', label: 'ออก'),
  ]);
  final pos = sfAutoLayout(d);
  for (final node in d.nodes) {
    final p = pos[node.id];
    if (p != null) {
      node.x = p.x + 60;
      node.y = p.y + 60;
    }
  }
  return d;
}

// ---------------------------------------------------------------- API (6 endpoint)

ApiTableRef _t(String table, [String? col]) => ApiTableRef(docId: kEr, tableId: table, columnId: col == null ? null : c(table, col));

ApiDocument buildApi() {
  int n = 0;
  ApiField f(String name, ApiType type, {bool req = false, ApiTableRef? col, String desc = ''}) =>
      ApiField(id: 'f${++n}', name: name, type: type, required: req, column: col, description: desc);
  return ApiDocument(title: 'Mini Library API', version: '1.0.0', baseUrl: 'https://api.mini-library.example/v1', endpoints: [
    ApiEndpoint(id: 'e_books_list', method: ApiMethod.get, path: '/books', summary: 'ค้นหาหนังสือ', group: 'books', table: _t('books'), responses: [
      ApiResponse(status: 200, example: '[{"id":1,"isbn":"9786160000011","title":"สี่แผ่นดิน","copies":2}]'),
    ]),
    ApiEndpoint(id: 'e_book_create', method: ApiMethod.post, path: '/books', summary: 'เพิ่มหนังสือ', group: 'books', auth: true, table: _t('books'), fields: [
      f('isbn', ApiType.string, req: true, col: _t('books', 'isbn')),
      f('title', ApiType.string, req: true, col: _t('books', 'title')),
      f('category_id', ApiType.integer, req: true, col: _t('books', 'category_id')),
      f('copies', ApiType.integer, col: _t('books', 'copies')),
    ], responses: [
      ApiResponse(status: 201),
      ApiResponse(status: 409, description: 'ISBN ซ้ำ', example: '{"error":"isbn_taken"}'),
    ]),
    ApiEndpoint(id: 'e_member_get', method: ApiMethod.get, path: '/members/{id}', summary: 'ข้อมูลสมาชิก', group: 'members', auth: true, table: _t('members'), responses: [
      ApiResponse(status: 200, example: '{"id":1,"full_name":"สมชาย ใจดี","email":"somchai@example.com"}'),
      ApiResponse(status: 404, example: '{"error":"not_found"}'),
    ]),
    ApiEndpoint(id: 'e_loan_create', method: ApiMethod.post, path: '/loans', summary: 'ยืมหนังสือ', group: 'loans', auth: true, table: _t('loans'), fields: [
      f('member_id', ApiType.integer, req: true, col: _t('loans', 'member_id')),
      f('book_id', ApiType.integer, req: true, col: _t('loans', 'book_id')),
      f('due_at', ApiType.string, req: true, col: _t('loans', 'due_at'), desc: 'YYYY-MM-DD'),
    ], responses: [
      ApiResponse(status: 201, description: 'ยืมสำเร็จ'),
      ApiResponse(status: 409, description: 'หนังสือไม่ว่าง หรือยืมครบ 3 เล่มแล้ว', example: '{"error":"not_available"}'),
    ]),
    ApiEndpoint(id: 'e_loan_return', method: ApiMethod.patch, path: '/loans/{id}', summary: 'คืนหนังสือ', group: 'loans', auth: true, table: _t('loans'), fields: [
      f('returned_at', ApiType.string, col: _t('loans', 'returned_at')),
    ], responses: [ApiResponse(status: 200)]),
    ApiEndpoint(id: 'e_overdue', method: ApiMethod.get, path: '/loans/overdue', summary: 'รายการค้างคืน', group: 'loans', auth: true, table: _t('loans'), responses: [
      ApiResponse(status: 200, example: '[{"loan_id":7,"member":"สมหญิง รักอ่าน","title":"จักรวาลในเปลือกนัท","days_late":3}]'),
    ]),
  ]);
}

// ---------------------------------------------------------------- ความต้องการ (2 ข้อครบ, 2 ข้อเว้นช่องไว้ทดสอบ)

TraceCell _links(List<TraceLink> l) => TraceCell(links: l);

List<Requirement> buildRequirements() => [
      Requirement(id: 'r1', code: 'REQ-01', text: 'สมาชิกค้นหาหนังสือตามชื่อเรื่อง/ISBN/หมวดได้', priority: ReqPriority.high, cells: {
        DocType.er: _links([const TraceLink(kEr, 'books')]),
        DocType.dfd: _links([const TraceLink(kDfd1, 'd2')]),
        DocType.flowchart: TraceCell(notNeeded: true),
        DocType.wireframe: _links([const TraceLink('wf_books', 'b_search')]),
        DocType.screenflow: _links([const TraceLink('sf_main', 'sf_books')]),
        DocType.api: _links([const TraceLink(kApi, 'e_books_list')]),
      }),
      Requirement(id: 'r2', code: 'REQ-02', text: 'ยืมหนังสือได้คนละไม่เกิน 3 เล่ม กำหนดคืน 14 วัน', priority: ReqPriority.high, cells: {
        DocType.er: _links([const TraceLink(kEr, 'loans')]),
        DocType.dfd: _links([const TraceLink(kDfd1, 'p1')]),
        DocType.flowchart: _links([const TraceLink('fc_borrow', 'save')]),
        DocType.wireframe: _links([const TraceLink('wf_loan', 'l_btn')]),
        DocType.screenflow: _links([const TraceLink('sf_main', 'sf_loan')]),
        DocType.api: _links([const TraceLink(kApi, 'e_loan_create')]),
      }),
      // ตั้งใจเว้นช่อง Wireframe/Screen Flow — ทดสอบเมทริกซ์ช่องว่างและ "สร้างเอกสารจากช่องว่าง"
      Requirement(id: 'r3', code: 'REQ-03', text: 'บรรณารักษ์บันทึกการคืนและดูรายการค้างคืน', priority: ReqPriority.medium, cells: {
        DocType.er: _links([const TraceLink(kEr, 'loans')]),
        DocType.dfd: _links([const TraceLink(kDfd1, 'p2')]),
        DocType.flowchart: TraceCell(notNeeded: true),
        DocType.api: _links([const TraceLink(kApi, 'e_loan_return'), const TraceLink(kApi, 'e_overdue')]),
      }),
      Requirement(id: 'r4', code: 'REQ-04', text: 'ส่งอีเมลเตือนก่อนถึงกำหนดคืน 1 วัน', priority: ReqPriority.low),
    ];

// ---------------------------------------------------------------- รวมเป็นโปรเจกต์

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('ใช้: dart run tool/gen_mini_sample.dart <ไฟล์ปลายทาง.nsln>');
    exit(2);
  }
  final w = Workspace(name: 'ห้องสมุดเล็ก');
  w.meta.description = 'โปรเจกต์ตัวอย่างขนาดเล็กที่ใช้ทุกฟีเจอร์ของ NSL Nebular — ระบบยืม-คืนหนังสือ';
  w.meta.createdAt = DateTime.utc(2026, 11, 19).toIso8601String();
  w.folders.addAll([DocFolder(id: 'f_design', name: 'ออกแบบระบบ'), DocFolder(id: 'f_ui', name: 'หน้าจอ')]);

  ReviewNote note(String id, NoteKind k, String text, {bool done = false, double? x, double? y, String? anchor}) =>
      ReviewNote(id: id, kind: k, text: text, done: done, x: x, y: y, anchorId: anchor, created: DateTime.utc(2026, 11, 19));

  w.documents.addAll([
    ProjectDocument.er(id: kEr, name: 'ER — ห้องสมุด', content: buildEr(), folderId: 'f_design')
      ..reviewNotes = [
        note('n1', NoteKind.todo, 'เพิ่มตารางค่าปรับ (fines) เมื่อคืนช้า', x: 760, y: 100),
        note('n2', NoteKind.question, 'สมาชิกหนึ่งคนจองคิวหนังสือที่ถูกยืมอยู่ได้ไหม?', anchor: 'loans'),
        note('n3', NoteKind.memo, 'ตั้งชื่อดัชนีขึ้นต้น idx_ ทุกอัน', done: true),
      ],
    ProjectDocument.dfd(id: 'dfd_ctx', name: 'DFD ระดับ 0', content: buildDfd0(), folderId: 'f_design'),
    ProjectDocument.dfd(id: kDfd1, name: 'DFD ระดับ 1', content: buildDfd1(), folderId: 'f_design'),
    ProjectDocument.flowchart(id: 'fc_borrow', name: 'Flowchart — ยืมหนังสือ', content: buildFlowchart(), folderId: 'f_design'),
    ProjectDocument.wireframe(id: 'wf_books', name: 'Books — ค้นหาหนังสือ', content: buildBooksPage(), folderId: 'f_ui')
      ..reviewNotes = [note('n4', NoteKind.todo, 'ใส่ภาพปกหนังสือในตาราง', anchor: 'b_table')],
    ProjectDocument.wireframe(id: 'wf_loan', name: 'Loan — ยืมหนังสือ (มือถือ)', content: buildLoanPage(), folderId: 'f_ui'),
    ProjectDocument.screenflow(id: 'sf_main', name: 'Screen Flow — ยืมหนังสือ', content: buildScreenFlow(), folderId: 'f_ui'),
    ProjectDocument.api(id: kApi, name: 'API — ห้องสมุด', content: buildApi()),
  ]);
  w.requirements.addAll(buildRequirements());

  w.meta.extra['codegen'] = {
    'targets': ['sqlDdl', 'seedSql', 'prisma', 'typescript', 'openApi', 'htmlTailwind'],
    'folder': 'generated/mini',
  };
  w.meta.extra['mock'] = const MockSettings(apiDocId: kApi, port: 8788).withEndpoint('e_loan_create', const MockEndpointSetting(delayMs: 400)).toJson();

  await File(args.first).parent.create(recursive: true);
  await File(args.first).writeAsString(ProjectFile.encode(w));
  stdout.writeln('เขียนแล้ว: ${args.first} (เอกสาร ${w.documents.length} ชิ้น · ความต้องการ ${w.requirements.length} ข้อ)');
}
