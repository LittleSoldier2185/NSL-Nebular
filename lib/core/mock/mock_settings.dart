/// สถานการณ์ที่เซิร์ฟเวอร์จำลองตอบต่อ endpoint
enum MockScenario {
  /// ทำงานตามสัญญา (ตรวจ request, จำข้อมูลที่ POST/PUT/DELETE ถ้าผูกตาราง ER)
  normal(null),

  /// ตอบ 409 Conflict เสมอ
  conflict(409),

  /// ตอบ 401 Unauthorized เสมอ
  unauthorized(401),

  /// ตอบ 500 เสมอ
  serverError(500),

  /// สุ่มต่อคำขอ: ปกติ 70% · 500 20% · 409 10%
  random(null);

  const MockScenario(this.status);

  /// รหัสที่บังคับตอบ (null = ไม่บังคับ)
  final int? status;
}

/// ค่าของ endpoint หนึ่งตัว: สถานการณ์ + หน่วงเวลา (มิลลิวินาที ; ใช้ได้กับทุกสถานการณ์)
class MockEndpointSetting {
  const MockEndpointSetting({this.scenario = MockScenario.normal, this.delayMs = 0});
  final MockScenario scenario;
  final int delayMs;

  bool get isDefault => scenario == MockScenario.normal && delayMs == 0;

  MockEndpointSetting copyWith({MockScenario? scenario, int? delayMs}) =>
      MockEndpointSetting(scenario: scenario ?? this.scenario, delayMs: delayMs ?? this.delayMs);

  Map<String, dynamic> toJson() => {
        if (scenario != MockScenario.normal) 's': scenario.name,
        if (delayMs > 0) 'delay': delayMs,
      };
}

const kMockMaxDelayMs = 30000;
const kMockDefaultPort = 8787;

/// ค่าตั้งของ Mock Server ที่เก็บในไฟล์โปรเจกต์ (`meta.mock`)
class MockSettings {
  const MockSettings({this.apiDocId, this.port = kMockDefaultPort, this.endpoints = const {}});

  /// เอกสาร API ที่ใช้ (null = เอกสาร API แรกของโปรเจกต์)
  final String? apiDocId;
  final int port;

  /// id endpoint -> ค่า (ไม่มี = ค่าเริ่มต้น)
  final Map<String, MockEndpointSetting> endpoints;

  MockEndpointSetting of(String endpointId) => endpoints[endpointId] ?? const MockEndpointSetting();

  MockSettings copyWith({String? apiDocId, int? port, Map<String, MockEndpointSetting>? endpoints}) =>
      MockSettings(apiDocId: apiDocId ?? this.apiDocId, port: port ?? this.port, endpoints: endpoints ?? this.endpoints);

  /// ตั้งค่าของ endpoint หนึ่งตัว (ค่าเริ่มต้น = เอาออก ไม่เก็บในไฟล์)
  MockSettings withEndpoint(String endpointId, MockEndpointSetting s) {
    final m = Map<String, MockEndpointSetting>.of(endpoints);
    if (s.isDefault) {
      m.remove(endpointId);
    } else {
      m[endpointId] = MockEndpointSetting(scenario: s.scenario, delayMs: s.delayMs.clamp(0, kMockMaxDelayMs));
    }
    return copyWith(endpoints: m);
  }

  Map<String, dynamic> toJson() => {
        if (apiDocId != null) 'api': apiDocId,
        'port': port,
        if (endpoints.isNotEmpty) 'endpoints': {for (final e in endpoints.entries) e.key: e.value.toJson()},
      };

  /// อ่านจาก JSON ; ข้อมูลเสียทีละรายการถูกข้าม (พอร์ตนอกช่วง = ค่าเริ่มต้น)
  factory MockSettings.fromJson(Object? j) {
    if (j is! Map) return const MockSettings();
    final p = j['port'];
    final eps = <String, MockEndpointSetting>{};
    final raw = j['endpoints'];
    if (raw is Map) {
      final byName = MockScenario.values.asNameMap();
      for (final e in raw.entries) {
        final v = e.value;
        if (e.key is! String || v is! Map) continue;
        final s = byName[v['s']] ?? MockScenario.normal;
        final d = v['delay'] is int ? (v['delay'] as int).clamp(0, kMockMaxDelayMs) : 0;
        final setting = MockEndpointSetting(scenario: s, delayMs: d);
        if (!setting.isDefault) eps[e.key as String] = setting;
      }
    }
    return MockSettings(
      apiDocId: j['api'] is String && (j['api'] as String).isNotEmpty ? j['api'] as String : null,
      port: p is int && p >= 0 && p <= 65535 ? p : kMockDefaultPort,
      endpoints: eps,
    );
  }
}
