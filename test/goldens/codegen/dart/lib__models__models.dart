// สร้างโดย NSL Nebular จากโปรเจกต์ "untitled" — ไม่มีวันที่เพื่อให้ diff ใน git อ่านง่าย

/// ลูกค้า
class Customer {
  const Customer({
    required this.id,
    required this.email,
    this.createdAt,
  });

  final int id;
  final String email;
  final DateTime? createdAt;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'] as int,
        email: json['email'] as String,
        createdAt: json['created_at'] == null ? null : DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'created_at': createdAt?.toIso8601String(),
      };
}

class Order {
  const Order({
    required this.id,
    required this.customerId,
    required this.status,
    this.total,
  });

  final int id;
  final int customerId;
  /// สถานะ
  final String status;
  final double? total;

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as int,
        customerId: json['customer_id'] as int,
        status: json['status'] as String,
        total: (json['total'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer_id': customerId,
        'status': status,
        'total': total,
      };
}
