import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../viewmodels/semestre_provider.dart';
import '../models/semestre.dart';

import 'semestre_detail_view.dart';
import 'agenda_view.dart';
import 'horario_view.dart';
import 'add_semestre_dialog.dart';
import 'settings_view.dart';

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  int _currentTab = 0; // 0 = Semestres, 1 = Agenda
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

    return Container(
      height: 60,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: semestres.length,
        itemBuilder: (context, index) {
          final sem = semestres[index];
          final isSelected = sem.id == _selectedSemesterId;
          return Padding(
            padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
            child: ChoiceChip(
              label: Text(
                sem.nombre,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              selected: isSelected,
              selectedColor: Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? Colors.transparent : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                ),
              ),
              onSelected: (val) {
                if (val) _selectSemester(sem.id!);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSemestersTab(List<Semestre> semestres) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    if (semestres.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Mis Semestres', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsView())),
            ),
          ],
        ),
        body: const Center(child: Text('No hay semestres creados.', style: TextStyle(color: Colors.grey))),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 80),
          child: FloatingActionButton(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            elevation: 2,
            child: const Icon(Icons.add),
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
      orElse: () => semestres.last
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
          icon: const Icon(Icons.settings),
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
      return Scaffold(
        appBar: AppBar(
          title: Text('Horario de Clases', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
        ),
        body: const Center(child: Text('Selecciona un semestre en la pestaña de Ramos primero.', style: TextStyle(color: Colors.grey))),
      );
    }
    return HorarioView(semesterId: _selectedSemesterId!);
  }

  Widget _buildBottomBubble() {
    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(40),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
              width: 1,
            )
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BubbleItem(
                icon: Icons.school,
                label: 'Ramos',
                isActive: _currentTab == 0,
                onTap: () => setState(() => _currentTab = 0),
              ),
              const SizedBox(width: 8),
              _BubbleItem(
                icon: Icons.calendar_today,
                label: 'Horario',
                isActive: _currentTab == 2,
                onTap: () => setState(() => _currentTab = 2),
              ),
              const SizedBox(width: 8),
              _BubbleItem(
                icon: Icons.event_note,
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
          // Main content
          Positioned.fill(
            child: _currentTab == 0 
                ? _buildSemestersTab(semestres) 
                : _currentTab == 1 ? _buildAgendaTab() : _buildHorarioTab(),
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
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Theme.of(context).colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              size: 24,
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
