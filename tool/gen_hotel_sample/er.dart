import 'package:nsl_nebular/core/models/check_model.dart';
import 'package:nsl_nebular/core/models/column_model.dart';
import 'package:nsl_nebular/core/models/enums.dart';
import 'package:nsl_nebular/core/models/group_model.dart';
import 'package:nsl_nebular/core/models/index_model.dart';
import 'package:nsl_nebular/core/models/note_model.dart';
import 'package:nsl_nebular/core/models/project.dart';
import 'package:nsl_nebular/core/models/relation_model.dart';
import 'package:nsl_nebular/core/models/table_model.dart';

/// รหัสคงที่ของตาราง/คอลัมน์ (อ่านง่าย ใช้อ้างจากเอกสารอื่น)
String c(String table, String col) => '${table}_$col';

ColumnModel _col(
  String table,
  String name,
  DataType type, {
  int? len,
  int? scale,
  bool pk = false,
  bool nn = false,
  bool uq = false,
  bool ai = false,
  String? def,
  String comment = '',
  List<String> allowed = const [],
}) =>
    ColumnModel(
      id: c(table, name),
      name: name,
      type: type,
      length: len,
      scale: scale,
      isPrimaryKey: pk,
      notNull: nn || pk,
      unique: uq,
      autoIncrement: ai,
      defaultValue: def,
      comment: comment,
      allowedValues: allowed,
    );

Map<String, String?> _row(String table, Map<String, String> values) => {for (final e in values.entries) c(table, e.key): e.value};

/// ER ของระบบจองห้องพัก (MySQL) — 9 ตาราง, FK ครบ, ข้อมูลตั้งต้น, ดัชนี, กลุ่ม, โน้ตบนแคนวาส
Project buildEr() {
  final p = Project(name: 'Hotel Booking', dialect: Dialect.mysql, boardWidth: 2400, boardHeight: 1500);

  final users = TableModel(id: 'users', name: 'users', comment: 'ผู้ใช้งาน (ผู้เข้าพักและแอดมิน)', x: 80, y: 90, width: 250, colorIndex: 1, columns: [
    _col('users', 'id', DataType.bigint, pk: true, ai: true),
    _col('users', 'full_name', DataType.varchar, len: 120, nn: true, comment: 'ชื่อ-นามสกุล'),
    _col('users', 'email', DataType.varchar, len: 190, nn: true, uq: true, comment: 'ใช้เข้าสู่ระบบ'),
    _col('users', 'phone', DataType.varchar, len: 30),
    _col('users', 'password_hash', DataType.varchar, len: 255, nn: true),
    _col('users', 'role', DataType.varchar, len: 20, nn: true, def: "'guest'", comment: 'guest | admin'),
    _col('users', 'created_at', DataType.timestamp, nn: true, def: 'CURRENT_TIMESTAMP'),
  ], seedRows: [
    _row('users', {'id': '1', 'full_name': 'ผู้ดูแลระบบ', 'email': 'admin@siam-residence.example', 'phone': '020000000', 'password_hash': r'$2y$10$exampleexampleexampleexampleexampleexampleexample', 'role': 'admin'}),
    _row('users', {'id': '2', 'full_name': 'สมชาย ใจดี', 'email': 'somchai@example.com', 'phone': '0812345678', 'password_hash': r'$2y$10$exampleexampleexampleexampleexampleexampleexample', 'role': 'guest'}),
  ]);

  final roomTypes = TableModel(id: 'room_types', name: 'room_types', comment: 'ประเภทห้องและราคาพื้นฐาน', x: 420, y: 90, width: 250, colorIndex: 2, columns: [
    _col('room_types', 'id', DataType.integer, pk: true, ai: true),
    _col('room_types', 'name', DataType.varchar, len: 80, nn: true, uq: true),
    _col('room_types', 'description', DataType.text),
    _col('room_types', 'capacity', DataType.smallint, nn: true, def: '2', comment: 'จำนวนผู้เข้าพักสูงสุด'),
    _col('room_types', 'bed_type', DataType.varchar, len: 40),
    _col('room_types', 'base_price', DataType.decimal, len: 10, scale: 2, nn: true, comment: 'ราคาต่อคืน (บาท)'),
  ], seedRows: [
    _row('room_types', {'id': '1', 'name': 'Standard', 'description': 'ห้องมาตรฐาน เตียงคู่ เหมาะกับคู่รัก', 'capacity': '2', 'bed_type': 'Queen', 'base_price': '1290.00'}),
    _row('room_types', {'id': '2', 'name': 'Deluxe', 'description': 'ห้องกว้างขึ้น วิวเมือง พร้อมโซฟา', 'capacity': '3', 'bed_type': 'King', 'base_price': '1890.00'}),
    _row('room_types', {'id': '3', 'name': 'Family Suite', 'description': 'สองห้องนอน เหมาะกับครอบครัว', 'capacity': '5', 'bed_type': 'King + Twin', 'base_price': '3290.00'}),
    _row('room_types', {'id': '4', 'name': 'Executive Suite', 'description': 'สวีทชั้นบน ห้องนั่งเล่นแยก', 'capacity': '2', 'bed_type': 'King', 'base_price': '4590.00'}),
  ]);

  final rooms = TableModel(id: 'rooms', name: 'rooms', comment: 'ห้องจริงแต่ละห้อง', x: 760, y: 90, width: 250, colorIndex: 2, columns: [
    _col('rooms', 'id', DataType.integer, pk: true, ai: true),
    _col('rooms', 'room_number', DataType.varchar, len: 10, nn: true, uq: true),
    _col('rooms', 'room_type_id', DataType.integer, nn: true),
    _col('rooms', 'floor', DataType.smallint, nn: true),
    _col('rooms', 'status', DataType.varchar, len: 20, nn: true, def: "'available'", comment: 'สถานะห้อง', allowed: ['available', 'maintenance']),
  ], seedRows: [
    for (final r in const [
      ['1', '101', '1', '1'],
      ['2', '102', '1', '1'],
      ['3', '201', '2', '2'],
      ['4', '202', '2', '2'],
      ['5', '301', '3', '3'],
      ['6', '302', '3', '3'],
      ['7', '401', '4', '4'],
    ])
      _row('rooms', {'id': r[0], 'room_number': r[1], 'room_type_id': r[2], 'floor': r[3], 'status': 'available'}),
  ]);

  final amenities = TableModel(id: 'amenities', name: 'amenities', comment: 'สิ่งอำนวยความสะดวก', x: 1100, y: 90, width: 230, columns: [
    _col('amenities', 'id', DataType.integer, pk: true, ai: true),
    _col('amenities', 'name', DataType.varchar, len: 80, nn: true, uq: true),
    _col('amenities', 'icon', DataType.varchar, len: 40),
  ], seedRows: [
    for (final r in const [
      ['1', 'Wi-Fi ฟรี', 'wifi'],
      ['2', 'อาหารเช้า', 'breakfast'],
      ['3', 'สระว่ายน้ำ', 'pool'],
      ['4', 'ที่จอดรถ', 'parking'],
      ['5', 'เครื่องปรับอากาศ', 'ac'],
      ['6', 'อ่างอาบน้ำ', 'bathtub'],
    ])
      _row('amenities', {'id': r[0], 'name': r[1], 'icon': r[2]}),
  ]);

  final rta = TableModel(id: 'room_type_amenities', name: 'room_type_amenities', comment: 'ประเภทห้อง ↔ สิ่งอำนวยความสะดวก (หลายต่อหลาย)', x: 1100, y: 330, width: 260, columns: [
    _col('room_type_amenities', 'room_type_id', DataType.integer, pk: true),
    _col('room_type_amenities', 'amenity_id', DataType.integer, pk: true),
  ], seedRows: [
    for (final r in const [
      ['1', '1'], ['1', '5'], ['2', '1'], ['2', '2'], ['2', '5'], ['3', '1'], ['3', '2'], ['3', '3'], ['3', '5'], ['4', '1'], ['4', '2'], ['4', '3'], ['4', '5'], ['4', '6'],
    ])
      _row('room_type_amenities', {'room_type_id': r[0], 'amenity_id': r[1]}),
  ]);

  final seasonal = TableModel(id: 'seasonal_prices', name: 'seasonal_prices', comment: 'ราคาตามฤดูกาล (คูณราคาพื้นฐาน)', x: 420, y: 430, width: 250, columns: [
    _col('seasonal_prices', 'id', DataType.integer, pk: true, ai: true),
    _col('seasonal_prices', 'room_type_id', DataType.integer, nn: true),
    _col('seasonal_prices', 'start_date', DataType.date, nn: true),
    _col('seasonal_prices', 'end_date', DataType.date, nn: true),
    _col('seasonal_prices', 'multiplier', DataType.decimal, len: 4, scale: 2, nn: true, def: '1.00'),
  ], seedRows: [
    _row('seasonal_prices', {'id': '1', 'room_type_id': '1', 'start_date': '2026-12-20', 'end_date': '2027-01-05', 'multiplier': '1.50'}),
    _row('seasonal_prices', {'id': '2', 'room_type_id': '2', 'start_date': '2026-12-20', 'end_date': '2027-01-05', 'multiplier': '1.50'}),
  ]);

  final bookings = TableModel(id: 'bookings', name: 'bookings', comment: 'การจองห้อง (ดัชนี room+วันที่ ช่วยค้นหา แต่ไม่ได้กันการจองซ้อนทับ — ต้องตรวจในระบบ)', x: 80, y: 560, width: 270, colorIndex: 3, columns: [
    _col('bookings', 'id', DataType.bigint, pk: true, ai: true),
    _col('bookings', 'booking_code', DataType.varchar, len: 20, nn: true, uq: true, comment: 'รหัสที่แสดงให้ลูกค้า'),
    _col('bookings', 'user_id', DataType.bigint, nn: true),
    _col('bookings', 'room_id', DataType.integer, nn: true),
    _col('bookings', 'check_in', DataType.date, nn: true),
    _col('bookings', 'check_out', DataType.date, nn: true),
    _col('bookings', 'guests', DataType.smallint, nn: true, def: '1'),
    _col('bookings', 'total_price', DataType.decimal, len: 10, scale: 2, nn: true),
    _col('bookings', 'status', DataType.varchar, len: 20, nn: true, def: "'pending'", comment: 'สถานะการจอง', allowed: ['pending', 'confirmed', 'cancelled', 'completed']),
    _col('bookings', 'note', DataType.text),
    _col('bookings', 'created_at', DataType.timestamp, nn: true, def: 'CURRENT_TIMESTAMP'),
  ])
    ..checks.addAll([
      CheckModel(id: 'chk_bookings_dates', name: 'chk_bookings_dates', expr: 'check_out > check_in'),
      CheckModel(id: 'chk_bookings_total', name: 'chk_bookings_total', expr: 'total_price >= 0'),
    ])
    ..indexes.add(IndexModel(id: 'idx_bookings_room_dates', name: 'idx_bookings_room_dates', columnIds: [c('bookings', 'room_id'), c('bookings', 'check_in'), c('bookings', 'check_out')]));

  final payments = TableModel(id: 'payments', name: 'payments', comment: 'การชำระเงิน', x: 480, y: 800, width: 260, colorIndex: 3, columns: [
    _col('payments', 'id', DataType.bigint, pk: true, ai: true),
    _col('payments', 'booking_id', DataType.bigint, nn: true),
    _col('payments', 'amount', DataType.decimal, len: 10, scale: 2, nn: true),
    _col('payments', 'method', DataType.varchar, len: 30, nn: true, comment: 'วิธีชำระเงิน', allowed: ['card', 'promptpay', 'transfer']),
    _col('payments', 'status', DataType.varchar, len: 20, nn: true, def: "'pending'", allowed: ['pending', 'paid', 'failed', 'refunded']),
    _col('payments', 'transaction_ref', DataType.varchar, len: 80, uq: true),
    _col('payments', 'paid_at', DataType.timestamp),
    _col('payments', 'created_at', DataType.timestamp, nn: true, def: 'CURRENT_TIMESTAMP'),
  ])
    ..checks.add(CheckModel(id: 'chk_payments_amount', name: 'chk_payments_amount', expr: 'amount >= 0'));

  final reviews = TableModel(id: 'reviews', name: 'reviews', comment: 'รีวิวหลังเข้าพัก (1 การจอง = 1 รีวิว)', x: 860, y: 640, width: 250, columns: [
    _col('reviews', 'id', DataType.bigint, pk: true, ai: true),
    _col('reviews', 'booking_id', DataType.bigint, nn: true, uq: true),
    _col('reviews', 'rating', DataType.smallint, nn: true, comment: '1–5'),
    _col('reviews', 'comment', DataType.text),
    _col('reviews', 'created_at', DataType.timestamp, nn: true, def: 'CURRENT_TIMESTAMP'),
  ]);

  p.tables.addAll([users, roomTypes, rooms, amenities, rta, seasonal, bookings, payments, reviews]);

  // ดัชนีของคอลัมน์ FK ที่ยังไม่ขึ้นต้นดัชนีอื่น
  void idx(TableModel t, String col) => t.indexes.add(IndexModel(id: 'idx_${t.id}_$col', name: 'idx_${t.id}_$col', columnIds: [c(t.id, col)]));
  idx(rooms, 'room_type_id');
  idx(rta, 'amenity_id');
  idx(seasonal, 'room_type_id');
  idx(bookings, 'user_id');
  idx(payments, 'booking_id');

  int n = 0;
  void fk(String from, String fromCol, String to, String toCol, {RefAction del = RefAction.restrict, RefAction upd = RefAction.noAction}) {
    p.relations.add(RelationModel(
      id: 'fk_${++n}',
      fromTableId: from,
      fromColumnId: c(from, fromCol),
      toTableId: to,
      toColumnId: c(to, toCol),
      onDelete: del,
      onUpdate: upd,
    ));
  }

  fk('rooms', 'room_type_id', 'room_types', 'id');
  fk('room_type_amenities', 'room_type_id', 'room_types', 'id', del: RefAction.cascade);
  fk('room_type_amenities', 'amenity_id', 'amenities', 'id', del: RefAction.cascade);
  fk('seasonal_prices', 'room_type_id', 'room_types', 'id', del: RefAction.cascade);
  fk('bookings', 'user_id', 'users', 'id');
  fk('bookings', 'room_id', 'rooms', 'id');
  fk('payments', 'booking_id', 'bookings', 'id', del: RefAction.cascade);
  fk('reviews', 'booking_id', 'bookings', 'id', del: RefAction.cascade);

  p.groups.addAll([
    GroupModel(id: 'g_catalog', name: 'แค็ตตาล็อกห้อง', x: 400, y: 50, width: 640, height: 340, colorIndex: 2),
    GroupModel(id: 'g_booking', name: 'การจองและการเงิน', x: 50, y: 520, width: 1100, height: 440, colorIndex: 3),
  ]);

  p.notes.add(NoteModel(
    id: 'note_overlap',
    text: 'กันจองซ้อน: ตรวจ bookings ที่ room_id เดียวกันและช่วงวันทับกัน (status ≠ cancelled) ก่อนสร้างการจองใหม่ — ใช้ idx_bookings_room_dates',
    x: 1180,
    y: 560,
    width: 260,
  ));
  return p;
}
