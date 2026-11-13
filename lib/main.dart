import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/notification_service.dart';
import 'services/widget_service.dart';
import 'theme/app_theme.dart';
import 'viewmodels/settings_provider.dart';
import 'views/home_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await NotificationService.initialize();
  WidgetService.updateAgendaWidget();
  WidgetService.updateHorarioWidget();
  runApp(const ProviderScope(child: NotasApp()));
}

class NotasApp extends ConsumerWidget {
  const NotasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ThemeData themeFor(Brightness brightness, ColorScheme? dynamicScheme) {
          return AppTheme.buildTheme(
            brightness: brightness,
            useDynamicColor: settings.useDynamicColor,
            frostedGlassIntensity: settings.frostedGlassIntensity,
            tertiaryColorValue: settings.tertiaryColor,
            dynamicScheme: dynamicScheme,
            surfaceStyle: settings.surfaceStyle,
            cardRadiusStyle: settings.cardRadiusStyle,
            subjectColorStyle: settings.subjectColorStyle,
            hapticsEnabled: settings.hapticsEnabled,
          );
        }

        return MaterialApp(
          title: 'Gestión Universitaria',
          debugShowCheckedModeBanner: false,
          themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
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
