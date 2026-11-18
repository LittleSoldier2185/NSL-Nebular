import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nsl_ui/nsl_ui.dart' show NslThemeController, NslThemeStore;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'core/models/workspace.dart';
import 'core/db/saved_connections.dart';
import 'core/db/secret_codec.dart';
import 'core/storage/autosave.dart';
import 'core/storage/project_file.dart';
import 'core/l10n/l10n.dart';
import 'state/app_settings.dart';
import 'state/autosave_coordinator.dart';
import 'state/dfd_controller.dart';
import 'state/flowchart_controller.dart';
import 'state/project_controller.dart';
import 'state/screenflow_controller.dart';
import 'state/wireframe_controller.dart';
import 'state/workspace_controller.dart';
import 'ui/canvas/canvas_controller.dart';
import 'ui/db_connect_dialog.dart';
import 'ui/home_page.dart';
import 'ui/window_chrome.dart';
import 'ui/theme.dart';
import 'core/storage/history_store.dart';
import 'state/version_history.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowChrome.initDesktop(); // ซ่อนแถบชื่อของระบบ ใช้แถบบนของแอปแทน

  // auto-save: ถ้าหาที่เก็บไม่ได้ก็ทำงานต่อโดยไม่มี auto-save (ไม่ให้แอปเปิดไม่ขึ้น)
  AutosaveStore? store;
  HistoryStore? history;
  AutosaveInfo? recovery;
  AppSettings? settings;
  try {
    final dir = await getApplicationSupportDirectory();
    settings = AppSettings.load(File('${dir.path}${Platform.pathSeparator}settings.json'));
    store = FileAutosaveStore(Directory('${dir.path}${Platform.pathSeparator}autosave'));
    history = HistoryStore(Directory('${dir.path}${Platform.pathSeparator}history'));
    DbConnectDialog.store = SavedConnectionStore(
      File('${dir.path}${Platform.pathSeparator}connections.json'),
      WindowsDpapiCodec.forPlatform(),
    );
    recovery = await store.readRecoverable();
  } catch (_) {
    store = null;
  }
  // ดับเบิลคลิกไฟล์ .nsln / .nslm / .erd (หรือ nsl_nebular.exe <ไฟล์>) = เปิดไฟล์นั้นทันที ไม่ถามกู้คืนงานค้าง
  Workspace? initial;
  String? initialPath;
  for (final a in args) {
    final lower = a.toLowerCase();
    if (!kOpenableExts.any((e) => lower.endsWith('.$e'))) continue;
    try {
      initial = await ProjectFile.load(a);
      initialPath = a;
      recovery = null;
    } catch (_) {}
    break;
  }
  // หาที่เก็บไม่ได้ = ใช้ค่าเริ่มต้น (ไทย/สว่าง) โดยไม่ถามภาษา เพราะบันทึกคำตอบไม่ได้อยู่ดี
  runApp(NslDevApp(autosave: store, history: history, recovery: recovery, settings: settings ?? AppSettings(lang: Lang.th), initialProject: initial, initialPath: initialPath, themes: await _openThemes(args), showStart: true));
}

/// ที่เก็บธีมกลางของ NSL (ธีมที่ทำจาก NSL Palette แชร์กับแอปอื่น) — ล้มเหลวทุกกรณี = null = ใช้ธีมในตัว ไม่ให้แอปเปิดไม่ขึ้น
/// `--safe-mode` = ไม่ใช้ธีมของผู้ใช้เลย (กู้กรณีธีมทำให้อ่านไม่ออก)
Future<NslThemeController?> _openThemes(List<String> args) async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    final c = NslThemeController(NslThemeStore.standard(documents: docs));
    await c.reload();
    if (args.contains('--safe-mode')) await c.setSafeMode(true);
    c.startWatching();
    return c;
  } catch (_) {
    return null;
  }
}

class NslDevApp extends StatefulWidget {
  const NslDevApp({super.key, this.autosave, this.history, this.recovery, this.settings, this.initialProject, this.initialPath, this.themes, this.showStart = false});

  /// ที่เก็บ/ตัวเลือกธีมกลางของ NSL (null = ใช้ธีมในตัว) — ธีมเปลี่ยนสดตามไฟล์ที่ NSL Palette หรือแอปอื่นเขียน
  final NslThemeController? themes;

  /// โปรเจกต์ที่เปิดตั้งแต่เริ่ม (จากไฟล์ที่ส่งมาทางบรรทัดคำสั่ง) — null = เริ่มว่าง
  final Workspace? initialProject;
  final String? initialPath;

  /// เปิดหน้า Start ตอนเริ่ม (แอปจริงส่ง true เมื่อไม่มีไฟล์ให้เปิดและไม่มีงานค้างให้กู้คืน ; เทสต์ส่วนใหญ่ไม่ส่ง = เข้าหน้าหลักเลย)
  final bool showStart;

  /// การตั้งค่าแอป (null = ค่าเริ่มต้น ไทย/สว่าง ไม่ถามภาษา)
  final AppSettings? settings;

  /// ที่เก็บ auto-save (null = ปิด auto-save)
  final AutosaveStore? autosave;

  /// ที่เก็บประวัติเวอร์ชัน (null = ปิดประวัติเวอร์ชัน — เทสต์ส่วนใหญ่ไม่ส่ง)
  final HistoryStore? history;

  /// งานค้างจากครั้งก่อนที่จะถามผู้ใช้ว่าจะกู้คืนไหม
  final AutosaveInfo? recovery;

  @override
  State<NslDevApp> createState() => _NslDevAppState();
}

class _NslDevAppState extends State<NslDevApp> with WidgetsBindingObserver {
  late final AppSettings _settings = widget.settings ?? AppSettings(lang: Lang.th);
  bool _recoveryPending = true;
  late final WorkspaceController _workspace = WorkspaceController();
  late final VersionHistory _versions = VersionHistory(widget.history, _workspace);
  late final CanvasController _canvas = CanvasController();
  late final AutosaveCoordinator? _autosave =
      widget.autosave == null ? null : AutosaveCoordinator(_workspace, widget.autosave!);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settings.addListener(_onSettings);
    widget.themes?.addListener(_onThemes);
    final p = widget.initialProject;
    if (p != null) _workspace.loadWorkspace(p, widget.initialPath);
    // ไฟล์ที่เปิดตั้งแต่เริ่มก็นับเป็นไฟล์ล่าสุด
    if (p != null && widget.initialPath != null) {
      _settings.addRecent(widget.initialPath!, name: p.name.isEmpty || p.name == 'untitled' ? widget.initialPath!.split(RegExp(r'[\/]')).last.replaceFirst(RegExp(r'.[^.]*$'), '') : p.name, now: DateTime.now(), docCount: p.documents.length, docTypes: [for (final t in {for (final d in p.documents) d.type?.name}) ?t]);
    }
    if (widget.showStart && p == null && widget.recovery == null) _workspace.showStart();
    _workspace.addListener(_onWorkspace);
    _onWorkspace();
  }

  int _themeRevision = 0;

  void _onSettings() => setState(() {});

  /// ธีมกลางเปลี่ยน → สร้างต้นไม้วิดเจ็ตใหม่ (สีมาจากตัวแปรกลาง `C` ไม่ใช่ InheritedWidget — เหมือนตอนสลับสว่าง/มืด) ; เอกสารที่เปิดอยู่ไม่หาย เพราะ controller อยู่นอกต้นไม้
  void _onThemes() => setState(() => _themeRevision++);

  /// มุมมอง (เลื่อน/ซูม) ของแคนวาส ER แยกต่อเอกสาร
  void _onWorkspace() => _canvas.showDoc(_workspace.currentEr.docId);

  /// หน้าต่างเสียโฟกัส/ถูกซ่อน/กำลังปิด -> เขียนสำเนาทันที ไม่รอ timer
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _autosave?.flush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_onSettings);
    widget.themes?.removeListener(_onThemes);
    _workspace.removeListener(_onWorkspace);
    _autosave?.dispose();
    _versions.dispose();
    _workspace.dispose();
    _canvas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ธีม/ภาษาเปลี่ยน -> สร้างต้นไม้วิดเจ็ตใหม่ทั้งหมด (สีมาจากตัวแปรกลาง ไม่ใช่ InheritedWidget)
    final themes = widget.themes;
    final palette = paletteFor(_settings.dark ? Brightness.dark : Brightness.light, theme: themes?.activeSpec, lookup: themes?.lookup);
    C.use(palette);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _settings),
        ChangeNotifierProvider.value(value: _workspace),
        ChangeNotifierProvider.value(value: _versions),
        ChangeNotifierProvider.value(value: _canvas),
        Provider<AutosaveCoordinator?>.value(value: _autosave),
        ChangeNotifierProvider<NslThemeController?>.value(value: widget.themes),
      ],
      // controller ของเอกสาร ER/DFD/Flowchart ที่ใช้งานอยู่: เปลี่ยนตามแท็บ (วิดเจ็ตเดิมใช้ watch<ProjectController>() ได้ต่อ)
      child: ListenableBuilder(
        listenable: _workspace,
        builder: (context, child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectController>.value(value: _workspace.currentEr),
            ChangeNotifierProvider<DfdController>.value(value: _workspace.currentDfd),
            ChangeNotifierProvider<FlowchartController>.value(value: _workspace.currentFlowchart),
            ChangeNotifierProvider<WireframeController>.value(value: _workspace.currentWireframe),
            ChangeNotifierProvider<ScreenFlowController>.value(value: _workspace.currentScreenflow),
          ],
          child: child,
        ),
        child: MaterialApp(
          key: ValueKey('${_settings.lang.code}-${_settings.dark}-$_themeRevision'),
          title: 'NSL Nebular',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(palette),
          home: HomePage(
            recovery: _recoveryPending ? widget.recovery : null,
            onRecoveryOffered: () => _recoveryPending = false,
          ),
        ),
      ),
    );
  }
}
