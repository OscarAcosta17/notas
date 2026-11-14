import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/aula_course.dart';
import '../models/ramo.dart';
import '../services/aula_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/expressive_widgets.dart';
import '../viewmodels/categoria_provider.dart';
import '../viewmodels/ramo_provider.dart';
import '../viewmodels/semestre_provider.dart';
import '../viewmodels/settings_provider.dart';
import 'aula_sheets.dart';

enum _AulaContentFilter { all, files, deadlines, downloaded }

class AulaView extends ConsumerStatefulWidget {
  final int refreshTick;
  final int? selectedSemesterId;
  final VoidCallback? onAcademicDataChanged;
  final bool autoLoad;

  const AulaView({
    super.key,
    this.refreshTick = 0,
    this.selectedSemesterId,
    this.onAcademicDataChanged,
    this.autoLoad = true,
  });

  @override
  ConsumerState<AulaView> createState() => _AulaViewState();
}

class _AulaViewState extends ConsumerState<AulaView> {
  final AulaSettingsService _settings = AulaSettingsService();
  final AulaDownloaderService _downloader = AulaDownloaderService();
  final TextEditingController _searchCtrl = TextEditingController();

  AulaSessionData _session = const AulaSessionData();
  AulaMoodleService? _moodle;
  String _downloadRoot = '';
  String? _obsidianVaultPath;
  Map<int, String> _courseFolders = {};
  Map<int, String> _courseSubfolders = {};
  Map<int, bool> _courseOrgSections = {};
  Set<int> _hiddenCourseIds = {};
  Map<int, int> _courseRamoLinks = {};
  bool _notifyNewFiles = true;
  bool _notifyDeadlines = true;
  int _deadlineHours = 24;

  bool _initializing = true;
  bool _loadingCourses = false;
  bool _showOnlyCurrentSemester = true;
  bool _showHiddenCourses = false;
  bool _batchDownloading = false;
  double _batchProgress = 0.0;
  String? _errorMessage;
  String _searchQuery = '';
  _AulaContentFilter _contentFilter = _AulaContentFilter.all;
  String? _extensionFilter;

  List<MoodleCourse> _courses = [];
  int? _selectedDesktopCourseId;
  final Set<int> _expandedCourseIds = {};
  final Set<int> _loadingCourseIds = {};
  final Set<String> _selectedItemKeys = {};
  final Map<String, MoodleItem> _selectedItemRefs = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(AulaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick &&
        widget.autoLoad &&
        _session.hasCredentials &&
        !_loadingCourses) {
      _refreshCourses(silent: true);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _reloadLocalSettings();
    final isTestEnv = Platform.environment.containsKey('FLUTTER_TEST');
    if (!widget.autoLoad || isTestEnv) {
      if (mounted) setState(() => _initializing = false);
      return;
    }

    if (!_session.hasCredentials && Platform.isWindows) {
      final imported = await _settings.detectAndImportLocalDesktopData(
        overwriteExistingSession: false,
      );
      if (imported != null) {
        await _reloadLocalSettings();
        if (mounted && imported.foundSession) {
          _showSnack(
            'Sesión de Aula-Scrapt PC detectada (${imported.userName ?? 'USM'})',
          );
        }
      }
    }

    if (mounted) {
      setState(() {
        _initializing = false;
      });
    }

    if (_session.hasCredentials) {
      await _refreshCourses();
    }
  }

  Future<void> _reloadLocalSettings() async {
    final session = await _settings.loadSession();
    final dlRoot = await _settings.getDownloadRoot();
    final vault = await _settings.getObsidianVaultPath();
    final folders = await _settings.getCourseFolders();
    final subs = await _settings.getCourseSubfolders();
    final orgSec = await _settings.getCourseOrgSections();
    final hidden = await _settings.getHiddenCourses();
    final links = await _settings.getCourseRamoLinks();
    final notif = await _settings.getNotificationSettings();

    if (!mounted) return;
    setState(() {
      _session = session;
      _moodle = session.hasCredentials ? AulaMoodleService(session: session) : null;
      _downloadRoot = dlRoot;
      _obsidianVaultPath = vault;
      _courseFolders = folders;
      _courseSubfolders = subs;
      _courseOrgSections = orgSec;
      _hiddenCourseIds = hidden;
      _courseRamoLinks = links;
      _notifyNewFiles = notif.notifyNewFiles;
      _notifyDeadlines = notif.notifyDeadlines;
      _deadlineHours = notif.deadlineHours;
    });
  }

  Future<void> _refreshCourses({bool silent = false}) async {
    final moodle = _moodle;
    if (moodle == null) return;
    if (!silent) {
      setState(() {
        _loadingCourses = true;
        _errorMessage = null;
      });
    }
    try {
      final updatedSession = await moodle.validateSession();
      await _settings.saveSession(updatedSession);
      final fetched = await moodle.fetchCourses(hiddenCourseIds: _hiddenCourseIds);
      if (!mounted) return;
      setState(() {
        _session = updatedSession;
        _courses = fetched;
        _loadingCourses = false;
        _errorMessage = null;
        if (_selectedDesktopCourseId == null && fetched.isNotEmpty) {
          _selectedDesktopCourseId = fetched.firstWhere(
            (c) => !c.isHidden,
            orElse: () => fetched.first,
          ).id;
        }
      });

      final targetId = _selectedDesktopCourseId;
      if (targetId != null) {
        final target = fetched.where((c) => c.id == targetId).firstOrNull;
        if (target != null) {
          unawaited(_ensureCourseLoaded(target));
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCourses = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _ensureCourseLoaded(MoodleCourse course, {bool force = false}) async {
    final moodle = _moodle;
    if (moodle == null) return;
    if (!force && (course.isLoaded || _loadingCourseIds.contains(course.id))) return;

    setState(() => _loadingCourseIds.add(course.id));
    try {
      final loaded = await moodle.fetchCourseContents(course);
      await _downloader.scanDownloadedItems(
        course: loaded,
        downloadRoot: _downloadRoot,
        courseFolders: _courseFolders,
        courseSubfolders: _courseSubfolders,
        courseOrgSections: _courseOrgSections,
      );
      final addedNames = await _settings.detectNewItemsAndUpdateSnapshot(loaded);
      if (_notifyNewFiles && addedNames.isNotEmpty && Platform.isAndroid) {
        await NotificationService.showInstantNotification(
          'Nuevo material en ${loaded.cleanName}',
          addedNames.length == 1
              ? addedNames.first
              : '${addedNames.length} archivos nuevos disponibles',
        );
      }

      if (!mounted) return;
      setState(() {
        final idx = _courses.indexWhere((c) => c.id == loaded.id);
        if (idx >= 0) {
          _courses[idx] = loaded;
        }
        _loadingCourseIds.remove(course.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingCourseIds.remove(course.id));
      _showSnack('Error al cargar ${course.cleanName}: $e', isError: true);
    }
  }

  Future<void> _openWebViewLogin() async {
    if (!Platform.isAndroid) return;
    final result = await Navigator.of(context).push<AulaSessionData>(
      MaterialPageRoute(builder: (_) => const AulaWebViewLoginScreen()),
    );
    if (result != null && result.hasCredentials) {
      final moodle = AulaMoodleService(session: result);
      try {
        final validated = await moodle.validateSession();
        await _settings.saveSession(validated);
        await _reloadLocalSettings();
        await _refreshCourses();
      } catch (e) {
        _showSnack('No se pudo validar la sesión web: $e', isError: true);
      }
    }
  }

  Future<void> _openAuthSheet() async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AulaAuthSheet(
        currentSession: _session,
        settingsService: _settings,
        onAuthenticated: (validatedSession, {extraFolders}) async {
          await _settings.saveSession(validatedSession);
          if (extraFolders != null) {
            for (final entry in extraFolders.entries) {
              await _settings.setCourseFolder(entry.key, entry.value);
            }
          }
          await _reloadLocalSettings();
          await _refreshCourses();
        },
      ),
    );
  }

  Future<void> _openCourseConfig(MoodleCourse course, List<Ramo> ramos) async {
    final currentLink = _courseRamoLinks[course.id] ??
        MoodleCourse.findMatchingRamo(course, ramos)?.id;

    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AulaFolderConfigSheet(
        course: course,
        currentFolder: _courseFolders[course.id] ?? '',
        currentSubfolder: _courseSubfolders[course.id] ?? '',
        organizeBySections: _courseOrgSections[course.id] ?? false,
        availableRamos: ramos,
        linkedRamoId: currentLink,
        onSave: ({
          required String folderName,
          required String subfolder,
          required bool orgBySections,
          required bool hidden,
          required int? linkedRamoId,
        }) async {
          await _settings.setCourseFolder(course.id, folderName);
          await _settings.setCourseSubfolder(course.id, subfolder);
          await _settings.setCourseOrgSections(course.id, orgBySections);
          await _settings.setCourseHidden(course.id, hidden);
          await _settings.setCourseRamoLink(course.id, linkedRamoId);
          await _reloadLocalSettings();
          setState(() {
            final idx = _courses.indexWhere((c) => c.id == course.id);
            if (idx >= 0) _courses[idx].isHidden = hidden;
          });
        },
      ),
    );
  }

  Future<void> _openGlobalSettings() async {
    final hiddenList = _courses.where((c) => c.isHidden).toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AulaGlobalSettingsSheet(
        settingsService: _settings,
        downloadRoot: _downloadRoot,
        obsidianVaultPath: _obsidianVaultPath,
        notifyNewFiles: _notifyNewFiles,
        notifyDeadlines: _notifyDeadlines,
        deadlineHours: _deadlineHours,
        hiddenCourses: hiddenList,
        onUnhideCourse: (courseId) async {
          await _settings.setCourseHidden(courseId, false);
          await _reloadLocalSettings();
          setState(() {
            final idx = _courses.indexWhere((c) => c.id == courseId);
            if (idx >= 0) _courses[idx].isHidden = false;
          });
        },
        onLogout: () async {
          await _settings.clearSession();
          setState(() {
            _session = const AulaSessionData();
            _moodle = null;
            _courses = [];
            _selectedDesktopCourseId = null;
            _selectedItemKeys.clear();
            _selectedItemRefs.clear();
          });
        },
        onSettingsChanged: _reloadLocalSettings,
      ),
    );
  }

  Ramo? _resolveMatchedRamo(MoodleCourse course, List<Ramo> ramos) {
    final manualId = _courseRamoLinks[course.id];
    if (manualId != null) {
      final manual = ramos.where((r) => r.id == manualId).firstOrNull;
      if (manual != null) return manual;
    }
    return MoodleCourse.findMatchingRamo(course, ramos);
  }

  Future<void> _importMissingRamos(
    List<MoodleCourse> missing,
    List<Ramo> currentRamos,
  ) async {
    if (missing.isEmpty) return;
    final semestres = ref.read(semestreProvider);
    final settings = ref.read(settingsProvider);
    final semId = await AulaNotasSynergyService.ensureActiveSemester(
      currentSemesterId: widget.selectedSemesterId,
      semestres: semestres,
    );

    int nextOrder = currentRamos.length;
    int created = 0;
    for (final c in missing) {
      final ramo = await AulaNotasSynergyService.createRamoFromCourse(
        course: c,
        semesterId: semId,
        escalaNotas: settings.escalaNotas,
        orderIndex: nextOrder++,
      );
      if (ramo.id != null) {
        await _settings.setCourseRamoLink(c.id, ramo.id);
        created++;
      }
    }

    await ref.read(semestreProvider.notifier).cargarSemestres();
    ref.invalidate(ramoProvider);
    widget.onAcademicDataChanged?.call();
    await _reloadLocalSettings();
    _showSnack('Se crearon $created ramo(s) en NotasApp con sus colores asignados.');
  }

  Future<void> _importCourseToRamoAndAgenda(
    MoodleCourse course,
    List<Ramo> currentRamos,
  ) async {
    final semestres = ref.read(semestreProvider);
    final settings = ref.read(settingsProvider);
    final semId = await AulaNotasSynergyService.ensureActiveSemester(
      currentSemesterId: widget.selectedSemesterId,
      semestres: semestres,
    );

    var matched = _resolveMatchedRamo(course, currentRamos);
    bool createdRamo = false;
    if (matched == null) {
      matched = await AulaNotasSynergyService.createRamoFromCourse(
        course: course,
        semesterId: semId,
        escalaNotas: settings.escalaNotas,
        orderIndex: currentRamos.length,
      );
      if (matched.id != null) {
        await _settings.setCourseRamoLink(course.id, matched.id);
      }
      createdRamo = true;
    }

    if (!course.isLoaded) {
      await _ensureCourseLoaded(course);
    }
    final latestCourse = _courses.where((c) => c.id == course.id).firstOrNull ?? course;
    final synced = await AulaNotasSynergyService.importDeadlinesToAgenda(
      items: latestCourse.items,
      ramo: matched,
    );

    if (matched.id != null) {
      ref.invalidate(categoriaProvider(matched.id!));
    }
    await ref.read(semestreProvider.notifier).cargarSemestres();
    ref.invalidate(ramoProvider);
    widget.onAcademicDataChanged?.call();
    await _reloadLocalSettings();

    final msgParts = <String>[
      if (createdRamo) 'Ramo "${matched.nombre}" creado',
      if (synced.added > 0) '${synced.added} entrega(s) añadidas a Agenda',
      if (synced.added == 0 && synced.skipped > 0) 'Las entregas ya estaban en tu Agenda',
      if (synced.added == 0 && synced.skipped == 0 && !createdRamo) 'No hay fechas pendientes en este curso',
    ];
    _showSnack(msgParts.join(' · '));
  }

  Future<void> _importSingleItemToAgenda(
    MoodleCourse course,
    MoodleItem item,
    List<Ramo> ramos,
  ) async {
    var matched = _resolveMatchedRamo(course, ramos);
    if (matched == null) {
      final semestres = ref.read(semestreProvider);
      final settings = ref.read(settingsProvider);
      final semId = await AulaNotasSynergyService.ensureActiveSemester(
        currentSemesterId: widget.selectedSemesterId,
        semestres: semestres,
      );
      matched = await AulaNotasSynergyService.createRamoFromCourse(
        course: course,
        semesterId: semId,
        escalaNotas: settings.escalaNotas,
        orderIndex: ramos.length,
      );
      if (matched.id != null) {
        await _settings.setCourseRamoLink(course.id, matched.id);
      }
    }

    final res = await AulaNotasSynergyService.importDeadlinesToAgenda(
      items: [item],
      ramo: matched,
    );
    if (matched.id != null) ref.invalidate(categoriaProvider(matched.id!));
    ref.invalidate(ramoProvider);
    widget.onAcademicDataChanged?.call();
    await _reloadLocalSettings();

    if (res.added > 0) {
      _showSnack('"${item.cleanName}" añadida a Agenda (${matched.nombre})');
    } else {
      _showSnack('"${item.cleanName}" ya está en Agenda');
    }
  }

  Future<void> _downloadSingleItem(MoodleCourse course, MoodleItem item) async {
    try {
      setState(() => item.status = 'downloading');
      final saved = await _downloader.downloadItem(
        course: course,
        item: item,
        session: _session,
        downloadRoot: _downloadRoot,
        courseFolders: _courseFolders,
        courseSubfolders: _courseSubfolders,
        courseOrgSections: _courseOrgSections,
        onProgress: (_) {
          if (mounted) setState(() {});
        },
      );
      if (!mounted) return;
      setState(() {});
      if (saved != null) {
        _showSnack('Descargado: ${item.cleanName}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => item.status = 'error');
      _showSnack('Error descargando ${item.cleanName}: $e', isError: true);
    }
  }

  Future<void> _downloadMissingForCourse(MoodleCourse course) async {
    final pending = course.downloadableItems.where((i) => !i.isDownloaded).toList();
    if (pending.isEmpty) {
      _showSnack('Todos los archivos de ${course.cleanName} ya están descargados.');
      return;
    }
    setState(() {
      _batchDownloading = true;
      _batchProgress = 0.0;
    });
    int completed = 0;
    for (final item in pending) {
      await _downloadSingleItem(course, item);
      completed++;
      if (mounted) {
        setState(() => _batchProgress = completed / pending.length);
      }
    }
    if (mounted) setState(() => _batchDownloading = false);
  }

  Future<void> _downloadSelectedBatch() async {
    final entries = _selectedItemRefs.entries.toList();
    if (entries.isEmpty) return;

    setState(() {
      _batchDownloading = true;
      _batchProgress = 0.0;
    });

    int done = 0;
    for (final entry in entries) {
      final courseId = int.tryParse(entry.key.split('::').first);
      final course = _courses.where((c) => c.id == courseId).firstOrNull;
      if (course != null) {
        await _downloadSingleItem(course, entry.value);
      }
      done++;
      if (mounted) {
        setState(() => _batchProgress = done / entries.length);
      }
    }

    if (mounted) {
      setState(() {
        _batchDownloading = false;
        _selectedItemKeys.clear();
        _selectedItemRefs.clear();
      });
    }
  }

  Future<void> _openCourseFolder(MoodleCourse course) async {
    final dir = await _downloader.resolveCourseDirectory(
      course: course,
      downloadRoot: _downloadRoot,
      courseFolders: _courseFolders,
      courseSubfolders: _courseSubfolders,
    );
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [dir.path]);
    } else {
      await OpenFilex.open(dir.path);
    }
  }

  Future<void> _exportObsidian(MoodleCourse course) async {
    if (!course.isLoaded) await _ensureCourseLoaded(course);
    final updated = _courses.where((c) => c.id == course.id).firstOrNull ?? course;
    final targetRoot = (_obsidianVaultPath != null && _obsidianVaultPath!.isNotEmpty)
        ? _obsidianVaultPath!
        : _downloadRoot;
    final indexPath = await _downloader.exportCourseToObsidian(
      course: updated,
      vaultOrRootPath: targetRoot,
    );
    _showSnack('Grafo Obsidian exportado en:\n$indexPath');
  }

  void _toggleSelectItem(int courseId, MoodleItem item) {
    final compositeKey = '$courseId::${item.key}';
    setState(() {
      if (_selectedItemKeys.contains(compositeKey)) {
        _selectedItemKeys.remove(compositeKey);
        _selectedItemRefs.remove(compositeKey);
      } else {
        _selectedItemKeys.add(compositeKey);
        _selectedItemRefs[compositeKey] = item;
      }
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? theme.colorScheme.error : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<MoodleCourse> _visibleCourses() {
    final q = _searchQuery.trim().toLowerCase();
    return _courses.where((c) {
      if (!_showHiddenCourses && c.isHidden) return false;
      if (_showOnlyCurrentSemester && c.isCurrentSemester == false) return false;
      if (q.isNotEmpty) {
        final inName = c.cleanName.toLowerCase().contains(q) ||
            c.shortName.toLowerCase().contains(q) ||
            c.fullName.toLowerCase().contains(q);
        final inItems = c.items.any(
          (i) => i.cleanName.toLowerCase().contains(q) || (i.fileName ?? '').toLowerCase().contains(q),
        );
        if (!inName && !inItems) return false;
      }
      return true;
    }).toList();
  }

  List<MoodleItem> _filterCourseItems(MoodleCourse course) {
    final q = _searchQuery.trim().toLowerCase();
    return course.items.where((item) {
      if (q.isNotEmpty) {
        final matchCourse = course.cleanName.toLowerCase().contains(q);
        final matchItem = item.cleanName.toLowerCase().contains(q) ||
            (item.fileName ?? '').toLowerCase().contains(q) ||
            item.sectionName.toLowerCase().contains(q);
        if (!matchCourse && !matchItem) return false;
      }
      switch (_contentFilter) {
        case _AulaContentFilter.files:
          if (!item.isDownloadable) return false;
          break;
        case _AulaContentFilter.deadlines:
          if (!item.hasDeadline) return false;
          break;
        case _AulaContentFilter.downloaded:
          if (!item.isDownloaded) return false;
          break;
        case _AulaContentFilter.all:
          break;
      }
      if (_extensionFilter != null && _extensionFilter!.isNotEmpty) {
        if (item.normalizedExtension != _extensionFilter) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.visualTokens;
    final activeSemId = widget.selectedSemesterId;
    final List<Ramo> activeRamos =
        activeSemId != null ? ref.watch(ramoProvider(activeSemId)) : const [];

    return Scaffold(
      appBar: FrostedAppBar(
        title: Row(
          children: [
            TonalIconBadge(
              icon: Icons.cloud_download_rounded,
              color: tokens.accentColor,
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Aula USM', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  Text(
                    _session.hasCredentials
                        ? (_session.userName.isNotEmpty ? _session.userName : 'Sesión activa')
                        : 'Sin conexión institucional',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_session.hasCredentials)
            IconButton(
              tooltip: 'Sincronizar cursos de Aula',
              onPressed: _loadingCourses ? null : () => _refreshCourses(),
              icon: _loadingCourses
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
            ),
          IconButton(
            tooltip: 'Credenciales y vinculación PC',
            onPressed: _openAuthSheet,
            icon: const Icon(Icons.key_rounded),
          ),
          IconButton(
            tooltip: 'Ajustes de descargas y Obsidian',
            onPressed: _openGlobalSettings,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_initializing)
            const Center(child: CircularProgressIndicator())
          else if (!_session.hasCredentials)
            _buildUnauthenticatedView(theme, tokens)
          else
            _buildAuthenticatedBody(theme, tokens, activeRamos),
          if (_selectedItemKeys.isNotEmpty || _batchDownloading)
            Positioned(
              left: 16,
              right: 16,
              bottom: 108,
              child: _buildBatchDownloadDock(theme, tokens),
            ),
        ],
      ),
    );
  }

  Widget _buildUnauthenticatedView(ThemeData theme, NotasVisualTokens tokens) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
          child: FrostedGlassSurface(
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TonalIconBadge(
                      icon: Icons.school_rounded,
                      color: tokens.accentColor,
                      size: 54,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Conecta tu Aula USM',
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Sincroniza archivos, entregas con fecha en tu Agenda y grafos de Obsidian.',
                            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (Platform.isAndroid) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openWebViewLogin,
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Iniciar sesión en Aula (WebView USM)'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: Platform.isWindows
                      ? FilledButton.icon(
                          onPressed: _openAuthSheet,
                          icon: const Icon(Icons.vpn_key_rounded),
                          label: const Text('Importar de PC, Token o Vincular'),
                        )
                      : FilledButton.tonalIcon(
                          onPressed: _openAuthSheet,
                          icon: const Icon(Icons.phonelink_rounded),
                          label: const Text('Token WebService / Vincular PIN PC'),
                        ),
                ),
                const SizedBox(height: 18),
                ExpressiveGroupedSection(
                  margin: EdgeInsets.zero,
                  children: [
                    ListTile(
                      leading: TonalIconBadge(icon: Icons.sync_alt_rounded, color: tokens.accentColor),
                      title: const Text('Sinergia directa con Ramos y Agenda'),
                      subtitle: const Text(
                        'Importa ramos faltantes con su color y manda tareas/certámenes directo a tus recordatorios.',
                      ),
                    ),
                    ListTile(
                      leading: TonalIconBadge(icon: Icons.folder_zip_rounded, color: tokens.accentColor),
                      title: const Text('Descarga inteligente multi-curso'),
                      subtitle: const Text(
                        'Organiza PDF, guías y diapositivas por carpeta o semana, sin volver a descargar repetidos.',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthenticatedBody(
    ThemeData theme,
    NotasVisualTokens tokens,
    List<Ramo> activeRamos,
  ) {
    final visible = _visibleCourses();
    final unlinked = visible.where((c) => _resolveMatchedRamo(c, activeRamos) == null).toList();
    final totalDeadlines = _courses.fold<int>(0, (sum, c) => sum + c.pendingDeadlineCount);
    final availableExtensions = <String>{};
    for (final c in visible) {
      for (final item in c.items) {
        final ext = item.normalizedExtension;
        if (ext.isNotEmpty) availableExtensions.add(ext);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 860;
        if (isWide) {
          final selected = visible.where((c) => c.id == _selectedDesktopCourseId).firstOrNull ??
              (visible.isNotEmpty ? visible.first : null);
          return Row(
            children: [
              SizedBox(
                width: 360,
                child: Column(
                  children: [
                    _buildControlsHeader(theme, tokens, visible, unlinked, totalDeadlines, activeRamos, availableExtensions, compact: true),
                    Expanded(
                      child: visible.isEmpty
                          ? _buildEmptyCoursesState(theme)
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 120),
                              itemCount: visible.length,
                              itemBuilder: (_, idx) {
                                final course = visible[idx];
                                final matched = _resolveMatchedRamo(course, activeRamos);
                                final isSelected = selected?.id == course.id;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _buildDesktopCourseTile(
                                    theme,
                                    tokens,
                                    course,
                                    matched,
                                    isSelected,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35)),
              Expanded(
                child: selected == null
                    ? _buildEmptyCoursesState(theme)
                    : _buildDesktopCourseDetailPane(theme, tokens, selected, activeRamos),
              ),
            ],
          );
        }

        // Mobile / narrow layout
        return RefreshIndicator(
          onRefresh: _refreshCourses,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 124),
            children: [
              _buildControlsHeader(
                theme,
                tokens,
                visible,
                unlinked,
                totalDeadlines,
                activeRamos,
                availableExtensions,
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(tokens.cardRadius),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ),
              if (visible.isEmpty && !_loadingCourses)
                _buildEmptyCoursesState(theme)
              else
                for (final course in visible)
                  _buildMobileCourseCard(
                    theme,
                    tokens,
                    course,
                    _resolveMatchedRamo(course, activeRamos),
                    activeRamos,
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlsHeader(
    ThemeData theme,
    NotasVisualTokens tokens,
    List<MoodleCourse> visible,
    List<MoodleCourse> unlinked,
    int totalDeadlines,
    List<Ramo> activeRamos,
    Set<String> extensions, {
    bool compact = false,
  }) {
    final downloadedCount = visible.fold<int>(0, (s, c) => s + c.downloadedCount);
    final downloadableCount = visible.fold<int>(0, (s, c) => s + c.downloadableCount);

    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 8, compact ? 12 : 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Academic synergy banner
          FrostedGlassSurface(
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 18, color: tokens.accentColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${visible.length} cursos · $downloadedCount/$downloadableCount descargas · $totalDeadlines entregas',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                if (unlinked.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _importMissingRamos(unlinked, activeRamos),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                      label: Text('Importar ${unlinked.length} ramo(s) faltantes a NotasApp'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Buscar ramo, archivo o entrega...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  selected: _showOnlyCurrentSemester,
                  label: const Text('Semestre actual'),
                  onSelected: (v) => setState(() => _showOnlyCurrentSemester = v),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  selected: _contentFilter == _AulaContentFilter.all,
                  label: const Text('Todo'),
                  onSelected: (_) => setState(() => _contentFilter = _AulaContentFilter.all),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  selected: _contentFilter == _AulaContentFilter.files,
                  label: const Text('Archivos'),
                  onSelected: (_) => setState(() => _contentFilter = _AulaContentFilter.files),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  selected: _contentFilter == _AulaContentFilter.deadlines,
                  label: const Text('Entregas'),
                  onSelected: (_) => setState(() => _contentFilter = _AulaContentFilter.deadlines),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  selected: _contentFilter == _AulaContentFilter.downloaded,
                  label: const Text('Descargados'),
                  onSelected: (_) => setState(() => _contentFilter = _AulaContentFilter.downloaded),
                ),
                if (extensions.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  for (final ext in extensions.take(6)) ...[
                    FilterChip(
                      selected: _extensionFilter == ext,
                      label: Text(ext.toUpperCase()),
                      onSelected: (sel) => setState(() => _extensionFilter = sel ? ext : null),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
                if (_hiddenCourseIds.isNotEmpty)
                  FilterChip(
                    selected: _showHiddenCourses,
                    label: Text('Ocultos (${_hiddenCourseIds.length})'),
                    onSelected: (v) => setState(() => _showHiddenCourses = v),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopCourseTile(
    ThemeData theme,
    NotasVisualTokens tokens,
    MoodleCourse course,
    Ramo? matched,
    bool isSelected,
  ) {
    final accent = matched?.color != null ? Color(matched!.color!) : tokens.accentColor;
    final promedioText = _formatMatchedAverage(matched);

    return Material(
      color: isSelected
          ? accent.withValues(alpha: 0.14)
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(tokens.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          setState(() => _selectedDesktopCourseId = course.id);
          _ensureCourseLoaded(course);
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected
                  ? accent
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: isSelected ? 1.5 : 1.0,
            ),
            borderRadius: BorderRadius.circular(tokens.cardRadius),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 44,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.cleanName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (course.courseCode != null)
                          _miniBadge(course.courseCode!, theme.colorScheme.surfaceContainerHighest,
                              theme.colorScheme.onSurfaceVariant),
                        if (matched != null)
                          _miniBadge(
                            promedioText != null ? '${matched.nombre} · $promedioText' : 'En NotasApp',
                            accent.withValues(alpha: 0.16),
                            accent,
                          ),
                        if (course.pendingDeadlineCount > 0)
                          _miniBadge(
                            '${course.pendingDeadlineCount} entregas',
                            Colors.orange.withValues(alpha: 0.16),
                            Colors.deepOrange,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopCourseDetailPane(
    ThemeData theme,
    NotasVisualTokens tokens,
    MoodleCourse course,
    List<Ramo> activeRamos,
  ) {
    final matched = _resolveMatchedRamo(course, activeRamos);
    final accent = matched?.color != null ? Color(matched!.color!) : tokens.accentColor;
    final items = _filterCourseItems(course);
    final isLoading = _loadingCourseIds.contains(course.id);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 124),
      children: [
        FrostedGlassSurface(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          borderColor: accent.withValues(alpha: 0.4),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TonalIconBadge(icon: Icons.menu_book_rounded, color: accent, size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.cleanName,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${course.shortName} · ${course.downloadedCount}/${course.downloadableCount} archivos',
                          style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Recargar contenido del curso',
                    onPressed: isLoading ? null : () => _ensureCourseLoaded(course, force: true),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _downloadMissingForCourse(course),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Descargar faltantes'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _importCourseToRamoAndAgenda(course, activeRamos),
                    icon: Icon(matched == null ? Icons.add_rounded : Icons.event_available_rounded, size: 18),
                    label: Text(matched == null ? 'Crear Ramo + Agenda' : 'Sincronizar a Agenda'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openCourseFolder(course),
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('Abrir carpeta'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _exportObsidian(course),
                    icon: const Icon(Icons.hub_rounded, size: 18),
                    label: const Text('Obsidian .md'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openCourseConfig(course, activeRamos),
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('Configurar'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ..._buildGroupedItemSections(theme, tokens, course, items, activeRamos, accent),
      ],
    );
  }

  Widget _buildMobileCourseCard(
    ThemeData theme,
    NotasVisualTokens tokens,
    MoodleCourse course,
    Ramo? matched,
    List<Ramo> activeRamos,
  ) {
    final accent = matched?.color != null ? Color(matched!.color!) : tokens.accentColor;
    final expanded = _expandedCourseIds.contains(course.id);
    final isLoading = _loadingCourseIds.contains(course.id);
    final items = _filterCourseItems(course);
    final promedioText = _formatMatchedAverage(matched);

    final bool applyTint = tokens.subjectColorStyle == 'tinte' ||
        tokens.subjectColorStyle == 'mixto' ||
        tokens.subjectColorStyle == 'degradado';
    final bool applyBorder = tokens.subjectColorStyle == 'borde' ||
        tokens.subjectColorStyle == 'mixto' ||
        tokens.subjectColorStyle == 'neon';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: applyTint
            ? accent.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            border: Border.all(
              color: applyBorder
                  ? accent.withValues(alpha: 0.5)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: applyBorder ? 1.4 : 1.0,
            ),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  AppHaptics.selection(context);
                  setState(() {
                    if (expanded) {
                      _expandedCourseIds.remove(course.id);
                    } else {
                      _expandedCourseIds.add(course.id);
                    }
                  });
                  if (!expanded) {
                    _ensureCourseLoaded(course);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Row(
                    children: [
                      TonalIconBadge(
                        icon: Icons.class_rounded,
                        color: accent,
                        size: 42,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              course.cleanName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (course.courseCode != null)
                                  _miniBadge(
                                    course.courseCode!,
                                    theme.colorScheme.surfaceContainerHighest,
                                    theme.colorScheme.onSurfaceVariant,
                                  ),
                                if (matched != null)
                                  _miniBadge(
                                    promedioText != null ? '${matched.nombre} ($promedioText)' : matched.nombre,
                                    accent.withValues(alpha: 0.16),
                                    accent,
                                  ),
                                if (course.isLoaded)
                                  _miniBadge(
                                    '${course.downloadedCount}/${course.downloadableCount} arch.',
                                    theme.colorScheme.secondaryContainer,
                                    theme.colorScheme.onSecondaryContainer,
                                  ),
                                if (course.pendingDeadlineCount > 0)
                                  _miniBadge(
                                    '${course.pendingDeadlineCount} pend.',
                                    Colors.orange.withValues(alpha: 0.18),
                                    Colors.deepOrange,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                    ],
                  ),
                ),
              ),
              if (expanded) ...[
                Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.download_rounded, size: 16),
                          label: const Text('Descargar todo'),
                          onPressed: () => _downloadMissingForCourse(course),
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: Icon(
                            matched == null ? Icons.add_rounded : Icons.event_available_rounded,
                            size: 16,
                          ),
                          label: Text(matched == null ? 'Agregar Ramo' : 'Sincronizar Agenda'),
                          onPressed: () => _importCourseToRamoAndAgenda(course, activeRamos),
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: const Icon(Icons.folder_open_rounded, size: 16),
                          label: const Text('Carpeta'),
                          onPressed: () => _openCourseFolder(course),
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: const Icon(Icons.hub_rounded, size: 16),
                          label: const Text('Obsidian .md'),
                          onPressed: () => _exportObsidian(course),
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: const Icon(Icons.tune_rounded, size: 16),
                          label: const Text('Configurar'),
                          onPressed: () => _openCourseConfig(course, activeRamos),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                    child: Column(
                      children: _buildGroupedItemSections(
                        theme,
                        tokens,
                        course,
                        items,
                        activeRamos,
                        accent,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGroupedItemSections(
    ThemeData theme,
    NotasVisualTokens tokens,
    MoodleCourse course,
    List<MoodleItem> items,
    List<Ramo> activeRamos,
    Color accent,
  ) {
    if (items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(
            'Sin elementos que coincidan con el filtro.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ];
    }

    final grouped = <String, List<MoodleItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.sectionName, () => []).add(item);
    }

    final widgets = <Widget>[];
    for (final entry in grouped.entries) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
          child: Text(
            entry.key,
            style: theme.textTheme.labelLarge?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
      widgets.add(
        ExpressiveGroupedSection(
          margin: EdgeInsets.zero,
          children: [
            for (final item in entry.value)
              _buildItemRow(theme, tokens, course, item, activeRamos, accent),
          ],
        ),
      );
    }
    return widgets;
  }

  Widget _buildItemRow(
    ThemeData theme,
    NotasVisualTokens tokens,
    MoodleCourse course,
    MoodleItem item,
    List<Ramo> activeRamos,
    Color accent,
  ) {
    final compositeKey = '${course.id}::${item.key}';
    final isSelected = _selectedItemKeys.contains(compositeKey);
    final iconData = _iconForItem(item);

    return ListTile(
      dense: true,
      leading: item.isDownloadable
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => _toggleSelectItem(course.id, item),
            )
          : Icon(iconData, color: accent, size: 22),
      title: Text(
        item.cleanName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: item.completed ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: _buildItemSubtitle(theme, item),
      trailing: _buildItemTrailing(theme, course, item, activeRamos, accent),
      onTap: () async {
        if (item.isDownloaded && item.localPath != null) {
          await OpenFilex.open(item.localPath!);
        } else if (item.isDownloadable) {
          await _downloadSingleItem(course, item);
        } else if (item.url != null && item.url!.isNotEmpty) {
          await launchUrl(Uri.parse(item.url!), mode: LaunchMode.externalApplication);
        }
      },
    );
  }

  Widget? _buildItemSubtitle(ThemeData theme, MoodleItem item) {
    final parts = <String>[];
    if (item.formattedSize.isNotEmpty) parts.add(item.formattedSize);
    if (item.normalizedExtension.isNotEmpty) parts.add(item.normalizedExtension.toUpperCase());
    if (item.dueDate != null) {
      final dt = item.dueDate!;
      final diff = dt.difference(DateTime.now());
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      final tag = diff.isNegative
          ? 'Venció ${dt.day}/${dt.month}'
          : diff.inDays > 0
              ? 'Vence en ${diff.inDays}d (${dt.day}/${dt.month} $hh:$mm)'
              : 'Hoy $hh:$mm';
      parts.add(tag);
    }
    if (item.isDownloaded) parts.add('Guardado');
    if (item.type == 'folder' && item.subFiles.isNotEmpty) {
      parts.add('${item.subFiles.length} archivos');
    }
    if (parts.isEmpty) return null;

    return Text(
      parts.join(' · '),
      style: TextStyle(
        fontSize: 11.5,
        color: item.isPendingSubmission
            ? Colors.deepOrange
            : (item.isDownloaded ? Colors.green.shade700 : theme.colorScheme.onSurfaceVariant),
        fontWeight: item.isPendingSubmission ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  Widget _buildItemTrailing(
    ThemeData theme,
    MoodleCourse course,
    MoodleItem item,
    List<Ramo> activeRamos,
    Color accent,
  ) {
    if (item.isDownloading) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          value: item.downloadProgress > 0 ? item.downloadProgress : null,
        ),
      );
    }
    if (item.hasDeadline) {
      return IconButton(
        tooltip: 'Añadir a Agenda de NotasApp',
        icon: Icon(Icons.event_note_rounded, color: accent),
        onPressed: () => _importSingleItemToAgenda(course, item, activeRamos),
      );
    }
    if (item.isDownloaded) {
      return IconButton(
        tooltip: 'Abrir archivo',
        icon: const Icon(Icons.check_circle_rounded, color: Colors.green),
        onPressed: () {
          if (item.localPath != null) OpenFilex.open(item.localPath!);
        },
      );
    }
    if (item.isDownloadable) {
      return IconButton(
        tooltip: 'Descargar',
        icon: Icon(Icons.download_for_offline_outlined, color: accent),
        onPressed: () => _downloadSingleItem(course, item),
      );
    }
    return const Icon(Icons.open_in_new_rounded, size: 18);
  }

  Widget _buildBatchDownloadDock(ThemeData theme, NotasVisualTokens tokens) {
    return FrostedGlassSurface(
      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.14),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
      child: Row(
        children: [
          if (_batchDownloading) ...[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, value: _batchProgress),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Descargando lote (${(_batchProgress * 100).round()}%)...',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ] else ...[
            Expanded(
              child: Text(
                '${_selectedItemKeys.length} archivo(s) seleccionados',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _selectedItemKeys.clear();
                _selectedItemRefs.clear();
              }),
              child: const Text('Limpiar'),
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              onPressed: _downloadSelectedBatch,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Descargar'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyCoursesState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_done_rounded, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              'No hay cursos visibles con este filtro',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => setState(() {
                _showOnlyCurrentSemester = false;
                _searchCtrl.clear();
                _searchQuery = '';
                _contentFilter = _AulaContentFilter.all;
                _extensionFilter = null;
              }),
              icon: const Icon(Icons.filter_alt_off_rounded),
              label: const Text('Ver todos los cursos'),
            ),
          ],
        ),
      ),
    );
  }

  String? _formatMatchedAverage(Ramo? matched) {
    if (matched == null || matched.id == null) return null;
    final cats = ref.watch(categoriaProvider(matched.id!));
    if (cats.isEmpty) return null;
    final copy = Ramo(
      id: matched.id,
      idSemestre: matched.idSemestre,
      nombre: matched.nombre,
      tipoPromedio: matched.tipoPromedio,
      tieneGlobal: matched.tieneGlobal,
      reemplazaPeorNota: matched.reemplazaPeorNota,
      notaAprobacion: matched.notaAprobacion,
      orderIndex: matched.orderIndex,
      color: matched.color,
      categorias: cats,
    );
    final avg = copy.calcularNotaActual();
    if (avg <= 0) return null;
    return avg.toStringAsFixed(1);
  }

  IconData _iconForItem(MoodleItem item) {
    switch (item.type) {
      case 'assignment':
        return Icons.assignment_rounded;
      case 'quiz':
        return Icons.quiz_rounded;
      case 'folder':
        return Icons.folder_rounded;
      case 'url':
        return Icons.link_rounded;
      case 'forum':
        return Icons.forum_rounded;
      case 'page':
        return Icons.article_rounded;
      default:
        final ext = item.normalizedExtension;
        if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
        if (ext == 'ppt' || ext == 'pptx') return Icons.slideshow_rounded;
        if (ext == 'zip' || ext == 'rar' || ext == '7z') return Icons.folder_zip_rounded;
        return Icons.insert_drive_file_rounded;
    }
  }

  Widget _miniBadge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
