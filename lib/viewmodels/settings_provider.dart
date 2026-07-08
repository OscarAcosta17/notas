import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final bool isDarkMode;
  final String escalaNotas; // '1 a 7' o '0 a 100'

  final int minutosAntesClase;
  final int horasAntesEvaluacion;
  
  final String selectedClassSound;
  final String selectedEvalSound;

  SettingsState({
    required this.isDarkMode,
    required this.escalaNotas,
    required this.minutosAntesClase,
    required this.horasAntesEvaluacion,
    required this.selectedClassSound,
    required this.selectedEvalSound,
  });

  SettingsState copyWith({
    bool? isDarkMode,
    String? escalaNotas,
    int? minutosAntesClase,
    int? horasAntesEvaluacion,
    String? selectedClassSound,
    String? selectedEvalSound,
  }) {
    return SettingsState(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      escalaNotas: escalaNotas ?? this.escalaNotas,
      minutosAntesClase: minutosAntesClase ?? this.minutosAntesClase,
      horasAntesEvaluacion: horasAntesEvaluacion ?? this.horasAntesEvaluacion,
      selectedClassSound: selectedClassSound ?? this.selectedClassSound,
      selectedEvalSound: selectedEvalSound ?? this.selectedEvalSound,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _darkModeKey = 'isDarkMode';
  static const _escalaKey = 'escalaNotas';
  static const _minClaseKey = 'minutosAntesClase';
  static const _hrsEvalKey = 'horasAntesEvaluacion';
  static const _classSoundKey = 'selectedClassSound';
  static const _evalSoundKey = 'selectedEvalSound';

  @override
  SettingsState build() {
    _loadSettings();
    return SettingsState(
      isDarkMode: false, 
      escalaNotas: '1 a 7',
      minutosAntesClase: 15,
      horasAntesEvaluacion: 24,
      selectedClassSound: 'clase_sound',
      selectedEvalSound: 'eval_sound',
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkMode = prefs.getBool(_darkModeKey) ?? false;
    final escalaNotas = prefs.getString(_escalaKey) ?? '1 a 7';
    final minClase = prefs.getInt(_minClaseKey) ?? 15;
    final hrsEval = prefs.getInt(_hrsEvalKey) ?? 24;
    final classSound = prefs.getString(_classSoundKey) ?? 'clase_sound';
    final evalSound = prefs.getString(_evalSoundKey) ?? 'eval_sound';
    
    state = SettingsState(
      isDarkMode: isDarkMode, 
      escalaNotas: escalaNotas,
      minutosAntesClase: minClase,
      horasAntesEvaluacion: hrsEval,
      selectedClassSound: classSound,
      selectedEvalSound: evalSound,
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
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
