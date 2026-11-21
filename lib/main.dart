import 'dart:io';
import 'dart:ui';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/bug_report_service.dart';
import 'services/cloud_sync_service.dart';
import 'services/database_helper.dart';
import 'services/notification_service.dart';
import 'services/widget_service.dart';
import 'theme/app_theme.dart';
import 'viewmodels/settings_provider.dart';
import 'views/home_view.dart';

class _DesktopTouchScrollBehavior extends MaterialScrollBehavior {
  const _DesktopTouchScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BugReportService.initErrorHooks();
  DatabaseHelper.ensureInitialized();
  CloudSyncService.initAutoSyncHook();
  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  await NotificationService.initialize();
  WidgetService.updateAgendaWidget();
  WidgetService.updateHorarioWidget();
  runApp(const ProviderScope(child: NotasApp()));
}

class NotasApp extends ConsumerWidget {
  const NotasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeCfg = ref.watch(settingsProvider.select((s) => (
      isDarkMode: s.isDarkMode,
      useDynamicColor: s.useDynamicColor,
      frostedGlassIntensity: s.frostedGlassIntensity,
      tertiaryColor: s.tertiaryColor,
      surfaceStyle: s.surfaceStyle,
      cardRadiusStyle: s.cardRadiusStyle,
      subjectColorStyle: s.subjectColorStyle,
      hapticsEnabled: s.hapticsEnabled,
    )));

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ThemeData themeFor(Brightness brightness, ColorScheme? dynamicScheme) {
          return AppTheme.buildTheme(
            brightness: brightness,
            useDynamicColor: themeCfg.useDynamicColor,
            frostedGlassIntensity: themeCfg.frostedGlassIntensity,
            tertiaryColorValue: themeCfg.tertiaryColor,
            dynamicScheme: dynamicScheme,
            surfaceStyle: themeCfg.surfaceStyle,
            cardRadiusStyle: themeCfg.cardRadiusStyle,
            subjectColorStyle: themeCfg.subjectColorStyle,
            hapticsEnabled: themeCfg.hapticsEnabled,
          );
        }

        return MaterialApp(
          title: 'NotasApp - Gestión Universitaria',
          debugShowCheckedModeBanner: false,
          scrollBehavior: const _DesktopTouchScrollBehavior(),
          themeMode: themeCfg.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          theme: themeFor(Brightness.light, lightDynamic),
          darkTheme: themeFor(Brightness.dark, darkDynamic),
          builder: (context, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
                statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
                systemNavigationBarContrastEnforced: false,
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const HomeView(),
        );
      },
    );
  }
}
