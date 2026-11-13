import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens for Android 17 / Material 3 Expressive styling in NotasApp.
@immutable
class NotasVisualTokens extends ThemeExtension<NotasVisualTokens> {
  final String frostedGlassIntensity; // 'solido', 'sutil', 'intenso'
  final double blurSigma;
  final double glassOpacity;
  final double glassBorderOpacity;
  final Color passingColor;
  final Color failingColor;
  final Color neutralColor;
  final Color accentColor;
  final Color onAccentColor;
  final Color accentContainer;
  final Color onAccentContainer;
  final String surfaceStyle; // 'tonal', 'oled'
  final String cardRadiusStyle; // 'compacto', 'equilibrado', 'expresivo'
  final double cardRadius;
  final String subjectColorStyle; // 'mixto', 'franja', 'tinte', 'borde'
  final bool hapticsEnabled;
  final bool isDynamicPalette;

  const NotasVisualTokens({
    required this.frostedGlassIntensity,
    required this.blurSigma,
    required this.glassOpacity,
    required this.glassBorderOpacity,
    required this.passingColor,
    required this.failingColor,
    required this.neutralColor,
    required this.accentColor,
    required this.onAccentColor,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.surfaceStyle,
    required this.cardRadiusStyle,
    required this.cardRadius,
    required this.subjectColorStyle,
    required this.hapticsEnabled,
    required this.isDynamicPalette,
  });

  factory NotasVisualTokens.from({
    required Brightness brightness,
    required String frostedGlassIntensity,
    required bool isDynamicPalette,
    Color? accentColor,
    Color? onAccentColor,
    Color? accentContainer,
    Color? onAccentContainer,
    String surfaceStyle = 'tonal',
    String cardRadiusStyle = 'expresivo',
    String subjectColorStyle = 'mixto',
    bool hapticsEnabled = true,
  }) {
    final isDark = brightness == Brightness.dark;
    final double blurSigma;
    final double glassOpacity;
    final double glassBorderOpacity;

    switch (frostedGlassIntensity) {
      case 'solido':
        blurSigma = 0.0;
        glassOpacity = 1.0;
        glassBorderOpacity = isDark ? 0.14 : 0.10;
        break;
      case 'sutil':
        blurSigma = 10.0;
        glassOpacity = isDark ? 0.88 : 0.90;
        glassBorderOpacity = isDark ? 0.16 : 0.12;
        break;
      case 'intenso':
      default:
        blurSigma = 22.0;
        glassOpacity = isDark ? 0.68 : 0.72;
        glassBorderOpacity = isDark ? 0.24 : 0.28;
        break;
    }

    final resolvedAccent = accentColor ?? (isDark ? const Color(0xFFF5F6FA) : const Color(0xFF0E0F13));
    final resolvedOnAccent = onAccentColor ?? (isDark ? const Color(0xFF0E0F13) : Colors.white);
    final resolvedAccentContainer = accentContainer ??
        (isDark ? const Color(0xFF2A2D36) : const Color(0xFFE5E7EE));
    final resolvedOnAccentContainer = onAccentContainer ??
        (isDark ? const Color(0xFFF5F6FA) : const Color(0xFF0E0F13));

    final double resolvedRadius;
    switch (cardRadiusStyle) {
      case 'compacto':
        resolvedRadius = 12.0;
        break;
      case 'equilibrado':
        resolvedRadius = 17.0;
        break;
      case 'expresivo':
      default:
        resolvedRadius = 22.0;
        break;
    }

    return NotasVisualTokens(
      frostedGlassIntensity: frostedGlassIntensity,
      blurSigma: blurSigma,
      glassOpacity: glassOpacity,
      glassBorderOpacity: glassBorderOpacity,
      passingColor: isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
      failingColor: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
      neutralColor: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
      accentColor: resolvedAccent,
      onAccentColor: resolvedOnAccent,
      accentContainer: resolvedAccentContainer,
      onAccentContainer: resolvedOnAccentContainer,
      surfaceStyle: surfaceStyle,
      cardRadiusStyle: cardRadiusStyle,
      cardRadius: resolvedRadius,
      subjectColorStyle: subjectColorStyle,
      hapticsEnabled: hapticsEnabled,
      isDynamicPalette: isDynamicPalette,
    );
  }

  @override
  NotasVisualTokens copyWith({
    String? frostedGlassIntensity,
    double? blurSigma,
    double? glassOpacity,
    double? glassBorderOpacity,
    Color? passingColor,
    Color? failingColor,
    Color? neutralColor,
    Color? accentColor,
    Color? onAccentColor,
    Color? accentContainer,
    Color? onAccentContainer,
    String? surfaceStyle,
    String? cardRadiusStyle,
    double? cardRadius,
    String? subjectColorStyle,
    bool? hapticsEnabled,
    bool? isDynamicPalette,
  }) {
    return NotasVisualTokens(
      frostedGlassIntensity: frostedGlassIntensity ?? this.frostedGlassIntensity,
      blurSigma: blurSigma ?? this.blurSigma,
      glassOpacity: glassOpacity ?? this.glassOpacity,
      glassBorderOpacity: glassBorderOpacity ?? this.glassBorderOpacity,
      passingColor: passingColor ?? this.passingColor,
      failingColor: failingColor ?? this.failingColor,
      neutralColor: neutralColor ?? this.neutralColor,
      accentColor: accentColor ?? this.accentColor,
      onAccentColor: onAccentColor ?? this.onAccentColor,
      accentContainer: accentContainer ?? this.accentContainer,
      onAccentContainer: onAccentContainer ?? this.onAccentContainer,
      surfaceStyle: surfaceStyle ?? this.surfaceStyle,
      cardRadiusStyle: cardRadiusStyle ?? this.cardRadiusStyle,
      cardRadius: cardRadius ?? this.cardRadius,
      subjectColorStyle: subjectColorStyle ?? this.subjectColorStyle,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      isDynamicPalette: isDynamicPalette ?? this.isDynamicPalette,
    );
  }

  @override
  NotasVisualTokens lerp(ThemeExtension<NotasVisualTokens>? other, double t) {
    if (other is! NotasVisualTokens) return this;
    return NotasVisualTokens(
      frostedGlassIntensity: t < 0.5 ? frostedGlassIntensity : other.frostedGlassIntensity,
      blurSigma: blurSigma + (other.blurSigma - blurSigma) * t,
      glassOpacity: glassOpacity + (other.glassOpacity - glassOpacity) * t,
      glassBorderOpacity: glassBorderOpacity + (other.glassBorderOpacity - glassBorderOpacity) * t,
      passingColor: Color.lerp(passingColor, other.passingColor, t) ?? passingColor,
      failingColor: Color.lerp(failingColor, other.failingColor, t) ?? failingColor,
      neutralColor: Color.lerp(neutralColor, other.neutralColor, t) ?? neutralColor,
      accentColor: Color.lerp(accentColor, other.accentColor, t) ?? accentColor,
      onAccentColor: Color.lerp(onAccentColor, other.onAccentColor, t) ?? onAccentColor,
      accentContainer: Color.lerp(accentContainer, other.accentContainer, t) ?? accentContainer,
      onAccentContainer: Color.lerp(onAccentContainer, other.onAccentContainer, t) ?? onAccentContainer,
      surfaceStyle: t < 0.5 ? surfaceStyle : other.surfaceStyle,
      cardRadiusStyle: t < 0.5 ? cardRadiusStyle : other.cardRadiusStyle,
      cardRadius: cardRadius + (other.cardRadius - cardRadius) * t,
      subjectColorStyle: t < 0.5 ? subjectColorStyle : other.subjectColorStyle,
      hapticsEnabled: t < 0.5 ? hapticsEnabled : other.hapticsEnabled,
      isDynamicPalette: t < 0.5 ? isDynamicPalette : other.isDynamicPalette,
    );
  }
}

extension NotasThemeContext on BuildContext {
  NotasVisualTokens get visualTokens =>
      Theme.of(this).extension<NotasVisualTokens>() ??
      NotasVisualTokens.from(
        brightness: Theme.of(this).brightness,
        frostedGlassIntensity: 'intenso',
        isDynamicPalette: false,
      );
}

class AppTheme {
  // Symmetrical Material 3 Expressive shape tokens
  static const double radiusExtraSmall = 6.0;
  static const double radiusSmall = 12.0;
  static const double radiusMedium = 18.0;
  static const double radiusLarge = 22.0;
  static const double radiusExtraLarge = 28.0;
  static const double radiusFull = 999.0;

  static ThemeData buildTheme({
    required Brightness brightness,
    required bool useDynamicColor,
    required String frostedGlassIntensity,
    int? tertiaryColorValue,
    ColorScheme? dynamicScheme,
    String surfaceStyle = 'tonal',
    String cardRadiusStyle = 'expresivo',
    String subjectColorStyle = 'mixto',
    bool hapticsEnabled = true,
  }) {
    final isDark = brightness == Brightness.dark;
    final bool usingDynamic = useDynamicColor && dynamicScheme != null;
    final bool isOled = surfaceStyle == 'oled';

    ColorScheme colorScheme = usingDynamic
        ? _buildDynamicScheme(dynamicScheme, brightness)
        : _buildMonochromeScheme(brightness, tertiaryColorValue);

    if (isOled) {
      colorScheme = _applyOledSurfaces(colorScheme, isDark);
    }

    final Color? customTertiary = !usingDynamic && tertiaryColorValue != null ? Color(tertiaryColorValue) : null;
    final Color accentColor = customTertiary ?? colorScheme.primary;
    final Color onAccentColor = ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
        ? Colors.white
        : const Color(0xFF0E0F12);

    final Color accentContainer;
    final Color onAccentContainer;
    if (customTertiary != null) {
      accentContainer = customTertiary.withValues(alpha: isDark ? 0.24 : 0.14);
      final bool accentIsLight = ThemeData.estimateBrightnessForColor(customTertiary) == Brightness.light;
      if (!isDark && accentIsLight) {
        onAccentContainer = Color.lerp(customTertiary, const Color(0xFF111217), 0.65)!;
      } else if (isDark && !accentIsLight) {
        onAccentContainer = Color.lerp(customTertiary, Colors.white, 0.72)!;
      } else {
        onAccentContainer = customTertiary;
      }
    } else {
      accentContainer = colorScheme.primaryContainer;
      onAccentContainer = colorScheme.onPrimaryContainer;
    }

    final tokens = NotasVisualTokens.from(
      brightness: brightness,
      frostedGlassIntensity: frostedGlassIntensity,
      isDynamicPalette: usingDynamic,
      accentColor: accentColor,
      onAccentColor: onAccentColor,
      accentContainer: accentContainer,
      onAccentContainer: onAccentContainer,
      surfaceStyle: surfaceStyle,
      cardRadiusStyle: cardRadiusStyle,
      subjectColorStyle: subjectColorStyle,
      hapticsEnabled: hapticsEnabled,
    );

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      extensions: [tokens],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlayStyle,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: usingDynamic ? colorScheme.primaryContainer : accentColor,
        foregroundColor: usingDynamic ? colorScheme.onPrimaryContainer : onAccentColor,
        elevation: 2,
        focusElevation: 3,
        hoverElevation: 3,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusExtraLarge),
        ),
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        contentTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 15,
          height: 1.4,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        dragHandleSize: const Size(38, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusExtraLarge)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.55 : 0.45),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accentColor, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: onAccentColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: onAccentColor,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return onAccentColor;
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentColor;
          return colorScheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return colorScheme.outlineVariant;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentColor;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(onAccentColor),
        side: BorderSide(color: colorScheme.outline, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentColor;
          return colorScheme.onSurfaceVariant;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accentColor,
        linearTrackColor: colorScheme.surfaceContainerHighest,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return accentContainer;
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return onAccentContainer;
            return colorScheme.onSurfaceVariant;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        elevation: 2,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        thickness: 1,
        space: 1,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accentColor,
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
        thumbColor: accentColor,
        overlayColor: accentColor.withValues(alpha: 0.12),
      ),
    );
  }

  static ColorScheme _applyOledSurfaces(ColorScheme scheme, bool isDark) {
    if (isDark) {
      return scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0D),
        surfaceContainer: const Color(0xFF121216),
        surfaceContainerHigh: const Color(0xFF1A1A20),
        surfaceContainerHighest: const Color(0xFF23232A),
        outlineVariant: const Color(0xFF2E2E38),
      );
    }
    return scheme.copyWith(
      surface: Colors.white,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF6F7FA),
      surfaceContainer: const Color(0xFFEEEFF4),
      surfaceContainerHigh: const Color(0xFFE5E7EE),
      surfaceContainerHighest: const Color(0xFFDCE0E9),
      outlineVariant: const Color(0xFFC5C9D4),
    );
  }

  static ColorScheme _buildDynamicScheme(ColorScheme dynamicScheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final seeded = ColorScheme.fromSeed(
      seedColor: dynamicScheme.primary,
      secondary: dynamicScheme.secondary,
      tertiary: dynamicScheme.tertiary,
      brightness: brightness,
    );
    // Keep Material You wallpaper palette while populating M3 tonal surfaceContainer roles.
    return seeded.copyWith(
      primary: dynamicScheme.primary,
      onPrimary: dynamicScheme.onPrimary,
      primaryContainer: dynamicScheme.primaryContainer,
      onPrimaryContainer: dynamicScheme.onPrimaryContainer,
      secondary: dynamicScheme.secondary,
      onSecondary: dynamicScheme.onSecondary,
      secondaryContainer: dynamicScheme.secondaryContainer,
      onSecondaryContainer: dynamicScheme.onSecondaryContainer,
      tertiary: dynamicScheme.tertiary,
      onTertiary: dynamicScheme.onTertiary,
      tertiaryContainer: dynamicScheme.tertiaryContainer,
      onTertiaryContainer: dynamicScheme.onTertiaryContainer,
      error: dynamicScheme.error,
      onError: dynamicScheme.onError,
      errorContainer: dynamicScheme.errorContainer,
      onErrorContainer: dynamicScheme.onErrorContainer,
      surfaceContainerLowest: isDark ? seeded.surfaceContainerLowest : Colors.white,
    );
  }

  static ColorScheme _buildMonochromeScheme(Brightness brightness, int? tertiaryColorValue) {
    final isDark = brightness == Brightness.dark;

    final Color? customTertiary = tertiaryColorValue != null ? Color(tertiaryColorValue) : null;
    final Color tertiary = customTertiary ?? (isDark ? const Color(0xFFD4D6DF) : const Color(0xFF2B2D36));
    final Color onTertiary = ThemeData.estimateBrightnessForColor(tertiary) == Brightness.dark
        ? Colors.white
        : const Color(0xFF0E0F12);
    final Color tertiaryContainer = customTertiary != null
        ? customTertiary.withValues(alpha: isDark ? 0.24 : 0.16)
        : (isDark ? const Color(0xFF282B34) : const Color(0xFFE7E9F0));
    final Color onTertiaryContainer = isDark ? const Color(0xFFF3F4F8) : const Color(0xFF111217);

    if (isDark) {
      return ColorScheme.fromSeed(
        seedColor: customTertiary ?? const Color(0xFF8E92A4),
        brightness: Brightness.dark,
      ).copyWith(
        brightness: Brightness.dark,
        primary: const Color(0xFFF5F6FA),
        onPrimary: const Color(0xFF0E0F13),
        primaryContainer: const Color(0xFF2A2D36),
        onPrimaryContainer: const Color(0xFFF5F6FA),
        secondary: const Color(0xFFC4C7D2),
        onSecondary: const Color(0xFF14151A),
        secondaryContainer: const Color(0xFF22252D),
        onSecondaryContainer: const Color(0xFFE6E8F0),
        tertiary: tertiary,
        onTertiary: onTertiary,
        tertiaryContainer: tertiaryContainer,
        onTertiaryContainer: onTertiaryContainer,
        surface: const Color(0xFF0F1014),
        onSurface: const Color(0xFFF2F3F7),
        onSurfaceVariant: const Color(0xFFA6A9B6),
        surfaceContainerLowest: const Color(0xFF090A0D),
        surfaceContainerLow: const Color(0xFF17191F),
        surfaceContainer: const Color(0xFF1D2028),
        surfaceContainerHigh: const Color(0xFF252832),
        surfaceContainerHighest: const Color(0xFF2F333F),
        outline: const Color(0xFF7B7F8D),
        outlineVariant: const Color(0xFF2D313C),
        inverseSurface: const Color(0xFFF2F3F7),
        onInverseSurface: const Color(0xFF14151A),
        inversePrimary: const Color(0xFF111216),
      );
    }

    return ColorScheme.fromSeed(
      seedColor: customTertiary ?? const Color(0xFF474A57),
      brightness: Brightness.light,
    ).copyWith(
      brightness: Brightness.light,
      primary: const Color(0xFF0E0F13),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE5E7EE),
      onPrimaryContainer: const Color(0xFF0E0F13),
      secondary: const Color(0xFF454854),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFECEEF4),
      onSecondaryContainer: const Color(0xFF181A20),
      tertiary: tertiary,
      onTertiary: onTertiary,
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: onTertiaryContainer,
      surface: const Color(0xFFF6F7FA),
      onSurface: const Color(0xFF111217),
      onSurfaceVariant: const Color(0xFF5A5D6A),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFEDEFF4),
      surfaceContainer: const Color(0xFFE5E8EF),
      surfaceContainerHigh: const Color(0xFFDDE0E8),
      surfaceContainerHighest: const Color(0xFFD3D7E1),
      outline: const Color(0xFF737684),
      outlineVariant: const Color(0xFFD0D4DF),
      inverseSurface: const Color(0xFF16181E),
      onInverseSurface: const Color(0xFFF5F6FA),
      inversePrimary: Colors.white,
    );
  }
}
