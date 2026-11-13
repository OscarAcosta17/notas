import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/semestre.dart';
import '../services/updater_service.dart';
import '../theme/app_theme.dart';
import '../theme/expressive_widgets.dart';
import '../viewmodels/semestre_provider.dart';
import '../viewmodels/settings_provider.dart';
import 'add_semestre_dialog.dart';
import 'agenda_view.dart';
import 'edit_semestre_dialog.dart';
import 'horario_view.dart';
import 'semestre_detail_view.dart';
import 'settings_view.dart';

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  int _currentTab = 0;
  int? _programmaticTargetTab;
  int? _selectedSemesterId;
  bool _isRamoSelectionMode = false;
  int _horarioRefreshTick = 0;
  int _agendaRefreshTick = 0;

  late final PageController _pageController;
  final GlobalKey<SemestreDetailViewState> _semestreDetailKey = GlobalKey<SemestreDetailViewState>();
  final GlobalKey<HorarioViewState> _horarioKey = GlobalKey<HorarioViewState>();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        UpdaterService.checkForUpdatesOnStartup(context);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _selectTab(int index) async {
    if (index == _currentTab) return;
    AppHaptics.selection(context);

    setState(() {
      _programmaticTargetTab = index;
      _currentTab = index;
      if (index != 0) _isRamoSelectionMode = false;
      if (index == 1) _horarioRefreshTick++;
      if (index == 2) _agendaRefreshTick++;
    });

    if (_pageController.hasClients) {
      await _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }

    if (mounted) {
      setState(() {
        _programmaticTargetTab = null;
      });
    }
  }

  void _onPageChanged(int index) {
    // Skip intermediate page notifications emitted while animateToPage hops tabs.
    if (_programmaticTargetTab != null && index != _programmaticTargetTab) {
      return;
    }

    final changed = index != _currentTab;
    if (changed) {
      AppHaptics.selection(context);
    }

    setState(() {
      _currentTab = index;
      if (index != 0) _isRamoSelectionMode = false;
      if (_programmaticTargetTab == null && changed) {
        if (index == 1) _horarioRefreshTick++;
        if (index == 2) _agendaRefreshTick++;
      }
    });
  }

  void _openAddSemesterDialog() {
    showDialog(
      context: context,
      builder: (_) => const AddSemestreDialog(),
    );
  }

  void _showSemesterOptions(Semestre semestre) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;
    AppHaptics.light(context);

    showExpressiveModalSheet(
      context: context,
      builder: (sheetCtx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                TonalIconBadge(
                  icon: Icons.school_rounded,
                  color: tokens.accentColor,
                  size: 42,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    semestre.nombre,
                    style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(Icons.edit_outlined, color: scheme.onSurface),
            title: const Text('Renombrar Semestre', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(sheetCtx);
              showDialog(
                context: context,
                builder: (_) => EditSemestreDialog(semestre: semestre),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
            title: Text(
              'Eliminar Semestre',
              style: TextStyle(fontWeight: FontWeight.w600, color: scheme.error),
            ),
            onTap: () {
              Navigator.pop(sheetCtx);
              _confirmDeleteSemester(semestre);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _confirmDeleteSemester(Semestre semestre) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('¿Eliminar semestre?'),
        content: Text(
          'Se eliminará "${semestre.nombre}" junto con todos sus ramos, evaluaciones y horarios.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              if (semestre.id != null) {
                await ref.read(semestreProvider.notifier).eliminarSemestre(semestre.id!);
                if (_selectedSemesterId == semestre.id && mounted) {
                  setState(() => _selectedSemesterId = null);
                }
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _showSemesterPickerSheet(List<Semestre> semestres, Semestre? activeSemestre) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;
    AppHaptics.selection(context);

    showExpressiveModalSheet(
      context: context,
      builder: (sheetCtx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.65,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Semestres',
                          style: Theme.of(sheetCtx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Selecciona, renombra o administra tus períodos',
                          style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                itemCount: semestres.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, idx) {
                  final sem = semestres[idx];
                  final isSelected = activeSemestre?.id == sem.id;
                  return Material(
                    color: isSelected ? tokens.accentContainer : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(tokens.cardRadius),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(tokens.cardRadius),
                      onTap: () {
                        AppHaptics.selection(context);
                        setState(() => _selectedSemesterId = sem.id);
                        Navigator.pop(sheetCtx);
                      },
                      onLongPress: () {
                        Navigator.pop(sheetCtx);
                        _showSemesterOptions(sem);
                      },
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(tokens.cardRadius),
                          border: Border.all(
                            color: isSelected
                                ? tokens.accentColor.withValues(alpha: 0.45)
                                : scheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.check_circle_rounded : Icons.school_outlined,
                              color: isSelected ? tokens.accentColor : scheme.onSurfaceVariant,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                sem.nombre,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                  fontSize: 15,
                                  color: isSelected ? tokens.onAccentContainer : scheme.onSurface,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Renombrar',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.edit_outlined, size: 18, color: scheme.onSurfaceVariant),
                              onPressed: () {
                                Navigator.pop(sheetCtx);
                                showDialog(
                                  context: context,
                                  builder: (_) => EditSemestreDialog(semestre: sem),
                                );
                              },
                            ),
                            IconButton(
                              tooltip: 'Eliminar',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error),
                              onPressed: () {
                                Navigator.pop(sheetCtx);
                                _confirmDeleteSemester(sem);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheetCtx);
                  _openAddSemesterDialog();
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nuevo Semestre'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsButton() {
    return IconButton(
      tooltip: 'Configuración',
      icon: const Icon(Icons.settings_rounded),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsView()),
        );
      },
    );
  }

  Widget _buildHeaderTitlePill(List<Semestre> semestres, Semestre activeSemestre) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          onTap: () => _showSemesterPickerSheet(semestres, activeSemestre),
          onLongPress: () => _showSemesterOptions(activeSemestre),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    activeSemestre.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: tokens.accentColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSemesterChipsBar(List<Semestre> semestres, Semestre activeSemestre) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ...semestres.map((sem) {
            final isSelected = sem.id == activeSemestre.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  AppHaptics.selection(context);
                  setState(() => _selectedSemesterId = sem.id);
                },
                onLongPress: () => _showSemesterOptions(sem),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? tokens.accentColor : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    border: isSelected
                        ? null
                        : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    sem.nombre,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: isSelected ? tokens.onAccentColor : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            );
          }),
          Material(
            color: tokens.accentContainer,
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              onTap: _openAddSemesterDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 17, color: tokens.onAccentContainer),
                    const SizedBox(width: 4),
                    Text(
                      'Nuevo',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: tokens.onAccentContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySemestersView(SettingsState settings) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final bottomGap = bottomInset + (settings.bottomNavStyle == 'dock' ? 96 : 112);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scheme.surface,
      appBar: FrostedAppBar(
        title: const Text('Mis Semestres'),
        actions: [_buildSettingsButton()],
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(32, 32, 32, bottomGap),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TonalIconBadge(
                icon: Icons.school_outlined,
                color: tokens.accentColor,
                size: 84,
              ),
              const SizedBox(height: 20),
              Text(
                'No hay semestres creados',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Crea tu primer semestre para organizar tus ramos, horarios y fechas clave.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _openAddSemesterDialog,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Crear Primer Semestre'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyScheduleView() {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scheme.surface,
      appBar: FrostedAppBar(
        title: const Text('Mi Horario'),
        actions: [_buildSettingsButton()],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TonalIconBadge(
                icon: Icons.calendar_today_rounded,
                color: tokens.accentColor,
                size: 80,
              ),
              const SizedBox(height: 20),
              Text(
                'Sin semestre activo',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Crea un semestre en la pestaña Ramos para organizar tu horario.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleCoupledFab(Semestre? activeSemestre) {
    AppHaptics.light(context);
    if (_currentTab == 0) {
      if (activeSemestre == null) {
        _openAddSemesterDialog();
      } else {
        _semestreDetailKey.currentState?.openAddRamoDialog();
      }
      return;
    }
    if (_currentTab == 1 && activeSemestre != null) {
      _horarioKey.currentState?.openAddDialogForCurrentDay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final semestres = ref.watch(semestreProvider);
    final settings = ref.watch(settingsProvider);

    Semestre? activeSemestre;
    if (semestres.isNotEmpty) {
      final idx = semestres.indexWhere((s) => s.id == _selectedSemesterId);
      activeSemestre = idx != -1 ? semestres[idx] : semestres.last;
    }

    final useCoupledFab = settings.bottomNavStyle != 'dock';
    final useHeaderSelector = settings.semesterSelectorStyle == 'header';
    final showCoupledFab = useCoupledFab &&
        !_isRamoSelectionMode &&
        (_currentTab == 0 || (_currentTab == 1 && activeSemestre != null));

    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: settings.enableHorizontalSwipe ? null : const NeverScrollableScrollPhysics(),
            onPageChanged: _onPageChanged,
            children: [
              // Tab 0: Ramos
              if (activeSemestre == null)
                _buildEmptySemestersView(settings)
              else
                SemestreDetailView(
                  key: _semestreDetailKey,
                  semestre: activeSemestre,
                  showBackButton: false,
                  showInternalFab: !useCoupledFab,
                  titleWidget: useHeaderSelector ? _buildHeaderTitlePill(semestres, activeSemestre) : null,
                  headerWidget: useHeaderSelector ? null : _buildSemesterChipsBar(semestres, activeSemestre),
                  actions: [_buildSettingsButton()],
                  onSelectionModeChanged: (selecting) {
                    if (_isRamoSelectionMode != selecting) {
                      setState(() => _isRamoSelectionMode = selecting);
                    }
                  },
                ),

              // Tab 1: Horario
              if (activeSemestre?.id != null)
                HorarioView(
                  key: _horarioKey,
                  semesterId: activeSemestre!.id!,
                  showInternalFab: !useCoupledFab,
                  bottomNavStyle: settings.bottomNavStyle,
                  disableDaySwipe: settings.enableHorizontalSwipe,
                  refreshTick: _horarioRefreshTick,
                )
              else
                _buildEmptyScheduleView(),

              // Tab 2: Agenda
              AgendaView(refreshTick: _agendaRefreshTick),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ExpressiveBottomNavigation(
              currentTab: _currentTab,
              pageController: _pageController,
              bottomNavStyle: settings.bottomNavStyle,
              navLabelMode: settings.navLabelMode,
              showCoupledFab: showCoupledFab,
              onSelectTab: _selectTab,
              onPressedFab: () => _handleCoupledFab(activeSemestre),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpressiveBottomNavigation extends StatelessWidget {
  final int currentTab;
  final PageController pageController;
  final String bottomNavStyle;
  final String navLabelMode;
  final bool showCoupledFab;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onPressedFab;

  const _ExpressiveBottomNavigation({
    required this.currentTab,
    required this.pageController,
    required this.bottomNavStyle,
    required this.navLabelMode,
    required this.showCoupledFab,
    required this.onSelectTab,
    required this.onPressedFab,
  });

  static const _items = [
    (icon: Icons.school_rounded, label: 'Ramos'),
    (icon: Icons.calendar_today_rounded, label: 'Horario'),
    (icon: Icons.event_note_rounded, label: 'Agenda'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final isDark = scheme.brightness == Brightness.dark;
    final isDock = bottomNavStyle == 'dock';
    final barHeight = navLabelMode == 'icon_only' ? 56.0 : 62.0;

    if (isDock) {
      return FrostedGlassSurface(
        borderRadius: BorderRadius.zero,
        customBorder: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
        padding: EdgeInsets.fromLTRB(12, 6, 12, bottomPadding + 6),
        child: SizedBox(
          height: barHeight,
          child: _buildNavTrack(context, tokens, scheme, isDock: true),
        ),
      );
    }

    Widget buildCoupledFab({required bool isCircular}) {
      final radius = isCircular ? barHeight / 2 : 19.0;
      return AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: showCoupledFab
            ? Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Material(
                  color: tokens.accentColor,
                  borderRadius: BorderRadius.circular(radius),
                  elevation: 3,
                  shadowColor: tokens.accentColor.withValues(alpha: 0.35),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(radius),
                    onTap: onPressedFab,
                    child: Tooltip(
                      message: currentTab == 0 ? 'Añadir Ramo' : 'Añadir Bloque',
                      child: SizedBox(
                        width: barHeight,
                        height: barHeight,
                        child: Icon(
                          Icons.add_rounded,
                          size: 28,
                          color: tokens.onAccentColor,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      );
    }

    if (bottomNavStyle == 'm3_expressive') {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding + 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Container(
                height: barHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.36 : 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: FrostedGlassSurface(
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  padding: const EdgeInsets.all(5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_items.length, (i) {
                      final item = _items[i];
                      final selected = currentTab == i;
                      final showLabel = navLabelMode != 'icon_only' && selected;
                      final activeFg = Color.lerp(tokens.onAccentContainer, tokens.accentColor, 0.35)!;
                      final fg = selected ? activeFg : scheme.onSurfaceVariant;

                      return Tooltip(
                        message: item.label,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                          onTap: () => onSelectTab(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            height: double.infinity,
                            padding: EdgeInsets.symmetric(
                              horizontal: showLabel ? 18 : 14,
                            ),
                            decoration: BoxDecoration(
                              color: selected ? tokens.accentContainer : Colors.transparent,
                              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                              border: selected
                                  ? Border.all(color: tokens.accentColor.withValues(alpha: 0.25))
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(item.icon, size: 22, color: fg),
                                if (showLabel) ...[
                                  const SizedBox(width: 7),
                                  Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: fg,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
            buildCoupledFab(isCircular: false),
          ],
        ),
      );
    }

    if (bottomNavStyle == 'ios_glass') {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding + 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 288),
                child: Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: FrostedGlassSurface(
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    customBorder: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.72),
                      width: 1.1,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    child: _buildGlassNavTrack(context, tokens, scheme),
                  ),
                ),
              ),
            ),
            buildCoupledFab(isCircular: true),
          ],
        ),
      );
    }

    final isOneUi = bottomNavStyle == 'one_ui';
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding + 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              height: barHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(isOneUi ? 28 : AppTheme.radiusFull),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.10),
                    blurRadius: isOneUi ? 26 : 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: FrostedGlassSurface(
                borderRadius: BorderRadius.circular(isOneUi ? 28 : AppTheme.radiusFull),
                customBorder: isOneUi
                    ? Border.all(
                        color: tokens.accentColor.withValues(alpha: isDark ? 0.32 : 0.22),
                        width: 1.2,
                      )
                    : null,
                padding: const EdgeInsets.all(5),
                child: _buildNavTrack(
                  context,
                  tokens,
                  scheme,
                  isDock: false,
                  isOneUi: isOneUi,
                ),
              ),
            ),
          ),
          buildCoupledFab(isCircular: isOneUi),
        ],
      ),
    );
  }

  Widget _buildGlassNavTrack(
    BuildContext context,
    NotasVisualTokens tokens,
    ColorScheme scheme,
  ) {
    return Row(
      children: List.generate(_items.length, (i) {
        final item = _items[i];
        final selected = currentTab == i;
        final showLabel = switch (navLabelMode) {
          'icon_only' => false,
          'selected' => selected,
          _ => true,
        };
        final fg = selected ? tokens.accentColor : scheme.onSurfaceVariant;

        return Expanded(
          child: Tooltip(
            message: item.label,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              onTap: () => onSelectTab(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: selected ? tokens.accentColor.withValues(alpha: 0.11) : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.icon, size: showLabel ? 19 : 22, color: fg),
                    if (showLabel) ...[
                      const SizedBox(height: 1),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.05,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                          color: fg,
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: selected ? 18 : 0,
                      height: 3,
                      decoration: BoxDecoration(
                        color: tokens.accentColor,
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: tokens.accentColor.withValues(alpha: 0.55),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildNavTrack(
    BuildContext context,
    NotasVisualTokens tokens,
    ColorScheme scheme, {
    required bool isDock,
    bool isOneUi = false,
  }) {
    final pillRadius = isDock ? 16.0 : (isOneUi ? 22.0 : AppTheme.radiusFull);

    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.maxWidth / _items.length;

        return AnimatedBuilder(
          animation: pageController,
          builder: (context, _) {
            var page = currentTab.toDouble();
            if (pageController.hasClients && pageController.position.hasViewportDimension) {
              page = (pageController.page ?? currentTab.toDouble()).clamp(0.0, (_items.length - 1).toDouble());
            }

            return Stack(
              children: [
                Positioned(
                  left: slotWidth * page,
                  top: 0,
                  bottom: 0,
                  width: slotWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isOneUi ? tokens.accentColor : tokens.accentContainer,
                      borderRadius: BorderRadius.circular(pillRadius),
                      border: isOneUi
                          ? null
                          : Border.all(
                              color: tokens.accentColor.withValues(alpha: 0.25),
                            ),
                      boxShadow: isOneUi
                          ? [
                              BoxShadow(
                                color: tokens.accentColor.withValues(alpha: 0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
                Row(
                  children: List.generate(_items.length, (i) {
                    final item = _items[i];
                    final selected = currentTab == i;
                    final showLabel = switch (navLabelMode) {
                      'icon_only' => false,
                      'selected' => selected,
                      _ => true,
                    };
                    final activeFg = isOneUi
                        ? tokens.onAccentColor
                        : Color.lerp(tokens.onAccentContainer, tokens.accentColor, 0.35)!;
                    final fg = selected ? activeFg : scheme.onSurfaceVariant;

                    return Expanded(
                      child: Tooltip(
                        message: item.label,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(pillRadius),
                          onTap: () => onSelectTab(i),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  item.icon,
                                  size: showLabel ? 21 : 24,
                                  color: fg,
                                ),
                                if (showLabel) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.05,
                                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                      color: fg,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
