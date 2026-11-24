import '../l10n/l10n.dart';
import '../models/use_case.dart';
import '../models/workspace.dart';
import 'issue.dart' show Severity;

/// ผลตรวจของ Use Case ; [ucId] = null คือปัญหาระดับโปรเจกต์ (เช่น ความต้องการที่ไม่มี Use Case) ; [reqId] ใช้กับปัญหาของความต้องการ
class UcIssue {
  const UcIssue({required this.code, required this.severity, required this.title, required this.detail, this.ucId, this.stepId, this.reqId});
  final String code;
  final Severity severity;
  final String title, detail;
  final String? ucId, stepId, reqId;
}

/// ตรวจ Use Case ทั้งโปรเจกต์ (เรียงตามลำดับ Use Case แล้วปัญหาระดับโปรเจกต์ต่อท้าย)
List<UcIssue> validateUseCases(Workspace w) {
  final out = <UcIssue>[];
  final ids = {for (final u in w.useCases) u.id};
  final reqIds = {for (final r in w.requirements) r.id};
  for (final u in w.useCases) {
    final label = u.name.trim().isEmpty ? u.code : '${u.code} ${u.name.trim()}';
    void add(String code, Severity s, String title, String detail, {String? stepId}) =>
        out.add(UcIssue(code: code, severity: s, title: title, detail: detail, ucId: u.id, stepId: stepId));

    if (u.name.trim().isEmpty) add('uc_no_name', Severity.error, tr('Use Case ยังไม่มีชื่อ'), label);
    if (u.actor.trim().isEmpty) add('uc_no_actor', Severity.error, tr('ยังไม่ระบุผู้กระทำหลัก'), label);
    if (u.steps.isEmpty) {
      add('uc_no_steps', Severity.warning, tr('ยังไม่มีขั้นตอนหลัก'), label);
    } else if (u.steps.every((s) => s.text.trim().isEmpty)) {
      add('uc_empty_steps', Severity.warning, tr('ขั้นตอนทุกข้อยังว่างอยู่'), label);
    }
    if (u.reqIds.where(reqIds.contains).isEmpty && w.requirements.isNotEmpty) {
      add('uc_no_req', Severity.warning, tr('ยังไม่ผูกกับความต้องการข้อใด'), tr('ผูกเพื่อให้ความครอบคลุมของความต้องการนับ Use Case นี้'));
    }
    for (final r in u.reqIds) {
      if (!reqIds.contains(r)) add('uc_req_missing', Severity.warning, tr('ผูกกับความต้องการที่ถูกลบไปแล้ว'), label);
    }
    for (final i in u.includes) {
      if (i == u.id) {
        add('uc_include_self', Severity.error, tr('เรียกใช้ตัวเอง'), label);
      } else if (!ids.contains(i)) {
        add('uc_include_missing', Severity.error, tr('เรียกใช้ Use Case ที่ไม่มีอยู่แล้ว'), label);
      }
    }
    for (final (i, s) in u.steps.indexed) {
      for (final l in s.links) {
        if (!ucLinkValid(w, l)) {
          add('uc_link_broken', Severity.warning, tr('ขั้นที่ {0} ลิงก์ไปเอกสารหรือวัตถุที่ถูกลบแล้ว', [i + 1]), label, stepId: s.id);
        }
      }
    }
    for (final b in u.branches) {
      final tag = u.branchLabel(b);
      if (b.atStepId == null || u.stepById(b.atStepId!) == null) {
        add('uc_branch_step_missing', Severity.error, tr('{0} อ้างถึงขั้นตอนที่ไม่มีแล้ว', [tag]), label);
      }
      if (b.condition.trim().isEmpty) add('uc_branch_no_condition', Severity.warning, tr('{0} ยังไม่ระบุเงื่อนไข', [tag]), label);
      if (b.returnStepId != null && u.stepById(b.returnStepId!) == null) {
        add('uc_branch_return_missing', Severity.error, tr('{0} กลับไปยังขั้นตอนที่ไม่มีแล้ว', [tag]), label);
      } else if (b.returnStepId == null && !b.ends) {
        add('uc_branch_no_target', Severity.error, tr('{0} ไม่บอกว่าจบหรือกลับไปขั้นไหน', [tag]), tr('ทางเลือกต้องจบ Use Case หรือกลับไปขั้นตอนหนึ่ง'));
      }
    }
  }
  // ความต้องการที่ยังไม่มี Use Case (เฉพาะเมื่อมี Use Case อย่างน้อยหนึ่งข้อ — ยังไม่เริ่มเขียนก็ไม่ต้องเตือนทุกข้อ)
  if (w.useCases.isNotEmpty) {
    final covered = {for (final u in w.useCases) ...u.reqIds};
    for (final r in w.requirements) {
      if (!covered.contains(r.id)) {
        out.add(UcIssue(
          code: 'req_no_usecase',
          severity: Severity.warning,
          title: tr('{0} ยังไม่มี Use Case', [r.code]),
          detail: r.text.trim(),
          reqId: r.id,
        ));
      }
    }
  }
  return out;
}

/// สรุปความครอบคลุมของความต้องการ (จำนวนข้อที่มี Use Case อย่างน้อยหนึ่งข้อ)
({int covered, int total}) useCaseCoverage(Workspace w) {
  final covered = {for (final u in w.useCases) ...u.reqIds};
  return (covered: w.requirements.where((r) => covered.contains(r.id)).length, total: w.requirements.length);
}
