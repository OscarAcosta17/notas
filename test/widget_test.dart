import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:notas/main.dart';
import 'package:notas/models/aula_course.dart';
import 'package:notas/models/categoria_evaluacion.dart';
import 'package:notas/models/evaluacion.dart';
import 'package:notas/models/ramo.dart';
import 'package:notas/models/semestre.dart';
import 'package:notas/services/aula_service.dart';
import 'package:notas/services/bug_report_service.dart';
import 'package:notas/services/cloud_sync_service.dart';
import 'package:notas/services/updater_service.dart';
import 'package:notas/theme/app_theme.dart';
import 'package:notas/viewmodels/categoria_provider.dart';
import 'package:notas/viewmodels/ramo_provider.dart';
import 'package:notas/viewmodels/semestre_provider.dart';
import 'package:notas/viewmodels/settings_provider.dart';
import 'package:notas/views/aula_view.dart';
import 'package:notas/views/bug_report_sheet.dart';
import 'package:notas/views/formula_editor_dialog.dart';
import 'package:notas/views/home_view.dart';
import 'package:notas/views/ramo_detail_view.dart';
import 'package:notas/views/semestre_detail_view.dart';
import 'package:notas/views/settings/appearance_settings_view.dart';
import 'package:notas/views/settings/data_settings_view.dart';
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

    test('CloudSyncService builds and applies portable sync bundles without data loss', () async {
      SharedPreferences.setMockInitialValues({
        'isDarkMode': true,
        'bottomNavStyle': 'one_ui',
        'escalaNotas': '1 a 7',
        'tertiaryColor': 0xFF6750A4,
      });

      final mockDb = <String, dynamic>{
        'semesters': [
          {'id': 1, 'name': '2026-2'},
        ],
        'subjects': [
          {
            'id': 10,
            'semester_id': 1,
            'name': 'Cálculo II',
            'average_type': 'Aritmetico',
            'has_global_exam': 0,
            'global_exam_replaces_worst': 0,
            'min_passing_grade': 4.0,
            'order_index': 0,
            'color': 0xFF1E88E5,
          },
        ],
        'categories': <Map<String, dynamic>>[],
        'evaluations': <Map<String, dynamic>>[],
        'horario_clases': <Map<String, dynamic>>[],
      };

      final bundle = await CloudSyncService.buildSyncBundle(
        databaseOverride: mockDb,
      );

      expect(bundle['app'], 'NotasApp');
      expect(bundle['formatVersion'], CloudSyncService.bundleFormatVersion);
      expect((bundle['database'] as Map)['semesters'], hasLength(1));
      expect((bundle['settings'] as Map)['bottomNavStyle'], 'one_ui');

      // Mutate local settings and verify restore re-applies bundle settings
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isDarkMode', false);
      await prefs.setString('bottomNavStyle', 'dock');
      await prefs.remove('tertiaryColor');

      await CloudSyncService.applySyncBundle(bundle, restoreDatabase: false);

      expect(prefs.getBool('isDarkMode'), isTrue);
      expect(prefs.getString('bottomNavStyle'), 'one_ui');
      expect(prefs.getString('escalaNotas'), '1 a 7');
      expect(prefs.getInt('tertiaryColor'), 0xFF6750A4);
    });

    testWidgets('DataSettingsView renders multiplatform sync and backup sections',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DataSettingsView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sincronización Multiplataforma (Android y PC)'), findsOneWidget);
      expect(find.text('Google Drive (Obsidian Sync)'), findsOneWidget);
      expect(find.text('Subir a Google Drive'), findsOneWidget);
      expect(find.text('Descargar de Google Drive'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Nube Privada (GitHub Gist)'),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Nube Privada (GitHub Gist)'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Subir a la Nube'),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Subir a la Nube'), findsOneWidget);
      expect(find.text('Descargar de la Nube'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Carpeta Sincronizada (Drive / OneDrive)'),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Carpeta Sincronizada (Drive / OneDrive)'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Importar Datos (.json o .db)'),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Exportar Paquete Completo (.json)'), findsOneWidget);
      expect(find.text('Exportar Base SQLite (.db)'), findsOneWidget);
      expect(find.text('Importar Datos (.json o .db)'), findsOneWidget);
    });

    test('BugReportService records error logs and builds GitHub issue Markdown and URI',
        () async {
      SharedPreferences.setMockInitialValues({});
      await BugReportService.clearErrorLogs();

      await BugReportService.recordError(
        'Database locked',
        'at DatabaseHelper.init (database_helper.dart:42)',
        source: 'UnitTest',
      );

      final logs = await BugReportService.getErrorLogs();
      expect(logs, hasLength(1));
      expect(logs.first.error, 'Database locked');
      expect(logs.first.source, 'UnitTest');

      final report = await BugReportService.buildDiagnosticReport(
        title: 'Fallo al guardar',
        description: 'No guarda el ramo',
        stepsToReproduce: '1. Abrir app',
        category: 'bug',
        appVersionOverride: 'v1.2.3+24',
      );

      expect(report, contains('Fallo al guardar'));
      expect(report, contains('v1.2.3+24'));
      expect(report, contains('Database locked'));

      final uri = BugReportService.buildGitHubIssueUri(
        title: 'Fallo al guardar',
        markdownBody: report,
        category: 'bug',
      );

      expect(uri.host, 'github.com');
      expect(uri.path, '/OscarAcosta17/notas/issues/new');
      expect(uri.queryParameters['title'], '[BUG] Fallo al guardar');
      expect(uri.queryParameters['labels'], 'bug');

      await BugReportService.clearErrorLogs();
    });

    testWidgets('BugReportSheet renders form fields, category chips, and GitHub ticket actions',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await BugReportService.clearErrorLogs();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BugReportSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reportar Fallo o Sugerencia'), findsOneWidget);
      expect(find.text('Fallo / Bug'), findsOneWidget);
      expect(find.text('Sugerencia'), findsOneWidget);
      expect(find.text('Visual / UI'), findsOneWidget);
      expect(find.text('Levantar Ticket en GitHub'), findsOneWidget);
      expect(find.text('Enviar con Token API'), findsOneWidget);
      expect(find.text('Copiar Diagnóstico'), findsOneWidget);
    });

    test('CloudSyncService persists and clears Google Drive Obsidian credentials', () async {
      SharedPreferences.setMockInitialValues({});

      await CloudSyncService.setGoogleDriveCredentials(
        refreshToken: '1//0test-refresh-token',
        clientId: 'custom-client-id',
        tokenUrl: 'https://ogd-server.richardxiong.com/api/access',
      );

      final cfg = await CloudSyncService.getConfig();
      expect(cfg.hasGoogleDriveAuth, isTrue);
      expect(cfg.googleDriveRefreshToken, '1//0test-refresh-token');
      expect(cfg.googleDriveClientId, 'custom-client-id');
      expect(cfg.googleDriveTokenUrl, 'https://ogd-server.richardxiong.com/api/access');

      await CloudSyncService.setGoogleDriveCredentials(refreshToken: null);
      final cleared = await CloudSyncService.getConfig();
      expect(cleared.hasGoogleDriveAuth, isFalse);
      expect(cleared.googleDriveRefreshToken, isNull);
    });

    testWidgets('AppearanceSettingsView renders all 6 selectable app icons and updates selection',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const AppearanceSettingsView();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Cristal A+'),
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Clásico'), findsOneWidget);
      expect(find.text('Minimalista (Nuevo)'), findsOneWidget);
      expect(find.text('Cristal A+'), findsOneWidget);
      expect(find.text('Cápsulas M3'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Material You'),
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Libreta Glass'), findsOneWidget);
      expect(find.text('Material You'), findsOneWidget);

      await tester.ensureVisible(find.text('Cristal A+'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cristal A+'));
      await tester.pumpAndSettle();

      expect(capturedRef.read(settingsProvider).appIcon, 'icon3');
    });

    test('Aula USM models normalize academic text, match Ramos accurately, and parse Spanish dates', () {
      final ramos = [
        Ramo(
          id: 1,
          idSemestre: 1,
          nombre: 'Arquitectura de Computadores',
          tipoPromedio: 'Aritmetico',
          tieneGlobal: false,
          reemplazaPeorNota: false,
          notaAprobacion: 55.0,
        ),
        Ramo(
          id: 2,
          idSemestre: 1,
          nombre: 'MAT-023 Matemáticas III',
          tipoPromedio: 'Aritmetico',
          tieneGlobal: false,
          reemplazaPeorNota: false,
          notaAprobacion: 55.0,
        ),
      ];

      final c1 = MoodleCourse(
        id: 101,
        fullName: 'INF-253 Arquitectura de Computadores - 2026-2',
        shortName: 'INF-253-2026-2',
      );
      final c2 = MoodleCourse(
        id: 102,
        fullName: 'Matemáticas III Paralelo 1',
        shortName: 'MAT023-2026-2',
      );

      expect(MoodleCourse.findMatchingRamo(c1, ramos)?.id, 1);
      expect(MoodleCourse.findMatchingRamo(c2, ramos)?.id, 2);

      final due = AulaMoodleService.parseSpanishMoodleDate('lunes, 18 de noviembre de 2026, 23:59');
      expect(due, DateTime(2026, 11, 18, 23, 59));

      final existingEval = Evaluacion(
        id: 10,
        idCategoria: 3,
        nombre: 'Aula: Tarea 1 MIPS',
        fecha: due,
      );
      final item = MoodleItem(
        name: 'Tarea 1 MIPS Tarea',
        type: 'assignment',
        dueDate: due,
      );
      expect(MoodleCourse.findMatchingEvaluacion(item, [existingEval])?.id, 10);
      expect(MoodleItem.sanitizeFileName('Guía 1: MIPS / ARM?.pdf '), 'Guía 1_ MIPS _ ARM_.pdf');
    });

    test('AulaSettingsService persists session, folder mappings, and Ramo links', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = AulaSettingsService();

      await settings.saveSession(const AulaSessionData(
        token: 'tok-abc',
        userName: 'Oscar USM',
        userId: 42,
      ));
      await settings.setCourseFolder(501, 'Arquitectura PC');
      await settings.setCourseRamoLink(501, 7);

      final loadedSession = await settings.loadSession();
      final folders = await settings.getCourseFolders();
      final links = await settings.getCourseRamoLinks();

      expect(loadedSession.hasCredentials, isTrue);
      expect(loadedSession.userName, 'Oscar USM');
      expect(loadedSession.userId, 42);
      expect(folders[501], 'Arquitectura PC');
      expect(links[501], 7);
      expect(AulaSettingsService.syncedPrefKeys, contains('aula_course_folders'));
      expect(AulaSettingsService.syncedPrefKeys, isNot(contains('aula_download_root')));
    });

    testWidgets('HomeView shows 4 tabs including Aula and opens AulaView cleanly',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'bottomNavStyle': 'm3_expressive'});
      final fakeSemestres = [Semestre(id: 1, nombre: '2026-2')];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            semestreProvider.overrideWith(() => _FakeSemestreNotifier(fakeSemestres)),
            ramoProvider(1).overrideWith(() => _FakeRamoNotifier([])),
          ],
          child: const MaterialApp(home: HomeView()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ramos'), findsOneWidget);
      expect(find.byIcon(Icons.school_rounded), findsWidgets);
      expect(find.byIcon(Icons.calendar_today_rounded), findsOneWidget);
      expect(find.byIcon(Icons.event_note_rounded), findsOneWidget);
      expect(find.byIcon(Icons.cloud_download_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.cloud_download_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Aula'), findsOneWidget);
      expect(find.text('Aula-Scrapt USM'), findsOneWidget);
      expect(find.text('Iniciar sesión en Aula USM'), findsOneWidget);
    });

    testWidgets('AulaView onboarding renders cleanly without overflows on wide desktop size',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AulaView(autoLoad: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aula-Scrapt USM'), findsOneWidget);
      expect(
        find.text('Sincronizador Material 3 para Aula USM & Obsidian'),
        findsOneWidget,
      );
      expect(find.text('Iniciar sesión en Aula USM'), findsOneWidget);
    });

    test('SettingsService resolves folders and DownloaderService builds Obsidian Markdown graph',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('notas_aula_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService.instance;
      await settings.load();
      await settings.setDownloadRoot(tempDir.path);

      // Verify fuzzy / course-code matching against existing Obsidian vault folders
      final matched = settings.resolveCourseFolderSync(
        courseId: 777,
        fullname: '[S2-2026] ESTRUCTURAS DE DATOS - Paralelo 200',
        cleanName: 'ESTRUCTURAS DE DATOS',
        shortname: 'INF134-200',
        existingFolders: ['Cálculo II', 'INF-134 Estructuras', 'Física'],
      );
      expect(matched, 'INF-134 Estructuras');

      final moodle = MoodleService();
      final downloader = DownloaderService(moodle: moodle, settings: settings);
      final course = MoodleCourse(
        id: 777,
        fullname: '[S2-2026] ESTRUCTURAS DE DATOS',
        shortname: 'INF134-200',
        url: 'https://aula.usm.cl/course/view.php?id=777',
        obsidianFolder: 'INF-134 Estructuras',
        targetSubfolder: 'Aula',
        organizeBySection: true,
        items: [
          MoodleItem(
            id: '777_1',
            courseId: 777,
            title: 'Apuntes Árboles AVL',
            section: 'Semana 1 / Carpeta Diapos',
            type: 'resource',
            url: 'https://aula.usm.cl/pluginfile.php/1/avl.pdf',
            fileName: 'avl.pdf',
            fileExt: 'pdf',
            downloadable: true,
          ),
          MoodleItem(
            id: '777_2',
            courseId: 777,
            title: 'Tarea 1 ABB',
            section: 'Semana 1',
            type: 'assign',
            url: 'https://aula.usm.cl/mod/assign/view.php?id=2',
            dueTimestamp:
                DateTime(2026, 12, 15, 23, 59).millisecondsSinceEpoch ~/ 1000,
          ),
        ],
      );

      final indexPath = await downloader.syncCourseObsidianIndex(course);
      expect(await File(indexPath).exists(), isTrue);
      expect(p.basename(indexPath), '00 - Indice Aula - INF-134 Estructuras.md');

      final indexContent = await File(indexPath).readAsString();
      expect(indexContent, contains('[[Semana 1/00 - Seccion - Semana 1.md|Semana 1]]'));
      expect(indexContent, contains('Tarea 1 ABB'));

      final secFile = File(p.join(
        tempDir.path,
        'INF-134 Estructuras',
        'Aula',
        'Semana 1',
        '00 - Seccion - Semana 1.md',
      ));
      expect(await secFile.exists(), isTrue);
      final secContent = await secFile.readAsString();
      expect(secContent, contains('Apuntes Árboles AVL'));
    });

    test('CloudSyncService tracks Google Drive sync status and expired token renewal flow',
        () async {
      SharedPreferences.setMockInitialValues({});
      var status = await CloudSyncService.refreshStatusNotifier();
      expect(status.state, DriveSyncState.unconfigured);

      await CloudSyncService.setGoogleDriveCredentials(
        refreshToken: '1//sample-refresh-token',
      );
      status = CloudSyncService.driveStatusNotifier.value;
      expect(status.state, DriveSyncState.synced);
      expect(status.isExpired, isFalse);

      await CloudSyncService.markDriveTokenExpired('Token expirado HTTP 401');
      status = CloudSyncService.driveStatusNotifier.value;
      expect(status.state, DriveSyncState.tokenExpired);
      expect(status.isExpired, isTrue);
      expect(status.message, contains('401'));

      // Saving a new refresh token clears the expired error state immediately
      await CloudSyncService.setGoogleDriveCredentials(
        refreshToken: '1//renewed-refresh-token',
      );
      status = CloudSyncService.driveStatusNotifier.value;
      expect(status.state, DriveSyncState.synced);
      expect(status.isExpired, isFalse);
    });
  });
}
