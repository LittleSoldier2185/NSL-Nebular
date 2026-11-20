import '../l10n/l10n.dart';
import 'wf_block.dart';
import 'wireframe_model.dart';

/// แม่แบบสำเร็จรูป 8 ชุดของ Wireframe (Phase 18b) — ประกอบจากชิ้นส่วนที่มีอยู่ ไม่เพิ่มชนิดใหม่/ตัวสร้างโค้ดใหม่
/// สร้างตอนเรียก (ไม่ใช่ค่าคงที่) เพราะข้อความเริ่มต้นแปลตามภาษาที่เลือก ; ข้อความทุกชิ้นแก้ได้หลังวาง

const int _white = 0xFFFFFFFF;
const int _grey = 0xFF667085;

class _B {
  final parts = <WfComponent>[];
  var _n = 0;

  WfComponent add(WfKind k, double x, double y, double w, double h,
      {String text = '', bool bold = false, WfAlign align = WfAlign.left, double? fontSize, int? fill, int? textColor, bool checked = false, bool secondary = false, int rows = 3}) {
    final c = WfComponent(
      id: 't${_n++}',
      kind: k,
      text: text,
      x: x,
      y: y,
      w: w,
      h: h,
      bold: bold,
      align: align,
      fontSize: fontSize,
      fill: fill,
      textColor: textColor,
      checked: checked,
      secondary: secondary,
      rows: rows,
    );
    parts.add(c);
    return c;
  }

  /// กรอบพื้นขาวของการ์ด/ฟอร์ม (container ที่ใส่สีพื้นจึงเป็นเส้นทึบ ไม่ใช่เส้นประ)
  void card(double w, double h) => add(WfKind.container, 0, 0, w, h, fill: _white);

  void field(String label, String placeholder, double x, double y, double w, {bool password = false}) {
    add(WfKind.label, x, y, w, 18, text: label, fontSize: 12, textColor: _grey);
    if (password) {
      add(WfKind.password, x, y + 20, w, 40);
    } else {
      add(WfKind.input, x, y + 20, w, 40, text: placeholder);
    }
  }

  WfBlock build(String id, String name, double w, double h) => WfBlock(id: 'tpl-$id', name: name, w: w, h: h, parts: parts, isTemplate: true);
}

WfBlock _login() {
  final b = _B()..card(360, 440);
  b.add(WfKind.avatar, 158, 24, 44, 44);
  b.add(WfKind.heading, 28, 76, 304, 36, text: tr('เข้าสู่ระบบ'), align: WfAlign.center, fontSize: 20);
  b.field(tr('อีเมล'), 'you@example.com', 28, 126, 304);
  b.field(tr('รหัสผ่าน'), '', 28, 196, 304, password: true);
  b.add(WfKind.checkbox, 28, 268, 150, 24, text: tr('จดจำฉัน'), checked: true);
  b.add(WfKind.link, 200, 268, 132, 24, text: tr('ลืมรหัสผ่าน?'), align: WfAlign.right);
  b.add(WfKind.button, 28, 304, 304, 42, text: tr('เข้าสู่ระบบ'));
  b.add(WfKind.divider, 28, 372, 304, 12);
  b.add(WfKind.label, 150, 366, 60, 24, text: tr('หรือ'), align: WfAlign.center, fill: _white);
  b.add(WfKind.button, 28, 392, 304, 40, text: tr('ต่อด้วย Google'), secondary: true);
  return b.build('login', tr('ฟอร์มเข้าสู่ระบบ'), 360, 440);
}

WfBlock _signup() {
  final b = _B()..card(360, 500);
  b.add(WfKind.heading, 28, 24, 304, 36, text: tr('สร้างบัญชีใหม่'), align: WfAlign.center, fontSize: 20);
  b.field(tr('ชื่อ-นามสกุล'), tr('สมชาย ใจดี'), 28, 76, 304);
  b.field(tr('อีเมล'), 'you@example.com', 28, 146, 304);
  b.field(tr('รหัสผ่าน'), '', 28, 216, 304, password: true);
  b.field(tr('ยืนยันรหัสผ่าน'), '', 28, 286, 304, password: true);
  b.add(WfKind.checkbox, 28, 362, 304, 24, text: tr('ฉันยอมรับเงื่อนไขการใช้งาน'));
  b.add(WfKind.button, 28, 398, 304, 42, text: tr('สมัครสมาชิก'));
  b.add(WfKind.label, 28, 458, 304, 24, text: tr('มีบัญชีอยู่แล้ว? เข้าสู่ระบบ'), align: WfAlign.center, textColor: _grey);
  return b.build('signup', tr('ฟอร์มสมัครสมาชิก'), 360, 500);
}

WfBlock _profile() {
  final b = _B()..card(480, 180);
  b.add(WfKind.image, 1, 1, 478, 70, text: '');
  b.add(WfKind.avatar, 26, 36, 72, 72, fill: _white);
  b.add(WfKind.heading, 112, 80, 220, 30, text: tr('สมชาย ใจดี'), fontSize: 18);
  b.add(WfKind.label, 112, 112, 240, 20, text: tr('@somchai · กรุงเทพฯ'), fontSize: 12.5, textColor: _grey);
  final stats = [('128', tr('โพสต์')), ('2.4k', tr('ผู้ติดตาม')), ('310', tr('กำลังติดตาม'))];
  for (var i = 0; i < 3; i++) {
    b.add(WfKind.label, 112.0 + i * 92, 138, 86, 20, text: stats[i].$1, bold: true, fontSize: 15);
    b.add(WfKind.label, 112.0 + i * 92, 158, 86, 16, text: stats[i].$2, fontSize: 11, textColor: _grey);
  }
  b.add(WfKind.button, 358, 84, 98, 34, text: tr('ติดตาม'));
  return b.build('profile', tr('หัวโปรไฟล์'), 480, 180);
}

WfBlock _product() {
  final b = _B()..card(240, 330);
  b.add(WfKind.image, 10, 10, 220, 150);
  b.add(WfKind.badge, 18, 18, 58, 20, text: '-20%');
  b.add(WfKind.label, 14, 170, 212, 24, text: tr('เก้าอี้ไม้โอ๊ค รุ่น Nara'), bold: true);
  b.add(WfKind.rating, 14, 198, 100, 22);
  b.add(WfKind.label, 160, 198, 66, 22, text: '(86)', fontSize: 12, textColor: _grey, align: WfAlign.right);
  b.add(WfKind.label, 14, 226, 90, 30, text: '฿2,490', bold: true, fontSize: 18);
  b.add(WfKind.label, 108, 232, 80, 20, text: '฿3,100', fontSize: 12.5, textColor: _grey);
  b.add(WfKind.button, 14, 272, 212, 40, text: tr('ใส่ตะกร้า'));
  return b.build('product', tr('การ์ดสินค้า'), 240, 330);
}

WfBlock _cartRow() {
  final b = _B()..card(560, 100);
  b.add(WfKind.image, 12, 12, 76, 76);
  b.add(WfKind.label, 104, 14, 280, 24, text: tr('เก้าอี้ไม้โอ๊ค รุ่น Nara'), bold: true);
  b.add(WfKind.label, 104, 40, 280, 20, text: tr('สี: ธรรมชาติ · ขนาด: M'), fontSize: 12.5, textColor: _grey);
  b.add(WfKind.numberInput, 104, 62, 120, 30, text: '1');
  b.add(WfKind.label, 410, 34, 100, 28, text: '฿2,490', bold: true, fontSize: 16, align: WfAlign.right);
  b.add(WfKind.icon, 526, 38, 24, 24);
  return b.build('cart-row', tr('แถวสินค้าในตะกร้า'), 560, 100);
}

WfBlock _pricing() {
  final b = _B()..card(280, 390);
  b.add(WfKind.badge, 100, 8, 80, 22, text: tr('ยอดนิยม'));
  b.add(WfKind.heading, 24, 44, 232, 28, text: tr('โปร'), align: WfAlign.center, fontSize: 18);
  b.add(WfKind.label, 24, 84, 232, 54, text: '฿299', bold: true, fontSize: 38, align: WfAlign.center);
  b.add(WfKind.label, 24, 140, 232, 20, text: tr('ต่อเดือน'), fontSize: 12.5, textColor: _grey, align: WfAlign.center);
  final feats = [tr('โปรเจกต์ไม่จำกัด'), tr('ส่งออกทุกรูปแบบ'), tr('พื้นที่ 50 GB'), tr('สนับสนุนทางอีเมล')];
  for (var i = 0; i < feats.length; i++) {
    b.add(WfKind.checkbox, 30, 178.0 + i * 34, 220, 24, text: feats[i], checked: true);
  }
  b.add(WfKind.button, 24, 324, 232, 44, text: tr('เลือกแผนนี้'));
  return b.build('pricing', tr('การ์ดราคา'), 280, 390);
}

WfBlock _hero() {
  final b = _B()..card(640, 300);
  b.add(WfKind.heading, 36, 56, 310, 44, text: tr('ค้นหาห้องพักที่ใช่'), fontSize: 30);
  b.add(WfKind.paragraph, 36, 108, 310, 48, text: tr('เปรียบเทียบราคาและรีวิวจริง จองง่าย ยกเลิกฟรีภายใน 24 ชั่วโมง'), textColor: _grey);
  b.add(WfKind.button, 36, 178, 140, 46, text: tr('เริ่มค้นหา'));
  b.add(WfKind.button, 190, 178, 120, 46, text: tr('ดูตัวอย่าง'), secondary: true);
  b.add(WfKind.image, 366, 30, 244, 240);
  return b.build('hero', tr('Hero + ปุ่ม CTA'), 640, 300);
}

WfBlock _pageHeader() {
  final b = _B();
  b.add(WfKind.breadcrumb, 0, 0, 300, 24, text: tr('หน้าแรก\nค้นหาห้อง'));
  b.add(WfKind.heading, 0, 30, 330, 40, text: tr('ผลการค้นหา 42 รายการ'), fontSize: 22);
  b.add(WfKind.search, 340, 24, 300, 40, text: tr('ค้นหาชื่อห้อง'));
  final chips = [(tr('ทั้งหมด'), 80.0), (tr('ราคาไม่เกิน ฿2,000'), 150.0), (tr('มีอาหารเช้า'), 110.0), (tr('ใกล้ BTS'), 90.0)];
  var x = 0.0;
  for (final (t, w) in chips) {
    b.add(WfKind.chip, x, 88, w, 30, text: t);
    x += w + 8;
  }
  return b.build('page-header', tr('หัวหน้า + ค้นหา + ตัวกรอง'), 640, 130);
}

/// แม่แบบทั้ง 8 ชุด ตามลำดับที่แสดงในคลัง
List<WfBlock> wfTemplateBlocks() => [_login(), _signup(), _profile(), _product(), _cartRow(), _pricing(), _hero(), _pageHeader()];
