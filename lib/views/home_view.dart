import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/semestre_provider.dart';

import 'semestre_detail_view.dart';
import 'add_semestre_dialog.dart';
import 'edit_semestre_dialog.dart';
import 'settings_view.dart';

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  final Set<int> _selectedIds = {};

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  void _deleteSelected() {
    for (final id in _selectedIds) {
      ref.read(semestreProvider.notifier).eliminarSemestre(id);
    }
    _clearSelection();
  }

  void _editSelected() {
    if (_selectedIds.length != 1) return;
    final id = _selectedIds.first;
    final semestres = ref.read(semestreProvider);
    final semestre = semestres.firstWhere((s) => s.id == id);

    showDialog(
      context: context,
      builder: (context) => EditSemestreDialog(semestre: semestre),
    ).then((_) => _clearSelection());
  }

  @override
  Widget build(BuildContext context) {
    final semestres = ref.watch(semestreProvider);
    final isSelectionMode = _selectedIds.isNotEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: isSelectionMode
          ? AppBar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              title: Text(
                '${_selectedIds.length} seleccionado(s)',
                style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
              actions: [
                if (_selectedIds.length == 1)
                  IconButton(
                    icon: const Icon(Icons.edit),
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    onPressed: _editSelected,
                  ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  onPressed: _deleteSelected,
                ),
              ],
            )
          : AppBar(
              title: Text('Mis Semestres', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
              backgroundColor: Theme.of(context).colorScheme.surface,
              elevation: 0,
              iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
              actions: [
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
            ),
      body: semestres.isEmpty
          ? const Center(child: Text('No hay semestres creados.', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: semestres.length,
              itemBuilder: (context, index) {
                final sem = semestres[index];
                final isSelected = _selectedIds.contains(sem.id);

                return Card(
                  color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5) : Theme.of(context).colorScheme.surface,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    title: Text(
                      sem.nombre,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    trailing: isSelectionMode
                        ? Icon(
                            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                          )
                        : const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    onTap: () {
                      if (isSelectionMode) {
                        _toggleSelection(sem.id!);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => SemestreDetailView(semestre: sem)),
                        );
                      }
                    },
                    onLongPress: () {
                      _toggleSelection(sem.id!);
                    },
                  ),
                );
              },
            ),
      floatingActionButton: isSelectionMode
          ? null
          : FloatingActionButton(
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
    );
  }
}
