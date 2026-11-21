import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/aula_course.dart';
import '../models/ramo.dart';
import '../services/aula_service.dart';
import 'aula_sheets.dart';

enum ResourceFilter { files, pending, deadlines, all }

class AulaView extends StatefulWidget {
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
  State<AulaView> createState() => _AulaViewState();
}

class _AulaViewState extends State<AulaView> with AutomaticKeepAliveClientMixin {
  final SettingsService _settings = SettingsService.instance;
  final MoodleService _moodle = MoodleService();
  late final DownloaderService _downloader =
      DownloaderService(moodle: _moodle, settings: _settings);
  final AulaNotasSynergyService _synergy = AulaNotasSynergyService();

  final TextEditingController _searchCtrl = TextEditingController();
  final Set<int> _expandedCourseIds = {};
  final Set<String> _collapsedSections = {};
  final Set<int> _sizingStartedIds = {};

  List<MoodleCourse> _courses = [];
  int _coursesRevision = 0;
  List<MoodleCourse>? _cachedVisibleCourses;
  int _cachedRevision = -1;
  String? _cachedQuery;
  bool? _cachedShowHidden;

  List<Ramo> _semesterRamos = [];
  int? _activeSemesterId;
  List<String> _existingSubfolders = [];
  int? _wideSelectedCourseId;

  // Login screen state
  int _selectedAuthTab = Platform.isAndroid ? 0 : 1; // 0: Browser, 1: Token, 2: Cookie
  bool _isAuthenticating = false;

  // Courses screen state
  late bool _isInitializing = widget.autoLoad;
  bool _isScanning = false;
  bool _isDownloading = false;
  bool _hasStoragePermission = true;
  bool _showHiddenCourses = false;
  bool _radarExpanded = false;
  ResourceFilter _filter = ResourceFilter.files;
  String _searchQuery = '';
  int _dlCurrent = 0;
  int _dlTotal = 0;
  String _dlLabel = '';
  String? _statusBanner;

  @override
  bool get wantKeepAlive => true;

  void _invalidateCoursesCache() => _coursesRevision++;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (_searchQuery != _searchCtrl.text) {
        setState(() => _searchQuery = _searchCtrl.text.trim());
      }
    });
    if (widget.autoLoad) {
      _initScreen();
    } else {
      _initMinimalForTest();
    }
  }

  Future<void> _initMinimalForTest() async {
    await _moodle.loadSession();
    if (mounted) {
      setState(() => _isInitializing = false);
    }
  }

  @override
  void didUpdateWidget(covariant AulaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoLoad &&
        _moodle.isAuthenticated &&
        (widget.refreshTick != oldWidget.refreshTick ||
            widget.selectedSemesterId != oldWidget.selectedSemesterId)) {
      _refreshNotasSynergy();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _moodle.dispose();
    super.dispose();
  }

  Future<void> _performLogout() async {
    await _moodle.logout();
    if (!mounted) return;
    setState(() {
      _courses = [];
      _invalidateCoursesCache();
      _expandedCourseIds.clear();
      _collapsedSections.clear();
      _sizingStartedIds.clear();
      _wideSelectedCourseId = null;
      _statusBanner = null;
      _searchCtrl.clear();
      _searchQuery = '';
      _dlCurrent = 0;
      _dlTotal = 0;
      _dlLabel = '';
    });
  }

  Future<void> _openLocalFileWithGuard(String path) async {
    if (SettingsService.isDangerousFile(path)) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Archivo potencialmente peligroso'),
          content: Text(
            'El archivo "${p.basename(path)}" es ejecutable o un script y podría ejecutar código en tu dispositivo. ¿Deseas abrirlo de todas formas?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Abrir de todos modos'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      await _settings.openLocalFile(path, allowDangerous: true);
      return;
    }
    await _settings.openLocalFile(path);
  }

  Future<void> _initScreen() async {
    setState(() => _isInitializing = true);
    await _moodle.loadSession();

    if (!_moodle.isAuthenticated) {
      await _settings.load();
      if (mounted) setState(() => _isInitializing = false);
      return;
    }

    await _settings.load();
    _hasStoragePermission = await _settings.hasStoragePermission();
    _filter = _filterFromKey(_settings.defaultFilterKey);

    await _refreshNotasSynergy();

    // Load cached scan immediately for zero-wait responsiveness
    final cached = await _settings.loadScanCache();
    if (cached.isNotEmpty) {
      await _applyCourseConfigs(cached);
      await _moodle.enrichItemsWithLocalStatus(cached, _settings);
      if (mounted) {
        setState(() {
          _courses = cached;
          _invalidateCoursesCache();
          _wideSelectedCourseId ??=
              cached.isNotEmpty ? cached.first.id : null;
          _isInitializing = false;
        });
      }
    } else {
      if (mounted) setState(() => _isInitializing = false);
    }

    await _scanAula(silentIfCached: cached.isNotEmpty);
  }

  ResourceFilter _filterFromKey(String key) {
    switch (key) {
      case 'pending':
        return ResourceFilter.pending;
      case 'deadlines':
        return ResourceFilter.deadlines;
      case 'all':
        return ResourceFilter.all;
      default:
        return ResourceFilter.files;
    }
  }

  String _keyFromFilter(ResourceFilter f) => f.name;

  Future<void> _refreshNotasSynergy() async {
    try {
      final sem = await _synergy.ensureActiveSemester(widget.selectedSemesterId);
      if (sem.id != null) {
        final ramos = await _synergy.loadRamosForSemester(sem.id!);
        final links = await _settings.getCourseRamoLinks();
        if (mounted) {
          setState(() {
            _activeSemesterId = sem.id;
            _semesterRamos = ramos;
            for (final c in _courses) {
              if (links.containsKey(c.id)) {
                final stored = links[c.id];
                c.linkedRamoId = stored == SettingsService.unlinkedRamoSentinel
                    ? null
                    : stored;
              } else {
                c.linkedRamoId = MoodleCourse.findMatchingRamo(c, ramos)?.id;
              }
            }
            _invalidateCoursesCache();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _applyCourseConfigs(List<MoodleCourse> list) async {
    _existingSubfolders = await _settings.listExistingSubfolders();
    final links = await _settings.getCourseRamoLinks();
    for (final c in list) {
      final resolvedFolder = _settings.resolveCourseFolderSync(
        courseId: c.id,
        fullname: c.fullname,
        cleanName: c.cleanName,
        shortname: c.shortname,
        existingFolders: _existingSubfolders,
      );
      c.obsidianFolder = resolvedFolder ??
          MoodleCourse.sanitizeFileName(c.cleanName);
      c.targetSubfolder = _settings.getCourseSubfolder(c.id);
      c.organizeBySection = _settings.getCourseOrganizeBySection(c.id);
      c.isHidden = _settings.hiddenCourseIds.contains(c.id);
      if (links.containsKey(c.id)) {
        final stored = links[c.id];
        c.linkedRamoId =
            stored == SettingsService.unlinkedRamoSentinel ? null : stored;
      } else {
        c.linkedRamoId = MoodleCourse.findMatchingRamo(c, _semesterRamos)?.id;
      }
    }
  }

  Future<void> _scanAula({bool silentIfCached = false}) async {
    if (_isScanning || _isDownloading || !_moodle.isAuthenticated) return;
    _sizingStartedIds.clear();
    setState(() {
      _isScanning = true;
      if (!silentIfCached) _statusBanner = 'Conectando con Aula USM...';
    });

    try {
      final fetchedCourses = await _moodle.getCourses();
      await _applyCourseConfigs(fetchedCourses);

      // Preserve existing items briefly while rescanning
      final prevMap = {for (final c in _courses) c.id: c.items};
      for (final c in fetchedCourses) {
        if (prevMap.containsKey(c.id)) c.items = prevMap[c.id]!;
      }
      if (mounted) {
        setState(() {
          _courses = fetchedCourses;
          _invalidateCoursesCache();
          _wideSelectedCourseId ??=
              fetchedCourses.isNotEmpty ? fetchedCourses.first.id : null;
        });
      }

      // Scan visible courses with bounded concurrency (3)
      final toScan = fetchedCourses
          .where((c) => !c.isHidden || _showHiddenCourses)
          .toList();
      var done = 0;

      for (var i = 0; i < toScan.length; i += 3) {
        final batch = toScan.sublist(
          i,
          i + 3 > toScan.length ? toScan.length : i + 3,
        );
        await Future.wait(batch.map((course) async {
          course.isLoadingContents = true;
          course.scanError = null;
          try {
            final items = await _moodle.scanCourseContents(course);
            course.items = items;
          } on SessionExpiredException {
            rethrow;
          } catch (e) {
            course.scanError = e.toString();
          } finally {
            course.isLoadingContents = false;
            done++;
            if (mounted) {
              setState(() {
                _statusBanner =
                    'Escaneando Aula ($done/${toScan.length}): ${course.cleanName}';
              });
            }
          }
        }));
      }

      await _moodle.enrichItemsWithLocalStatus(fetchedCourses, _settings);
      await _settings.saveScanCache(fetchedCourses);
      await _moodle.processScanNotifications(
        courses: fetchedCourses,
        settings: _settings,
      );

      if (mounted) {
        setState(() {
          _courses = fetchedCourses;
          _invalidateCoursesCache();
          _isScanning = false;
          _statusBanner = null;
        });
      }
    } on SessionExpiredException catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _statusBanner = null;
        });
        _showSessionExpiredPrompt(e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _statusBanner = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al escanear Aula USM: $e')),
        );
      }
    }
  }

  void _showSessionExpiredPrompt(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Reconectar',
          onPressed: _performLogout,
        ),
      ),
    );
  }

  Future<void> _pickFolder() async {
    final chosen = await showFolderPickerDialog(context, _settings);
    if (chosen == null || chosen.isEmpty) return;
    await _settings.setDownloadRoot(chosen);
    await _applyCourseConfigs(_courses);
    await _moodle.enrichItemsWithLocalStatus(_courses, _settings);
    if (mounted) setState(() {});
  }

  Future<void> _syncAllObsidianGraphs() async {
    if (_courses.isEmpty) return;
    var ok = 0;
    for (final c in _courses) {
      if (c.isHidden || c.items.isEmpty) continue;
      try {
        await _downloader.syncCourseObsidianIndex(c);
        ok++;
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Índices .md de Obsidian actualizados para $ok ramo(s).'),
      ),
    );
  }

  Future<void> _syncAllCoursesWithNotasApp() async {
    final sem = await _synergy.ensureActiveSemester(_activeSemesterId);
    if (sem.id == null) return;

    var createdRamos = 0;
    var syncedEvals = 0;
    final currentRamos = List<Ramo>.from(_semesterRamos);

    for (final course in _courses) {
      if (course.isHidden) continue;
      var matched = MoodleCourse.findMatchingRamo(course, currentRamos);
      if (matched == null) {
        matched = await _synergy.createRamoFromCourse(
          course,
          semesterId: sem.id!,
        );
        currentRamos.add(matched);
        createdRamos++;
      } else {
        course.linkedRamoId = matched.id;
        await _settings.setCourseRamoLink(course.id, matched.id);
      }
      syncedEvals += await _synergy.syncCourseDeadlinesToRamo(
        course: course,
        ramo: matched,
      );
    }

    await _refreshNotasSynergy();
    widget.onAcademicDataChanged?.call();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'NotasApp sincronizado: +$createdRamos ramo(s) creado(s), +$syncedEvals entrega(s) en Agenda.',
        ),
      ),
    );
  }

  Future<void> _syncSingleDeadlineToAgenda(
    MoodleCourse course,
    MoodleItem item,
  ) async {
    final sem = await _synergy.ensureActiveSemester(_activeSemesterId);
    if (sem.id == null) return;
    var ramo = MoodleCourse.findMatchingRamo(course, _semesterRamos);
    ramo ??= await _synergy.createRamoFromCourse(course, semesterId: sem.id!);
    final count = await _synergy.syncCourseDeadlinesToRamo(
      course: course,
      ramo: ramo,
      specificItems: [item],
    );
    await _refreshNotasSynergy();
    widget.onAcademicDataChanged?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count > 0
              ? 'Agregado "${item.title}" al ramo "${ramo.nombre}" y tu Agenda.'
              : '"${item.title}" ya estaba en "${ramo.nombre}".',
        ),
      ),
    );
  }

  // Selection helpers
  void _selectAllPending() {
    setState(() {
      for (final c in _visibleCourses) {
        for (final it in _filteredItemsForCourse(c)) {
          if (!it.downloadable) continue;
          if (_settings.skipAlreadyDownloaded && it.isDownloaded) continue;
          if (_settings.skipSeenOnSelect && !it.isNew) continue;
          if (_settings.maxAutoSelectMb > 0 &&
              it.sizeBytes != null &&
              it.sizeBytes! > _settings.maxAutoSelectMb * 1024 * 1024) {
            continue;
          }
          if (_settings.preferredExtensions.isNotEmpty &&
              it.effectiveExt.isNotEmpty &&
              !_settings.preferredExtensions.contains(it.effectiveExt)) {
            continue;
          }
          it.isSelected = true;
        }
      }
    });
  }

  void _clearSelection() {
    setState(() {
      for (final c in _courses) {
        for (final it in c.items) {
          it.isSelected = false;
        }
      }
    });
  }

  void _toggleCourseSelection(MoodleCourse course, bool select) {
    setState(() {
      for (final it in _filteredItemsForCourse(course)) {
        if (!it.downloadable) continue;
        if (select && _settings.skipAlreadyDownloaded && it.isDownloaded) {
          continue;
        }
        it.isSelected = select;
      }
    });
  }

  void _toggleSectionSelection(List<MoodleItem> secItems, bool select) {
    setState(() {
      for (final it in secItems) {
        if (!it.downloadable) continue;
        if (select && _settings.skipAlreadyDownloaded && it.isDownloaded) {
          continue;
        }
        it.isSelected = select;
      }
    });
  }

  Future<void> _startDownload() async {
    if (_isDownloading || _isScanning) return;
    setState(() {
      _isDownloading = true;
      _dlCurrent = 0;
      _dlTotal = 0;
      _dlLabel = 'Preparando descargas...';
    });

    try {
      final result = await _downloader.downloadSelectedItems(
        _courses,
        onProgress: (cur, total, item) {
          if (mounted) {
            setState(() {
              _dlCurrent = cur;
              _dlTotal = total;
              _dlLabel = item.title;
            });
          }
        },
      );

      await _settings.saveScanCache(_courses);
      if (!mounted) return;
      setState(() => _isDownloading = false);

      final summary = result.failed > 0
          ? 'Guardados: ${result.savedFiles} · Omitidos: ${result.skipped} · Errores: ${result.failed}'
          : 'Guardados: ${result.savedFiles} archivo(s)${result.skipped > 0 ? " (${result.skipped} omitidos)" : ""}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(summary)),
      );
    } on StoragePermissionException catch (e) {
      if (!mounted) return;
      setState(() => _isDownloading = false);
      _hasStoragePermission = await _settings.hasStoragePermission();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          action: Platform.isAndroid
              ? SnackBarAction(
                  label: 'Permitir',
                  onPressed: () => _settings.openAppAllFilesSettings(),
                )
              : null,
        ),
      );
    } on SessionExpiredException catch (e) {
      if (!mounted) return;
      setState(() => _isDownloading = false);
      _showSessionExpiredPrompt(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDownloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al descargar: $e')),
      );
    }
  }

  List<MoodleCourse> get _visibleCourses {
    if (_cachedVisibleCourses != null &&
        _cachedRevision == _coursesRevision &&
        _cachedQuery == _searchQuery &&
        _cachedShowHidden == _showHiddenCourses) {
      return _cachedVisibleCourses!;
    }
    final q = _searchQuery.isEmpty
        ? ''
        : MoodleCourse.normalizeForMatch(_searchQuery);
    final computed = _courses
        .where((c) => _showHiddenCourses || !c.isHidden)
        .where((c) {
          if (q.isEmpty) return true;
          if (MoodleCourse.normalizeForMatch(c.cleanName).contains(q) ||
              MoodleCourse.normalizeForMatch(c.shortname).contains(q)) {
            return true;
          }
          return c.items.any((it) =>
              MoodleCourse.normalizeForMatch(it.title).contains(q) ||
              MoodleCourse.normalizeForMatch(it.section).contains(q));
        })
        .toList();
    _cachedVisibleCourses = computed;
    _cachedRevision = _coursesRevision;
    _cachedQuery = _searchQuery;
    _cachedShowHidden = _showHiddenCourses;
    return computed;
  }

  List<MoodleItem> _filteredItemsForCourse(MoodleCourse course) {
    final q = _searchQuery.isEmpty
        ? ''
        : MoodleCourse.normalizeForMatch(_searchQuery);
    final courseNameMatches = q.isNotEmpty &&
        (MoodleCourse.normalizeForMatch(course.cleanName).contains(q) ||
            MoodleCourse.normalizeForMatch(course.shortname).contains(q));

    return course.items.where((it) {
      if (q.isNotEmpty && !courseNameMatches) {
        final inTitle = MoodleCourse.normalizeForMatch(it.title).contains(q);
        final inSec = MoodleCourse.normalizeForMatch(it.section).contains(q);
        if (!inTitle && !inSec) return false;
      }

      switch (_filter) {
        case ResourceFilter.files:
          return it.downloadable;
        case ResourceFilter.pending:
          return it.downloadable && !it.isDownloaded;
        case ResourceFilter.deadlines:
          return it.hasDeadline ||
              it.type == 'assign' ||
              it.type == 'assignment' ||
              it.type == 'quiz';
        case ResourceFilter.all:
          return true;
      }
    }).toList();
  }

  // ===========================================================================
  // Build Root
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_moodle.isAuthenticated) {
      return _buildLoginView(context);
    }
    return _buildCoursesView(context);
  }

  // ===========================================================================
  // 1. Login View (Diseño fiel a Aula-Scrapt + Sinergia PC/Android)
  // ===========================================================================

  Widget _buildLoginView(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomNavClearance = 104.0 + MediaQuery.of(context).padding.bottom;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomNavClearance),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                // Brand Hero matching Aula-Scrapt
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.primaryContainer, cs.secondaryContainer],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Image.asset(
                      'assets/aula_logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.school_rounded,
                        size: 46,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Aula-Scrapt USM',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sincronizador Material 3 para Aula USM & Obsidian',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),

                // Main Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Método de conexión',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(
                            value: 0,
                            icon: Icon(Icons.public_rounded, size: 17),
                            label: Text('Navegador'),
                          ),
                          ButtonSegment(
                            value: 1,
                            icon: Icon(Icons.vpn_key_rounded, size: 17),
                            label: Text('Token'),
                          ),
                          ButtonSegment(
                            value: 2,
                            icon: Icon(Icons.cookie_rounded, size: 17),
                            label: Text('Cookie'),
                          ),
                        ],
                        selected: {_selectedAuthTab},
                        onSelectionChanged: (sel) {
                          setState(() => _selectedAuthTab = sel.first);
                        },
                      ),
                      const SizedBox(height: 14),
                      Text(
                        switch (_selectedAuthTab) {
                          0 => Platform.isAndroid
                              ? 'Inicia sesión normalmente con tu cuenta institucional USM (Microsoft SSO). Capturaremos tu sesión al instante.'
                              : 'En esta plataforma usa Token de WebService o Cookie MoodleSession desde tu navegador.',
                          1 =>
                            'Conexión rápida vía API REST de Moodle. Útil si obtuviste tu clave personal en Preferencias de Aula.',
                          _ =>
                            'Pega la cookie MoodleSession directamente desde tu navegador de escritorio.',
                        },
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed:
                            _isAuthenticating ? null : _handlePrimaryAuthTap,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: _isAuthenticating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.login_rounded),
                        label: const Text(
                          'Iniciar sesión en Aula USM',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _isAuthenticating ? null : _openPairing,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text('Emparejar con PC (QR / PIN)'),
                      ),
                      if (Platform.isWindows ||
                          Platform.isLinux ||
                          Platform.isMacOS) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _importFromLocalPc,
                          icon: const Icon(Icons.computer_rounded, size: 18),
                          label: const Text('Importar configuración de PC local'),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                // Security / Obsidian Note Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.verified_user_outlined,
                          color: cs.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Descarga todo el material de tus ramos, incluye carpetas internas de Moodle, organiza por secciones, genera notas índice .md para Obsidian y sincroniza entregas con tus Ramos y Agenda.',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handlePrimaryAuthTap() async {
    setState(() => _isAuthenticating = true);
    var ok = false;
    try {
      if (_selectedAuthTab == 0) {
        if (Platform.isAndroid) {
          final res = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => WebViewLoginScreen(moodle: _moodle),
            ),
          );
          ok = res == true;
        } else {
          ok = await showTokenLoginDialog(context, _moodle);
        }
      } else if (_selectedAuthTab == 1) {
        ok = await showTokenLoginDialog(context, _moodle);
      } else {
        ok = await showCookieLoginDialog(context, _moodle);
      }
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }

    if (ok && mounted) {
      await _initScreen();
    }
  }

  Future<void> _openPairing() async {
    final ok = await showPairingSheet(context, _moodle, _settings);
    if (ok && mounted) {
      await _initScreen();
    }
  }

  Future<void> _importFromLocalPc() async {
    final res = await _settings.detectAndImportLocalDesktopData();
    if (!mounted) return;
    if (!res.found) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontró instalación previa de Aula-Scrapt PC.'),
        ),
      );
      return;
    }
    await _moodle.loadSession();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Importado desde PC (${res.importedFolders} mapeos de ramos).',
        ),
      ),
    );
    if (_moodle.isAuthenticated) {
      await _initScreen();
    } else {
      setState(() {});
    }
  }

  // ===========================================================================
  // 2. Courses View (Phone Sliver + Wide Adaptive 2-Pane Split)
  // ===========================================================================

  Widget _buildCoursesView(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 720;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Stack(
      children: [
        isWide ? _buildWideAdaptiveBody(context) : _buildPhoneBody(context),
        Positioned(
          left: 12,
          right: 12,
          bottom: 92 + bottomInset,
          child: _buildFloatingBottomDock(context),
        ),
      ],
    );
  }

  Widget _buildPhoneBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visible = _visibleCourses;
    final bottomClearance = 180.0 + MediaQuery.of(context).padding.bottom;

    return RefreshIndicator(
      onRefresh: () => _scanAula(),
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            floating: true,
            titleSpacing: 16,
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/aula_logo.png',
                    width: 28,
                    height: 28,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Icon(Icons.school_rounded, color: cs.primary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Aula-Scrapt USM',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        _moodle.userName.isNotEmpty
                            ? _moodle.userName
                            : (_moodle.isTokenAuth
                                ? 'Token WebService'
                                : 'Sesión Web'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              _buildNotificationsBell(),
              IconButton(
                tooltip: 'Actualizar Aula USM',
                onPressed:
                    (_isScanning || _isDownloading) ? null : () => _scanAula(),
                icon: _isScanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: 'Ajustes de Aula y Obsidian',
                onPressed: _openAccountSettingsSheet,
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
          if (_statusBanner != null)
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const LinearProgressIndicator(minHeight: 3),
                  Container(
                    width: double.infinity,
                    color: cs.primaryContainer.withValues(alpha: 0.35),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text(
                      _statusBanner!,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (Platform.isAndroid && !_hasStoragePermission)
            SliverToBoxAdapter(child: _buildPermissionBanner(context)),
          SliverToBoxAdapter(child: _buildDestinationSummaryCard(context)),
          SliverToBoxAdapter(child: _buildNotasSynergyCard(context)),
          SliverToBoxAdapter(child: _buildSearchAndFilters(context)),
          SliverToBoxAdapter(child: _buildFilterAndBulkRow(context)),
          SliverToBoxAdapter(child: _buildDeadlinesRadarBanner(context)),
          if (visible.isEmpty && !_isScanning)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.school_outlined, size: 48, color: cs.outline),
                      const SizedBox(height: 10),
                      const Text(
                        'No se encontraron ramos para mostrar',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      FilledButton.tonalIcon(
                        onPressed: () => _scanAula(),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Escanear Aula'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(14, 4, 14, bottomClearance),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, idx) => _buildExpressiveCourseCard(visible[idx]),
                  childCount: visible.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWideAdaptiveBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visible = _visibleCourses;
    final selectedCourse = visible.isEmpty
        ? null
        : visible.firstWhere(
            (c) => c.id == _wideSelectedCourseId,
            orElse: () => visible.first,
          );
    final bottomClearance = 120.0 + MediaQuery.of(context).padding.bottom;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // Wide header
          Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                bottom: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/aula_logo.png',
                    width: 30,
                    height: 30,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Icon(Icons.school_rounded, color: cs.primary),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Aula-Scrapt USM',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 10),
                if (_moodle.userName.isNotEmpty)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      _moodle.userName,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                const Spacer(),
                if (_statusBanner != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      _statusBanner!,
                      style: TextStyle(fontSize: 12, color: cs.primary),
                    ),
                  ),
                _buildNotificationsBell(),
                IconButton(
                  tooltip: 'Actualizar Aula USM',
                  onPressed: (_isScanning || _isDownloading)
                      ? null
                      : () => _scanAula(),
                  icon: _isScanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Ajustes',
                  onPressed: _openAccountSettingsSheet,
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                // Left pane: controls + course list
                SizedBox(
                  width: 360,
                  child: ListView(
                    padding: EdgeInsets.only(bottom: bottomClearance),
                    children: [
                      if (Platform.isAndroid && !_hasStoragePermission)
                        _buildPermissionBanner(context),
                      _buildDestinationSummaryCard(context),
                      _buildNotasSynergyCard(context),
                      _buildSearchAndFilters(context),
                      _buildFilterAndBulkRow(context),
                      _buildDeadlinesRadarBanner(context),
                      const SizedBox(height: 6),
                      for (final c in visible)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: ListTile(
                            selected: selectedCourse?.id == c.id,
                            selectedTileColor:
                                cs.primaryContainer.withValues(alpha: 0.45),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: selectedCourse?.id == c.id
                                    ? cs.primary
                                    : cs.outlineVariant.withValues(alpha: 0.4),
                              ),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: cs.primaryContainer,
                              child: Text(
                                c.cleanName.isNotEmpty
                                    ? c.cleanName[0].toUpperCase()
                                    : 'C',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                            ),
                            title: Text(
                              c.cleanName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '📁 ${c.obsidianFolder} · ${c.pendingCount} pend.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            onTap: () {
                              setState(() {
                                _wideSelectedCourseId = c.id;
                                _expandedCourseIds.add(c.id);
                              });
                              _ensureSizesLoaded(c);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                VerticalDivider(
                    width: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                // Right pane: active course detail
                Expanded(
                  child: selectedCourse == null
                      ? const Center(child: Text('Selecciona un ramo'))
                      : ListView(
                          padding: EdgeInsets.fromLTRB(
                              16, 12, 16, bottomClearance),
                          children: [
                            _buildExpressiveCourseCard(
                              selectedCourse,
                              forceExpanded: true,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsBell() {
    return ValueListenableBuilder<int>(
      valueListenable: _settings.notificationsNotifier,
      builder: (_, unread, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Notificaciones',
              onPressed: () => showNotificationsSheet(context, _settings),
              icon: const Icon(Icons.notifications_outlined),
            ),
            if (unread > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPermissionBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_off_rounded, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Falta permiso de almacenamiento para escribir directo en Obsidian/Documents.',
              style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
            ),
          ),
          FilledButton.tonal(
            onPressed: () async {
              await _settings.requestStoragePermission();
              _hasStoragePermission = await _settings.hasStoragePermission();
              if (!_hasStoragePermission) {
                await _settings.openAppAllFilesSettings();
              }
              if (mounted) setState(() {});
            },
            child: const Text('Permitir'),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationSummaryCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final configuredCount =
        _courses.where((c) => _settings.getCourseFolder(c.id).isNotEmpty).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.folder_special_rounded,
                    size: 18, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Carpeta destino (Obsidian / Archivos)',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    Text(
                      _settings.shortDownloadRoot,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: _pickFolder,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Cambiar'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _miniStatChip(
                Icons.school_rounded,
                '${_visibleCourses.length} ramos ($configuredCount mapeados)',
                cs,
              ),
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.auto_stories_rounded, size: 15),
                label: const Text('Actualizar Índices .md',
                    style: TextStyle(fontSize: 11.5)),
                onPressed: _syncAllObsidianGraphs,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotasSynergyCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final linkedCount =
        _visibleCourses.where((c) => c.linkedRamoId != null).length;
    final totalDeadlines =
        _visibleCourses.fold<int>(0, (sum, c) => sum + c.deadlinesCount);

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 2, 14, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.secondaryContainer.withValues(alpha: 0.45),
            cs.tertiaryContainer.withValues(alpha: 0.35),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.hub_rounded, color: cs.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sinergia NotasApp · Ramos & Agenda',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
                Text(
                  '$linkedCount/${_visibleCourses.length} ramos vinculados · $totalDeadlines entrega(s) detectada(s)',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed:
                _visibleCourses.isEmpty ? null : _syncAllCoursesWithNotasApp,
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.sync_rounded, size: 16),
            label: const Text('Sincronizar'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Buscar archivo, sección, ramo o entrega...',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: () => _searchCtrl.clear(),
                  icon: const Icon(Icons.close_rounded),
                ),
          isDense: true,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterAndBulkRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<ResourceFilter>(
            segments: const [
              ButtonSegment(
                value: ResourceFilter.files,
                label: Text('Archivos', style: TextStyle(fontSize: 11.5)),
              ),
              ButtonSegment(
                value: ResourceFilter.pending,
                label: Text('Pendientes', style: TextStyle(fontSize: 11.5)),
              ),
              ButtonSegment(
                value: ResourceFilter.deadlines,
                label: Text('Entregas', style: TextStyle(fontSize: 11.5)),
              ),
              ButtonSegment(
                value: ResourceFilter.all,
                label: Text('Todo', style: TextStyle(fontSize: 11.5)),
              ),
            ],
            selected: {_filter},
            onSelectionChanged: (sel) {
              setState(() => _filter = sel.first);
              _settings.setDefaultFilterKey(_keyFromFilter(sel.first));
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _selectAllPending,
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.checklist_rounded, size: 17),
                  label: const Text('Sel. pendientes'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _clearSelection,
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.clear_all_rounded, size: 17),
                label: const Text('Limpiar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeadlinesRadarBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final urgent = <({MoodleCourse course, MoodleItem item})>[];
    for (final c in _visibleCourses) {
      for (final it in c.items) {
        if (it.isUrgentDeadline) {
          urgent.add((course: c, item: it));
        }
      }
    }
    if (urgent.isEmpty) return const SizedBox.shrink();
    urgent.sort((a, b) =>
        (a.item.dueTimestamp ?? 0).compareTo(b.item.dueTimestamp ?? 0));

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading:
                const Icon(Icons.alarm_on_rounded, color: Colors.deepOrange),
            title: Text(
              'Radar de Entregas (${urgent.length} próxima${urgent.length == 1 ? "" : "s"})',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            subtitle: const Text(
              'Vencimientos en los próximos 7 días',
              style: TextStyle(fontSize: 11.5),
            ),
            trailing: Icon(_radarExpanded
                ? Icons.expand_less_rounded
                : Icons.expand_more_rounded),
            onTap: () => setState(() => _radarExpanded = !_radarExpanded),
          ),
          if (_radarExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                children: urgent.take(8).map((pair) {
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      pair.item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                    subtitle: Text(
                      '${pair.course.cleanName} · ${pair.item.formattedDueDate}',
                      style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                    ),
                    trailing: IconButton(
                      tooltip: 'Agregar a Agenda NotasApp',
                      icon: const Icon(Icons.event_available_rounded, size: 19),
                      onPressed: () =>
                          _syncSingleDeadlineToAgenda(pair.course, pair.item),
                    ),
                    onTap: () => _openItemViewer(pair.item),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExpressiveCourseCard(
    MoodleCourse course, {
    bool forceExpanded = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isExpanded = forceExpanded || _expandedCourseIds.contains(course.id);
    final filtered = _filteredItemsForCourse(course);
    final pending = course.pendingCount;
    final newCount = course.newFilesCount;
    final linkedRamo = _semesterRamos
        .where((r) => r.id == course.linkedRamoId)
        .cast<Ramo?>()
        .firstOrNull;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isExpanded
              ? cs.primary.withValues(alpha: 0.45)
              : cs.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: forceExpanded
                ? null
                : () {
                    setState(() {
                      if (isExpanded) {
                        _expandedCourseIds.remove(course.id);
                      } else {
                        _expandedCourseIds.add(course.id);
                        _ensureSizesLoaded(course);
                      }
                    });
                  },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      course.cleanName.isNotEmpty
                          ? course.cleanName[0].toUpperCase()
                          : 'R',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.cleanName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _miniStatChip(
                              Icons.folder_outlined,
                              course.obsidianFolder.isNotEmpty
                                  ? course.obsidianFolder
                                  : course.cleanName,
                              cs,
                            ),
                            if (pending > 0)
                              _badgeChip('$pending pend.', cs.primaryContainer,
                                  cs.onPrimaryContainer),
                            if (newCount > 0)
                              _badgeChip('$newCount nuevo${newCount == 1 ? "" : "s"}',
                                  cs.tertiaryContainer, cs.onTertiaryContainer),
                            if (linkedRamo != null)
                              _badgeChip(
                                '🔗 ${linkedRamo.nombre}',
                                cs.secondaryContainer,
                                cs.onSecondaryContainer,
                              ),
                          ],
                        ),
                        if (course.scanError != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Error: ${course.scanError}',
                            style: TextStyle(fontSize: 11.5, color: cs.error),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!forceExpanded)
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                    ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
            // Course toolbar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        final allSelected = filtered
                            .where((i) => i.downloadable)
                            .every((i) => i.isSelected || i.isDownloaded);
                        _toggleCourseSelection(course, !allSelected);
                      },
                      icon: const Icon(Icons.select_all_rounded, size: 17),
                      label: const Text('Sel. ramo'),
                    ),
                    TextButton.icon(
                      onPressed: () => _openCourseConfigSheet(course),
                      icon: const Icon(Icons.tune_rounded, size: 17),
                      label: const Text('Carpeta & Ramo'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final path =
                            await _downloader.syncCourseObsidianIndex(course);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Índice Obsidian guardado en ${p.basename(path)}',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.auto_stories_rounded, size: 17),
                      label: const Text('Índice .md'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        final cleanUrl =
                            MoodleService.stripSensitiveQueryParams(course.url);
                        if (cleanUrl.isEmpty) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AuthenticatedWebViewerScreen(
                              url: cleanUrl,
                              title: course.cleanName,
                              cookie: _moodle.cookie,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.open_in_browser_rounded, size: 17),
                      label: const Text('Aula Web'),
                    ),
                  ],
                ),
              ),
            ),
            if (course.isLoadingContents)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(minHeight: 3),
              )
            else if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No hay elementos con el filtro actual en este curso.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              )
            else
              _buildSectionsList(course, filtered),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionsList(MoodleCourse course, List<MoodleItem> items) {
    final cs = Theme.of(context).colorScheme;
    final bySection = <String, List<MoodleItem>>{};
    for (final it in items) {
      bySection.putIfAbsent(it.section, () => []).add(it);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      child: Column(
        children: bySection.entries.map((entry) {
          final secTitle = entry.key;
          final secItems = entry.value;
          final secKey = '${course.id}::$secTitle';
          final collapsed = _collapsedSections.contains(secKey);
          final downloadableCount =
              secItems.where((it) => it.downloadable).length;
          final hasSlash = secTitle.contains('/');

          return Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Column(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    setState(() {
                      if (collapsed) {
                        _collapsedSections.remove(secKey);
                      } else {
                        _collapsedSections.add(secKey);
                      }
                    });
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        if (downloadableCount > 0)
                          Builder(
                            builder: (_) {
                              final downloadableItems =
                                  secItems.where((i) => i.downloadable).toList();
                              final eligible = downloadableItems
                                  .where((i) =>
                                      !(_settings.skipAlreadyDownloaded &&
                                          i.isDownloaded))
                                  .toList();
                              final allEligibleSelected = eligible.isNotEmpty &&
                                  eligible.every((i) => i.isSelected);
                              final someSelected = downloadableItems
                                  .any((i) => i.isSelected);
                              return Checkbox(
                                visualDensity: VisualDensity.compact,
                                tristate: true,
                                value: eligible.isNotEmpty
                                    ? (allEligibleSelected
                                        ? true
                                        : (someSelected ? null : false))
                                    : (someSelected ? null : false),
                                onChanged: (_) {
                                  final select = eligible.isNotEmpty
                                      ? !allEligibleSelected
                                      : false;
                                  _toggleSectionSelection(secItems, select);
                                },
                              );
                            },
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(
                              hasSlash
                                  ? Icons.folder_copy_rounded
                                  : Icons.topic_rounded,
                              size: 18,
                              color: cs.primary,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            secTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          '${secItems.length}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          collapsed
                              ? Icons.chevron_right_rounded
                              : Icons.expand_more_rounded,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
                if (!collapsed)
                  ...secItems.map((it) => _buildItemRow(course, it)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildItemRow(MoodleCourse course, MoodleItem item) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (icon, tint) = switch (item.type.toLowerCase()) {
      'resource' => (Icons.insert_drive_file_rounded, cs.primary),
      'folder' => (Icons.folder_zip_rounded, Colors.amber.shade700),
      'assign' || 'assignment' => (Icons.assignment_turned_in_rounded, Colors.deepOrange),
      'quiz' => (Icons.quiz_rounded, Colors.purple),
      'url' => (Icons.link_rounded, Colors.teal),
      'forum' => (Icons.forum_rounded, Colors.indigo),
      'page' => (Icons.article_rounded, cs.secondary),
      _ => (Icons.extension_rounded, cs.onSurfaceVariant),
    };

    return InkWell(
      onTap: () {
        if (item.isDownloaded &&
            item.localPath != null &&
            item.localPath!.isNotEmpty) {
          _openLocalFileWithGuard(item.localPath!);
        } else if (item.downloadable) {
          setState(() => item.isSelected = !item.isSelected);
        } else {
          _openItemViewer(item);
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 8),
        child: Row(
          children: [
            if (item.downloadable)
              Checkbox(
                visualDensity: VisualDensity.compact,
                value: item.isSelected,
                onChanged: (val) =>
                    setState(() => item.isSelected = val == true),
              )
            else
              const SizedBox(width: 10),
            Icon(icon, size: 19, color: tint),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: item.isDownloaded ? cs.onSurfaceVariant : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _badgeChip(
                        item.typeLabel,
                        cs.surfaceContainerHighest,
                        cs.onSurfaceVariant,
                      ),
                      if (item.formattedSize.isNotEmpty)
                        _badgeChip(
                          item.formattedSize,
                          cs.surfaceContainerHighest,
                          cs.onSurfaceVariant,
                        ),
                      if (item.isDownloaded)
                        _badgeChip(
                          'En carpeta',
                          Colors.green.withValues(alpha: isDark ? 0.22 : 0.16),
                          isDark ? Colors.green.shade200 : Colors.green.shade800,
                        )
                      else if (item.isNew && item.downloadable)
                        _badgeChip(
                          'Nuevo',
                          cs.primaryContainer,
                          cs.onPrimaryContainer,
                        ),
                      if (item.hasDeadline)
                        _badgeChip(
                          '📅 ${item.formattedDueDate}',
                          item.isUrgentDeadline
                              ? cs.errorContainer
                              : cs.secondaryContainer,
                          item.isUrgentDeadline
                              ? cs.onErrorContainer
                              : cs.onSecondaryContainer,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (item.isAssessableActivity && item.dueDate != null)
              IconButton(
                tooltip: 'Agregar entrega a NotasApp',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.event_available_rounded, size: 18),
                onPressed: () => _syncSingleDeadlineToAgenda(course, item),
              )
            else if (item.url.isNotEmpty)
              IconButton(
                tooltip: 'Abrir en Aula USM',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.open_in_new_rounded, size: 17),
                onPressed: () => _openItemViewer(item),
              ),
          ],
        ),
      ),
    );
  }

  void _openItemViewer(MoodleItem item) {
    final cleanUrl = MoodleService.stripSensitiveQueryParams(item.url);
    if (cleanUrl.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuthenticatedWebViewerScreen(
          url: cleanUrl,
          title: item.title,
          cookie: _moodle.cookie,
        ),
      ),
    );
  }

  void _ensureSizesLoaded(MoodleCourse course) {
    if (_sizingStartedIds.contains(course.id)) return;
    _sizingStartedIds.add(course.id);
    _moodle.fetchMissingFileSizes(course).then((_) {
      if (mounted) setState(() {});
    });
  }

  // ===========================================================================
  // 3. Floating Download Dock
  // ===========================================================================

  Widget _buildFloatingBottomDock(BuildContext context) {
    final selectedItems = <MoodleItem>[];
    for (final c in _courses) {
      for (final it in c.items) {
        if (it.downloadable && it.isSelected) selectedItems.add(it);
      }
    }
    final show = _isDownloading || selectedItems.isNotEmpty;
    if (!show) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final totalBytes = selectedItems.fold<int>(
      0,
      (sum, it) => sum + (it.sizeBytes ?? 0),
    );
    final sizeLabel = totalBytes > 0
        ? ' · ${MoodleItem.formatFileSize(totalBytes)}'
        : '';

    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(22),
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: _isDownloading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Descargando ($_dlCurrent/$_dlTotal): $_dlLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _dlTotal > 0 ? _dlCurrent / _dlTotal : null,
                  ),
                ],
              )
            : Row(
                children: [
                  Icon(Icons.download_for_offline_rounded,
                      color: cs.onPrimaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${selectedItems.length} seleccionado${selectedItems.length == 1 ? "" : "s"}$sizeLabel',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Limpiar selección',
                    onPressed: _clearSelection,
                    icon: Icon(Icons.close_rounded,
                        color: cs.onPrimaryContainer),
                  ),
                  FilledButton.icon(
                    onPressed: _startDownload,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text('Descargar (${selectedItems.length})'),
                  ),
                ],
              ),
      ),
    );
  }

  // ===========================================================================
  // 4. Course Config Sheet & Account Settings Sheet
  // ===========================================================================

  Future<void> _openCourseConfigSheet(MoodleCourse course) async {
    final result = await showModalBottomSheet<
        ({
          String folder,
          String subfolder,
          bool orgSection,
          bool hidden,
          int? ramoId,
        })>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CourseConfigSheet(
        course: course,
        existingSubfolders: _existingSubfolders,
        semesterRamos: _semesterRamos,
      ),
    );
    if (result == null || !mounted) return;

    course.obsidianFolder = result.folder.isNotEmpty
        ? MoodleCourse.sanitizeFileName(result.folder)
        : MoodleCourse.sanitizeFileName(course.cleanName);
    course.targetSubfolder = result.subfolder;
    course.organizeBySection = result.orgSection;
    course.isHidden = result.hidden;
    course.linkedRamoId = result.ramoId;

    await _settings.setCourseConfig(
      course.id,
      folder: course.obsidianFolder,
      subfolder: result.subfolder,
      organizeBySection: result.orgSection,
    );
    await _settings.toggleCourseHidden(course.id, result.hidden);
    await _settings.setCourseRamoLink(course.id, result.ramoId);
    await _moodle.enrichItemsWithLocalStatus([course], _settings);
    if (mounted) {
      setState(() {
        _invalidateCoursesCache();
      });
    }
  }

  Future<void> _openAccountSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final cs = Theme.of(ctx).colorScheme;
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.78,
            maxChildSize: 0.94,
            builder: (_, scrollCtrl) => ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              children: [
                Row(
                  children: [
                    Icon(Icons.tune_rounded, color: cs.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Configuración Aula-Scrapt',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_rounded),
                  title: Text(_moodle.userName.isNotEmpty
                      ? _moodle.userName
                      : 'Sesión activa Aula USM'),
                  subtitle: Text(_moodle.isTokenAuth
                      ? 'Conectado con Token WebService'
                      : 'Conectado con Cookie de Sesión'),
                  trailing: TextButton.icon(
                    onPressed: () async {
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _performLogout();
                    },
                    icon: Icon(Icons.logout_rounded, color: cs.error),
                    label: Text('Salir', style: TextStyle(color: cs.error)),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_open_rounded),
                  title: const Text('Carpeta destino'),
                  subtitle: Text(_settings.shortDownloadRoot),
                  trailing: TextButton(
                    onPressed: () async {
                      await _pickFolder();
                      setSheetState(() {});
                    },
                    child: const Text('Cambiar'),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Omitir archivos ya descargados'),
                  value: _settings.skipAlreadyDownloaded,
                  onChanged: (v) async {
                    await _settings.setSkipAlreadyDownloaded(v);
                    setSheetState(() {});
                    if (mounted) setState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Omitir archivos ya vistos al seleccionar'),
                  value: _settings.skipSeenOnSelect,
                  onChanged: (v) async {
                    await _settings.setSkipSeenOnSelect(v);
                    setSheetState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Exportar enlaces URL al índice .md'),
                  value: _settings.autoExportLinksToObsidian,
                  onChanged: (v) async {
                    await _settings.setAutoExportLinksToObsidian(v);
                    setSheetState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Exportar foros al índice .md'),
                  value: _settings.autoExportForumsToObsidian,
                  onChanged: (v) async {
                    await _settings.setAutoExportForumsToObsidian(v);
                    setSheetState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mostrar cursos ocultos'),
                  value: _showHiddenCourses,
                  onChanged: (v) {
                    setSheetState(() => _showHiddenCourses = v);
                    if (mounted) setState(() {});
                  },
                ),
                if (Platform.isAndroid)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Notificaciones nativas Android'),
                    value: _settings.notifyNativeEnabled,
                    onChanged: (v) async {
                      if (v) {
                        await _settings.requestNotificationPermission();
                      }
                      await _settings.setNotifyNativeEnabled(v);
                      setSheetState(() {});
                    },
                  ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Historial reciente (${_settings.history.length})',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (_settings.history.isNotEmpty)
                      TextButton(
                        onPressed: () async {
                          await _settings.clearHistory();
                          setSheetState(() {});
                        },
                        child: const Text('Limpiar'),
                      ),
                  ],
                ),
                if (_settings.history.isEmpty)
                  Text(
                    'Aún no hay descargas registradas.',
                    style:
                        TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                  )
                else
                  ..._settings.history.take(10).map(
                        (h) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.description_outlined,
                              size: 18),
                          title: Text(h.fileName,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${h.course} · ${MoodleItem.formatFileSize(h.sizeBytes)}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          onTap: () => _openLocalFileWithGuard(h.savedPath),
                        ),
                      ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _miniStatChip(IconData icon, String label, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badgeChip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _CourseConfigSheet extends StatefulWidget {
  final MoodleCourse course;
  final List<String> existingSubfolders;
  final List<Ramo> semesterRamos;

  const _CourseConfigSheet({
    required this.course,
    required this.existingSubfolders,
    required this.semesterRamos,
  });

  @override
  State<_CourseConfigSheet> createState() => _CourseConfigSheetState();
}

class _CourseConfigSheetState extends State<_CourseConfigSheet> {
  late final TextEditingController _folderCtrl =
      TextEditingController(text: widget.course.obsidianFolder);
  late final TextEditingController _subCtrl =
      TextEditingController(text: widget.course.targetSubfolder);
  late bool _orgSection = widget.course.organizeBySection;
  late bool _hidden = widget.course.isHidden;
  late int? _selectedRamoId = widget.course.linkedRamoId;

  @override
  void dispose() {
    _folderCtrl.dispose();
    _subCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.course.cleanName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _folderCtrl,
              decoration: const InputDecoration(
                labelText: 'Carpeta del ramo en Vault / Descargas',
                prefixIcon: Icon(Icons.folder_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.existingSubfolders.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: widget.existingSubfolders.map((sf) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(sf, style: const TextStyle(fontSize: 11.5)),
                        onPressed: () {
                          setState(() => _folderCtrl.text = sf);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _subCtrl,
              decoration: const InputDecoration(
                labelText: 'Subcarpeta interna (vacío = raíz del ramo)',
                hintText: 'Aula',
                prefixIcon: Icon(Icons.subdirectory_arrow_right_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Organizar en subcarpetas por sección'),
              value: _orgSection,
              onChanged: (v) => setState(() => _orgSection = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ocultar curso de la lista principal'),
              value: _hidden,
              onChanged: (v) => setState(() => _hidden = v),
            ),
            const Divider(height: 20),
            const Text(
              'Vínculo con NotasApp',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              initialValue:
                  widget.semesterRamos.any((r) => r.id == _selectedRamoId)
                      ? _selectedRamoId
                      : null,
              decoration: const InputDecoration(
                labelText: 'Ramo vinculado en este semestre',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Sin vincular'),
                ),
                ...widget.semesterRamos.map(
                  (r) => DropdownMenuItem<int?>(
                    value: r.id,
                    child: Text(r.nombre),
                  ),
                ),
              ],
              onChanged: (val) => setState(() => _selectedRamoId = val),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context, (
                        folder: _folderCtrl.text.trim(),
                        subfolder: _subCtrl.text.trim(),
                        orgSection: _orgSection,
                        hidden: _hidden,
                        ramoId: _selectedRamoId,
                      ));
                    },
                    child: const Text('Guardar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
