import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/semestre.dart';
import '../theme/app_theme.dart';
import '../theme/expressive_widgets.dart';
import '../viewmodels/semestre_provider.dart';

import 'add_semestre_dialog.dart';
import 'agenda_view.dart';
import 'horario_view.dart';
import 'semestre_detail_view.dart';
import 'settings_view.dart';

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  int _currentTab = 0; // 0 = Semestres, 1 = Agenda, 2 = Horario
  int? _selectedSemesterId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSelectedSemester();
  }

  Future<void> _loadSelectedSemester() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getInt('last_semester_id');
    if (mounted) {
      setState(() {
        _selectedSemesterId = savedId;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectSemester(int id) async {
    setState(() {
      _selectedSemesterId = id;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_semester_id', id);
  }

  Widget _buildSemestersHeader(List<Semestre> semestres) {
    if (semestres.isEmpty) return const SizedBox.shrink();

    // Ensure selected semester is valid
    if (_selectedSemesterId == null || !semestres.any((s) => s.id == _selectedSemesterId)) {
      _selectedSemesterId = semestres.last.id;
      _selectSemester(_selectedSemesterId!); // Save it async
    }

    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: semestres.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final sem = semestres[index];
          final isSelected = sem.id == _selectedSemesterId;

          return GestureDetector(
            onTap: () => _selectSemester(sem.id!),
            onLongPress: () => _showSemesterOptions(sem),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: isSelected
                    ? scheme.primary
                    : scheme.surfaceContainerHigh.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                border: Border.all(
                  color: isSelected
                      ? Colors.transparent
                      : scheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                sem.nombre,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showSemesterOptions(Semestre sem) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;

    showExpressiveModalSheet(
      context: context,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  sem.nombre,
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(height: 4),
              ExpressiveGroupedSection(
                margin: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const TonalIconBadge(icon: Icons.edit_rounded),
                    title: const Text('Renombrar Semestre', style: TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _renameSemester(sem);
                    },
                  ),
                  ListTile(
                    leading: TonalIconBadge(
                      icon: Icons.delete_outline_rounded,
                      color: tokens.failingColor,
                    ),
                    title: Text(
                      'Eliminar Semestre',
                      style: TextStyle(color: tokens.failingColor, fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _deleteSemester(sem);
                    },
                  ),
                ],
              ),
              SizedBox(height: scheme.surface == Colors.transparent ? 0 : 4),
            ],
          ),
        );
      },
    );
  }

  void _renameSemester(Semestre sem) {
    final ctrl = TextEditingController(text: sem.nombre);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renombrar Semestre'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Nombre'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                sem.nombre = ctrl.text.trim();
                ref.read(semestreProvider.notifier).actualizarSemestre(sem);
                Navigator.pop(context);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _deleteSemester(Semestre sem) {
    final tokens = context.visualTokens;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Semestre'),
        content: Text(
          '¿Estás seguro de que deseas eliminar el semestre "${sem.nombre}"? Se borrarán todos los ramos, clases y evaluaciones asociados. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: tokens.failingColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              ref.read(semestreProvider.notifier).eliminarSemestre(sem.id!);
              if (_selectedSemesterId == sem.id) {
                _selectedSemesterId = null;
              }
              Navigator.pop(context);
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Widget _buildSemestersTab(List<Semestre> semestres) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    if (semestres.isEmpty) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: FrostedAppBar(
          title: const Text('Mis Semestres'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Configuración',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsView()),
              ),
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppTheme.radiusExtraLarge),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TonalIconBadge(icon: Icons.school_rounded, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'No hay semestres creados',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Toca el botón + para agregar tu primer semestre y comenzar a organizar tus ramos.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: Padding(
          padding: EdgeInsets.only(bottom: 84 + bottomInset),
          child: FloatingActionButton(
            child: const Icon(Icons.add_rounded),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const AddSemestreDialog(),
              );
            },
          ),
        ),
      );
    }

    // Valid semester selected
    final currentSemestre = semestres.firstWhere(
      (s) => s.id == _selectedSemesterId,
      orElse: () => semestres.last,
    );

    return SemestreDetailView(
      semestre: currentSemestre,
      showBackButton: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.add_box_outlined),
          tooltip: 'Añadir Semestre',
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => const AddSemestreDialog(),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Configuración',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsView()),
            );
          },
        ),
      ],
      headerWidget: _buildSemestersHeader(semestres),
    );
  }

  Widget _buildAgendaTab() {
    return const AgendaView();
  }

  Widget _buildHorarioTab() {
    if (_selectedSemesterId == null) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: const FrostedAppBar(title: Text('Horario de Clases')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppTheme.radiusExtraLarge),
              ),
              child: Text(
                'Selecciona un semestre en la pestaña de Ramos primero.',
                style: TextStyle(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }
    return HorarioView(semesterId: _selectedSemesterId!);
  }

  Widget _buildBottomBubble() {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      bottom: 18 + bottomInset,
      left: 0,
      right: 0,
      child: Center(
        child: FrostedGlassSurface(
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          padding: const EdgeInsets.all(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BubbleItem(
                icon: Icons.school_rounded,
                label: 'Ramos',
                isActive: _currentTab == 0,
                onTap: () => setState(() => _currentTab = 0),
              ),
              const SizedBox(width: 4),
              _BubbleItem(
                icon: Icons.calendar_today_rounded,
                label: 'Horario',
                isActive: _currentTab == 2,
                onTap: () => setState(() => _currentTab = 2),
              ),
              const SizedBox(width: 4),
              _BubbleItem(
                icon: Icons.event_note_rounded,
                label: 'Agenda',
                isActive: _currentTab == 1,
                onTap: () => setState(() => _currentTab = 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final semestres = ref.watch(semestreProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          // Main content with smooth expressive switch while preserving fresh tab loading
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: KeyedSubtree(
                key: ValueKey<int>(_currentTab),
                child: _currentTab == 0
                    ? _buildSemestersTab(semestres)
                    : _currentTab == 1
                        ? _buildAgendaTab()
                        : _buildHorarioTab(),
              ),
            ),
          ),

          // Navigation Bubble
          _buildBottomBubble(),
        ],
      ),
    );
  }
}

class _BubbleItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _BubbleItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: isActive ? 18 : 16, vertical: 11),
        decoration: BoxDecoration(
          color: isActive ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? scheme.onPrimary : scheme.onSurface.withValues(alpha: 0.65),
              size: 22,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: isActive
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
