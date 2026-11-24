import 'requirement.dart' show TraceLink;
import 'workspace.dart';

/// สถานะของ Use Case
enum UcStatus { draft, review, approved }

/// ความสำคัญของ Use Case
enum UcPriority { high, medium, low }

/// ใครเป็นคนทำขั้นตอนนั้น : ผู้ใช้ (ผู้กระทำ) หรือระบบ
enum UcWho { user, system }

/// ขั้นตอนหนึ่งของ flow หลัก ; [links] ชี้ไปเอกสาร/วัตถุที่ขั้นตอนนี้ใช้ (หน้าจอ, endpoint, ตาราง, Flowchart ฯลฯ)
class UcStep {
  UcStep({required this.id, this.who = UcWho.user, this.text = '', List<TraceLink>? links, Map<String, dynamic>? extra})
      : links = links ?? [],
        extra = extra ?? {};

  final String id;
  UcWho who;
  String text;
  final List<TraceLink> links;
  final Map<String, dynamic> extra;

  static const _keys = {'id', 'who', 'text', 'links'};

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'who': who.name,
        'text': text,
        if (links.isNotEmpty) 'links': [for (final l in links) l.toJson()],
      };

  static UcStep? tryFromJson(Object? j) {
    if (j is! Map || j['id'] is! String || (j['id'] as String).isEmpty) return null;
    final seen = <TraceLink>{};
    return UcStep(
      id: j['id'] as String,
      who: UcWho.values.asNameMap()[j['who']] ?? UcWho.user,
      text: j['text'] is String ? j['text'] as String : '',
      links: [
        for (final l in (j['links'] is List ? j['links'] as List : const []))
          if (TraceLink.tryFromJson(l) case final x? when seen.add(x)) x,
      ],
      extra: {
        for (final e in j.entries)
          if (e.key is String && !_keys.contains(e.key)) e.key as String: e.value,
      },
    );
  }
}

/// ทางเลือก (เกิดแล้วไปต่ออีกทาง) หรือข้อผิดพลาด ([exception]) ที่เกิดตอนขั้นตอน [atStepId]
/// ผลลัพธ์ต้องบอกว่า [ends] = จบ Use Case หรือ [returnStepId] = กลับไปขั้นนั้น (ไม่บอกเลย = ตัวตรวจเตือน)
class UcBranch {
  UcBranch({
    required this.id,
    this.atStepId,
    this.exception = false,
    this.condition = '',
    this.outcome = '',
    this.returnStepId,
    this.ends = false,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  final String id;
  String? atStepId;
  bool exception;

  /// เกิดเมื่อ… (เช่น "ห้องเต็มแล้ว")
  String condition;

  /// ระบบ/ผู้ใช้ทำอะไรต่อ
  String outcome;
  String? returnStepId;
  bool ends;
  final Map<String, dynamic> extra;

  static const _keys = {'id', 'at', 'ex', 'cond', 'out', 'ret', 'end'};

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        if (atStepId != null) 'at': atStepId,
        if (exception) 'ex': true,
        'cond': condition,
        'out': outcome,
        if (returnStepId != null) 'ret': returnStepId,
        if (ends) 'end': true,
      };

  static UcBranch? tryFromJson(Object? j) {
    if (j is! Map || j['id'] is! String || (j['id'] as String).isEmpty) return null;
    String? s(Object? v) => v is String && v.isNotEmpty ? v : null;
    return UcBranch(
      id: j['id'] as String,
      atStepId: s(j['at']),
      exception: j['ex'] == true,
      condition: j['cond'] is String ? j['cond'] as String : '',
      outcome: j['out'] is String ? j['out'] as String : '',
      returnStepId: s(j['ret']),
      ends: j['end'] == true,
      extra: {
        for (final e in j.entries)
          if (e.key is String && !_keys.contains(e.key)) e.key as String: e.value,
      },
    );
  }
}

/// ความสัมพันธ์ «extend» : Use Case นี้เป็นส่วนขยายของ Use Case ฐาน [baseId] ที่ทำงานเพิ่มเมื่อ [condition] เป็นจริง
/// (ลูกศรในแผนภาพชี้จากส่วนขยายไปที่ฐาน)
class UcExtend {
  UcExtend({required this.baseId, this.condition = '', Map<String, dynamic>? extra}) : extra = extra ?? {};

  String baseId;
  String condition;
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() => {...extra, 'base': baseId, if (condition.isNotEmpty) 'cond': condition};

  static UcExtend? tryFromJson(Object? j) {
    if (j is! Map || j['base'] is! String || (j['base'] as String).isEmpty) return null;
    return UcExtend(
      baseId: j['base'] as String,
      condition: j['cond'] is String ? j['cond'] as String : '',
      extra: {
        for (final e in j.entries)
          if (e.key is String && e.key != 'base' && e.key != 'cond') e.key as String: e.value,
      },
    );
  }
}

/// Use Case หนึ่งข้อ
class UseCase {
  UseCase({
    required this.id,
    this.code = '',
    this.name = '',
    this.actor = '',
    this.secondaryActor = '',
    this.priority = UcPriority.medium,
    this.status = UcStatus.draft,
    this.goal = '',
    this.trigger = '',
    this.preconditions = '',
    this.postconditions = '',
    List<UcStep>? steps,
    List<UcBranch>? branches,
    List<String>? reqIds,
    List<String>? includes,
    List<UcExtend>? extendsFrom,
    Map<String, dynamic>? extra,
  })  : steps = steps ?? [],
        branches = branches ?? [],
        reqIds = reqIds ?? [],
        includes = includes ?? [],
        extendsFrom = extendsFrom ?? [],
        extra = extra ?? {};

  final String id;

  /// รหัสที่แสดง เช่น UC-01
  String code;
  String name;

  /// ผู้กระทำหลัก (เช่น Guest) — ใช้จัดกลุ่มรายการและวาดแผนภาพ
  String actor;

  /// ผู้กระทำรอง/ระบบภายนอก (เช่น Payment Gateway) ; คั่นหลายตัวด้วยจุลภาค
  String secondaryActor;
  UcPriority priority;
  UcStatus status;
  String goal, trigger, preconditions, postconditions;
  final List<UcStep> steps;
  final List<UcBranch> branches;

  /// id ของความต้องการ (REQ) ที่ Use Case นี้ทำให้เป็นจริง
  final List<String> reqIds;

  /// id ของ Use Case อื่นที่ Use Case นี้เรียกใช้ (include)
  final List<String> includes;

  /// Use Case ฐานที่ข้อนี้ขยาย (extend) พร้อมเงื่อนไข — แผนภาพวาดลูกศร «extend» จากข้อนี้ไปที่ฐาน
  final List<UcExtend> extendsFrom;
  final Map<String, dynamic> extra;

  UcStep? stepById(String id) {
    for (final s in steps) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// ลำดับขั้นตอน (เริ่ม 1) ; ไม่พบ = 0
  int stepNumber(String id) => steps.indexWhere((s) => s.id == id) + 1;

  /// ป้ายของทางเลือก/ข้อผิดพลาด เช่น 2a, 2b (ทางเลือก) · 5x, 5y (ข้อผิดพลาด) ; ขั้นที่อ้างถึงไม่มี = "?a"
  String branchLabel(UcBranch b) {
    final n = b.atStepId == null ? 0 : stepNumber(b.atStepId!);
    final same = [for (final x in branches) if (x.atStepId == b.atStepId && x.exception == b.exception) x];
    final i = same.indexOf(b);
    final letter = b.exception ? 'xyz' : 'abcdefghijklmnopqrstuvw';
    final ch = i >= 0 && i < letter.length ? letter[i] : '${i + 1}';
    return '${n == 0 ? '?' : n}$ch';
  }

  /// ผู้กระทำรองแยกเป็นรายการ
  List<String> get secondaryActors => [for (final a in secondaryActor.split(',')) if (a.trim().isNotEmpty) a.trim()];

  static const _keys = {
    'id', 'code', 'name', 'actor', 'actor2', 'priority', 'status', 'goal', 'trigger', 'pre', 'post', 'steps', 'branches', 'reqs', 'includes', 'extends',
  };

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'code': code,
        'name': name,
        'actor': actor,
        if (secondaryActor.isNotEmpty) 'actor2': secondaryActor,
        'priority': priority.name,
        'status': status.name,
        if (goal.isNotEmpty) 'goal': goal,
        if (trigger.isNotEmpty) 'trigger': trigger,
        if (preconditions.isNotEmpty) 'pre': preconditions,
        if (postconditions.isNotEmpty) 'post': postconditions,
        if (steps.isNotEmpty) 'steps': [for (final s in steps) s.toJson()],
        if (branches.isNotEmpty) 'branches': [for (final b in branches) b.toJson()],
        if (reqIds.isNotEmpty) 'reqs': reqIds,
        if (includes.isNotEmpty) 'includes': includes,
        if (extendsFrom.isNotEmpty) 'extends': [for (final e in extendsFrom) e.toJson()],
      };

  static UseCase? tryFromJson(Object? j) {
    if (j is! Map || j['id'] is! String || (j['id'] as String).isEmpty) return null;
    String str(String k) => j[k] is String ? j[k] as String : '';
    List<String> ids(Object? v) {
      final seen = <String>{};
      return [
        if (v is List)
          for (final e in v)
            if (e is String && e.isNotEmpty && seen.add(e)) e,
      ];
    }

    final stepIds = <String>{}, branchIds = <String>{};
    return UseCase(
      id: j['id'] as String,
      code: str('code'),
      name: str('name'),
      actor: str('actor'),
      secondaryActor: str('actor2'),
      priority: UcPriority.values.asNameMap()[j['priority']] ?? UcPriority.medium,
      status: UcStatus.values.asNameMap()[j['status']] ?? UcStatus.draft,
      goal: str('goal'),
      trigger: str('trigger'),
      preconditions: str('pre'),
      postconditions: str('post'),
      steps: [
        for (final e in (j['steps'] is List ? j['steps'] as List : const []))
          if (UcStep.tryFromJson(e) case final s? when stepIds.add(s.id)) s,
      ],
      branches: [
        for (final e in (j['branches'] is List ? j['branches'] as List : const []))
          if (UcBranch.tryFromJson(e) case final b? when branchIds.add(b.id)) b,
      ],
      reqIds: ids(j['reqs']),
      includes: ids(j['includes']),
      extendsFrom: [
        for (final e in (j['extends'] is List ? j['extends'] as List : const []))
          ?UcExtend.tryFromJson(e),
      ],
      extra: {
        for (final e in j.entries)
          if (e.key is String && !_keys.contains(e.key)) e.key as String: e.value,
      },
    );
  }
}

/// อ่านรายการ Use Case (ข้อมูลเสียทีละข้อถูกข้าม ; id ซ้ำ = ใช้ตัวแรก)
List<UseCase> decodeUseCases(Object? j) {
  if (j is! List) return [];
  final ids = <String>{};
  return [
    for (final e in j)
      if (UseCase.tryFromJson(e) case final u? when ids.add(u.id)) u,
  ];
}

/// รหัสถัดไปแบบ UC-01, UC-02… (ต่อจากเลขสูงสุดที่มี)
String nextUseCaseCode(Workspace w) {
  var max = 0;
  for (final u in w.useCases) {
    final m = RegExp(r'(\d+)\s*$').firstMatch(u.code);
    final n = m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
    if (n > max) max = n;
  }
  return 'UC-${(max + 1).toString().padLeft(2, '0')}';
}

/// ลิงก์ของขั้นตอนยังใช้ได้ : เอกสารยังอยู่ และถ้าชี้วัตถุ วัตถุต้องยังอยู่
bool ucLinkValid(Workspace w, TraceLink l) {
  final d = w.documentById(l.docId);
  final t = d?.type;
  if (d == null || t == null) return false;
  final el = l.elementId;
  if (el == null) return true;
  return switch (t) {
    DocType.er => d.er!.tableById(el) != null,
    DocType.dfd => d.dfd!.nodeById(el) != null,
    DocType.flowchart => d.flowchart!.nodeById(el) != null,
    DocType.wireframe => d.wireframe!.componentById(el) != null,
    DocType.screenflow => d.screenflow!.nodeById(el) != null,
    DocType.api => d.api!.endpointById(el) != null,
  };
}
