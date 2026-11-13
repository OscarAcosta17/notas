import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/main.dart';
import 'package:notas/models/categoria_evaluacion.dart';
import 'package:notas/models/evaluacion.dart';
import 'package:notas/models/ramo.dart';
import 'package:notas/models/semestre.dart';
import 'package:notas/services/updater_service.dart';
import 'package:notas/theme/app_theme.dart';
import 'package:notas/viewmodels/categoria_provider.dart';
import 'package:notas/viewmodels/ramo_provider.dart';
import 'package:notas/viewmodels/semestre_provider.dart';
import 'package:notas/viewmodels/settings_provider.dart';
import 'package:notas/views/formula_editor_dialog.dart';
import 'package:notas/views/ramo_detail_view.dart';
import 'package:notas/views/semestre_detail_view.dart';
import 'package:notas/views/settings/appearance_settings_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSemestreNotifier extends SemestreNotifier {
  final List<Semestre> initial;
  _FakeSemestreNotifier([this.initial = const []]);

  @override
  List<Semestre> build() => initial;

  @override
  Future<void> cargarSemestres() async {}
}

class _FakeRamoNotifier extends RamoNotifier {
  final List<Ramo> initial;
  _FakeRamoNotifier(this.initial);

  @override
  List<Ramo> build() => initial;

  @override
  Future<void> cargarRamos() async {}
}

class _FakeCategoriaNotifier extends CategoriaNotifier {
  final List<CategoriaEvaluacion> initial;
  _FakeCategoriaNotifier(this.initial);

  @override
  List<CategoriaEvaluacion> build() => initial;

  @override
  Future<void> cargarCategorias() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UpdaterService.resetStartupCheck();
  });

  group('AppTheme & NotasVisualTokens', () {
    test('frosted glass presets produce expected blur and opacity tokens', () {
      final solidTheme = AppTheme.buildTheme(
        brightness: Brightness.light,
        useDynamicColor: false,
        frostedGlassIntensity: 'solido',
      );
      final subtleTheme = AppTheme.buildTheme(
        brightness: Brightness.light,
        useDynamicColor: false,
        frostedGlassIntensity: 'sutil',
      );
      final intenseTheme = AppTheme.buildTheme(
        brightness: Brightness.dark,
        useDynamicColor: false,
        frostedGlassIntensity: 'intenso',
      );

      final solid = solidTheme.extension<NotasVisualTokens>()!;
      final subtle = subtleTheme.extension<NotasVisualTokens>()!;
      final intense = intenseTheme.extension<NotasVisualTokens>()!;

      expect(solid.blurSigma, 0.0);
      expect(solid.glassOpacity, 1.0);
      expect(subtle.blurSigma, 10.0);
      expect(intense.blurSigma, 22.0);
      expect(intense.glassOpacity, lessThan(subtle.glassOpacity));
    });

    test('dynamic color activates only when useDynamicColor is true and scheme provided', () {
      final dynamicSeed = ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.light);

      final monoWhenDisabled = AppTheme.buildTheme(
        brightness: Brightness.light,
        useDynamicColor: false,
        frostedGlassIntensity: 'intenso',
        dynamicScheme: dynamicSeed,
      );
      final dynamicWhenEnabled = AppTheme.buildTheme(
        brightness: Brightness.light,
        useDynamicColor: true,
        frostedGlassIntensity: 'intenso',
        dynamicScheme: dynamicSeed,
      );

      expect(monoWhenDisabled.extension<NotasVisualTokens>()!.isDynamicPalette, isFalse);
      expect(monoWhenDisabled.colorScheme.primary, const Color(0xFF0E0F13));
      expect(dynamicWhenEnabled.extension<NotasVisualTokens>()!.isDynamicPalette, isTrue);
      expect(dynamicWhenEnabled.colorScheme.primary, dynamicSeed.primary);
    });

    test('FAB inherits tertiaryColor when monochrome and auto-contrasts bright accents', () {
      final theme = AppTheme.buildTheme(
        brightness: Brightness.light,
        useDynamicColor: false,
        frostedGlassIntensity: 'intenso',
        tertiaryColorValue: Colors.yellow.toARGB32(),
      );

      expect(theme.floatingActionButtonTheme.backgroundColor, Color(Colors.yellow.toARGB32()));
      expect(theme.floatingActionButtonTheme.foregroundColor, const Color(0xFF0E0F12));
    });

    test('v1.2.1 accent, OLED surface, radius, and subject tokens propagate globally', () {
      final theme = AppTheme.buildTheme(
        brightness: Brightness.dark,
        useDynamicColor: false,
        frostedGlassIntensity: 'sutil',
        tertiaryColorValue: 0xFF2563EB,
        surfaceStyle: 'oled',
        cardRadiusStyle: 'compacto',
        subjectColorStyle: 'borde',
        hapticsEnabled: false,
      );
      final tokens = theme.extension<NotasVisualTokens>()!;

      expect(theme.colorScheme.surface, const Color(0xFF000000));
      expect(tokens.accentColor, const Color(0xFF2563EB));
      expect(tokens.surfaceStyle, 'oled');
      expect(tokens.cardRadiusStyle, 'compacto');
      expect(tokens.cardRadius, 12.0);
      expect(tokens.subjectColorStyle, 'borde');
      expect(tokens.hapticsEnabled, isFalse);
      expect(theme.floatingActionButtonTheme.backgroundColor, const Color(0xFF2563EB));
      expect(theme.progressIndicatorTheme.color, const Color(0xFF2563EB));
      expect(theme.sliderTheme.activeTrackColor, const Color(0xFF2563EB));
    });

    test('dynamic color backfills distinct M3 tonal surfaceContainer roles', () {
      const legacyDynamic = ColorScheme.light(
        primary: Colors.indigo,
        secondary: Colors.teal,
        tertiary: Colors.amber,
      );

      final theme = AppTheme.buildTheme(
        brightness: Brightness.light,
        useDynamicColor: true,
        frostedGlassIntensity: 'intenso',
        dynamicScheme: legacyDynamic,
      );

      expect(theme.colorScheme.primary, Colors.indigo);
      expect(theme.colorScheme.surfaceContainerLow, isNot(equals(theme.colorScheme.surface)));
      expect(theme.colorScheme.surfaceContainerHigh, isNot(equals(theme.colorScheme.surfaceContainerLow)));
    });
  });

  group('SettingsNotifier', () {
    test('defaults to monochrome, expressive v1.2.1 navigation/tokens, and updates live', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Let async _loadSettings settle
      await Future<void>.delayed(Duration.zero);

      final notifier = container.read(settingsProvider.notifier);
      final initial = container.read(settingsProvider);
      expect(initial.useDynamicColor, isFalse);
      expect(initial.frostedGlassIntensity, 'intenso');
      expect(initial.tertiaryColor, isNull);
      expect(initial.bottomNavStyle, 'floating_fab');
      expect(initial.navLabelMode, 'always');
      expect(initial.semesterSelectorStyle, 'header');
      expect(initial.enableHorizontalSwipe, isTrue);
      expect(initial.surfaceStyle, 'tonal');
      expect(initial.cardRadiusStyle, 'expresivo');
      expect(initial.subjectColorStyle, 'mixto');
      expect(initial.appIcon, 'classic');
      expect(initial.hapticsEnabled, isTrue);

      await notifier.setUseDynamicColor(true);
      await notifier.setFrostedGlassIntensity('sutil');
      await notifier.setTertiaryColor(0xFF3366FF);
      await notifier.setBottomNavStyle('m3_expressive');
      await notifier.setNavLabelMode('selected');
      await notifier.setSemesterSelectorStyle('chips');
      await notifier.setEnableHorizontalSwipe(false);
      await notifier.setSurfaceStyle('oled');
      await notifier.setCardRadiusStyle('compacto');
      await notifier.setSubjectColorStyle('degradado');
      await notifier.setAppIcon('icon2');
      await notifier.setHapticsEnabled(false);

      var updated = container.read(settingsProvider);
      expect(updated.useDynamicColor, isTrue);
      expect(updated.frostedGlassIntensity, 'sutil');
      expect(updated.tertiaryColor, 0xFF3366FF);
      expect(updated.bottomNavStyle, 'm3_expressive');
      expect(updated.navLabelMode, 'selected');
      expect(updated.semesterSelectorStyle, 'chips');
      expect(updated.enableHorizontalSwipe, isFalse);
      expect(updated.surfaceStyle, 'oled');
      expect(updated.cardRadiusStyle, 'compacto');
      expect(updated.subjectColorStyle, 'degradado');
      expect(updated.appIcon, 'icon2');
      expect(updated.hapticsEnabled, isFalse);

      await notifier.setBottomNavStyle('one_ui');
      expect(container.read(settingsProvider).bottomNavStyle, 'one_ui');
      await notifier.setBottomNavStyle('ios_glass');
      expect(container.read(settingsProvider).bottomNavStyle, 'ios_glass');
      await notifier.setSubjectColorStyle('resplandor');
      expect(container.read(settingsProvider).subjectColorStyle, 'resplandor');
      await notifier.setSubjectColorStyle('neon');
      expect(container.read(settingsProvider).subjectColorStyle, 'neon');
      await notifier.setSubjectColorStyle('encabezado');
      expect(container.read(settingsProvider).subjectColorStyle, 'encabezado');

      await notifier.setTertiaryColor(null);
      updated = container.read(settingsProvider);
      expect(updated.tertiaryColor, isNull);
    });
  });

  group('UI Smoke & Android 17 Views', () {
    testWidgets('NotasApp renders empty state and floating navigation with coupled + button',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            semestreProvider.overrideWith(() => _FakeSemestreNotifier()),
          ],
          child: const NotasApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mis Semestres'), findsOneWidget);
      expect(find.text('No hay semestres creados'), findsOneWidget);
      expect(find.text('Ramos'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_rounded), findsOneWidget);
      expect(find.byIcon(Icons.event_note_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsWidgets);
    });

    testWidgets('AppearanceSettingsView exposes v1.2.1 navigation, contrast, radius, and subject style options',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AppearanceSettingsView()),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> tapCentered(String label) async {
        final finder = find.text(label);
        await tester.scrollUntilVisible(finder, 180);
        await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      expect(find.text('Colores del sistema (Material You)'), findsOneWidget);
      expect(find.text('OLED puro'), findsOneWidget);
      expect(find.text('Color Destacado (Terciario)'), findsOneWidget);

      await tapCentered('Google M3');
      await tapCentered('One UI 7');
      await tapCentered('Cristal');
      await tapCentered('Dock clásico');
      expect(find.text('Flotante + FAB'), findsOneWidget);
      expect(find.text('Cabecera'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Intensidad de desenfoque'), 180);
      await Scrollable.ensureVisible(tester.element(find.text('Sutil')), alignment: 0.5);
      await tester.pumpAndSettle();
      expect(find.text('Sólido'), findsOneWidget);
      expect(find.text('Sutil'), findsOneWidget);
      expect(find.text('Intenso'), findsOneWidget);

      await tapCentered('Sutil');
      await tapCentered('Cuadrícula');
      expect(find.text('Columnas en Cuadrícula'), findsOneWidget);
      await tapCentered('Degradado Izq ➔ Der');
      await tapCentered('Resplandor');
      await tapCentered('Neón / Doble');
      await tapCentered('Banda Superior');
      await tapCentered('Borde');

      await tester.scrollUntilVisible(find.text('Ramo 1'), 180);
      await Scrollable.ensureVisible(tester.element(find.text('Ramo 1')), alignment: 0.5);
      await tester.pumpAndSettle();
      expect(find.text('Ramo 1'), findsOneWidget);
      expect(find.text('Ramo 2'), findsOneWidget);

      await tapCentered('Minimalista (Nuevo)');
      expect(find.text('Clásico'), findsOneWidget);
      expect(find.text('Minimalista (Nuevo)'), findsOneWidget);
    });

    testWidgets('SemestreDetailView displays subject cards and supports long-press selection',
        (WidgetTester tester) async {
      final sem = Semestre(id: 1, nombre: '2026-2');
      final ramos = [
        Ramo(
          id: 10,
          idSemestre: 1,
          nombre: 'Cálculo III',
          tipoPromedio: 'Aritmético',
          tieneGlobal: false,
          reemplazaPeorNota: false,
          notaAprobacion: 55.0,
          color: Colors.teal.toARGB32(),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ramoProvider(1).overrideWith(() => _FakeRamoNotifier(ramos)),
          ],
          child: MaterialApp(home: SemestreDetailView(semestre: sem)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cálculo III'), findsOneWidget);

      await tester.longPress(find.text('Cálculo III'));
      await tester.pumpAndSettle();
      expect(find.text('1 seleccionado(s)'), findsOneWidget);
    });

    testWidgets('RamoDetailView displays Nota Actual hero card and pill tabs', (WidgetTester tester) async {
      final ramo = Ramo(
        id: 10,
        idSemestre: 1,
        nombre: 'Física II',
        tipoPromedio: 'Aritmético',
        tieneGlobal: false,
        reemplazaPeorNota: false,
        notaAprobacion: 55.0,
      );
      final cats = [
        CategoriaEvaluacion(
          id: 100,
          idRamo: 10,
          nombre: 'Certámenes',
          porcentajeTotal: 100,
          evaluaciones: [
            Evaluacion(id: 1, idCategoria: 100, nombre: 'Certamen 1', nota: 78.0),
          ],
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoriaProvider(10).overrideWith(() => _FakeCategoriaNotifier(cats)),
          ],
          child: MaterialApp(home: RamoDetailView(ramo: ramo)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NOTA ACTUAL'), findsOneWidget);
      expect(find.text('78.00'), findsWidgets);
      expect(find.text('100% evaluado'), findsOneWidget);
      expect(find.text('Certámenes'), findsOneWidget);
      expect(find.text('Certamen 1'), findsOneWidget);
      expect(find.text('Notas'), findsOneWidget);
      expect(find.text('Fechas'), findsOneWidget);

      await tester.tap(find.text('Fechas'));
      await tester.pumpAndSettle();
      expect(find.text('Sin fecha asignada'), findsOneWidget);
    });

    testWidgets('NotasApp renders header semester selector pill and switches tabs smoothly',
        (WidgetTester tester) async {
      final semestres = [
        Semestre(id: 1, nombre: '2026-1'),
        Semestre(id: 2, nombre: '2026-2'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            semestreProvider.overrideWith(() => _FakeSemestreNotifier(semestres)),
            ramoProvider(2).overrideWith(() => _FakeRamoNotifier([])),
          ],
          child: const NotasApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2026-2'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

      // Tapping the header pill opens the semester modal sheet
      await tester.tap(find.text('2026-2'));
      await tester.pumpAndSettle();
      expect(find.text('2026-1'), findsOneWidget);
      expect(find.text('Nuevo Semestre'), findsOneWidget);

      // Dismiss modal sheet cleanly
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.event_note_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Agenda de Evaluaciones'), findsOneWidget);
    });

    testWidgets('NotasApp supports classic chips selector, tertiary accent live, and dock bar mode',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'semesterSelectorStyle': 'chips',
        'bottomNavStyle': 'dock',
        'tertiaryColor': 0xFFE11D48,
      });
      final semestres = [
        Semestre(id: 1, nombre: '2026-1'),
        Semestre(id: 2, nombre: '2026-2'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            semestreProvider.overrideWith(() => _FakeSemestreNotifier(semestres)),
            ramoProvider(2).overrideWith(() => _FakeRamoNotifier([])),
          ],
          child: const NotasApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2026-1'), findsOneWidget);
      expect(find.text('2026-2'), findsWidgets);

      // Verify tertiary accent renders on active chip & FAB
      final fabFinder = find.byType(FloatingActionButton);
      expect(fabFinder, findsOneWidget);
      final context = tester.element(fabFinder);
      expect(Theme.of(context).floatingActionButtonTheme.backgroundColor, const Color(0xFFE11D48));
    });

    testWidgets('NotasApp renders Google M3 Expressive and One UI 7 bottom bars cleanly',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'bottomNavStyle': 'm3_expressive',
      });
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            semestreProvider.overrideWith(() => _FakeSemestreNotifier()),
          ],
          child: const NotasApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ramos'), findsOneWidget);
      expect(find.byTooltip('Horario'), findsOneWidget);
      expect(find.byTooltip('Agenda'), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsWidgets);

      SharedPreferences.setMockInitialValues({
        'bottomNavStyle': 'one_ui',
      });
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            semestreProvider.overrideWith(() => _FakeSemestreNotifier()),
          ],
          child: const NotasApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ramos'), findsOneWidget);
      expect(find.text('Horario'), findsOneWidget);
      expect(find.text('Agenda'), findsOneWidget);
    });

    testWidgets('NotasApp horizontal PageView swipe navigates from Ramos to Horario',
        (WidgetTester tester) async {
      final semestres = [
        Semestre(id: 1, nombre: '2026-2'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            semestreProvider.overrideWith(() => _FakeSemestreNotifier(semestres)),
            ramoProvider(1).overrideWith(() => _FakeRamoNotifier([])),
          ],
          child: const NotasApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Añadir Ramo'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byTooltip('Añadir Bloque'), findsOneWidget);
    });

    testWidgets('UpdateScreen renders version details, release notes, and update actions',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: UpdateScreen(
              info: ReleaseUpdateInfo(
                currentVersion: '1.2.0',
                latestVersion: '1.2.1',
                downloadUrl: 'https://example.com/app.apk',
                releaseNotes: '• Mejora de prueba',
                apkSizeBytes: 25165824,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Actualización Disponible'), findsOneWidget);
      expect(find.textContaining('v1.2.0'), findsWidgets);
      expect(find.textContaining('v1.2.1'), findsWidgets);
      expect(find.text('• Mejora de prueba'), findsOneWidget);
      expect(find.text('24.0 MB'), findsOneWidget);
      expect(find.text('Actualizar Ahora'), findsOneWidget);
      expect(find.text('Más tarde'), findsOneWidget);
    });

    testWidgets('FormulaEditorDialog builds expression and returns result', (WidgetTester tester) async {
      String? saved;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  saved = await showDialog<String>(
                    context: context,
                    builder: (_) => const FormulaEditorDialog(
                      initialFormula: '',
                      autoCreateCount: 2,
                    ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('e1'));
      await tester.tap(find.text('+'));
      await tester.tap(find.text('e2'));
      await tester.pump();
      expect(find.text('e1+e2'), findsOneWidget);

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(saved, 'e1+e2');
    });
  });
}
