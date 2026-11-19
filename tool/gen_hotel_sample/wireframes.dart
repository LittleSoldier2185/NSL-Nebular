import 'package:nsl_nebular/core/models/api_ref.dart';
import 'package:nsl_nebular/core/models/wireframe_model.dart';

import 'er.dart' show c;
import 'process.dart' show kApiDocId, kErDocId;

/// ตัวช่วยวางชิ้นส่วน: id ไม่ซ้ำในหน้าเดียว (prefix + เลขลำดับ) ; ref = ผูกตาราง/คอลัมน์ ER ; api = เรียก endpoint
class _Page {
  _Page(this.prefix, {this.height = 900});
  final String prefix;
  final double width = 1440;
  double height;
  final WfStyle style = WfStyle.clean;
  final comps = <WfComponent>[];
  int _n = 0;

  WfComponent add(
    WfKind k,
    double x,
    double y, {
    double? w,
    double? h,
    String text = '',
    String? table,
    String? col,
    String? api,
    bool checked = false,
    bool secondary = false,
    bool bold = false,
    WfAlign? align,
    int? fill,
    int? textColor,
    double? fontSize,
    List<String>? columns,
    int? rows,
    String? group,
    String? name,
  }) {
    final comp = WfComponent(
      id: name ?? '${prefix}_${++_n}',
      kind: k,
      text: text,
      x: x,
      y: y,
      w: w,
      h: h,
      checked: checked,
      secondary: secondary,
      bold: bold,
      align: align ?? ((k == WfKind.button || k == WfKind.badge || k == WfKind.chip || k == WfKind.tooltip || k == WfKind.footer) ? WfAlign.center : WfAlign.left),
      fill: fill,
      textColor: textColor,
      fontSize: fontSize,
      columns: columns,
      rows: rows ?? 3,
      group: group,
      ref: table == null ? null : WfDataRef(docId: kErDocId, tableId: table, columnId: col == null ? null : c(table, col)),
    );
    if (api != null) comp.api = ApiRef(docId: kApiDocId, endpointId: api);
    comps.add(comp);
    return comp;
  }

  /// แถบนำทางบน + เมนู + ปุ่มเข้าสู่ระบบ (ลูกของ navbar) ; จัดกลุ่ม "เมนูหลัก"
  void navbar({bool admin = false}) {
    add(WfKind.navbar, 0, 0, w: width, h: 64, text: 'Siam Residence', name: '${prefix}_nav');
    const g = 'g_menu';
    add(WfKind.link, 330, 20, w: 90, text: 'ห้องพัก', group: g);
    add(WfKind.link, 440, 20, w: 90, text: 'โปรโมชัน', group: g);
    add(WfKind.link, 550, 20, w: 110, text: 'การจองของฉัน', group: g);
    if (admin) add(WfKind.link, 680, 20, w: 90, text: 'แอดมิน', group: g);
    add(WfKind.avatar, width - 64, 8, w: 48, h: 48);
    add(WfKind.button, width - 190, 12, w: 110, h: 40, text: 'เข้าสู่ระบบ', secondary: true, api: 'e_login');
  }

  void footer() {
    add(WfKind.footer, 0, height - 80, w: width, h: 80, text: '© 2026 Siam Residence · โทร 02-000-0000');
  }
}

WireframeDiagram _done(_Page p) => WireframeDiagram(
      device: WfDevice.custom,
      width: p.width,
      height: p.height,
      style: p.style,
      components: p.comps,
    );

// ---------------------------------------------------------------------------------------------

/// หน้าแรก: ค้นหาห้อง + ประเภทห้องเด่น + วิดีโอ/แผนที่ + คำถามที่พบบ่อย
WireframeDiagram buildHome() {
  final p = _Page('h', height: 1760);
  p.navbar();
  p.add(WfKind.container, 0, 64, w: 1440, h: 440, text: 'ภาพพื้นหลังโรงแรม', name: 'h_hero');
  p.add(WfKind.heading, 120, 110, w: 760, h: 56, text: 'จองห้องพักง่าย ๆ ราคาดีที่สุด', fontSize: 34);
  p.add(WfKind.paragraph, 120, 176, w: 640, h: 56, text: 'ค้นหาห้องว่าง เลือกประเภทที่ใช่ ชำระเงินปลอดภัย ยกเลิกฟรีก่อนเข้าพัก 24 ชั่วโมง');
  p.add(WfKind.badge, 1120, 130, w: 150, h: 40, text: 'โปรฯ ลด 20%', fill: 0xFFFDE68A).rotation = -8;
  // กล่องค้นหา
  p.add(WfKind.card, 120, 270, w: 1200, h: 190, text: 'ค้นหาห้องว่าง', name: 'h_search');
  p.add(WfKind.label, 150, 320, w: 120, h: 22, text: 'วันเข้าพัก');
  p.add(WfKind.datepicker, 150, 346, w: 220, h: 44, text: 'เลือกวันที่', table: 'bookings', col: 'check_in');
  p.add(WfKind.label, 400, 320, w: 120, h: 22, text: 'วันออก');
  p.add(WfKind.datepicker, 400, 346, w: 220, h: 44, text: 'เลือกวันที่', table: 'bookings', col: 'check_out');
  p.add(WfKind.label, 650, 320, w: 120, h: 22, text: 'ผู้เข้าพัก');
  p.add(WfKind.input, 650, 346, w: 140, h: 44, text: '2 คน', table: 'bookings', col: 'guests');
  p.add(WfKind.label, 820, 320, w: 140, h: 22, text: 'ประเภทห้อง');
  p.add(WfKind.select, 820, 346, w: 240, h: 44, text: 'ทุกประเภท', table: 'room_types', col: 'name');
  p.add(WfKind.button, 1100, 346, w: 190, h: 44, text: 'ค้นหาห้องว่าง', api: 'e_rooms_available', name: 'h_btn_search');
  // ประเภทห้องเด่น
  p.add(WfKind.heading, 120, 540, w: 500, h: 40, text: 'ประเภทห้องพัก');
  const names = ['Standard', 'Deluxe', 'Family Suite'];
  const prices = ['฿1,290 / คืน', '฿1,890 / คืน', '฿3,290 / คืน'];
  for (var i = 0; i < 3; i++) {
    final x = 120.0 + i * 410;
    p.add(WfKind.card, x, 600, w: 380, h: 380, text: names[i]);
    p.add(WfKind.image, x + 16, 640, w: 348, h: 190);
    p.add(WfKind.label, x + 16, 842, w: 200, h: 24, text: names[i], table: 'room_types', col: 'name', bold: true);
    p.add(WfKind.label, x + 16, 872, w: 200, h: 24, text: prices[i], table: 'room_types', col: 'base_price');
    p.add(WfKind.rating, x + 220, 842, w: 144, h: 26);
    p.add(WfKind.button, x + 16, 920, w: 348, h: 40, text: 'ดูรายละเอียด', secondary: true, api: 'e_types_get');
  }
  // วิดีโอ + แผนที่
  p.add(WfKind.heading, 120, 1020, w: 500, h: 40, text: 'ชมบรรยากาศและที่ตั้ง');
  p.add(WfKind.video, 120, 1070, w: 640, h: 340);
  p.add(WfKind.map, 800, 1070, w: 520, h: 340);
  p.add(WfKind.tooltip, 1140, 1090, w: 150, h: 48, text: 'ใกล้ BTS 300 ม.');
  // FAQ
  p.add(WfKind.heading, 120, 1450, w: 500, h: 40, text: 'คำถามที่พบบ่อย');
  p.add(WfKind.accordion, 120, 1500, w: 700, h: 170, text: 'เช็คอิน/เช็คเอาท์กี่โมง?\nยกเลิกการจองได้หรือไม่?\nมีที่จอดรถหรือไม่?');
  p.add(WfKind.alert, 860, 1500, w: 460, h: 64, text: 'ยกเลิกฟรีก่อนวันเข้าพัก 24 ชั่วโมง');
  p.add(WfKind.label, 860, 1590, w: 300, h: 22, text: 'บันทึกดีไซน์: ใส่รีวิวจริงแทนข้อความตัวอย่าง', name: 'h_designnote').hidden = true;
  p.footer();
  return _done(p);
}

/// รายการห้อง: ตัวกรองซ้าย + การ์ดห้อง + เลขหน้า
WireframeDiagram buildRooms() {
  final p = _Page('r', height: 1300);
  p.navbar();
  p.add(WfKind.breadcrumb, 40, 84, w: 420, h: 24, text: 'หน้าแรก\nค้นหาห้อง\n12–14 ธ.ค. · 2 คน');
  p.add(WfKind.sidebar, 40, 124, w: 300, h: 1040, text: 'ตัวกรอง', name: 'r_filter');
  p.add(WfKind.heading, 60, 140, w: 240, h: 36, text: 'ตัวกรอง', fontSize: 18);
  p.add(WfKind.label, 60, 188, w: 240, h: 22, text: 'ช่วงราคาต่อคืน');
  p.add(WfKind.slider, 60, 214, w: 240, h: 28);
  p.add(WfKind.label, 60, 262, w: 240, h: 22, text: 'สิ่งอำนวยความสะดวก');
  const am = ['Wi-Fi ฟรี', 'อาหารเช้า', 'สระว่ายน้ำ', 'ที่จอดรถ'];
  for (var i = 0; i < am.length; i++) {
    p.add(WfKind.checkbox, 60, 292 + i * 34, w: 240, h: 24, text: am[i], checked: i < 2, table: 'amenities', col: 'name');
  }
  p.add(WfKind.label, 60, 448, w: 240, h: 22, text: 'ผู้เข้าพัก');
  p.add(WfKind.select, 60, 474, w: 240, h: 40, text: '2 คน');
  p.add(WfKind.toggle, 60, 540, w: 240, h: 28, text: 'เฉพาะห้องที่ยกเลิกฟรี', checked: true);
  p.add(WfKind.button, 60, 600, w: 240, h: 40, text: 'ล้างตัวกรอง', secondary: true);
  p.add(WfKind.search, 380, 124, w: 520, h: 44, text: 'ค้นหาชื่อประเภทห้อง…');
  p.add(WfKind.select, 1160, 124, w: 240, h: 44, text: 'เรียงตาม: ราคาต่ำไปสูง');
  final types = [('Standard', '฿1,290', 'Queen · 2 ท่าน'), ('Deluxe', '฿1,890', 'King · 3 ท่าน'), ('Family Suite', '฿3,290', 'King + Twin · 5 ท่าน')];
  for (var i = 0; i < types.length; i++) {
    final y = 196.0 + i * 270;
    p.add(WfKind.card, 380, y, w: 1020, h: 250, text: types[i].$1);
    p.add(WfKind.image, 396, y + 40, w: 300, h: 190);
    p.add(WfKind.label, 720, y + 48, w: 300, h: 24, text: types[i].$1, table: 'room_types', col: 'name', bold: true);
    p.add(WfKind.label, 720, y + 78, w: 300, h: 22, text: types[i].$3, table: 'room_types', col: 'bed_type');
    p.add(WfKind.chip, 720, y + 112, w: 110, h: 28, text: 'Wi-Fi ฟรี');
    p.add(WfKind.chip, 840, y + 112, w: 110, h: 28, text: 'อาหารเช้า');
    p.add(WfKind.rating, 720, y + 156, w: 150, h: 26);
    p.add(WfKind.label, 1120, y + 56, w: 250, h: 30, text: '${types[i].$2} / คืน', table: 'room_types', col: 'base_price', bold: true, align: WfAlign.right);
    p.add(WfKind.badge, 1250, y + 100, w: 120, h: 26, text: 'เหลือ 2 ห้อง');
    p.add(WfKind.button, 1120, y + 176, w: 250, h: 44, text: 'เลือกห้องนี้', api: 'e_types_get');
  }
  p.add(WfKind.skeleton, 380, 1014, w: 1020, h: 90);
  p.add(WfKind.pagination, 800, 1120, w: 260, h: 36);
  p.footer();
  return _done(p);
}

/// รายละเอียดห้อง: รูป + รายละเอียด + ปฏิทินว่าง + กล่องจอง + รีวิว
WireframeDiagram buildDetail() {
  final p = _Page('d', height: 1500);
  p.navbar();
  p.add(WfKind.breadcrumb, 40, 84, w: 420, h: 24, text: 'หน้าแรก\nค้นหาห้อง\nDeluxe');
  p.add(WfKind.image, 40, 124, w: 620, h: 380);
  p.add(WfKind.image, 680, 124, w: 300, h: 184);
  p.add(WfKind.image, 680, 320, w: 300, h: 184);
  p.add(WfKind.heading, 40, 530, w: 600, h: 44, text: 'Deluxe', fontSize: 30);
  p.add(WfKind.rating, 40, 580, w: 160, h: 28);
  p.add(WfKind.paragraph, 40, 620, w: 940, h: 80, text: 'ห้องกว้างขึ้น วิวเมือง พร้อมโซฟาและโต๊ะทำงาน เตียง King ผ้าปูคุณภาพโรงแรม 5 ดาว เหมาะกับการเข้าพักทั้งพักผ่อนและทำงาน', table: 'room_types', col: 'description');
  p.add(WfKind.heading, 40, 724, w: 400, h: 32, text: 'สิ่งอำนวยความสะดวก', fontSize: 18);
  const am = ['Wi-Fi ฟรี', 'อาหารเช้า', 'เครื่องปรับอากาศ', 'ที่จอดรถ'];
  for (var i = 0; i < am.length; i++) {
    p.add(WfKind.chip, 40.0 + i * 150, 764, w: 140, h: 30, text: am[i]);
  }
  p.add(WfKind.heading, 40, 830, w: 500, h: 32, text: 'ตรวจสอบวันว่าง', fontSize: 18);
  p.add(WfKind.calendar, 40, 872, w: 330, h: 300);
  p.add(WfKind.tree, 400, 872, w: 260, h: 150, text: 'ชั้น 2\n  201 ว่าง\n  202 มีผู้เข้าพัก\nชั้น 3\n  301 ว่าง');
  p.add(WfKind.progress, 400, 1050, w: 260, h: 22, text: '72%');
  p.add(WfKind.label, 400, 1080, w: 260, h: 22, text: 'อัตราการเข้าพักเดือนนี้');
  // กล่องจอง (ขวา)
  p.add(WfKind.card, 1010, 124, w: 390, h: 480, text: 'จองห้องนี้', name: 'd_book');
  p.add(WfKind.label, 1040, 176, w: 330, h: 30, text: '฿1,890 / คืน', table: 'room_types', col: 'base_price', bold: true, fontSize: 22);
  p.add(WfKind.datepicker, 1040, 224, w: 330, h: 44, text: 'วันเข้าพัก', table: 'bookings', col: 'check_in');
  p.add(WfKind.datepicker, 1040, 280, w: 330, h: 44, text: 'วันออก', table: 'bookings', col: 'check_out');
  p.add(WfKind.input, 1040, 336, w: 330, h: 44, text: '2 ผู้เข้าพัก', table: 'bookings', col: 'guests');
  p.add(WfKind.divider, 1040, 400, w: 330, h: 12);
  p.add(WfKind.label, 1040, 424, w: 200, h: 24, text: '2 คืน × ฿1,890');
  p.add(WfKind.label, 1240, 424, w: 130, h: 24, text: '฿3,780', align: WfAlign.right);
  p.add(WfKind.label, 1040, 456, w: 200, h: 24, text: 'รวมทั้งสิ้น', bold: true);
  p.add(WfKind.label, 1240, 456, w: 130, h: 24, text: '฿3,780', table: 'bookings', col: 'total_price', bold: true, align: WfAlign.right);
  p.add(WfKind.button, 1040, 516, w: 330, h: 48, text: 'จองเลย', api: 'e_booking_create', name: 'd_btn_book');
  // รีวิว
  p.add(WfKind.heading, 700, 1190, w: 500, h: 32, text: 'รีวิวจากผู้เข้าพัก', fontSize: 18);
  p.add(WfKind.list, 700, 1230, w: 700, h: 190, text: 'สมชาย: ห้องสะอาด พนักงานน่ารัก\nวิภา: เตียงนุ่ม วิวสวย\nนที: คุ้มค่ากับราคา', table: 'reviews', col: 'comment');
  p.footer();
  return _done(p);
}

/// จองและชำระเงิน: stepper + ฟอร์มผู้เข้าพัก + วิธีชำระ + สรุป
WireframeDiagram buildCheckout() {
  final p = _Page('c', height: 1200);
  p.navbar();
  p.add(WfKind.stepper, 120, 96, w: 700, h: 60, text: 'ข้อมูลผู้เข้าพัก\nชำระเงิน\nยืนยัน');
  p.add(WfKind.alert, 120, 176, w: 700, h: 56, text: 'ห้องถูกกันไว้ให้คุณ 15 นาที กรุณาชำระเงินให้เสร็จ');
  p.add(WfKind.heading, 120, 262, w: 500, h: 36, text: 'ข้อมูลผู้เข้าพัก', fontSize: 20);
  p.add(WfKind.label, 120, 312, w: 200, h: 22, text: 'ชื่อ-นามสกุล');
  p.add(WfKind.input, 120, 338, w: 700, h: 44, text: 'สมชาย ใจดี', table: 'users', col: 'full_name');
  p.add(WfKind.label, 120, 396, w: 200, h: 22, text: 'อีเมล');
  p.add(WfKind.input, 120, 422, w: 340, h: 44, text: 'somchai@example.com', table: 'users', col: 'email');
  p.add(WfKind.label, 480, 396, w: 200, h: 22, text: 'โทรศัพท์');
  p.add(WfKind.input, 480, 422, w: 340, h: 44, text: '081-234-5678', table: 'users', col: 'phone');
  p.add(WfKind.label, 120, 480, w: 300, h: 22, text: 'คำขอพิเศษ');
  p.add(WfKind.textarea, 120, 506, w: 700, h: 100, text: 'เช่น ชั้นสูง / เตียงเสริม', table: 'bookings', col: 'note');
  p.add(WfKind.heading, 120, 640, w: 500, h: 36, text: 'วิธีชำระเงิน', fontSize: 20);
  const methods = ['บัตรเครดิต/เดบิต', 'PromptPay', 'โอนผ่านธนาคาร'];
  for (var i = 0; i < methods.length; i++) {
    p.add(WfKind.radio, 120, 690.0 + i * 36, w: 320, h: 24, text: methods[i], checked: i == 1, table: 'payments', col: 'method');
  }
  p.add(WfKind.checkbox, 120, 820, w: 600, h: 24, text: 'ฉันยอมรับเงื่อนไขการจองและนโยบายการยกเลิก', checked: true);
  p.add(WfKind.tooltip, 740, 806, w: 200, h: 48, text: 'ยกเลิกฟรีก่อน 24 ชม.');
  p.add(WfKind.button, 120, 880, w: 260, h: 52, text: 'ชำระเงิน ฿3,780', api: 'e_pay_create', name: 'c_btn_pay');
  p.add(WfKind.button, 400, 880, w: 160, h: 52, text: 'ย้อนกลับ', secondary: true);
  // สรุป
  p.add(WfKind.card, 900, 96, w: 440, h: 460, text: 'สรุปการจอง', name: 'c_summary');
  p.add(WfKind.image, 916, 136, w: 408, h: 150);
  p.add(WfKind.label, 916, 300, w: 400, h: 26, text: 'Deluxe · ห้อง 201', bold: true);
  p.add(WfKind.label, 916, 332, w: 400, h: 22, text: '12 ธ.ค. 2569 → 14 ธ.ค. 2569 (2 คืน)');
  p.add(WfKind.label, 916, 360, w: 400, h: 22, text: '2 ผู้เข้าพัก');
  p.add(WfKind.divider, 916, 396, w: 408, h: 12);
  p.add(WfKind.label, 916, 420, w: 200, h: 24, text: 'ค่าห้อง');
  p.add(WfKind.label, 1200, 420, w: 124, h: 24, text: '฿3,780', align: WfAlign.right);
  p.add(WfKind.label, 916, 452, w: 200, h: 24, text: 'รวมทั้งสิ้น', bold: true);
  p.add(WfKind.label, 1200, 452, w: 124, h: 24, text: '฿3,780', table: 'payments', col: 'amount', bold: true, align: WfAlign.right);
  p.add(WfKind.progress, 916, 500, w: 408, h: 20, text: 'เหลือเวลา 12:30');
  p.footer();
  return _done(p);
}

/// การจองของฉัน: แท็บสถานะ + ตารางการจอง + กล่องเขียนรีวิว
WireframeDiagram buildMyBookings() {
  final p = _Page('m', height: 1100);
  p.navbar();
  p.add(WfKind.heading, 80, 90, w: 500, h: 44, text: 'การจองของฉัน', fontSize: 28);
  p.add(WfKind.tabs, 80, 150, w: 560, h: 44, text: 'กำลังจะมาถึง\nเสร็จสิ้น\nยกเลิก');
  p.add(WfKind.search, 900, 150, w: 460, h: 44, text: 'ค้นหารหัสการจอง…');
  p.add(WfKind.table, 80, 220, w: 1280, h: 280, columns: ['รหัสการจอง', 'ห้อง', 'เช็คอิน', 'เช็คเอาท์', 'ยอดรวม', 'สถานะ'], rows: 4, table: 'bookings');
  p.add(WfKind.badge, 1200, 270, w: 110, h: 26, text: 'ยืนยันแล้ว');
  p.add(WfKind.button, 80, 520, w: 180, h: 44, text: 'ยกเลิกการจอง', secondary: true, api: 'e_booking_cancel');
  p.add(WfKind.button, 280, 520, w: 180, h: 44, text: 'ดูรายละเอียด', api: 'e_booking_get');
  p.add(WfKind.pagination, 1100, 520, w: 260, h: 36);
  p.add(WfKind.alert, 80, 600, w: 700, h: 56, text: 'ค่าธรรมเนียมการยกเลิก: ฟรีก่อน 24 ชั่วโมง หลังจากนั้นคิด 1 คืน');
  // กล่องรีวิว
  p.add(WfKind.modal, 380, 690, w: 680, h: 320, text: 'เขียนรีวิว', name: 'm_review');
  p.add(WfKind.rating, 420, 750, w: 180, h: 30, table: 'reviews', col: 'rating');
  p.add(WfKind.textarea, 420, 794, w: 600, h: 100, text: 'เล่าประสบการณ์การเข้าพักของคุณ…', table: 'reviews', col: 'comment');
  p.add(WfKind.button, 860, 920, w: 160, h: 44, text: 'ส่งรีวิว', api: 'e_review_create');
  p.add(WfKind.button, 680, 920, w: 160, h: 44, text: 'ยกเลิก', secondary: true);
  p.footer();
  return _done(p);
}

/// แอดมิน: เมนูข้าง + ตัวเลขสรุป + กราฟ + ตารางเช็คอินวันนี้
WireframeDiagram buildAdmin() {
  final p = _Page('a', height: 1000);
  p.add(WfKind.sidebar, 0, 0, w: 240, h: 1000, text: 'แดชบอร์ด\nห้องพัก\nการจอง\nรายงาน\nตั้งค่า', name: 'a_side');
  p.add(WfKind.avatar, 20, 920, w: 48, h: 48);
  p.add(WfKind.label, 80, 930, w: 150, h: 24, text: 'ผู้ดูแลระบบ');
  p.add(WfKind.heading, 280, 30, w: 500, h: 44, text: 'ภาพรวมวันนี้', fontSize: 28);
  p.add(WfKind.datepicker, 1100, 30, w: 240, h: 44, text: '19 พ.ย. 2569');
  const kpis = ['อัตราเข้าพัก\n72%', 'เช็คอินวันนี้\n5', 'เช็คเอาท์วันนี้\n3', 'รายได้วันนี้\n฿18,450'];
  for (var i = 0; i < kpis.length; i++) {
    p.add(WfKind.stat, 280.0 + i * 275, 100, w: 250, h: 100, text: kpis[i], api: 'e_dashboard');
  }
  p.add(WfKind.heading, 280, 230, w: 400, h: 32, text: 'การจองรายสัปดาห์', fontSize: 18);
  p.add(WfKind.chart, 280, 270, w: 620, h: 300);
  p.add(WfKind.heading, 940, 230, w: 400, h: 32, text: 'อัตราเข้าพักแต่ละประเภท', fontSize: 18);
  const occ = ['Standard 80%', 'Deluxe 70%', 'Family 55%', 'Executive 40%'];
  for (var i = 0; i < occ.length; i++) {
    p.add(WfKind.progress, 940, 280.0 + i * 64, w: 400, h: 22, text: occ[i].split(' ').last);
    p.add(WfKind.label, 940, 306.0 + i * 64, w: 300, h: 22, text: occ[i].split(' ').first);
  }
  p.add(WfKind.heading, 280, 600, w: 400, h: 32, text: 'เช็คอินวันนี้', fontSize: 18);
  p.add(WfKind.table, 280, 640, w: 1060, h: 220, columns: ['รหัสการจอง', 'ผู้เข้าพัก', 'ห้อง', 'เวลา', 'สถานะ'], rows: 3, table: 'bookings');
  p.add(WfKind.button, 280, 890, w: 200, h: 44, text: '+ เพิ่มห้อง', api: 'e_rooms_create');
  p.add(WfKind.upload, 1000, 880, w: 340, h: 90, text: 'นำเข้ารายการห้องจากไฟล์ CSV');
  return _done(p);
}

/// แอดมิน: เพิ่ม/แก้ไขห้อง (ฟอร์ม + อัปโหลดรูป)
WireframeDiagram buildAdminRoom() {
  final p = _Page('x', height: 940);
  p.navbar(admin: true);
  p.add(WfKind.breadcrumb, 80, 84, w: 420, h: 24, text: 'แอดมิน\nห้องพัก\nเพิ่มห้อง');
  p.add(WfKind.heading, 80, 124, w: 500, h: 44, text: 'เพิ่มห้องพัก', fontSize: 28);
  p.add(WfKind.card, 80, 190, w: 760, h: 640, text: 'ข้อมูลห้อง', name: 'x_form');
  p.add(WfKind.label, 110, 240, w: 200, h: 22, text: 'หมายเลขห้อง');
  p.add(WfKind.input, 110, 266, w: 340, h: 44, text: '203', table: 'rooms', col: 'room_number');
  p.add(WfKind.label, 480, 240, w: 200, h: 22, text: 'ชั้น');
  p.add(WfKind.input, 480, 266, w: 330, h: 44, text: '2', table: 'rooms', col: 'floor');
  p.add(WfKind.label, 110, 330, w: 200, h: 22, text: 'ประเภทห้อง');
  p.add(WfKind.select, 110, 356, w: 700, h: 44, text: 'Deluxe', table: 'rooms', col: 'room_type_id');
  p.add(WfKind.label, 110, 420, w: 200, h: 22, text: 'สถานะ');
  p.add(WfKind.select, 110, 446, w: 340, h: 44, text: 'available', table: 'rooms', col: 'status');
  p.add(WfKind.toggle, 480, 454, w: 330, h: 28, text: 'เปิดให้จอง', checked: true);
  p.add(WfKind.label, 110, 510, w: 300, h: 22, text: 'รูปภาพห้อง');
  p.add(WfKind.upload, 110, 536, w: 700, h: 130);
  p.add(WfKind.button, 110, 700, w: 200, h: 48, text: 'บันทึก', api: 'e_rooms_create');
  p.add(WfKind.button, 330, 700, w: 160, h: 48, text: 'ยกเลิก', secondary: true);
  p.add(WfKind.button, 640, 700, w: 170, h: 48, text: 'ลบห้อง', secondary: true, api: 'e_rooms_delete');
  p.add(WfKind.alert, 880, 190, w: 460, h: 64, text: 'หมายเลขห้องต้องไม่ซ้ำกับห้องที่มีอยู่');
  p.add(WfKind.icon, 880, 280, w: 32, h: 32);
  p.add(WfKind.paragraph, 924, 280, w: 420, h: 72, text: 'ห้องที่ปิดการจองจะไม่ถูกนำไปคำนวณในผลการค้นหาห้องว่าง');
  p.footer();
  return _done(p);
}
