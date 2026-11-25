/// สัญลักษณ์ (glyph) ที่เลือกให้ชิ้นส่วนไอคอนของ Wireframe ได้ — วาดจากเส้นง่าย ๆ ในกริด 24×24 เป็นข้อมูลล้วน
/// ตัววาดบนจอ / PNG / SVG / HTML ใช้ข้อมูลชุดเดียวกัน จึงได้ภาพตรงกัน ; Flutter codegen แปลงเป็น `Icons.*`
library;

/// คำสั่งวาดหนึ่งคำสั่งในกริด 24×24 : 'L' = เส้นหลายจุด (เปิด) [x1,y1,x2,y2,...] ; 'P' = รูปหลายเหลี่ยมปิด ;
/// 'C' = วงกลม [cx,cy,r] ; 'R' = สี่เหลี่ยม [x,y,w,h,r]
typedef WfIconOp = (String op, List<double> a);

class WfIconDef {
  const WfIconDef(this.id, this.th, this.en, this.flutter, this.ops);
  final String id;
  final String th, en;

  /// ชื่อใน `Icons` ของ Flutter (ใช้ตอนสร้างโค้ด)
  final String flutter;
  final List<WfIconOp> ops;
}

const String kWfDefaultSymbol = 'star';

WfIconDef? wfIconById(String id) {
  for (final d in kWfIcons) {
    if (d.id == id) return d;
  }
  return null;
}

/// ข้อความ SVG (viewBox 0 0 24 24 ไม่มีแท็กครอบ) ของสัญลักษณ์ — ใช้ในไฟล์ HTML
String wfIconSvgBody(WfIconDef d) {
  String n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  final b = StringBuffer();
  for (final (op, a) in d.ops) {
    switch (op) {
      case 'L' || 'P':
        b.write('<path d="M${n(a[0])} ${n(a[1])}');
        for (var i = 2; i + 1 < a.length; i += 2) {
          b.write('L${n(a[i])} ${n(a[i + 1])}');
        }
        b.write(op == 'P' ? 'Z"/>' : '"/>');
      case 'C':
        b.write('<circle cx="${n(a[0])}" cy="${n(a[1])}" r="${n(a[2])}"/>');
      case 'R':
        b.write('<rect x="${n(a[0])}" y="${n(a[1])}" width="${n(a[2])}" height="${n(a[3])}" rx="${n(a[4])}"/>');
    }
  }
  return b.toString();
}

const List<WfIconOp> _menu = [
  ('L', [4, 6, 20, 6]),
  ('L', [4, 12, 20, 12]),
  ('L', [4, 18, 20, 18]),
];

/// ชุดสัญลักษณ์ที่เลือกได้ (ลำดับ = ลำดับในตัวเลือก)
const List<WfIconDef> kWfIcons = [
  WfIconDef('home', 'หน้าแรก', 'Home', 'home_outlined', [
    ('L', [3, 11, 12, 3, 21, 11]),
    ('L', [5, 10, 5, 21, 19, 21, 19, 10]),
    ('L', [10, 21, 10, 15, 14, 15, 14, 21]),
  ]),
  WfIconDef('search', 'ค้นหา', 'Search', 'search', [
    ('C', [10.5, 10.5, 6.5]),
    ('L', [15.5, 15.5, 21, 21]),
  ]),
  WfIconDef('user', 'ผู้ใช้', 'User', 'person_outline', [
    ('C', [12, 8, 4]),
    ('L', [4, 21, 5, 17, 9, 14.5, 15, 14.5, 19, 17, 20, 21]),
  ]),
  WfIconDef('settings', 'ตั้งค่า', 'Settings', 'settings_outlined', [
    ('C', [12, 12, 3]),
    ('C', [12, 12, 7.5]),
    ('L', [12, 2, 12, 4.5]),
    ('L', [12, 19.5, 12, 22]),
    ('L', [2, 12, 4.5, 12]),
    ('L', [19.5, 12, 22, 12]),
  ]),
  WfIconDef('bell', 'แจ้งเตือน', 'Notifications', 'notifications_none', [
    ('L', [6, 17, 6, 11, 8, 6, 12, 4.5, 16, 6, 18, 11, 18, 17, 20, 19, 4, 19, 6, 17]),
    ('L', [10, 21, 14, 21]),
  ]),
  WfIconDef('mail', 'อีเมล', 'Mail', 'mail_outline', [
    ('R', [3, 5, 18, 14, 2]),
    ('L', [3, 6.5, 12, 13, 21, 6.5]),
  ]),
  WfIconDef('heart', 'ถูกใจ', 'Favorite', 'favorite_border', [
    ('P', [12, 21, 3.5, 12, 3.5, 8, 6, 5, 9, 5, 12, 8, 15, 5, 18, 5, 20.5, 8, 20.5, 12]),
  ]),
  WfIconDef('star', 'ดาว', 'Star', 'star_outline', [
    ('P', [12, 3, 14.8, 9, 21, 9.6, 16.3, 13.8, 17.8, 20.5, 12, 17, 6.2, 20.5, 7.7, 13.8, 3, 9.6, 9.2, 9]),
  ]),
  WfIconDef('check', 'ถูกต้อง', 'Check', 'check', [
    ('L', [4, 12.5, 9.5, 18, 20, 6]),
  ]),
  WfIconDef('close', 'ปิด', 'Close', 'close', [
    ('L', [5, 5, 19, 19]),
    ('L', [19, 5, 5, 19]),
  ]),
  WfIconDef('plus', 'เพิ่ม', 'Add', 'add', [
    ('L', [12, 4, 12, 20]),
    ('L', [4, 12, 20, 12]),
  ]),
  WfIconDef('minus', 'ลบออก', 'Remove', 'remove', [
    ('L', [4, 12, 20, 12]),
  ]),
  WfIconDef('menu', 'เมนู', 'Menu', 'menu', _menu),
  WfIconDef('arrowLeft', 'ลูกศรซ้าย', 'Arrow left', 'arrow_back', [
    ('L', [20, 12, 4, 12]),
    ('L', [10, 6, 4, 12, 10, 18]),
  ]),
  WfIconDef('arrowRight', 'ลูกศรขวา', 'Arrow right', 'arrow_forward', [
    ('L', [4, 12, 20, 12]),
    ('L', [14, 6, 20, 12, 14, 18]),
  ]),
  WfIconDef('chevronDown', 'ลูกศรลง', 'Expand', 'expand_more', [
    ('L', [6, 9, 12, 15, 18, 9]),
  ]),
  WfIconDef('cart', 'ตะกร้า', 'Cart', 'shopping_cart_outlined', [
    ('L', [2, 4, 5, 4, 7.5, 15, 18, 15, 20, 7, 6, 7]),
    ('C', [9, 19.5, 1.5]),
    ('C', [16.5, 19.5, 1.5]),
  ]),
  WfIconDef('calendar', 'ปฏิทิน', 'Calendar', 'calendar_today_outlined', [
    ('R', [3, 5, 18, 16, 2]),
    ('L', [3, 10, 21, 10]),
    ('L', [8, 3, 8, 7]),
    ('L', [16, 3, 16, 7]),
  ]),
  WfIconDef('clock', 'เวลา', 'Time', 'schedule', [
    ('C', [12, 12, 9]),
    ('L', [12, 7, 12, 12, 15.5, 14]),
  ]),
  WfIconDef('phone', 'โทรศัพท์', 'Phone', 'phone_outlined', [
    ('P', [6, 3, 10, 3, 11.5, 8, 9.5, 9.5, 14.5, 14.5, 16, 12.5, 21, 14, 21, 18, 18, 21, 12, 19, 5, 12, 3, 6]),
  ]),
  WfIconDef('lock', 'ล็อก', 'Lock', 'lock_outline', [
    ('R', [5, 11, 14, 10, 2]),
    ('L', [8, 11, 8, 7, 12, 3.5, 16, 7, 16, 11]),
  ]),
  WfIconDef('trash', 'ถังขยะ', 'Delete', 'delete_outline', [
    ('L', [4, 7, 20, 7]),
    ('L', [9, 7, 9, 4, 15, 4, 15, 7]),
    ('P', [6, 7, 7, 21, 17, 21, 18, 7]),
  ]),
  WfIconDef('edit', 'แก้ไข', 'Edit', 'edit_outlined', [
    ('P', [4, 20, 5, 15, 16, 4, 20, 8, 9, 19]),
    ('L', [14, 6, 18, 10]),
  ]),
  WfIconDef('info', 'ข้อมูล', 'Info', 'info_outline', [
    ('C', [12, 12, 9]),
    ('L', [12, 11, 12, 17]),
    ('C', [12, 7.6, 0.8]),
  ]),
  WfIconDef('warning', 'คำเตือน', 'Warning', 'warning_amber_outlined', [
    ('P', [12, 3, 22, 20, 2, 20]),
    ('L', [12, 9, 12, 14]),
    ('C', [12, 17.2, 0.8]),
  ]),
  WfIconDef('location', 'ตำแหน่ง', 'Location', 'location_on_outlined', [
    ('P', [12, 22, 5.5, 13, 5.5, 9, 8, 4.5, 12, 3, 16, 4.5, 18.5, 9, 18.5, 13]),
    ('C', [12, 9.5, 2.5]),
  ]),
  WfIconDef('camera', 'กล้อง', 'Camera', 'photo_camera_outlined', [
    ('P', [3, 8, 7, 8, 9, 5, 15, 5, 17, 8, 21, 8, 21, 19, 3, 19]),
    ('C', [12, 13.5, 3.5]),
  ]),
  WfIconDef('download', 'ดาวน์โหลด', 'Download', 'download', [
    ('L', [12, 4, 12, 15]),
    ('L', [7, 10, 12, 15, 17, 10]),
    ('L', [4, 19, 20, 19]),
  ]),
  WfIconDef('upload', 'อัปโหลด', 'Upload', 'upload', [
    ('L', [12, 15, 12, 4]),
    ('L', [7, 9, 12, 4, 17, 9]),
    ('L', [4, 19, 20, 19]),
  ]),
  WfIconDef('eye', 'ดู', 'View', 'visibility_outlined', [
    ('P', [2, 12, 7, 6.5, 12, 5, 17, 6.5, 22, 12, 17, 17.5, 12, 19, 7, 17.5]),
    ('C', [12, 12, 3]),
  ]),
  WfIconDef('share', 'แชร์', 'Share', 'share_outlined', [
    ('C', [6, 12, 2.5]),
    ('C', [18, 6, 2.5]),
    ('C', [18, 18, 2.5]),
    ('L', [8.2, 10.8, 15.8, 7.2]),
    ('L', [8.2, 13.2, 15.8, 16.8]),
  ]),
  WfIconDef('filter', 'ตัวกรอง', 'Filter', 'filter_list', [
    ('P', [3, 5, 21, 5, 14, 13, 14, 20, 10, 18, 10, 13]),
  ]),
];
