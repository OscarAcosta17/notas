import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final bool isDarkMode;
  final bool useDynamicColor;
  final String frostedGlassIntensity; // 'solido', 'sutil', 'intenso'
  final String bottomNavStyle; // 'm3_expressive', 'one_ui', 'ios_glass', 'floating_fab', 'dock'
  final String navLabelMode; // 'always', 'selected', 'icon_only'
  final String semesterSelectorStyle; // 'header', 'chips'
  final bool enableHorizontalSwipe;
  final String surfaceStyle; // 'tonal', 'oled'
  final String cardRadiusStyle; // 'compacto', 'equilibrado', 'expresivo'
  final String subjectColorStyle; // 'degradado', 'resplandor', 'neon', 'encabezado', 'mixto', 'franja', 'tinte', 'borde'
  final String appIcon; // 'classic', 'icon2'
  final bool hapticsEnabled;
  final String escalaNotas; // '1 a 7' o '0 a 100'
  final String subjectViewMode; // 'lista', 'cuadricula'
  final bool isCompactList;
  final int gridCrossAxisCount;
  final int? tertiaryColor;

  final bool notificationsEnabled;
  final int minutosAntesClase;
  final int horasAntesEvaluacion;

  final String selectedClassSound;
  final String selectedEvalSound;

  SettingsState({
    required this.isDarkMode,
    required this.useDynamicColor,
    required this.frostedGlassIntensity,
    required this.bottomNavStyle,
    required this.navLabelMode,
    required this.semesterSelectorStyle,
    required this.enableHorizontalSwipe,
    required this.surfaceStyle,
    required this.cardRadiusStyle,
    required this.subjectColorStyle,
    required this.appIcon,
    required this.hapticsEnabled,
    required this.escalaNotas,
    required this.notificationsEnabled,
    required this.minutosAntesClase,
    required this.horasAntesEvaluacion,
    required this.selectedClassSound,
    required this.selectedEvalSound,
    required this.subjectViewMode,
    required this.isCompactList,
    required this.gridCrossAxisCount,
    this.tertiaryColor,
  });

  SettingsState copyWith({
    bool? isDarkMode,
    bool? useDynamicColor,
    String? frostedGlassIntensity,
    String? bottomNavStyle,
    String? navLabelMode,
    String? semesterSelectorStyle,
    bool? enableHorizontalSwipe,
    String? surfaceStyle,
    String? cardRadiusStyle,
    String? subjectColorStyle,
    String? appIcon,
    bool? hapticsEnabled,
    String? escalaNotas,
    bool? notificationsEnabled,
    int? minutosAntesClase,
    int? horasAntesEvaluacion,
    String? selectedClassSound,
    String? selectedEvalSound,
    String? subjectViewMode,
    bool? isCompactList,
    int? gridCrossAxisCount,
    int? tertiaryColor,
    bool clearTertiaryColor = false,
  }) {
    return SettingsState(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      frostedGlassIntensity: frostedGlassIntensity ?? this.frostedGlassIntensity,
      bottomNavStyle: bottomNavStyle ?? this.bottomNavStyle,
      navLabelMode: navLabelMode ?? this.navLabelMode,
      semesterSelectorStyle: semesterSelectorStyle ?? this.semesterSelectorStyle,
      enableHorizontalSwipe: enableHorizontalSwipe ?? this.enableHorizontalSwipe,
      surfaceStyle: surfaceStyle ?? this.surfaceStyle,
      cardRadiusStyle: cardRadiusStyle ?? this.cardRadiusStyle,
      subjectColorStyle: subjectColorStyle ?? this.subjectColorStyle,
      appIcon: appIcon ?? this.appIcon,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      escalaNotas: escalaNotas ?? this.escalaNotas,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      minutosAntesClase: minutosAntesClase ?? this.minutosAntesClase,
      horasAntesEvaluacion: horasAntesEvaluacion ?? this.horasAntesEvaluacion,
      selectedClassSound: selectedClassSound ?? this.selectedClassSound,
      selectedEvalSound: selectedEvalSound ?? this.selectedEvalSound,
      subjectViewMode: subjectViewMode ?? this.subjectViewMode,
      isCompactList: isCompactList ?? this.isCompactList,
      gridCrossAxisCount: gridCrossAxisCount ?? this.gridCrossAxisCount,
      tertiaryColor: clearTertiaryColor ? null : (tertiaryColor ?? this.tertiaryColor),
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _darkModeKey = 'isDarkMode';
  static const _dynamicColorKey = 'useDynamicColor';
  static const _frostedGlassKey = 'frostedGlassIntensity';
  static const _bottomNavStyleKey = 'bottomNavStyle';
  static const _navLabelModeKey = 'navLabelMode';
  static const _semesterSelectorKey = 'semesterSelectorStyle';
  static const _horizontalSwipeKey = 'enableHorizontalSwipe';
  static const _surfaceStyleKey = 'surfaceStyle';
  static const _cardRadiusKey = 'cardRadiusStyle';
  static const _subjectColorStyleKey = 'subjectColorStyle';
  static const _appIconKey = 'appIcon';
  static const _hapticsKey = 'hapticsEnabled';
  static const _escalaKey = 'escalaNotas';
  static const _notifEnabledKey = 'notificationsEnabled';
  static const _minClaseKey = 'minutosAntesClase';
  static const _hrsEvalKey = 'horasAntesEvaluacion';
  static const _classSoundKey = 'selectedClassSound';
  static const _evalSoundKey = 'selectedEvalSound';
  static const _viewModeKey = 'subjectViewMode';
  static const _isCompactListKey = 'isCompactList';
  static const _gridCrossAxisKey = 'gridCrossAxisCount';
  static const _tertiaryColorKey = 'tertiaryColor';

  @override
  SettingsState build() {
    _loadSettings();
    return SettingsState(
      isDarkMode: false,
      useDynamicColor: false,
      frostedGlassIntensity: 'intenso',
      bottomNavStyle: 'floating_fab',
      navLabelMode: 'always',
      semesterSelectorStyle: 'header',
      enableHorizontalSwipe: true,
      surfaceStyle: 'tonal',
      cardRadiusStyle: 'expresivo',
      subjectColorStyle: 'mixto',
      appIcon: 'classic',
      hapticsEnabled: true,
      escalaNotas: '0 a 100',
      notificationsEnabled: true,
      minutosAntesClase: 15,
      horasAntesEvaluacion: 24,
      selectedClassSound: 'clase_sound',
      selectedEvalSound: 'eval_sound',
      subjectViewMode: 'lista',
      isCompactList: false,
      gridCrossAxisCount: 2,
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    state = SettingsState(
      isDarkMode: prefs.getBool(_darkModeKey) ?? false,
      useDynamicColor: prefs.getBool(_dynamicColorKey) ?? false,
      frostedGlassIntensity: prefs.getString(_frostedGlassKey) ?? 'intenso',
      bottomNavStyle: prefs.getString(_bottomNavStyleKey) ?? 'floating_fab',
      navLabelMode: prefs.getString(_navLabelModeKey) ?? 'always',
      semesterSelectorStyle: prefs.getString(_semesterSelectorKey) ?? 'header',
      enableHorizontalSwipe: prefs.getBool(_horizontalSwipeKey) ?? true,
      surfaceStyle: prefs.getString(_surfaceStyleKey) ?? 'tonal',
      cardRadiusStyle: prefs.getString(_cardRadiusKey) ?? 'expresivo',
      subjectColorStyle: prefs.getString(_subjectColorStyleKey) ?? 'mixto',
      appIcon: prefs.getString(_appIconKey) ?? 'classic',
      hapticsEnabled: prefs.getBool(_hapticsKey) ?? true,
      escalaNotas: prefs.getString(_escalaKey) ?? '0 a 100',
      notificationsEnabled: prefs.getBool(_notifEnabledKey) ?? true,
      minutosAntesClase: prefs.getInt(_minClaseKey) ?? 15,
      horasAntesEvaluacion: prefs.getInt(_hrsEvalKey) ?? 24,
      selectedClassSound: prefs.getString(_classSoundKey) ?? 'clase_sound',
      selectedEvalSound: prefs.getString(_evalSoundKey) ?? 'eval_sound',
      subjectViewMode: prefs.getString(_viewModeKey) ?? 'lista',
      isCompactList: prefs.getBool(_isCompactListKey) ?? false,
      gridCrossAxisCount: prefs.getInt(_gridCrossAxisKey) ?? 2,
      tertiaryColor: prefs.getInt(_tertiaryColorKey),
    );
  }

  Future<void> _setBoolPref(String key, bool value, SettingsState nextState) async {
    state = nextState;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _setStringPref(String key, String value, SettingsState nextState) async {
    state = nextState;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> toggleDarkMode() async {
    final next = !state.isDarkMode;
    await _setBoolPref(_darkModeKey, next, state.copyWith(isDarkMode: next));
  }

  Future<void> setUseDynamicColor(bool value) async =>
      _setBoolPref(_dynamicColorKey, value, state.copyWith(useDynamicColor: value));

  Future<void> setFrostedGlassIntensity(String intensity) async =>
      _setStringPref(_frostedGlassKey, intensity, state.copyWith(frostedGlassIntensity: intensity));

  Future<void> setBottomNavStyle(String style) async =>
      _setStringPref(_bottomNavStyleKey, style, state.copyWith(bottomNavStyle: style));

  Future<void> setNavLabelMode(String mode) async =>
      _setStringPref(_navLabelModeKey, mode, state.copyWith(navLabelMode: mode));

  Future<void> setSemesterSelectorStyle(String style) async =>
      _setStringPref(_semesterSelectorKey, style, state.copyWith(semesterSelectorStyle: style));

  Future<void> setEnableHorizontalSwipe(bool enabled) async =>
      _setBoolPref(_horizontalSwipeKey, enabled, state.copyWith(enableHorizontalSwipe: enabled));

  Future<void> setSurfaceStyle(String style) async =>
      _setStringPref(_surfaceStyleKey, style, state.copyWith(surfaceStyle: style));

  Future<void> setCardRadiusStyle(String style) async =>
      _setStringPref(_cardRadiusKey, style, state.copyWith(cardRadiusStyle: style));

  Future<void> setSubjectColorStyle(String style) async =>
      _setStringPref(_subjectColorStyleKey, style, state.copyWith(subjectColorStyle: style));

  Future<void> setAppIcon(String icon) async =>
      _setStringPref(_appIconKey, icon, state.copyWith(appIcon: icon));

  Future<void> setHapticsEnabled(bool enabled) async =>
      _setBoolPref(_hapticsKey, enabled, state.copyWith(hapticsEnabled: enabled));

  Future<void> setEscalaNotas(String escala) async =>
      _setStringPref(_escalaKey, escala, state.copyWith(escalaNotas: escala));
  
  Future<void> setMinutosAntesClase(int minutos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_minClaseKey, minutos);
    state = state.copyWith(minutosAntesClase: minutos);
  }

  Future<void> setHorasAntesEvaluacion(int horas) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hrsEvalKey, horas);
    state = state.copyWith(horasAntesEvaluacion: horas);
  }
  
  Future<void> setClassSound(String soundName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_classSoundKey, soundName);
    state = state.copyWith(selectedClassSound: soundName);
  }

  Future<void> setEvalSound(String soundName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_evalSoundKey, soundName);
    state = state.copyWith(selectedEvalSound: soundName);
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifEnabledKey, enabled);
    state = state.copyWith(notificationsEnabled: enabled);
  }

  Future<void> setSubjectViewMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_viewModeKey, mode);
    state = state.copyWith(subjectViewMode: mode);
  }

  Future<void> setIsCompactList(bool isCompact) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isCompactListKey, isCompact);
    state = state.copyWith(isCompactList: isCompact);
  }

  Future<void> setGridCrossAxisCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_gridCrossAxisKey, count);
    state = state.copyWith(gridCrossAxisCount: count);
  }

  Future<void> setTertiaryColor(int? color) async {
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(_tertiaryColorKey);
      state = state.copyWith(clearTertiaryColor: true);
    } else {
      await prefs.setInt(_tertiaryColorKey, color);
      state = state.copyWith(tertiaryColor: color);
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
