import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../theme/expressive_widgets.dart';
import '../../viewmodels/settings_provider.dart';

class AppearanceSettingsView extends ConsumerStatefulWidget {
  const AppearanceSettingsView({super.key});

  @override
  ConsumerState<AppearanceSettingsView> createState() => _AppearanceSettingsViewState();
}

class _AppearanceSettingsViewState extends ConsumerState<AppearanceSettingsView> {
  Future<void> _changeIcon(String? iconName) async {
    try {
      if (await FlutterDynamicIconPlus.supportsAlternateIcons) {
        await FlutterDynamicIconPlus.setAlternateIconName(iconName: iconName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Icono cambiado (la app podría cerrarse momentáneamente)')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cambiar el icono: $e')),
        );
      }
    }
  }

  String _frostedDescription(String intensity) {
    switch (intensity) {
      case 'solido':
        return 'Superficies opacas para máximo contraste y menor consumo';
      case 'sutil':
        return 'Desenfoque suave y conservador que prioriza el contraste';
      case 'intenso':
      default:
        return 'Vidrio esmerilado marcado con profundidad estilo Android 17';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scheme.surface,
      appBar: const FrostedAppBar(
        title: Text('Apariencia'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(0, topInset + 8, 0, 32 + bottomInset),
        children: [
          const ExpressiveSectionHeader(title: 'Tema y Color'),
          ExpressiveGroupedSection(
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: const TonalIconBadge(icon: Icons.dark_mode_rounded),
                title: const Text('Modo Oscuro', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Activar paleta de colores oscuros'),
                value: settings.isDarkMode,
                onChanged: (bool value) {
                  ref.read(settingsProvider.notifier).toggleDarkMode();
                },
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: const TonalIconBadge(icon: Icons.wallpaper_rounded),
                title: const Text('Colores del sistema (Material You)', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Adapta la app a la paleta de tu fondo de pantalla en Android'),
                value: settings.useDynamicColor,
                onChanged: (bool value) {
                  ref.read(settingsProvider.notifier).setUseDynamicColor(value);
                },
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: TonalIconBadge(
                  icon: Icons.color_lens_rounded,
                  color: settings.tertiaryColor != null ? Color(settings.tertiaryColor!) : null,
                ),
                title: const Text('Color Destacado (Terciario)', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  settings.useDynamicColor
                      ? 'En pausa mientras Material You está activo'
                      : 'Personaliza el color de acento sobre el tema monocromático',
                ),
                trailing: settings.tertiaryColor != null
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        tooltip: 'Restablecer a monocromático',
                        onPressed: () => ref.read(settingsProvider.notifier).setTertiaryColor(null),
                      )
                    : Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                onTap: () async {
                  final Color newColor = await showColorPickerDialog(
                    context,
                    settings.tertiaryColor != null ? Color(settings.tertiaryColor!) : Colors.blue,
                    title: Text('Selecciona el Color', style: Theme.of(context).textTheme.titleLarge),
                    width: 40,
                    height: 40,
                    spacing: 0,
                    runSpacing: 0,
                    borderRadius: 0,
                    wheelDiameter: 165,
                    enableOpacity: false,
                    showColorCode: true,
                    colorCodeHasColor: true,
                    pickersEnabled: <ColorPickerType, bool>{
                      ColorPickerType.both: false,
                      ColorPickerType.primary: false,
                      ColorPickerType.accent: false,
                      ColorPickerType.bw: false,
                      ColorPickerType.custom: false,
                      ColorPickerType.wheel: true,
                    },
                  );
                  ref.read(settingsProvider.notifier).setTertiaryColor(newColor.toARGB32());
                },
              ),
            ],
          ),
          const ExpressiveSectionHeader(title: 'Efecto Cristal (Android 17)'),
          ExpressiveGroupedSection(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const TonalIconBadge(icon: Icons.blur_on_rounded),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Intensidad de desenfoque',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _frostedDescription(settings.frostedGlassIntensity),
                                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment<String>(value: 'solido', label: Text('Sólido')),
                          ButtonSegment<String>(value: 'sutil', label: Text('Sutil')),
                          ButtonSegment<String>(value: 'intenso', label: Text('Intenso')),
                        ],
                        selected: {settings.frostedGlassIntensity},
                        onSelectionChanged: (Set<String> newSelection) {
                          ref.read(settingsProvider.notifier).setFrostedGlassIntensity(newSelection.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Live frosted preview strip
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        height: 62,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Container(color: scheme.primary.withValues(alpha: 0.75))),
                                Expanded(child: Container(color: scheme.tertiary.withValues(alpha: 0.75))),
                                Expanded(child: Container(color: scheme.secondary.withValues(alpha: 0.75))),
                              ],
                            ),
                            Center(
                              child: FrostedGlassSurface(
                                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                child: Text(
                                  'Vista previa del cristal',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const ExpressiveSectionHeader(title: 'Apariencia de Asignaturas'),
          ExpressiveGroupedSection(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Modo de Vista', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text('Lista vertical o cuadrícula 2D', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'lista',
                            icon: Icon(Icons.view_agenda_rounded),
                            label: Text('Lista'),
                          ),
                          ButtonSegment<String>(
                            value: 'cuadricula',
                            icon: Icon(Icons.grid_view_rounded),
                            label: Text('Cuadrícula'),
                          ),
                        ],
                        selected: {settings.subjectViewMode},
                        onSelectionChanged: (Set<String> newSelection) {
                          ref.read(settingsProvider.notifier).setSubjectViewMode(newSelection.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: const TonalIconBadge(icon: Icons.density_small_rounded),
                title: const Text('Modo Compacto', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Muestra las asignaturas ocupando menos espacio'),
                value: settings.isCompactList,
                onChanged: (bool value) {
                  ref.read(settingsProvider.notifier).setIsCompactList(value);
                },
              ),
              if (settings.subjectViewMode == 'cuadricula')
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Columnas en Cuadrícula', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                              Text('Cantidad de cursos por fila', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                            ],
                          ),
                          SegmentedButton<int>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment<int>(value: 2, label: Text('2')),
                              ButtonSegment<int>(value: 3, label: Text('3')),
                            ],
                            selected: {settings.gridCrossAxisCount},
                            onSelectionChanged: (Set<int> newSelection) {
                              ref.read(settingsProvider.notifier).setGridCrossAxisCount(newSelection.first);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text('Previsualización:', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Row(
                        children: List.generate(settings.gridCrossAxisCount, (index) {
                          final accentColors = [Colors.blueGrey, Colors.teal, Colors.indigo];
                          return Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              height: settings.isCompactList ? 44 : 78,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                              ),
                              child: Row(
                                children: [
                                  Container(width: 10, color: accentColors[index % accentColors.length]),
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        'Ramo ${index + 1}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const ExpressiveSectionHeader(title: 'Icono de la App'),
          ExpressiveGroupedSection(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.apps_rounded),
                title: const Text('Clásico', style: TextStyle(fontWeight: FontWeight.w600)),
                trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                onTap: () => _changeIcon(null),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const TonalIconBadge(icon: Icons.apps_outage_rounded),
                title: const Text('Minimalista (Nuevo)', style: TextStyle(fontWeight: FontWeight.w600)),
                trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                onTap: () => _changeIcon('com.example.notas.Icon2'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
