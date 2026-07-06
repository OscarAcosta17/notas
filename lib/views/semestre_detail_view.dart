import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/semestre.dart';
import '../viewmodels/ramo_provider.dart';
import 'add_ramo_dialog.dart';
import 'edit_ramo_dialog.dart';
import 'ramo_detail_view.dart';

class SemestreDetailView extends ConsumerStatefulWidget {
  final Semestre semestre;
  const SemestreDetailView({super.key, required this.semestre});

  @override
  ConsumerState<SemestreDetailView> createState() => _SemestreDetailViewState();
}

class _SemestreDetailViewState extends ConsumerState<SemestreDetailView> {
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
      ref.read(ramoProvider(widget.semestre.id!).notifier).eliminarRamo(id);
    }
    _clearSelection();
  }

  void _editSelected() {
    if (_selectedIds.length != 1) return;
    final id = _selectedIds.first;
    final ramos = ref.read(ramoProvider(widget.semestre.id!));
    final ramo = ramos.firstWhere((r) => r.id == id);

    showDialog(
      context: context,
      builder: (context) => EditRamoDialog(ramo: ramo),
    ).then((_) => _clearSelection());
  }

  @override
  Widget build(BuildContext context) {
    final ramos = ref.watch(ramoProvider(widget.semestre.id!));
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
              title: Text(widget.semestre.nombre, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
              backgroundColor: Theme.of(context).colorScheme.surface,
              elevation: 0,
              iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
            ),
      body: ramos.isEmpty
          ? const Center(child: Text('No hay ramos configurados.', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: ramos.length,
              itemBuilder: (context, index) {
                final ramo = ramos[index];
                final isSelected = _selectedIds.contains(ramo.id);

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
                      ramo.nombre,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    subtitle: Text('Promedio: ${ramo.tipoPromedio} - Apruébase con: ${ramo.notaAprobacion}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                    trailing: isSelectionMode
                        ? Icon(
                            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                          )
                        : const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                    onTap: () {
                      if (isSelectionMode) {
                        _toggleSelection(ramo.id!);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => RamoDetailView(ramo: ramo)),
                        );
                      }
                    },
                    onLongPress: () {
                      _toggleSelection(ramo.id!);
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
                  builder: (context) => AddRamoDialog(semestreId: widget.semestre.id!),
                );
              },
            ),
    );
  }
}
