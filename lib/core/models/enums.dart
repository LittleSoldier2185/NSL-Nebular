/// Dialect ที่รองรับ
enum Dialect {
  mysql('MySQL / MariaDB'),
  postgres('PostgreSQL'),
  sqlite('SQLite'),
  mssql('SQL Server');

  const Dialect(this.label);
  final String label;
}

/// ชนิดข้อมูลกลาง (แมปเป็นชนิดจริงของแต่ละ dialect ในเฟส 2)
enum DataType {
  integer,
  bigint,
  smallint,
  varchar,
  text,
  decimal,
  float,
  boolean,
  date,
  datetime,
  timestamp,
  blob,
  uuid,
  json,
}

enum RefAction {
  noAction('NO ACTION'),
  cascade('CASCADE'),
  restrict('RESTRICT'),
  setNull('SET NULL');

  const RefAction(this.sql);
  final String sql;
}

/// ฝั่งแม่ของความสัมพันธ์ ER ที่ผู้ใช้กำหนดเอง (ไม่กำหนด = อนุมานจาก FK: NOT NULL/PK = [one] ไม่งั้น [zeroOne])
/// เป็นเอกสารล้วน ไม่มีผลกับ DDL
enum ParentCard { zeroOne, one }

/// ฝั่งลูก "จำนวน" ที่ผู้ใช้กำหนดเอง (ไม่กำหนด = อนุมาน: FK เป็น UNIQUE เดี่ยว/PK เดี่ยว = [one] ไม่งั้น [many])
enum ChildMax { one, many }

/// ฝั่งลูก "ขั้นต่ำ" ที่ผู้ใช้กำหนดเอง (ไม่กำหนด = [zero]) — [one] = แถวแม่ต้องมีลูกอย่างน้อย 1 (ฐานข้อมูลบังคับด้วย FK ไม่ได้)
enum ChildMin { zero, one }
