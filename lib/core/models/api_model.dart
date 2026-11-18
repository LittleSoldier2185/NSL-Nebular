import 'column_model.dart';
import 'enums.dart';
import 'workspace.dart';

/// HTTP method ของ endpoint
enum ApiMethod { get, post, put, patch, delete }

extension ApiMethodText on ApiMethod {
  String get label => name.toUpperCase();

  /// method ที่ปกติมี request body
  bool get hasBody => this == ApiMethod.post || this == ApiMethod.put || this == ApiMethod.patch;
}

/// ชนิดข้อมูลของฟิลด์ (ชุดเดียวกับ JSON Schema / OpenAPI)
enum ApiType { string, integer, number, boolean, array, object }

/// อ้างอิงตาราง (และคอลัมน์) ในเอกสาร ER
class ApiTableRef {
  const ApiTableRef({required this.docId, required this.tableId, this.columnId});
  final String docId;
  final String tableId;
  final String? columnId;

  Map<String, dynamic> toJson() => {'doc': docId, 'table': tableId, if (columnId != null) 'column': columnId};

  static ApiTableRef? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final d = j['doc'], t = j['table'], c = j['column'];
    if (d is! String || d.isEmpty || t is! String || t.isEmpty) return null;
    return ApiTableRef(docId: d, tableId: t, columnId: c is String && c.isNotEmpty ? c : null);
  }

  @override
  bool operator ==(Object other) => other is ApiTableRef && other.docId == docId && other.tableId == tableId && other.columnId == columnId;

  @override
  int get hashCode => Object.hash(docId, tableId, columnId);
}

/// ฟิลด์หนึ่งของ request body
class ApiField {
  ApiField({required this.id, this.name = '', this.type = ApiType.string, this.required = false, this.column, this.description = ''});

  final String id;
  String name;
  ApiType type;
  bool required;

  /// คอลัมน์ ER ที่ฟิลด์นี้มาจาก ; null = กำหนดเอง
  ApiTableRef? column;
  String description;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        if (required) 'required': true,
        if (column != null) 'column': column!.toJson(),
        if (description.isNotEmpty) 'description': description,
      };

  static ApiField? tryFromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return ApiField(
      id: j['id'] as String,
      name: j['name'] is String ? j['name'] as String : '',
      type: ApiType.values.asNameMap()[j['type']] ?? ApiType.string,
      required: j['required'] == true,
      column: ApiTableRef.tryFromJson(j['column']),
      description: j['description'] is String ? j['description'] as String : '',
    );
  }
}

/// คำตอบหนึ่งแบบของ endpoint
class ApiResponse {
  ApiResponse({required this.status, this.description = '', this.example = ''});
  int status;
  String description;

  /// ตัวอย่าง body (ข้อความ JSON ; ว่าง = ไม่มีตัวอย่าง)
  String example;

  Map<String, dynamic> toJson() => {
        'status': status,
        if (description.isNotEmpty) 'description': description,
        if (example.isNotEmpty) 'example': example,
      };

  static ApiResponse? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final s = j['status'];
    if (s is! int || s < 100 || s > 599) return null;
    return ApiResponse(
      status: s,
      description: j['description'] is String ? j['description'] as String : '',
      example: j['example'] is String ? j['example'] as String : '',
    );
  }
}

class ApiEndpoint {
  ApiEndpoint({
    required this.id,
    this.method = ApiMethod.get,
    this.path = '/',
    this.summary = '',
    this.group = '',
    this.auth = false,
    this.table,
    List<ApiField>? fields,
    List<ApiResponse>? responses,
  })  : fields = fields ?? [],
        responses = responses ?? [];

  final String id;
  ApiMethod method;

  /// path เช่น `/orders/{id}`
  String path;
  String summary;

  /// กลุ่ม (tag) ; ว่าง = ใช้ส่วนแรกของ path
  String group;

  /// ต้องล็อกอิน
  bool auth;

  /// ตาราง ER ที่ endpoint นี้ทำงานด้วย ; null = ไม่ผูก
  ApiTableRef? table;
  final List<ApiField> fields;
  final List<ApiResponse> responses;

  /// กลุ่มที่ใช้แสดง: [group] หรือส่วนแรกของ path (`/orders/{id}` → `orders`)
  String get effectiveGroup {
    if (group.trim().isNotEmpty) return group.trim();
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    return seg.isEmpty ? '' : seg.first;
  }

  /// ชื่อพารามิเตอร์ใน path (`{id}`)
  List<String> get pathParams => [for (final m in RegExp(r'\{([^}/]+)\}').allMatches(path)) m.group(1)!];

  String get title => '${method.label} $path';

  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method.name,
        'path': path,
        if (summary.isNotEmpty) 'summary': summary,
        if (group.isNotEmpty) 'group': group,
        if (auth) 'auth': true,
        if (table != null) 'table': table!.toJson(),
        'fields': [for (final f in fields) f.toJson()],
        'responses': [for (final r in responses) r.toJson()],
      };

  static ApiEndpoint? tryFromJson(Object? j) {
    if (j is! Map || j['id'] is! String || (j['id'] as String).isEmpty) return null;
    final ids = <String>{};
    return ApiEndpoint(
      id: j['id'] as String,
      method: ApiMethod.values.asNameMap()[j['method']] ?? ApiMethod.get,
      path: j['path'] is String ? j['path'] as String : '/',
      summary: j['summary'] is String ? j['summary'] as String : '',
      group: j['group'] is String ? j['group'] as String : '',
      auth: j['auth'] == true,
      table: ApiTableRef.tryFromJson(j['table']),
      fields: [
        for (final f in (j['fields'] is List ? j['fields'] as List : const []))
          if (ApiField.tryFromJson(f) case final x? when ids.add(x.id)) x,
      ],
      responses: [
        for (final r in (j['responses'] is List ? j['responses'] as List : const []))
          ?ApiResponse.tryFromJson(r),
      ],
    );
  }
}

/// เอกสาร API (ชนิดในไฟล์ `api`): ชื่อ/รุ่นของ API + รายการ endpoint
class ApiDocument implements DocContent {
  ApiDocument({this.title = '', this.version = '1.0.0', this.baseUrl = '', List<ApiEndpoint>? endpoints}) : endpoints = endpoints ?? [];

  String title;
  String version;
  String baseUrl;
  final List<ApiEndpoint> endpoints;

  ApiEndpoint? endpointById(String id) {
    for (final e in endpoints) {
      if (e.id == id) return e;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        if (title.isNotEmpty) 'title': title,
        'version': version,
        if (baseUrl.isNotEmpty) 'baseUrl': baseUrl,
        'endpoints': [for (final e in endpoints) e.toJson()],
      };

  @override
  Map<String, dynamic> toContentJson() => toJson();

  /// อ่านเนื้อหา ; ข้อมูลเสียทีละรายการถูกข้าม (id endpoint ซ้ำ = ใช้ตัวแรก)
  factory ApiDocument.fromJson(Object? j) {
    if (j is! Map) return ApiDocument();
    final ids = <String>{};
    return ApiDocument(
      title: j['title'] is String ? j['title'] as String : '',
      version: j['version'] is String ? j['version'] as String : '1.0.0',
      baseUrl: j['baseUrl'] is String ? j['baseUrl'] as String : '',
      endpoints: [
        for (final e in (j['endpoints'] is List ? j['endpoints'] as List : const []))
          if (ApiEndpoint.tryFromJson(e) case final x? when ids.add(x.id)) x,
      ],
    );
  }
}

/// ชนิดฟิลด์ API ที่ตรงกับชนิดคอลัมน์ ER
ApiType apiTypeOfColumn(ColumnModel c) => switch (c.type) {
      DataType.integer || DataType.bigint || DataType.smallint => ApiType.integer,
      DataType.decimal || DataType.float => ApiType.number,
      DataType.boolean => ApiType.boolean,
      DataType.json => ApiType.object,
      _ => ApiType.string,
    };

