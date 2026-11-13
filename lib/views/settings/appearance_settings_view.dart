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
  static const _presetAccents = <({int? value, String label, Color? swatch})>[
    (value: null, label: 'Mono', swatch: null),
    (value: 0xFF2563EB, label: 'Azul', swatch: Color(0xFF2563EB)),
    (value: 0xFF0D9488, label: 'Teal', swatch: Color(0xFF0D9488)),
    (value: 0xFF16A34A, label: 'Verde', swatch: Color(0xFF16A34A)),
    (value: 0xFFD97706, label: 'Ámbar', swatch: Color(0xFFD97706)),
    (value: 0xFFE11D48, label: 'Coral', swatch: Color(0xFFE11D48)),
    (value: 0xFF7C3AED, label: 'Violeta', swatch: Color(0xFF7C3AED)),
  ];

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

  Future<void> _applyTertiaryColor(SettingsState settings, int? colorValue) async {
    final notifier = ref.read(settingsProvider.notifier);
    if (colorValue != null && settings.useDynamicColor) {
      await notifier.setUseDynamicColor(false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Material You desactivado para aplicar tu color destacado')),
        );
      }
    }
    await notifier.setTertiaryColor(colorValue);
  }

  Future<void> _openColorWheel(SettingsState settings) async {
    final scheme = Theme.of(context).colorScheme;
    Color pickedColor = settings.tertiaryColor != null ? Color(settings.tertiaryColor!) : scheme.primary;

    final confirmed = await ColorPicker(
      color: pickedColor,
      onColorChanged: (Color color) => pickedColor = color,
      width: 40,
      height: 40,
      borderRadius: 12,
      wheelDiameter: 165,
      enableOpacity: false,
      showColorCode: true,
      colorCodeHasColor: true,
      pickersEnabled: const <ColorPickerType, bool>{
        ColorPickerType.both: false,
        ColorPickerType.primary: false,
        ColorPickerType.accent: false,
        ColorPickerType.bw: false,
        ColorPickerType.custom: false,
        ColorPickerType.wheel: true,
      },
    ).showPickerDialog(
      context,
      title: Text('Selecciona Color Destacado', style: Theme.of(context).textTheme.titleLarge),
    );

    if (!confirmed || !mounted) return;
    await _applyTertiaryColor(settings, pickedColor.toARGB32());
  }

  String _frostedDescription(String intensity) {
    switch (intensity) {
      case 'solido':
        return 'Superficies opacas para máximo contraste y menor consumo';
      case 'sutil':
        return 'Desenfoque suave y conservador que prioriza la legibilidad';
      case 'intenso':
      default:
        return 'Vidrio esmerilado profundo estilo Android 17';
    }
  }

  String _radiusDescription(String style) {
    switch (style) {
      case 'compacto':
        return 'Bordes definidos y geométricos (12 dp)';
      case 'equilibrado':
        return 'Curvatura intermedia versátil (17 dp)';
      case 'expresivo':
      default:
        return 'Bordes orgánicos Android 17 (22 dp)';
    }
  }

  String _subjectStyleDescription(String style) {
    switch (style) {
      case 'franja':
        return 'Barra vertical limpia del color del ramo';
      case 'tinte':
        return 'Tarjeta suavemente bañada en el tono del ramo';
      case 'borde':
        return 'Contorno marcado e insignia lateral';
      case 'mixto':
      default:
        return 'Franja lateral combinada con tinte sutil';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.visualTokens;
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
          const ExpressiveSectionHeader(title: 'Tema, Color y Contraste'),
          ExpressiveGroupedSection(
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: TonalIconBadge(
                  icon: settings.isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  color: tokens.accentColor,
                ),
                title: const Text('Modo Oscuro', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Activar paleta de colores oscuros'),
                value: settings.isDarkMode,
                onChanged: (_) => notifier.toggleDarkMode(),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: TonalIconBadge(
                  icon: Icons.wallpaper_rounded,
                  color: tokens.accentColor,
                ),
                title: const Text('Colores del sistema (Material You)', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Adapta la app a la paleta de tu fondo de pantalla en Android'),
                value: settings.useDynamicColor,
                onChanged: (bool value) => notifier.setUseDynamicColor(value),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TonalIconBadge(icon: Icons.contrast_rounded, color: tokens.accentColor),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Estilo de Superficie', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                              Text(
                                settings.surfaceStyle == 'oled'
                                    ? 'Negro puro (#000000) en modo oscuro para pantallas AMOLED'
                                    : 'Superficies tonales multicapa estándar',
                                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment<String>(value: 'tonal', label: Text('Tonal')),
                          ButtonSegment<String>(value: 'oled', label: Text('OLED puro')),
                        ],
                        selected: {settings.surfaceStyle},
                        onSelectionChanged: (sel) {
                          AppHaptics.selection(context);
                          notifier.setSurfaceStyle(sel.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _openColorWheel(settings),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            TonalIconBadge(
                              icon: Icons.color_lens_rounded,
                              color: settings.tertiaryColor != null ? Color(settings.tertiaryColor!) : tokens.accentColor,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Color Destacado (Terciario)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                                  Text(
                                    settings.useDynamicColor
                                        ? 'Material You está activo; al elegir un acento se aplicará automáticamente'
                                        : 'Resalta botones, interruptores, indicadores y navegación',
                                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            if (settings.tertiaryColor != null)
                              IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                tooltip: 'Restablecer a monocromático',
                                onPressed: () {
                                  AppHaptics.selection(context);
                                  notifier.setTertiaryColor(null);
                                },
                              )
                            else
                              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ..._presetAccents.map((preset) {
                          final isSelected = !settings.useDynamicColor && settings.tertiaryColor == preset.value;
                          final displayColor = preset.swatch ??
                              (scheme.brightness == Brightness.dark ? const Color(0xFFF3F4F6) : const Color(0xFF0E0F13));
                          return Tooltip(
                            message: preset.label,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                              onTap: () {
                                AppHaptics.selection(context);
                                _applyTertiaryColor(settings, preset.value);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: displayColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? scheme.onSurface : scheme.outlineVariant.withValues(alpha: 0.7),
                                    width: isSelected ? 2.8 : 1.2,
                                  ),
                                ),
                                child: isSelected
                                    ? Icon(
                                        preset.value == null ? Icons.auto_awesome_rounded : Icons.check_rounded,
                                        size: 17,
                                        color: ThemeData.estimateBrightnessForColor(displayColor) == Brightness.dark
                                            ? Colors.white
                                            : const Color(0xFF0E0F12),
                                      )
                                    : preset.value == null
                                        ? Icon(
                                            Icons.block_rounded,
                                            size: 15,
                                            color: ThemeData.estimateBrightnessForColor(displayColor) == Brightness.dark
                                                ? Colors.white
                                                : const Color(0xFF0E0F12),
                                          )
                                        : null,
                              ),
                            ),
                          );
                        }),
                        ActionChip(
                          avatar: const Icon(Icons.colorize_rounded, size: 17),
                          label: const Text('Personalizado'),
                          onPressed: () => _openColorWheel(settings),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const ExpressiveSectionHeader(title: 'Navegación e Interfaz'),
          ExpressiveGroupedSection(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: _buildNavPreview(context, settings, tokens, scheme),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Barra de Navegación', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      settings.bottomNavStyle == 'floating_fab'
                          ? 'Toolbar flotante acoplada con botón + lateral (Android 17)'
                          : 'Barra inferior de borde a borde con botón flotante clásico',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment<String>(value: 'floating_fab', label: Text('Flotante + FAB')),
                          ButtonSegment<String>(value: 'dock', label: Text('Dock clásico')),
                        ],
                        selected: {settings.bottomNavStyle},
                        onSelectionChanged: (sel) {
                          AppHaptics.selection(context);
                          notifier.setBottomNavStyle(sel.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Etiquetas en la Barra', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text('Visibilidad de nombres debajo de cada ícono', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment<String>(value: 'always', label: Text('Siempre')),
                          ButtonSegment<String>(value: 'selected', label: Text('Activa')),
                          ButtonSegment<String>(value: 'icon_only', label: Text('Íconos')),
                        ],
                        selected: {settings.navLabelMode},
                        onSelectionChanged: (sel) {
                          AppHaptics.selection(context);
                          notifier.setNavLabelMode(sel.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Selector de Semestre', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      settings.semesterSelectorStyle == 'header'
                          ? 'Desplegable compacto en la cabecera que libera espacio para tus ramos'
                          : 'Barra fija de chips horizontales debajo del título',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment<String>(value: 'header', label: Text('Cabecera')),
                          ButtonSegment<String>(value: 'chips', label: Text('Chips')),
                        ],
                        selected: {settings.semesterSelectorStyle},
                        onSelectionChanged: (sel) {
                          AppHaptics.selection(context);
                          notifier.setSemesterSelectorStyle(sel.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: TonalIconBadge(icon: Icons.swipe_rounded, color: tokens.accentColor),
                title: const Text('Deslizar entre secciones', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Cambia entre Ramos, Horario y Agenda deslizando horizontalmente'),
                value: settings.enableHorizontalSwipe,
                onChanged: (bool value) => notifier.setEnableHorizontalSwipe(value),
              ),
            ],
          ),

          const ExpressiveSectionHeader(title: 'Cristal, Formas y Respuesta'),
          ExpressiveGroupedSection(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TonalIconBadge(icon: Icons.blur_on_rounded, color: tokens.accentColor),
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
                          AppHaptics.selection(context);
                          notifier.setFrostedGlassIntensity(newSelection.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(tokens.cardRadius),
                      child: SizedBox(
                        height: 60,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Container(color: scheme.primary.withValues(alpha: 0.75))),
                                Expanded(child: Container(color: tokens.accentColor.withValues(alpha: 0.85))),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TonalIconBadge(icon: Icons.rounded_corner_rounded, color: tokens.accentColor),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Radio de Tarjetas', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                              Text(
                                _radiusDescription(settings.cardRadiusStyle),
                                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment<String>(value: 'compacto', label: Text('Compacto')),
                          ButtonSegment<String>(value: 'equilibrado', label: Text('Medio')),
                          ButtonSegment<String>(value: 'expresivo', label: Text('Expresivo')),
                        ],
                        selected: {settings.cardRadiusStyle},
                        onSelectionChanged: (sel) {
                          AppHaptics.selection(context);
                          notifier.setCardRadiusStyle(sel.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: TonalIconBadge(icon: Icons.vibration_rounded, color: tokens.accentColor),
                title: const Text('Vibración háptica', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Respuesta táctil sutil al cambiar secciones o seleccionar'),
                value: settings.hapticsEnabled,
                onChanged: (bool value) => notifier.setHapticsEnabled(value),
              ),
            ],
          ),

          const ExpressiveSectionHeader(title: 'Tarjetas de Asignaturas'),
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
                          AppHaptics.selection(context);
                          notifier.setSubjectViewMode(newSelection.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: TonalIconBadge(icon: Icons.density_small_rounded, color: tokens.accentColor),
                title: const Text('Modo Compacto', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Muestra las asignaturas ocupando menos espacio'),
                value: settings.isCompactList,
                onChanged: (bool value) => notifier.setIsCompactList(value),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Estilo de Color en Ramos', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      _subjectStyleDescription(settings.subjectColorStyle),
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final opt in const [
                          (id: 'mixto', label: 'Mixto'),
                          (id: 'franja', label: 'Franja'),
                          (id: 'tinte', label: 'Tinte'),
                          (id: 'borde', label: 'Borde'),
                        ])
                          ChoiceChip(
                            label: Text(opt.label),
                            selected: settings.subjectColorStyle == opt.id,
                            onSelected: (_) {
                              AppHaptics.selection(context);
                              notifier.setSubjectColorStyle(opt.id);
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (settings.subjectViewMode == 'cuadricula') ...[
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
                              AppHaptics.selection(context);
                              notifier.setGridCrossAxisCount(newSelection.first);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    Text('Previsualización:', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    _buildSubjectPreview(settings, tokens, scheme),
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
                leading: TonalIconBadge(icon: Icons.apps_rounded, color: tokens.accentColor),
                title: const Text('Clásico', style: TextStyle(fontWeight: FontWeight.w600)),
                trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                onTap: () => _changeIcon(null),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: TonalIconBadge(icon: Icons.apps_outage_rounded, color: tokens.accentColor),
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

  Widget _buildNavPreview(
    BuildContext context,
    SettingsState settings,
    NotasVisualTokens tokens,
    ColorScheme scheme,
  ) {
    final isDock = settings.bottomNavStyle == 'dock';
    final isDark = scheme.brightness == Brightness.dark;
    final items = const [
      (Icons.school_rounded, 'Ramos'),
      (Icons.calendar_today_rounded, 'Horario'),
      (Icons.event_note_rounded, 'Agenda'),
    ];

    Widget navRow(double itemHeight) {
      return Row(
        children: List.generate(items.length, (i) {
          final active = i == 0;
          final showText = settings.navLabelMode == 'always' || (settings.navLabelMode == 'selected' && active);
          return Expanded(
            child: Container(
              height: itemHeight,
              alignment: Alignment.center,
              decoration: active
                  ? BoxDecoration(
                      color: tokens.accentContainer,
                      borderRadius: BorderRadius.circular(isDock ? 12 : AppTheme.radiusFull),
                      border: Border.all(color: tokens.accentColor.withValues(alpha: 0.25)),
                    )
                  : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    items[i].$1,
                    size: showText ? 15 : 17,
                    color: active ? tokens.accentColor : scheme.onSurfaceVariant,
                  ),
                  if (showText)
                    Text(
                      items[i].$2,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        color: active ? tokens.onAccentContainer : scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      );
    }

    return Container(
      height: 76,
      padding: EdgeInsets.fromLTRB(isDock ? 0 : 10, 8, isDock ? 0 : 10, isDock ? 0 : 10),
      decoration: BoxDecoration(
        color: isDark ? scheme.surface : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: isDock
            ? Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(tokens.cardRadius),
                    bottomRight: Radius.circular(tokens.cardRadius),
                  ),
                  border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45))),
                ),
                child: navRow(34),
              )
            : Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: navRow(34),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: tokens.accentColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.add_rounded, size: 20, color: tokens.onAccentColor),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSubjectPreview(
    SettingsState settings,
    NotasVisualTokens tokens,
    ColorScheme scheme,
  ) {
    final isDark = scheme.brightness == Brightness.dark;
    final accentColors = [Colors.blueGrey, Colors.teal, Colors.indigo];

    Widget buildSampleCard(int index) {
      final accent = accentColors[index % accentColors.length];
      final style = settings.subjectColorStyle;
      final hasStrip = style == 'mixto' || style == 'franja';
      final hasTint = style == 'mixto' || style == 'tinte';
      final hasStrongBorder = style == 'borde';
      final baseCard = isDark ? scheme.surfaceContainer : scheme.surfaceContainerLowest;
      final bg = hasTint ? Color.alphaBlend(accent.withValues(alpha: isDark ? 0.14 : 0.08), baseCard) : baseCard;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.symmetric(horizontal: settings.subjectViewMode == 'cuadricula' ? 4 : 0, vertical: 3),
        height: settings.isCompactList ? 44 : 68,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          border: Border.all(
            color: hasStrongBorder ? accent.withValues(alpha: 0.85) : scheme.outlineVariant.withValues(alpha: 0.5),
            width: hasStrongBorder ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          children: [
            if (hasStrip) Container(width: 8, color: accent),
            if (hasStrongBorder) ...[
              const SizedBox(width: 10),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
            ],
            Expanded(
              child: Center(
                child: Text(
                  'Ramo ${index + 1}',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (settings.subjectViewMode == 'lista') {
      return Column(
        children: [
          buildSampleCard(0),
          buildSampleCard(1),
        ],
      );
    }

    return Row(
      children: List.generate(
        settings.gridCrossAxisCount,
        (index) => Expanded(child: buildSampleCard(index)),
      ),
    );
  }
}
