// สร้างโดย NSL Nebular จากโปรเจกต์ "untitled" — ไม่มีวันที่เพื่อให้ diff ใน git อ่านง่าย

/** ลูกค้า */
export interface Customer {
  id: string;
  email: string;
  createdAt?: Date | null;
}

export interface Order {
  id: string;
  customerId: string; // → customers.id
  /** สถานะ */
  status: string;
  total?: number | null;
}
