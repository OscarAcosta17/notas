import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import '../models/ramo.dart';
import '../models/semestre.dart';
import '../theme/app_theme.dart';
import '../theme/expressive_widgets.dart';
import '../viewmodels/ramo_provider.dart';
import '../viewmodels/settings_provider.dart';
import 'add_ramo_dialog.dart';
import 'edit_ramo_dialog.dart';
import 'ramo_detail_view.dart';

class SemestreDetailView extends ConsumerStatefulWidget {
  final Semestre semestre;
  final Widget? headerWidget;
  final List<Widget>? actions;
  final bool showBackButton;
  const SemestreDetailView({
    super.key,
    required this.semestre,
    this.headerWidget,
    this.actions,
    this.showBackButton = true,
  });

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
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: isSelectionMode
          ? AppBar(
              backgroundColor: scheme.primaryContainer,
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _clearSelection,
                color: scheme.onPrimaryContainer,
              ),
              title: Text(
                '${_selectedIds.length} seleccionado(s)',
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              actions: [
                if (_selectedIds.length == 1)
                  IconButton(
                    icon: const Icon(Icons.edit_rounded),
                    color: scheme.onPrimaryContainer,
                    onPressed: _editSelected,
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: scheme.onPrimaryContainer,
                  onPressed: _deleteSelected,
                ),
              ],
            )
          : AppBar(
              title: Text(widget.semestre.nombre),
              backgroundColor: scheme.surface,
              automaticallyImplyLeading: widget.showBackButton,
              actions: [
                if (widget.actions != null) ...widget.actions!,
              ],
            ),
      body: Column(
        children: [
          if (widget.headerWidget != null) widget.headerWidget!,
          Expanded(
            child: ramos.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppTheme.radiusExtraLarge),
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const TonalIconBadge(icon: Icons.menu_book_rounded, size: 56),
                            const SizedBox(height: 14),
                            Text(
                              'No hay ramos configurados',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Usa el botón + para añadir tu primera asignatura.',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : _buildRamosList(
                    context,
                    ramos,
                    settings.subjectViewMode,
                    settings.isCompactList,
                    settings.gridCrossAxisCount,
                    isSelectionMode,
                    bottomInset,
                  ),
          ),
        ],
      ),
      floatingActionButton: isSelectionMode
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: 84 + bottomInset),
              child: FloatingActionButton(
                child: const Icon(Icons.add_rounded),
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

  Widget _buildRamosList(
    BuildContext context,
    List<Ramo> ramos,
    String mode,
    bool isCompactList,
    int gridCols,
    bool isSelectionMode,
    double bottomInset,
  ) {
    final bottomPadding = 112.0 + bottomInset;

    if (mode == 'cuadricula') {
      return ReorderableGridView.builder(
        padding: EdgeInsets.fromLTRB(16, 10, 16, bottomPadding),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridCols,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: isCompactList ? (gridCols == 3 ? 1.5 : 2.0) : (gridCols == 3 ? 1.0 : 1.2),
        ),
        itemCount: ramos.length,
        onReorder: (oldIndex, newIndex) {
          ref.read(ramoProvider(widget.semestre.id!).notifier).reordenarRamos(oldIndex, newIndex);
        },
        itemBuilder: (context, index) {
          final ramo = ramos[index];
          return _buildCard(
            context,
            ramo,
            isSelectionMode,
            true,
            Key('grid_${ramo.id}'),
            index,
            isCompact: isCompactList,
            gridCols: gridCols,
          );
        },
      );
    } else {
      final isCompact = isCompactList;
      return ReorderableListView.builder(
        padding: EdgeInsets.fromLTRB(16, 10, 16, bottomPadding),
        itemCount: ramos.length,
        proxyDecorator: (child, index, animation) {
          return Material(
            color: Colors.transparent,
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            child: child,
          );
        },
        onReorder: (oldIndex, newIndex) {
          ref.read(ramoProvider(widget.semestre.id!).notifier).reordenarRamos(oldIndex, newIndex);
        },
        itemBuilder: (context, index) {
          final ramo = ramos[index];
          return Padding(
            key: Key('list_${ramo.id}'),
            padding: EdgeInsets.only(bottom: isCompact ? 8.0 : 12.0),
            child: _buildCard(
              context,
              ramo,
              isSelectionMode,
              false,
              null,
              index,
              isCompact: isCompact,
              gridCols: gridCols,
            ),
          );
        },
      );
    }
  }

  Widget _buildCard(
    BuildContext context,
    Ramo ramo,
    bool isSelectionMode,
    bool isGrid,
    Key? key,
    int index, {
    bool isCompact = false,
    int gridCols = 2,
  }) {
    final isSelected = _selectedIds.contains(ramo.id);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasCustomColor = ramo.color != null;
    final Color? customColor = hasCustomColor ? Color(ramo.color!) : null;

    final Color baseSurface = isDark ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest;
    final Color unselectedColor = customColor != null
        ? Color.alphaBlend(customColor.withValues(alpha: isDark ? 0.08 : 0.05), baseSurface)
        : baseSurface;

    final Color cardColor = isSelected ? scheme.primaryContainer.withValues(alpha: 0.72) : unselectedColor;

    final BorderSide borderSide = isSelected
        ? BorderSide(color: scheme.primary, width: 2)
        : BorderSide(
            color: customColor != null
                ? customColor.withValues(alpha: isDark ? 0.35 : 0.25)
                : scheme.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.6),
            width: 1,
          );

    final double cardRadius = isGrid && isCompact ? AppTheme.radiusMedium : AppTheme.radiusLarge;
    final double stripWidth = isGrid ? (gridCols == 3 ? 16 : 22) : 26;

    Widget content;
    if (isGrid) {
      content = Padding(
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 12, vertical: isCompact ? 8 : 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              ramo.nombre,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: isCompact ? 13.5 : 15.5,
                color: scheme.onSurface,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (!isCompact) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  'Aprob: ${ramo.notaAprobacion}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (isSelectionMode) ...[
              const SizedBox(height: 6),
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      );
    } else {
      content = ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: isCompact ? 14 : 18,
          vertical: isCompact ? 2 : 8,
        ),
        title: Text(
          ramo.nombre,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: isCompact ? 15.5 : 17,
            color: scheme.onSurface,
          ),
        ),
        subtitle: isCompact
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Promedio: ${ramo.tipoPromedio} · Aprobación: ${ramo.notaAprobacion}',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
        trailing: isSelectionMode
            ? Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
              )
            : ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                  ),
                ),
              ),
      );
    }

    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.fromBorderSide(borderSide),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
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
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (customColor != null)
                  Container(
                    width: stripWidth,
                    color: customColor,
                  ),
                Expanded(child: content),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
