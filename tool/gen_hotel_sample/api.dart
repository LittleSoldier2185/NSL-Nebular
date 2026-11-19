import 'package:nsl_nebular/core/models/api_model.dart';

import 'er.dart' show c;
import 'process.dart' show kErDocId;

ApiTableRef _t(String table, [String? col]) => ApiTableRef(docId: kErDocId, tableId: table, columnId: col == null ? null : c(table, col));

ApiField _f(String id, String name, ApiType type, {bool req = false, ApiTableRef? col, String desc = ''}) =>
    ApiField(id: id, name: name, type: type, required: req, column: col, description: desc);

/// เอกสาร API: ผูกตาราง ER, ฟิลด์ผูกคอลัมน์, สิทธิ์ล็อกอิน, ตัวอย่าง response (ใช้กับ OpenAPI / Mock Server / Route ว่าง)
ApiDocument buildApi() {
  int n = 0;
  ApiEndpoint ep(
    String id,
    ApiMethod m,
    String path,
    String summary, {
    String group = '',
    bool auth = false,
    ApiTableRef? table,
    List<ApiField>? fields,
    List<ApiResponse>? responses,
  }) =>
      ApiEndpoint(id: id, method: m, path: path, summary: summary, group: group, auth: auth, table: table, fields: fields, responses: responses ?? [ApiResponse(status: m == ApiMethod.post ? 201 : 200)]);

  String id() => 'f${++n}';

  return ApiDocument(title: 'Hotel Booking API', version: '1.0.0', baseUrl: 'https://api.siam-residence.example/v1', endpoints: [
    // --- ผู้ใช้ ---
    ep('e_register', ApiMethod.post, '/auth/register', 'สมัครสมาชิก', group: 'auth', table: _t('users'), fields: [
      _f(id(), 'full_name', ApiType.string, req: true, col: _t('users', 'full_name')),
      _f(id(), 'email', ApiType.string, req: true, col: _t('users', 'email')),
      _f(id(), 'phone', ApiType.string, col: _t('users', 'phone')),
      _f(id(), 'password', ApiType.string, req: true, desc: 'อย่างน้อย 8 ตัวอักษร (เก็บเป็น password_hash)'),
    ], responses: [
      ApiResponse(status: 201, description: 'สมัครสำเร็จ', example: '{"id":3,"full_name":"สมหญิง รักดี","email":"somying@example.com","role":"guest"}'),
      ApiResponse(status: 409, description: 'อีเมลนี้ถูกใช้แล้ว', example: '{"error":"email_taken"}'),
      ApiResponse(status: 422, description: 'ข้อมูลไม่ถูกต้อง', example: '{"error":"validation_failed"}'),
    ]),
    ep('e_login', ApiMethod.post, '/auth/login', 'เข้าสู่ระบบ', group: 'auth', fields: [
      _f(id(), 'email', ApiType.string, req: true, col: _t('users', 'email')),
      _f(id(), 'password', ApiType.string, req: true),
    ], responses: [
      ApiResponse(status: 200, description: 'ได้โทเคน', example: '{"token":"demo-token","expires_in":3600}'),
      ApiResponse(status: 401, description: 'อีเมลหรือรหัสผ่านไม่ถูกต้อง', example: '{"error":"invalid_credentials"}'),
    ]),
    ep('e_me', ApiMethod.get, '/me', 'ข้อมูลของฉัน', group: 'auth', auth: true, table: _t('users'), responses: [
      ApiResponse(status: 200, example: '{"id":2,"full_name":"สมชาย ใจดี","role":"guest"}'),
      ApiResponse(status: 401, example: '{"error":"unauthorized"}'),
    ]),
    // --- แค็ตตาล็อกห้อง (สาธารณะ) ---
    ep('e_types_list', ApiMethod.get, '/room-types', 'รายการประเภทห้อง', group: 'catalog', table: _t('room_types')),
    ep('e_types_get', ApiMethod.get, '/room-types/{id}', 'รายละเอียดประเภทห้อง', group: 'catalog', table: _t('room_types'), responses: [
      ApiResponse(status: 200),
      ApiResponse(status: 404, example: '{"error":"not_found"}'),
    ]),
    ep('e_amenities', ApiMethod.get, '/amenities', 'รายการสิ่งอำนวยความสะดวก', group: 'catalog', table: _t('amenities')),
    ep('e_type_amenities', ApiMethod.get, '/room-types/{id}/amenities', 'สิ่งอำนวยความสะดวกของประเภทห้อง', group: 'catalog', table: _t('room_type_amenities')),
    ep('e_rooms_available', ApiMethod.get, '/rooms/available', 'ค้นหาห้องว่าง (check_in, check_out, guests เป็น query)', group: 'catalog', responses: [
      ApiResponse(status: 200, description: 'รายการห้องว่างพร้อมราคารวม', example: '[{"room_type_id":1,"name":"Standard","available":2,"price_per_night":1290.00},{"room_type_id":2,"name":"Deluxe","available":2,"price_per_night":1890.00}]'),
      ApiResponse(status: 422, example: '{"error":"invalid_dates"}'),
    ]),
    // --- จัดการห้อง (แอดมิน) ---
    ep('e_rooms_list', ApiMethod.get, '/admin/rooms', 'รายการห้องทั้งหมด', group: 'admin', auth: true, table: _t('rooms')),
    ep('e_rooms_create', ApiMethod.post, '/admin/rooms', 'เพิ่มห้อง', group: 'admin', auth: true, table: _t('rooms'), fields: [
      _f(id(), 'room_number', ApiType.string, req: true, col: _t('rooms', 'room_number')),
      _f(id(), 'room_type_id', ApiType.integer, req: true, col: _t('rooms', 'room_type_id')),
      _f(id(), 'floor', ApiType.integer, req: true, col: _t('rooms', 'floor')),
      _f(id(), 'status', ApiType.string, col: _t('rooms', 'status')),
    ]),
    ep('e_rooms_update', ApiMethod.put, '/admin/rooms/{id}', 'แก้ไขห้อง', group: 'admin', auth: true, table: _t('rooms'), fields: [
      _f(id(), 'room_number', ApiType.string, req: true, col: _t('rooms', 'room_number')),
      _f(id(), 'floor', ApiType.integer, col: _t('rooms', 'floor')),
      _f(id(), 'status', ApiType.string, col: _t('rooms', 'status')),
    ]),
    ep('e_rooms_delete', ApiMethod.delete, '/admin/rooms/{id}', 'ลบห้อง', group: 'admin', auth: true, table: _t('rooms'), responses: [ApiResponse(status: 204)]),
    ep('e_seasonal_list', ApiMethod.get, '/admin/seasonal-prices', 'ราคาตามฤดูกาล', group: 'admin', auth: true, table: _t('seasonal_prices')),
    ep('e_seasonal_create', ApiMethod.post, '/admin/seasonal-prices', 'ตั้งราคาตามฤดูกาล', group: 'admin', auth: true, table: _t('seasonal_prices'), fields: [
      _f(id(), 'room_type_id', ApiType.integer, req: true, col: _t('seasonal_prices', 'room_type_id')),
      _f(id(), 'start_date', ApiType.string, req: true, col: _t('seasonal_prices', 'start_date')),
      _f(id(), 'end_date', ApiType.string, req: true, col: _t('seasonal_prices', 'end_date')),
      _f(id(), 'multiplier', ApiType.number, req: true, col: _t('seasonal_prices', 'multiplier')),
    ]),
    ep('e_dashboard', ApiMethod.get, '/admin/dashboard', 'สรุปภาพรวมวันนี้', group: 'admin', auth: true, responses: [
      ApiResponse(status: 200, example: '{"occupancy_percent":72,"check_ins_today":5,"check_outs_today":3,"revenue_today":18450.00}'),
      ApiResponse(status: 401, example: '{"error":"unauthorized"}'),
    ]),
    // --- การจอง ---
    ep('e_booking_create', ApiMethod.post, '/bookings', 'สร้างการจอง', group: 'bookings', auth: true, table: _t('bookings'), fields: [
      _f(id(), 'room_id', ApiType.integer, req: true, col: _t('bookings', 'room_id')),
      _f(id(), 'check_in', ApiType.string, req: true, col: _t('bookings', 'check_in'), desc: 'YYYY-MM-DD'),
      _f(id(), 'check_out', ApiType.string, req: true, col: _t('bookings', 'check_out'), desc: 'YYYY-MM-DD'),
      _f(id(), 'guests', ApiType.integer, req: true, col: _t('bookings', 'guests')),
      _f(id(), 'total_price', ApiType.number, req: true, col: _t('bookings', 'total_price')),
      _f(id(), 'booking_code', ApiType.string, req: true, col: _t('bookings', 'booking_code')),
      _f(id(), 'user_id', ApiType.integer, req: true, col: _t('bookings', 'user_id')),
      _f(id(), 'note', ApiType.string, col: _t('bookings', 'note')),
    ], responses: [
      ApiResponse(status: 201, description: 'สร้างการจอง สถานะ pending'),
      ApiResponse(status: 401, example: '{"error":"unauthorized"}'),
      ApiResponse(status: 409, description: 'ห้องไม่ว่างในช่วงวันนี้', example: '{"error":"room_unavailable"}'),
      ApiResponse(status: 422, example: '{"error":"validation_failed"}'),
    ]),
    ep('e_booking_list', ApiMethod.get, '/bookings', 'การจองของฉัน', group: 'bookings', auth: true, table: _t('bookings')),
    ep('e_booking_get', ApiMethod.get, '/bookings/{id}', 'รายละเอียดการจอง', group: 'bookings', auth: true, table: _t('bookings'), responses: [
      ApiResponse(status: 200),
      ApiResponse(status: 404, example: '{"error":"not_found"}'),
    ]),
    ep('e_booking_cancel', ApiMethod.patch, '/bookings/{id}', 'ยกเลิกการจอง (ส่ง status = cancelled)', group: 'bookings', auth: true, table: _t('bookings'), fields: [
      _f(id(), 'status', ApiType.string, req: true, col: _t('bookings', 'status')),
    ]),
    // --- ชำระเงิน / รีวิว ---
    ep('e_pay_create', ApiMethod.post, '/payments', 'ชำระเงินของการจอง', group: 'payments', auth: true, table: _t('payments'), fields: [
      _f(id(), 'booking_id', ApiType.integer, req: true, col: _t('payments', 'booking_id')),
      _f(id(), 'amount', ApiType.number, req: true, col: _t('payments', 'amount')),
      _f(id(), 'method', ApiType.string, req: true, col: _t('payments', 'method'), desc: 'card | promptpay | transfer'),
    ], responses: [
      ApiResponse(status: 201, description: 'ชำระสำเร็จ'),
      ApiResponse(status: 402, description: 'ชำระไม่สำเร็จ', example: '{"error":"payment_declined"}'),
    ]),
    ep('e_pay_list', ApiMethod.get, '/payments', 'ประวัติการชำระเงิน', group: 'payments', auth: true, table: _t('payments')),
    ep('e_review_create', ApiMethod.post, '/reviews', 'เขียนรีวิว (หลังเข้าพัก)', group: 'reviews', auth: true, table: _t('reviews'), fields: [
      _f(id(), 'booking_id', ApiType.integer, req: true, col: _t('reviews', 'booking_id')),
      _f(id(), 'rating', ApiType.integer, req: true, col: _t('reviews', 'rating'), desc: '1–5'),
      _f(id(), 'comment', ApiType.string, col: _t('reviews', 'comment')),
    ], responses: [
      ApiResponse(status: 201),
      ApiResponse(status: 409, description: 'การจองนี้รีวิวแล้ว', example: '{"error":"already_reviewed"}'),
    ]),
    ep('e_review_list', ApiMethod.get, '/reviews', 'รีวิวทั้งหมด', group: 'reviews', table: _t('reviews')),
  ]);
}
