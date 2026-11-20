import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_info.dart';
import '../core/l10n/l10n.dart';
import '../core/models/workspace.dart';
import '../core/validate/issue.dart';
import '../state/app_settings.dart';
import '../state/mock_controller.dart';
import '../state/project_controller.dart';
import '../state/workspace_controller.dart';
import 'app_actions.dart';
import '../state/dfd_controller.dart';
import '../state/flowchart_controller.dart';
import '../state/screenflow_controller.dart';
import '../state/wireframe_controller.dart';
import 'canvas/canvas_controller.dart';
import 'file_actions.dart';
import 'line_settings_dialog.dart';
import 'palette/command_palette.dart';
import 'search_launcher.dart';
import 'shortcuts.dart';
import 'whats_new_dialog.dart';
import 'theme.dart';
import 'theme_dialog.dart';
import 'window_chrome.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProjectController>();
    final w = context.watch<WorkspaceController>();

    // ใช้แถบของแอปเป็นแถบชื่อหน้าต่าง: ลากพื้นที่ว่างเพื่อย้ายหน้าต่าง ปุ่มควบคุมชิดมุมขวา
    final controls = WindowChrome.customControls;
    final isEr = w.activeDocument.type == DocType.er;
    return Container(
      height: 52,
      padding: EdgeInsets.only(
        left: 16 + WindowChrome.leadingInset,
        right: controls ? 0 : 16,
      ),
      decoration: BoxDecoration(
        color: C.barBg, // แถบบนพื้นเข้ม (Phase 17)
        border: Border(bottom: BorderSide(color: C.border)),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: C.onBar),
        child: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            // โลโก้แอป (ไฟล์เดียวกับไอคอนของโปรแกรม)
            Image.asset(
              'assets/icon/app_icon.png',
              key: const ValueKey('app-logo'),
              width: 34,
              height: 34,
              filterQuality: FilterQuality.medium,
            ),
            // หน้าต่างแคบ: ตัดชื่อโปรแกรมออกก่อน (เหลือโลโก้) ให้เมนูทั้ง 5 ไม่ล้น
            if (box.maxWidth >= 900) ...[
              const SizedBox(width: 10),
              const Text(
                'NSL Nebular',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ],
            const SizedBox(width: 14),
            Container(width: 1, height: 22, color: C.barBorder),
            const SizedBox(width: 8),
            ..._menus(context, c, w),
            const SizedBox(width: 8),
            // กลุ่มปุ่มขวา: ชิดขวาติดปุ่มควบคุมหน้าต่าง ได้ขนาดตามจริง (ย่อสัดส่วนลงถ้าที่ไม่พอ)
            // ที่ว่างทางซ้ายของกลุ่มปุ่ม = ช่องค้นหา + ที่จับลากย้ายหน้าต่าง
            Expanded(
              flex: 1000,
              child: _RightRegion(
                groupBuilder: (showSearchIcon) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showSearchIcon) ...[
                      _IconBtn(
                        Icons.search_rounded,
                        tr('ค้นหา / สั่งงาน (Ctrl+K)'),
                        () => showCommandPalette(context),
                      ),
                      const SizedBox(width: 4),
                    ],
                    _IconBtn(
                      Icons.undo,
                      tr('ย้อนกลับ (Ctrl+Z)'),
                      w.canUndo ? w.undo : null,
                    ),
                    const SizedBox(width: 4),
                    _IconBtn(
                      Icons.redo,
                      tr('ทำซ้ำ (Ctrl+Shift+Z)'),
                      w.canRedo ? w.redo : null,
                    ),
                    const SizedBox(width: 4),
                    Builder(
                      builder: (context) {
                        final s = context.watch<AppSettings>();
                        return _IconBtn(
                          s.dark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          s.dark ? tr('ธีมสว่าง') : tr('ธีมมืด'),
                          s.toggleDark,
                        );
                      },
                    ),
                    // เลือกธีมกลางของ NSL (ซ่อนเมื่อไม่มีที่เก็บธีม)
                    ThemeButton(
                      builder: (open) => Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: _IconBtn(Icons.palette_outlined, tr('เลือกธีม'), open),
                      ),
                    ),
                    // ปุ่มที่เกี่ยวกับ ER/SQL ซ่อนบนแท็บ DFD
                    if (isEr) ...[
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 34,
                        child: OutlinedButton.icon(
                          onPressed: c.project.tables.isEmpty
                              ? null
                              : () {
                                  c.autoLayoutTables();
                                  context.read<CanvasController>().fit(
                                    c.project,
                                  );
                                },
                          icon: const Icon(Icons.grid_view_rounded, size: 16),
                          label: Text(tr('จัดวางอัตโนมัติ')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: C.onBar,
                            side: BorderSide(color: C.barBorder),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            textStyle: const TextStyle(fontSize: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: C.primaryTint,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        alignment: Alignment.center,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Dialect  ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: C.primaryDark,
                                ),
                              ),
                              TextSpan(
                                text: c.project.dialect.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: C.primaryDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 34,
                        child: FilledButton.icon(
                          onPressed: () => FileActions.exportSql(context, c),
                          icon: const Icon(
                            Icons.file_download_outlined,
                            size: 16,
                          ),
                          label: const Text('Export .sql'),
                          style: FilledButton.styleFrom(
                            backgroundColor: C.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (controls) ...[
              const SizedBox(width: 12),
              const WindowControls(),
            ],
          ],
        ),
        ),
      ),
    );
  }

  /// เมนูหลัก: คีย์ลัดที่แสดงมาจาก [shortcutText] (ข้อมูลชุดเดียวกับตัวดักปุ่มจริง)
  /// รายการสร้างตอนกดเปิดเมนู ([_MenuButton.items] เป็นฟังก์ชัน) — ติ๊กและสถานะตรงกับตอนเปิดเสมอ
  static List<Widget> _menus(BuildContext context, ProjectController c, WorkspaceController w) {
    final a = AppActions(context);
    final cv = a.cv;
    PopupMenuEntry<VoidCallback> cmd(
      String label,
      Cmd k, {
      bool enabled = true,
      IconData? icon,
      bool? checked,
      Widget? tag,
    }) => _item(label, shortcutText(k), enabled ? () => a.run(k) : null, icon: icon, checked: checked, tag: tag);

    return [
      _MenuButton(label: tr('ไฟล์'), items: () => _fileMenu(context, w, cmd)),
      _MenuButton(label: tr('แก้ไข'), items: () => _editMenu(context, c, cv, w, cmd)),
      _MenuButton(label: tr('มุมมอง'), items: () => _viewMenu(context, c, w, a, cmd)),
      _MenuButton(label: tr('เครื่องมือ'), items: () => _toolsMenu(context, w, a, cmd)),
      _MenuButton(label: tr('ช่วยเหลือ'), items: () => _helpMenu(context, cmd)),
    ];
  }

  /// เมนูไฟล์: โปรเจกต์ / นำเข้า / ส่งออก / ฐานข้อมูล (ER) — นำเข้าใช้ได้ทุกเอกสาร (ผลเป็น ER ใหม่) ; Export .sql / Migration เฉพาะ ER
  static List<PopupMenuEntry<VoidCallback>> _fileMenu(
    BuildContext context,
    WorkspaceController w,
    PopupMenuEntry<VoidCallback> Function(String, Cmd, {bool enabled, IconData? icon, bool? checked, Widget? tag}) cmd,
  ) {
    final type = w.activeDocument.type;
    final er = type == DocType.er || type == null;
    const div = PopupMenuDivider();
    // ส่งออกภาพ: ทุกแผนภาพยกเว้น API (ไม่มีภาพ) ; ส่งออกเอกสาร: ยังไม่มีของ DFD
    final noImage = type == DocType.api;
    final noText = type == DocType.dfd;
    Widget notFor() => _tag(tr('ไม่มีสำหรับ {0}', [_docShort(type) ?? '']), muted: true);
    final erOnly = er ? null : _tag(tr('เฉพาะ ER'), muted: true);
    return [
      _section(tr('โปรเจกต์')),
      cmd(tr('โปรเจกต์ใหม่…'), Cmd.newProject, icon: Icons.note_add_outlined),
      cmd(tr('เปิด…'), Cmd.open, icon: Icons.folder_open_outlined),
      cmd(tr('บันทึก'), Cmd.save, icon: Icons.save_outlined),
      cmd(tr('บันทึกเป็น…'), Cmd.saveAs, icon: Icons.save_as_outlined),
      div,
      _section(tr('นำเข้า')),
      cmd(tr('นำเข้าจาก .sql…'), Cmd.importSql, icon: Icons.upload_file_outlined),
      cmd(tr('เชื่อมต่อฐานข้อมูล…'), Cmd.connectDb, icon: Icons.storage_rounded),
      div,
      _section(tr('ส่งออก')),
      cmd(tr('Export ภาพ (PNG / SVG)…'), Cmd.exportImage, icon: Icons.image_outlined, enabled: !noImage, tag: noImage ? notFor() : null),
      cmd(tr('Export เอกสาร / DBML / ข้อมูลตัวอย่าง…'), Cmd.exportText,
          icon: Icons.description_outlined, enabled: !noText, tag: noText ? notFor() : null),
      div,
      _section(tr('ฐานข้อมูล'), tag: 'ER'),
      cmd('Export .sql…', Cmd.exportSql, icon: Icons.code_rounded, enabled: er, tag: erOnly),
      cmd(tr('เปรียบเทียบกับไฟล์เก่า (Migration)…'), Cmd.compare, icon: Icons.compare_arrows_rounded, enabled: er, tag: erOnly),
    ];
  }

  /// สิ่งที่เลือกอยู่ในเอกสารที่เปิด: จำนวนวัตถุหลัก + หน่วย ; [any] = มีอะไรเลือกอยู่ (รวมเส้น/กลุ่ม) ; [items] = เอกสารมีวัตถุให้เลือก
  static ({int count, String unit, bool any, bool items}) _selection(BuildContext context, ProjectController c, WorkspaceController w) {
    switch (w.activeDocument.type) {
      case DocType.dfd:
        final d = context.read<DfdController>();
        final n = d.selectedNodeIds.length;
        return (
          count: n,
          unit: tr('วัตถุ'),
          any: n > 0 || d.selectedFlowId != null || d.selectedBoundaryId != null,
          items: d.diagram.nodes.isNotEmpty,
        );
      case DocType.flowchart:
        final f = context.read<FlowchartController>();
        final n = f.selectedNodeIds.length;
        return (count: n, unit: tr('สัญลักษณ์'), any: n > 0 || f.selectedEdgeId != null, items: f.diagram.nodes.isNotEmpty);
      case DocType.wireframe:
        final f = context.read<WireframeController>();
        final n = f.selectedIds.length;
        return (count: n, unit: tr('ชิ้นส่วน'), any: n > 0, items: f.diagram.components.isNotEmpty);
      case DocType.screenflow:
        final f = context.read<ScreenFlowController>();
        final n = f.selectedIds.length;
        return (count: n, unit: tr('หน้าจอ'), any: n > 0 || f.selectedEdgeId != null, items: f.diagram.nodes.isNotEmpty);
      case DocType.api:
        final n = w.currentApi.selectedId == null ? 0 : 1;
        return (count: n, unit: 'endpoint', any: n > 0, items: false);
      case DocType.er || null:
        final n = c.selectionCount;
        return (count: n, unit: tr('ตาราง'), any: n > 0 || c.selectedGroup != null, items: c.project.tables.isNotEmpty);
    }
  }

  /// เมนูแก้ไข: ชื่อคำสั่งเป็นกลางทุกชนิดเอกสาร ; หัวหมวดบอกจำนวนที่เลือก ; หมวด "ตาราง" เฉพาะ ER, "กลุ่ม" เฉพาะ Flowchart/Wireframe
  static List<PopupMenuEntry<VoidCallback>> _editMenu(
    BuildContext context,
    ProjectController c,
    CanvasController cv,
    WorkspaceController w,
    PopupMenuEntry<VoidCallback> Function(String, Cmd, {bool enabled, IconData? icon, bool? checked, Widget? tag}) cmd,
  ) {
    final type = w.activeDocument.type;
    final er = type == DocType.er || type == null;
    final api = type == DocType.api;
    final sel = _selection(context, c, w);
    final grouping = type == DocType.flowchart || type == DocType.wireframe;
    const div = PopupMenuDivider();
    return [
      cmd(tr('ย้อนกลับ'), Cmd.undo, icon: Icons.undo_rounded, enabled: w.canUndo),
      cmd(tr('ทำซ้ำ'), Cmd.redo, icon: Icons.redo_rounded, enabled: w.canRedo),
      div,
      _section(tr('ที่เลือก'), tag: sel.count > 0 ? '${sel.count} ${sel.unit}' : null),
      if (!api) ...[
        cmd(tr('คัดลอก'), Cmd.copy, icon: Icons.copy_rounded, enabled: sel.count > 0),
        cmd(tr('วาง'), Cmd.paste, icon: Icons.content_paste_rounded),
      ],
      cmd(tr('ทำสำเนา'), Cmd.duplicate, icon: Icons.library_add_outlined, enabled: sel.count > 0),
      if (!api) cmd(grouping ? tr('แก้ข้อความ…') : tr('เปลี่ยนชื่อ…'), Cmd.rename, icon: Icons.edit_outlined, enabled: sel.any),
      cmd(tr('ลบที่เลือก'), Cmd.delete, icon: Icons.delete_outline_rounded, enabled: sel.any),
      if (!api) cmd(tr('เลือกทั้งหมด'), Cmd.selectAll, icon: Icons.select_all_rounded, enabled: sel.items),
      if (er) ...[
        div,
        _section(tr('ตาราง'), tag: 'ER'),
        cmd(tr('สร้างตารางแบบฟอร์ม…'), Cmd.createTableForm, icon: Icons.table_chart_outlined),
        cmd(tr('แก้โครงสร้างตาราง…'), Cmd.editTableStructure, icon: Icons.edit_note_rounded, enabled: c.selectedTable != null),
        cmd(tr('จัดกลุ่มตารางที่เลือก'), Cmd.groupSelected, icon: Icons.auto_awesome_mosaic_outlined, enabled: sel.count > 0),
      ],
      if (grouping) ...[
        div,
        _section(tr('กลุ่ม')),
        cmd(tr('จัดกลุ่ม'), Cmd.groupSelected, icon: Icons.auto_awesome_mosaic_outlined, enabled: sel.count > 1),
        cmd(tr('เลิกจัดกลุ่ม'), Cmd.ungroupSelected, icon: Icons.grid_view_rounded, enabled: sel.count > 0),
      ],
      if (!api) ...[
        div,
        _item(tr('จัดวางอัตโนมัติ'), '', _autoLayout(context, c, cv, w), icon: Icons.dashboard_outlined),
      ],
    ];
  }

  /// เมนูช่วยเหลือ: คีย์ลัด / มีอะไรใหม่ (บอกรุ่น + จุดยังไม่ได้อ่าน) / เกี่ยวกับ ; ภาษา (คอลัมน์ติ๊ก)
  static List<PopupMenuEntry<VoidCallback>> _helpMenu(
    BuildContext context,
    PopupMenuEntry<VoidCallback> Function(String, Cmd, {bool enabled, IconData? icon, bool? checked, Widget? tag}) cmd,
  ) {
    final s = context.read<AppSettings>();
    final unseen = s.hasUnseenNotes(kAppVersion);
    const div = PopupMenuDivider();
    return [
      cmd(tr('ดูคีย์ลัดทั้งหมด'), Cmd.help, icon: Icons.keyboard_outlined),
      _item(
        tr('มีอะไรใหม่ (Patch note)…'),
        '',
        () => showWhatsNew(context),
        icon: Icons.auto_awesome_outlined,
        trailing: unseen
            ? Row(key: const ValueKey('menu-whats-new-unseen'), mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: C.palette.warnText, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(kAppVersion, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: C.palette.warnText)),
              ])
            : null,
      ),
      _item(tr('เกี่ยวกับ NSL Nebular…'), '', () => showAbout(context), icon: Icons.info_outline_rounded),
      div,
      _section(tr('ภาษา')),
      for (final l in Lang.values) _item(l.label, '', () => s.setLang(l), checked: l == currentLang),
    ];
  }

  /// จัดวางอัตโนมัติตามชนิดเอกสารที่เปิด (null = ใช้ไม่ได้ / มีวัตถุไม่พอ)
  static VoidCallback? _autoLayout(BuildContext context, ProjectController c, CanvasController cv, WorkspaceController w) {
    switch (w.activeDocument.type) {
      case DocType.wireframe || DocType.api || null:
        return null;
      case DocType.screenflow:
        if (w.screenflowOf(w.activeId).nodes.length < 2) return null;
        return () {
          final f = context.read<ScreenFlowController>();
          if (f.autoLayout()) f.fit(f.viewport);
        };
      case DocType.flowchart:
        if (w.flowchartOf(w.activeId).nodes.length < 2) return null;
        return () {
          final f = context.read<FlowchartController>();
          if (f.autoLayout()) f.fit(f.viewport);
        };
      case DocType.dfd:
        if (w.dfdOf(w.activeId).nodes.length < 2) return null;
        return () {
          final d = context.read<DfdController>();
          if (d.autoLayout()) d.fit(d.viewport);
        };
      case DocType.er:
        if (c.project.tables.isEmpty) return null;
        return () {
          c.autoLayoutTables();
          cv.fit(c.project);
        };
    }
  }

  /// ป้ายชนิดเอกสารสั้น ๆ บนหัวหมวด "แคนวาส"
  static String? _docShort(DocType? t) => switch (t) {
    null => null,
    DocType.er => 'ER',
    DocType.dfd => 'DFD',
    DocType.flowchart => 'Flowchart',
    DocType.wireframe => 'Wireframe',
    DocType.screenflow => 'Screen Flow',
    DocType.api => 'API',
  };

  /// เมนูมุมมอง: แผง / หน้า / แคนวาส (หมวดแคนวาสเปลี่ยนตามชนิดเอกสาร ; รายการเฉพาะ ER เป็นสีเทาหรือซ่อน)
  static List<PopupMenuEntry<VoidCallback>> _viewMenu(
    BuildContext context,
    ProjectController c,
    WorkspaceController w,
    AppActions a,
    PopupMenuEntry<VoidCallback> Function(String, Cmd, {bool enabled, IconData? icon, bool? checked, Widget? tag}) cmd,
  ) {
    final s = context.read<AppSettings>();
    final type = w.activeDocument.type;
    final canvas = !w.pageView && type != DocType.api;
    final erCanvas = type == DocType.er && !w.pageView;
    const div = PopupMenuDivider();
    return [
      cmd(tr('พอดีหน้าจอ'), Cmd.fit, icon: Icons.fit_screen_outlined, enabled: canvas),
      cmd(tr('ซูม 100%'), Cmd.zoom100, icon: Icons.zoom_in_rounded, enabled: canvas),
      div,
      _section(tr('แผง')),
      cmd(tr('ตัวสำรวจโปรเจกต์'), Cmd.toggleExplorer, icon: Icons.folder_outlined, checked: s.showExplorer),
      cmd(
        'SQL Preview',
        Cmd.toggleSqlPreview,
        icon: Icons.storage_rounded,
        checked: a.dockShowing(DockTab.sql),
        enabled: erCanvas,
        tag: erCanvas ? null : _tag(tr('เฉพาะ ER'), muted: true),
      ),
      cmd(tr('ปัญหาในเอกสารนี้'), Cmd.toggleIssues, icon: Icons.warning_amber_rounded, checked: a.dockShowing(DockTab.issues)),
      cmd(tr('แผงโน้ตและงานค้าง'), Cmd.toggleNotesPanel, icon: Icons.sticky_note_2_outlined, checked: w.notesPanel),
      cmd(tr('หมุดโน้ตบนแคนวาส'), Cmd.toggleNotePins, icon: Icons.push_pin_outlined, checked: w.notePinsVisible),
      div,
      _section(tr('หน้า')),
      cmd('Project Home', Cmd.showHome, icon: Icons.home_outlined, checked: w.homeView),
      _item(tr('พจนานุกรมข้อมูล'), '', () => w.showDictionary(!w.dictionaryView),
          icon: Icons.menu_book_outlined, checked: w.dictionaryView),
      cmd(tr('ประวัติเวอร์ชันและ Diff'), Cmd.showHistory, icon: Icons.history_rounded, checked: w.page == WorkspacePage.history),
      _item(tr('ความต้องการและการไล่ตาม'), '', () => w.showTrace(w.page != WorkspacePage.trace),
          icon: Icons.link_rounded, checked: w.page == WorkspacePage.trace),
      if (canvas) ...[
        div,
        _section(tr('แคนวาส'), tag: _docShort(type)),
        _item(tr('จัดแนวตามตาราง (Snap)'), '', () => s.setSnapToGrid(!s.snapToGrid),
            icon: Icons.grid_4x4_rounded, checked: s.snapToGrid),
        if (erCanvas) ...[
          _item(tr('ขนาดกระดาน…'), '', () => FileActions.changeBoardSize(context, c), icon: Icons.aspect_ratio_rounded),
          _item(tr('เส้นความสัมพันธ์ (FK)…'), '', () => showLineSettingsDialog(context, c), icon: Icons.timeline_rounded),
        ],
      ],
    ];
  }

  /// เมนูเครื่องมือ: ค้นหา / ตรวจ / สร้าง
  static List<PopupMenuEntry<VoidCallback>> _toolsMenu(
    BuildContext context,
    WorkspaceController w,
    AppActions a,
    PopupMenuEntry<VoidCallback> Function(String, Cmd, {bool enabled, IconData? icon, bool? checked, Widget? tag}) cmd,
  ) {
    final erCanvas = w.activeDocument.type == DocType.er && !w.pageView;
    final problems = w.workspaceIssues.where((i) => i.issue.severity != Severity.info).length;
    final mock = context.read<MockController>();
    const div = PopupMenuDivider();
    return [
      _section(tr('ค้นหา')),
      cmd('Command palette', Cmd.palette, icon: Icons.terminal_rounded),
      cmd(tr('ค้นหาตาราง / คอลัมน์'), Cmd.find, icon: Icons.search_rounded, enabled: erCanvas, tag: _tag('ER', muted: !erCanvas)),
      div,
      _section(tr('ตรวจ')),
      cmd(tr('ปัญหาทั้งโปรเจกต์…'), Cmd.workspaceIssues,
          icon: Icons.rule_rounded, tag: problems > 0 ? _tag('$problems', warn: true) : null),
      div,
      _section(tr('สร้าง')),
      cmd(tr('สร้างโค้ด'), Cmd.codegen, icon: Icons.code_rounded, checked: w.page == WorkspacePage.codegen),
      _item(
        'Mock Server',
        '',
        () => w.showMock(w.page != WorkspacePage.mock),
        icon: Icons.dns_outlined,
        checked: w.page == WorkspacePage.mock,
        trailing: mock.running
            ? Row(key: const ValueKey('menu-mock-running'), mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: C.primary, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(tr('ทำงานที่ :{0}', [mock.port ?? '']),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: C.primaryDark)),
              ])
            : null,
      ),
    ];
  }

  /// หัวหมวดในเมนู (กดไม่ได้)
  static PopupMenuEntry<VoidCallback> _section(String label, {String? tag}) => PopupMenuItem<VoidCallback>(
    enabled: false,
    height: 26,
    child: Padding(
      padding: const EdgeInsets.only(left: 24, top: 4),
      child: Row(children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.muted)),
        if (tag != null) ...[const SizedBox(width: 6), _tag(tag)],
      ]),
    ),
  );

  /// ป้ายเล็กข้างชื่อรายการ: ชนิดเอกสาร (สีหลัก) · "เฉพาะ ER" ([muted]) · จำนวนปัญหา ([warn])
  static Widget _tag(String text, {bool muted = false, bool warn = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: warn ? C.palette.warnBg : (muted ? C.border : C.primaryTint),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: warn ? C.palette.warnText : (muted ? C.muted : C.primaryDark),
      ),
    ),
  );

  /// รายการเมนู: [คอลัมน์ติ๊ก][ไอคอน] ชื่อ [ป้าย] ……… คีย์ลัด/[trailing]
  /// [checked] = null คือไม่ใช่รายการเปิด/ปิด (คอลัมน์ติ๊กยังเว้นที่ไว้ ทุกบรรทัดจึงตรงแนว)
  static PopupMenuEntry<VoidCallback> _item(
    String label,
    String shortcut,
    VoidCallback? onTap, {
    IconData? icon,
    bool? checked,
    Widget? tag,
    Widget? trailing,
  }) {
    final on = onTap != null;
    return PopupMenuItem<VoidCallback>(
      value: onTap,
      enabled: on,
      height: 34,
      child: SizedBox(
        width: 380,
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: checked == true
                  ? Icon(Icons.check_rounded, key: ValueKey('menu-checked-$label'), size: 16, color: C.primaryDark)
                  : null,
            ),
            const SizedBox(width: 8),
            if (icon != null) ...[
              Icon(icon, size: 16, color: on ? C.muted : C.muted.withValues(alpha: 0.45)),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Row(children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: on ? C.text : C.muted),
                  ),
                ),
                // ป้ายหดได้ (ตัดเป็น …) — ชื่อยาว + ป้ายยาวต้องไม่ล้นเมนู
                if (tag != null) ...[const SizedBox(width: 8), Flexible(child: tag)],
              ]),
            ),
            const SizedBox(width: 12),
            trailing ?? Text(shortcut, style: TextStyle(fontSize: 12, color: C.muted)),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.label, required this.items});
  final String label;

  /// สร้างรายการตอนเปิดเมนู
  final List<PopupMenuEntry<VoidCallback>> Function() items;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
    tooltip: '',
    offset: const Offset(0, 36),
    onSelected: (f) => f(),
    itemBuilder: (_) => items(),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(label, style: TextStyle(fontSize: 13, color: C.onBarMuted)),
    ),
  );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn(this.icon, this.tip, this.onTap);
  final IconData icon;
  final String tip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: SizedBox(
      width: 34,
      height: 34,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: C.onBar,
          disabledForegroundColor: C.onBar.withValues(alpha: 0.35),
          side: BorderSide(color: C.barBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Icon(icon, size: 17),
      ),
    ),
  );
}

/// พื้นที่ขวาของแถบบน: [ที่ว่าง: ที่จับลากหน้าต่าง + ช่องค้นหา] [กลุ่มปุ่ม]
/// กลุ่มปุ่มได้ขนาดตามจริงก่อน ที่ว่างที่เหลือเป็นของช่องค้นหา (จึงไม่ทับกันไม่ว่าฟอนต์/ภาษาจะกว้างแค่ไหน)
/// ที่ว่างน้อยเกินไป = ซ่อนช่องค้นหา แล้วแสดงเป็นปุ่มแว่นขยายในกลุ่มปุ่มแทน
class _RightRegion extends StatefulWidget {
  const _RightRegion({required this.groupBuilder});

  /// สร้างกลุ่มปุ่ม ([showSearchIcon] = ใส่ปุ่มแว่นขยายด้วย)
  final Widget Function(bool showSearchIcon) groupBuilder;

  @override
  State<_RightRegion> createState() => _RightRegionState();
}

class _RightRegionState extends State<_RightRegion> {
  /// ที่ว่างอย่างน้อยเท่านี้จึงโชว์ช่องค้นหา (ตอนปุ่มแว่นขยายอยู่ในกลุ่มปุ่ม ที่ว่างจะแคบลงอีก จึงไม่สั่นไปมา)
  static const _minFieldArea = 220.0;
  bool _showIcon = false;

  /// ตำแหน่งซ้ายของพื้นที่ว่างบนหน้าจอ (วัดหลังวาง layout แล้ว) ใช้คำนวณให้ช่องค้นหาอยู่กลางแถบทั้งแถบ
  final _areaKey = GlobalKey();
  double? _areaLeft;

  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _areaKey.currentContext?.findRenderObject() as RenderBox?;
      if (!mounted || box == null || !box.attached || !box.hasSize) return;
      final left = box.localToGlobal(Offset.zero).dx;
      if (_areaLeft == null || (left - _areaLeft!).abs() > 0.5) {
        setState(() => _areaLeft = left);
      }
    });
  }

  void _report(bool fieldShown) {
    if (_showIcon == !fieldShown) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _showIcon = !fieldShown);
    });
  }

  @override
  Widget build(BuildContext context) {
    _measure();
    return _buildRegion(context);
  }

  Widget _buildRegion(BuildContext context) => LayoutBuilder(
    builder: (context, region) => Row(
      children: [
        Expanded(
          child: Stack(
            key: _areaKey,
            children: [
              const Positioned.fill(
                child: WindowDragArea(child: SizedBox.expand()),
              ),
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, area) {
                    final show = area.maxWidth >= _minFieldArea;
                    _report(show);
                    if (!show) return const SizedBox.shrink();
                    // อยู่กึ่งกลางของแถบชื่อหน้าต่างทั้งแถบ (ไม่ใช่กึ่งกลางของที่ว่างที่เหลือ) ถ้าที่ว่างไม่พอจะชิดเข้ามาในที่ว่าง
                    final w = math.min(420.0, area.maxWidth - 24);
                    final left = _areaLeft;
                    final screenW = MediaQuery.sizeOf(context).width;
                    var x = left == null
                        ? (area.maxWidth - w) / 2
                        : screenW / 2 - left - w / 2;
                    x = x.clamp(12.0, math.max(12.0, area.maxWidth - w - 12));
                    return Stack(
                      children: [
                        Positioned(
                          left: x,
                          top: 0,
                          bottom: 0,
                          width: w,
                          child: const Center(child: SearchLauncher()),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: region.maxWidth),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: widget.groupBuilder(_showIcon),
          ),
        ),
      ],
    ),
  );
}
