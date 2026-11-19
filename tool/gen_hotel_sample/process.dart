import 'package:nsl_nebular/core/layout/dfd_layout.dart';
import 'package:nsl_nebular/core/layout/flowchart_layout.dart';
import 'package:nsl_nebular/core/models/api_ref.dart';
import 'package:nsl_nebular/core/models/dfd_model.dart';
import 'package:nsl_nebular/core/models/flowchart_model.dart';

const kErDocId = 'er_main';
const kApiDocId = 'api_main';
const kDfdLevel1Id = 'dfd_l1';

/// DFD ระดับ 0 (Context): ระบบเดียว + ผู้ใช้/ระบบภายนอก ; กระบวนการ 0 แตกรายละเอียดไปที่ระดับ 1
DfdDiagram buildDfdContext() {
  final d = DfdDiagram(nodes: [
    DfdNode(id: 'e_guest', kind: DfdKind.entity, name: 'ผู้เข้าพัก'),
    DfdNode(id: 'e_admin', kind: DfdKind.entity, name: 'แอดมินโรงแรม'),
    DfdNode(id: 'e_gw', kind: DfdKind.entity, name: 'ระบบชำระเงิน'),
    DfdNode(id: 'p0', kind: DfdKind.process, name: 'ระบบจองห้องพัก', number: '0', w: 220, h: 90, childId: kDfdLevel1Id),
  ], flows: [
    DfdFlow(id: 'f1', fromId: 'e_guest', toId: 'p0', label: 'คำค้นหาห้อง'),
    DfdFlow(id: 'f2', fromId: 'p0', toId: 'e_guest', label: 'รายการห้องว่าง'),
    DfdFlow(id: 'f3', fromId: 'e_guest', toId: 'p0', label: 'ข้อมูลการจอง'),
    DfdFlow(id: 'f4', fromId: 'p0', toId: 'e_guest', label: 'ใบยืนยันการจอง'),
    DfdFlow(id: 'f5', fromId: 'e_guest', toId: 'p0', label: 'รีวิว'),
    DfdFlow(id: 'f6', fromId: 'e_admin', toId: 'p0', label: 'ข้อมูลห้อง/ราคา'),
    DfdFlow(id: 'f7', fromId: 'p0', toId: 'e_admin', label: 'รายงานการจอง'),
    DfdFlow(id: 'f8', fromId: 'p0', toId: 'e_gw', label: 'คำขอชำระเงิน'),
    DfdFlow(id: 'f9', fromId: 'e_gw', toId: 'p0', label: 'ผลการชำระเงิน'),
  ]);
  _layout(d);
  return d;
}

/// DFD ระดับ 1: 5 กระบวนการ + ที่เก็บข้อมูล D1–D5 ผูกกับตาราง ER ; ลูกศรกับภายนอกตรงกับระดับ 0 (สมดุล)
DfdDiagram buildDfdLevel1() {
  DfdNode store(String id, String number, String name, String table) =>
      DfdNode(id: id, kind: DfdKind.store, name: name, number: number, tableId: table, tableDocId: kErDocId);

  final d = DfdDiagram(nodes: [
    DfdNode(id: 'e_guest', kind: DfdKind.entity, name: 'ผู้เข้าพัก'),
    DfdNode(id: 'e_admin', kind: DfdKind.entity, name: 'แอดมินโรงแรม'),
    DfdNode(id: 'e_gw', kind: DfdKind.entity, name: 'ระบบชำระเงิน'),
    DfdNode(id: 'p1', kind: DfdKind.process, name: 'ค้นหาห้องว่าง', number: '1.0')..api = const ApiRef(docId: kApiDocId, endpointId: 'e_rooms_available'),
    DfdNode(id: 'p2', kind: DfdKind.process, name: 'สร้างการจอง', number: '2.0')..api = const ApiRef(docId: kApiDocId, endpointId: 'e_booking_create'),
    DfdNode(id: 'p3', kind: DfdKind.process, name: 'ชำระเงิน', number: '3.0')..api = const ApiRef(docId: kApiDocId, endpointId: 'e_pay_create'),
    DfdNode(id: 'p4', kind: DfdKind.process, name: 'จัดการห้องและราคา', number: '4.0'),
    DfdNode(id: 'p5', kind: DfdKind.process, name: 'รีวิวและรายงาน', number: '5.0'),
    store('d1', 'D1', 'ผู้ใช้', 'users'),
    store('d2', 'D2', 'ห้องและประเภทห้อง', 'rooms'),
    store('d3', 'D3', 'การจอง', 'bookings'),
    store('d4', 'D4', 'การชำระเงิน', 'payments'),
    store('d5', 'D5', 'รีวิว', 'reviews'),
  ], flows: [
    DfdFlow(id: 'f1', fromId: 'e_guest', toId: 'p1', label: 'คำค้นหาห้อง'),
    DfdFlow(id: 'f2', fromId: 'p1', toId: 'e_guest', label: 'รายการห้องว่าง'),
    DfdFlow(id: 'f3', fromId: 'd2', toId: 'p1', label: 'ข้อมูลห้อง'),
    DfdFlow(id: 'f4', fromId: 'd3', toId: 'p1', label: 'การจองที่ทับซ้อน'),
    DfdFlow(id: 'f5', fromId: 'e_guest', toId: 'p2', label: 'ข้อมูลการจอง'),
    DfdFlow(id: 'f6', fromId: 'd1', toId: 'p2', label: 'ข้อมูลผู้ใช้'),
    DfdFlow(id: 'f7', fromId: 'd2', toId: 'p2', label: 'ราคาห้อง'),
    DfdFlow(id: 'f8', fromId: 'p2', toId: 'd3', label: 'การจองใหม่'),
    DfdFlow(id: 'f9', fromId: 'p2', toId: 'e_guest', label: 'ใบยืนยันการจอง'),
    DfdFlow(id: 'f10', fromId: 'p2', toId: 'p3', label: 'ยอดที่ต้องชำระ'),
    DfdFlow(id: 'f11', fromId: 'p3', toId: 'e_gw', label: 'คำขอชำระเงิน'),
    DfdFlow(id: 'f12', fromId: 'e_gw', toId: 'p3', label: 'ผลการชำระเงิน'),
    DfdFlow(id: 'f13', fromId: 'p3', toId: 'd4', label: 'บันทึกการชำระเงิน'),
    DfdFlow(id: 'f14', fromId: 'p3', toId: 'd3', label: 'สถานะการจอง'),
    DfdFlow(id: 'f15', fromId: 'e_admin', toId: 'p4', label: 'ข้อมูลห้อง/ราคา'),
    DfdFlow(id: 'f16', fromId: 'p4', toId: 'd2', label: 'ข้อมูลห้องที่แก้ไข'),
    DfdFlow(id: 'f17', fromId: 'e_guest', toId: 'p5', label: 'รีวิว'),
    DfdFlow(id: 'f18', fromId: 'p5', toId: 'd5', label: 'รีวิวใหม่'),
    DfdFlow(id: 'f19', fromId: 'd3', toId: 'p5', label: 'ข้อมูลการจอง'),
    DfdFlow(id: 'f20', fromId: 'd4', toId: 'p5', label: 'ข้อมูลรายได้'),
    DfdFlow(id: 'f21', fromId: 'p5', toId: 'e_admin', label: 'รายงานการจอง'),
  ]);
  _layout(d);
  return d;
}

void _layout(DfdDiagram d) {
  final plan = dfdLayoutPlan(d);
  for (final n in d.nodes) {
    final p = plan.positions[n.id];
    if (p != null) {
      n.x = p.x + 60;
      n.y = p.y + 60;
      n.h = plan.heights[n.id] ?? n.h;
    }
  }
}

/// Flowchart ขั้นตอนการจองห้อง: เริ่ม → ค้นหา → ตัดสินใจ (มีห้อง/ล็อกอิน/ชำระสำเร็จ) → ยืนยัน/ยกเลิก → จบ
FlowchartDiagram buildFlowchart() {
  FcNode n(String id, FcShape s, String text, {ApiRef? api}) => FcNode(id: id, shape: s, text: text)..api = api;
  final d = FlowchartDiagram(nodes: [
    n('start', FcShape.start, 'เริ่ม'),
    n('input', FcShape.io, 'เลือกวันเข้าพัก/ออก\nและจำนวนผู้เข้าพัก'),
    n('search', FcShape.process, 'ค้นหาห้องว่าง', api: const ApiRef(docId: kApiDocId, endpointId: 'e_rooms_available')),
    n('avail', FcShape.decision, 'มีห้องว่าง?'),
    n('none', FcShape.io, 'แจ้งว่าไม่มีห้องว่าง\nเสนอวันอื่น'),
    n('pick', FcShape.process, 'เลือกห้อง'),
    n('login', FcShape.decision, 'เข้าสู่ระบบแล้ว?'),
    n('auth', FcShape.subroutine, 'สมัครสมาชิก / เข้าสู่ระบบ', api: const ApiRef(docId: kApiDocId, endpointId: 'e_login')),
    n('guest', FcShape.io, 'กรอกข้อมูลผู้เข้าพัก'),
    n('create', FcShape.process, 'สร้างการจอง (pending)', api: const ApiRef(docId: kApiDocId, endpointId: 'e_booking_create')),
    n('pay', FcShape.subroutine, 'ชำระเงิน', api: const ApiRef(docId: kApiDocId, endpointId: 'e_pay_create')),
    n('paid', FcShape.decision, 'ชำระสำเร็จ?'),
    n('confirm', FcShape.process, 'ยืนยันการจอง\nส่งอีเมลยืนยัน'),
    n('cancel', FcShape.process, 'ยกเลิกการจอง\nคืนห้องว่าง'),
    n('end_ok', FcShape.end, 'จบ: จองสำเร็จ'),
    n('end_fail', FcShape.end, 'จบ: ไม่สำเร็จ'),
    n('note', FcShape.note, 'หมดเวลาชำระ 15 นาที = ยกเลิกอัตโนมัติ'),
  ], edges: [
    FcEdge(id: 'e1', fromId: 'start', toId: 'input'),
    FcEdge(id: 'e2', fromId: 'input', toId: 'search'),
    FcEdge(id: 'e3', fromId: 'search', toId: 'avail'),
    FcEdge(id: 'e4', fromId: 'avail', toId: 'pick', label: 'มี'),
    FcEdge(id: 'e5', fromId: 'avail', toId: 'none', label: 'ไม่มี'),
    FcEdge(id: 'e6', fromId: 'none', toId: 'end_fail'),
    FcEdge(id: 'e7', fromId: 'pick', toId: 'login'),
    FcEdge(id: 'e8', fromId: 'login', toId: 'guest', label: 'ใช่'),
    FcEdge(id: 'e9', fromId: 'login', toId: 'auth', label: 'ยัง'),
    FcEdge(id: 'e10', fromId: 'auth', toId: 'guest'),
    FcEdge(id: 'e11', fromId: 'guest', toId: 'create'),
    FcEdge(id: 'e12', fromId: 'create', toId: 'pay'),
    FcEdge(id: 'e13', fromId: 'pay', toId: 'paid'),
    FcEdge(id: 'e14', fromId: 'paid', toId: 'confirm', label: 'สำเร็จ'),
    FcEdge(id: 'e15', fromId: 'paid', toId: 'cancel', label: 'ไม่สำเร็จ'),
    FcEdge(id: 'e16', fromId: 'confirm', toId: 'end_ok'),
    FcEdge(id: 'e17', fromId: 'cancel', toId: 'end_fail'),
  ]);
  final pos = fcAutoLayout(d);
  for (final node in d.nodes) {
    final p = pos[node.id];
    if (p != null) {
      node.x = p.x + 60;
      node.y = p.y + 60;
    }
  }
  final paid = d.nodeById('paid')!;
  d.nodeById('note')!
    ..x = paid.x + paid.w + 80
    ..y = paid.y - 20;
  return d;
}
