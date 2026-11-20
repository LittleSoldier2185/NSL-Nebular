import 'enums.dart';

class ColumnModel {
  ColumnModel({
    required this.id,
    required this.name,
    this.type = DataType.integer,
    this.length,
    this.scale,
    this.isPrimaryKey = false,
    this.notNull = false,
    this.unique = false,
    this.autoIncrement = false,
    this.defaultValue,
    this.comment = '',
    List<String>? allowedValues,
  }) : allowedValues = allowedValues ?? [];

  String id;
  String name;
  DataType type;

  /// ความยาว (varchar) หรือ precision (decimal)
  int? length;

  /// จำนวนหลักทศนิยม (decimal)
  int? scale;
  bool isPrimaryKey;
  bool notNull;
  bool unique;
  bool autoIncrement;
  String? defaultValue;
  String comment;

  /// ค่าที่อนุญาต (Phase 19) — ว่าง = รับค่าอะไรก็ได้ ; ใช้ได้กับ varchar/text ([supportsAllowedValues]) ; MySQL/MariaDB = ENUM(...), dialect อื่น = CHECK (col IN (...))
  List<String> allowedValues;

  /// ชนิดที่กำหนดค่าที่อนุญาตได้
  static bool supportsAllowedValues(DataType t) => t == DataType.varchar || t == DataType.text;

  /// มีค่าที่อนุญาตที่ใช้งานได้จริง (ไม่ว่าง และชนิดรองรับ)
  bool get hasAllowedValues => allowedValues.isNotEmpty && supportsAllowedValues(type);

  ColumnModel copy() => ColumnModel.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        if (length != null) 'length': length,
        if (scale != null) 'scale': scale,
        'pk': isPrimaryKey,
        'notNull': notNull,
        'unique': unique,
        'autoIncrement': autoIncrement,
        if (defaultValue != null) 'default': defaultValue,
        if (comment.isNotEmpty) 'comment': comment,
        if (allowedValues.isNotEmpty) 'allowed': allowedValues,
      };

  factory ColumnModel.fromJson(Map<String, dynamic> j) => ColumnModel(
        id: j['id'] as String,
        name: j['name'] as String,
        type: DataType.values.byName(j['type'] as String),
        length: j['length'] as int?,
        scale: j['scale'] as int?,
        isPrimaryKey: j['pk'] as bool? ?? false,
        notNull: j['notNull'] as bool? ?? false,
        unique: j['unique'] as bool? ?? false,
        autoIncrement: j['autoIncrement'] as bool? ?? false,
        defaultValue: j['default'] as String?,
        comment: j['comment'] as String? ?? '',
        allowedValues: [
          for (final v in (j['allowed'] is List ? j['allowed'] as List : const []))
            if (v is String) v,
        ],
      );
}
