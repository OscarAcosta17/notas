import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas/main.dart';
import 'package:notas/models/categoria_evaluacion.dart';
import 'package:notas/models/evaluacion.dart';
import 'package:notas/models/ramo.dart';
import 'package:notas/models/semestre.dart';
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
    test('defaults to monochrome, intense frosted glass, and clears tertiaryColor live', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Let async _loadSettings settle
      await Future<void>.delayed(Duration.zero);

      final initial = container.read(settingsProvider);
      expect(initial.useDynamicColor, isFalse);
      expect(initial.frostedGlassIntensity, 'intenso');
      expect(initial.tertiaryColor, isNull);

      await container.read(settingsProvider.notifier).setUseDynamicColor(true);
      await container.read(settingsProvider.notifier).setFrostedGlassIntensity('sutil');
      await container.read(settingsProvider.notifier).setTertiaryColor(0xFF3366FF);

      var updated = container.read(settingsProvider);
      expect(updated.useDynamicColor, isTrue);
      expect(updated.frostedGlassIntensity, 'sutil');
      expect(updated.tertiaryColor, 0xFF3366FF);

      await container.read(settingsProvider.notifier).setTertiaryColor(null);
      updated = container.read(settingsProvider);
      expect(updated.tertiaryColor, isNull);
    });
  });

  group('UI Smoke & Android 17 Views', () {
    testWidgets('NotasApp renders empty state and bottom navigation bubble', (WidgetTester tester) async {
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
    });

    testWidgets('AppearanceSettingsView exposes Material You, Frosted Glass modes, and fixed grid preview',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AppearanceSettingsView()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Colores del sistema (Material You)'), findsOneWidget);
      expect(find.text('Intensidad de desenfoque'), findsOneWidget);
      expect(find.text('Sólido'), findsOneWidget);
      expect(find.text('Sutil'), findsOneWidget);
      expect(find.text('Intenso'), findsOneWidget);

      await tester.tap(find.text('Sutil'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Cuadrícula'), 250);
      await tester.tap(find.text('Cuadrícula'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Ramo 1'), 200);
      expect(find.text('Ramo 1'), findsOneWidget);
      expect(find.text('Ramo 2'), findsOneWidget);
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
      expect(find.text('Certámenes'), findsOneWidget);
      expect(find.text('Certamen 1'), findsOneWidget);
      expect(find.text('Notas'), findsOneWidget);
      expect(find.text('Fechas'), findsOneWidget);

      await tester.tap(find.text('Fechas'));
      await tester.pumpAndSettle();
      expect(find.text('Sin fecha asignada'), findsOneWidget);
    });

    testWidgets('NotasApp renders active semester chips and switches bubble tabs', (WidgetTester tester) async {
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

      await tester.tap(find.byIcon(Icons.event_note_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Agenda de Evaluaciones'), findsOneWidget);
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
