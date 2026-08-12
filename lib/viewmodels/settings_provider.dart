import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final bool isDarkMode;
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
  }) {
    return SettingsState(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      escalaNotas: escalaNotas ?? this.escalaNotas,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      minutosAntesClase: minutosAntesClase ?? this.minutosAntesClase,
      horasAntesEvaluacion: horasAntesEvaluacion ?? this.horasAntesEvaluacion,
      selectedClassSound: selectedClassSound ?? this.selectedClassSound,
      selectedEvalSound: selectedEvalSound ?? this.selectedEvalSound,
      subjectViewMode: subjectViewMode ?? this.subjectViewMode,
      isCompactList: isCompactList ?? this.isCompactList,
      gridCrossAxisCount: gridCrossAxisCount ?? this.gridCrossAxisCount,
      tertiaryColor: tertiaryColor ?? this.tertiaryColor,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _darkModeKey = 'isDarkMode';
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
    final isDarkMode = prefs.getBool(_darkModeKey) ?? false;
    final escalaNotas = prefs.getString(_escalaKey) ?? '0 a 100';
    final notifEnabled = prefs.getBool(_notifEnabledKey) ?? true;
    final minClase = prefs.getInt(_minClaseKey) ?? 15;
    final hrsEval = prefs.getInt(_hrsEvalKey) ?? 24;
    final classSound = prefs.getString(_classSoundKey) ?? 'clase_sound';
    final evalSound = prefs.getString(_evalSoundKey) ?? 'eval_sound';
    final viewMode = prefs.getString(_viewModeKey) ?? 'lista';
    final isCompact = prefs.getBool(_isCompactListKey) ?? false;
    final gridCols = prefs.getInt(_gridCrossAxisKey) ?? 2;
    final tColor = prefs.getInt(_tertiaryColorKey);
    
    state = SettingsState(
      isDarkMode: isDarkMode, 
      escalaNotas: escalaNotas,
      notificationsEnabled: notifEnabled,
      minutosAntesClase: minClase,
      horasAntesEvaluacion: hrsEval,
      selectedClassSound: classSound,
      selectedEvalSound: evalSound,
      subjectViewMode: viewMode,
      isCompactList: isCompact,
      gridCrossAxisCount: gridCols,
      tertiaryColor: tColor,
    );
  }

  Future<void> toggleDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    final newValue = !state.isDarkMode;
    await prefs.setBool(_darkModeKey, newValue);
    state = state.copyWith(isDarkMode: newValue);
  }

  Future<void> setEscalaNotas(String escala) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_escalaKey, escala);
    state = state.copyWith(escalaNotas: escala);
  }
  
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
    } else {
      await prefs.setInt(_tertiaryColorKey, color);
    }
    state = state.copyWith(tertiaryColor: color);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
