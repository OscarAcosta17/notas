import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/semestre.dart';
import '../models/ramo.dart';
import '../viewmodels/ramo_provider.dart';
import '../viewmodels/settings_provider.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'add_ramo_dialog.dart';
import 'edit_ramo_dialog.dart';
import 'ramo_detail_view.dart';

class SemestreDetailView extends ConsumerStatefulWidget {
  final Semestre semestre;
  final Widget? headerWidget;
  final List<Widget>? actions;
  final bool showBackButton;
  const SemestreDetailView({super.key, required this.semestre, this.headerWidget, this.actions, this.showBackButton = true});

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
    final settings = ref.watch(settingsProvider);
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
              automaticallyImplyLeading: widget.showBackButton,
              actions: [
                if (widget.actions != null) ...widget.actions!,
                PopupMenuButton<String>(
                  icon: const Icon(Icons.view_list),
                  onSelected: (value) {
                    ref.read(settingsProvider.notifier).setSubjectViewMode(value);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'lista', child: Text('Lista')),
                    const PopupMenuItem(value: 'cuadricula', child: Text('Cuadrícula')),
                    const PopupMenuItem(value: 'compacta', child: Text('Compacta')),
                  ],
                ),
              ],
            ),
      body: Column(
        children: [
          if (widget.headerWidget != null) widget.headerWidget!,
          Expanded(
            child: ramos.isEmpty
                ? const Center(child: Text('No hay ramos configurados.', style: TextStyle(color: Colors.grey)))
                : _buildRamosList(context, ramos, settings.subjectViewMode, isSelectionMode),
          ),
        ],
      ),
      floatingActionButton: isSelectionMode
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 80),
              child: FloatingActionButton(
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
            ),
    );
  }

  Widget _buildRamosList(BuildContext context, List<Ramo> ramos, String mode, bool isSelectionMode) {
    if (mode == 'cuadricula') {
      return ReorderableGridView.builder(
        padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.2,
        ),
        itemCount: ramos.length,
        onReorder: (oldIndex, newIndex) {
          ref.read(ramoProvider(widget.semestre.id!).notifier).reordenarRamos(oldIndex, newIndex);
        },
        itemBuilder: (context, index) {
          final ramo = ramos[index];
          return _buildCard(context, ramo, isSelectionMode, true, Key('grid_${ramo.id}'), index, isCompact: false);
        },
      );
    } else {
      // lista or compacta
      final isCompact = mode == 'compacta';
      return ReorderableListView.builder(
        padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
        itemCount: ramos.length,
        onReorder: (oldIndex, newIndex) {
          ref.read(ramoProvider(widget.semestre.id!).notifier).reordenarRamos(oldIndex, newIndex);
        },
        itemBuilder: (context, index) {
          final ramo = ramos[index];
          return Padding(
            key: Key('list_${ramo.id}'),
            padding: EdgeInsets.only(bottom: isCompact ? 8.0 : 12.0),
            child: _buildCard(context, ramo, isSelectionMode, false, null, index, isCompact: isCompact),
          );
        },
      );
    }
  }

  Widget _buildCard(BuildContext context, Ramo ramo, bool isSelectionMode, bool isGrid, Key? key, int index, {bool isCompact = false}) {
    final isSelected = _selectedIds.contains(ramo.id);
    
    Widget content;
    if (isGrid) {
      content = Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              ramo.nombre,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text('Aprob: ${ramo.notaAprobacion}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
            if (isSelectionMode)
              Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
              ),
          ],
        ),
      );
    } else {
      content = ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 20, vertical: isCompact ? 4 : 10),
        title: Text(
          ramo.nombre,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: isCompact ? 16 : 18, color: Theme.of(context).colorScheme.onSurface),
        ),
        subtitle: isCompact ? null : Text('Promedio: ${ramo.tipoPromedio} - Apruébase con: ${ramo.notaAprobacion}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
        trailing: isSelectionMode
            ? Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
              )
            : ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle, size: 20, color: Colors.grey),
              ),
      );
    }

    return Card(
      key: key,
      margin: EdgeInsets.zero,
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5) : Theme.of(context).colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
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
        child: content,
      ),
    );
  }
}
