import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final bool isDarkMode;
  final String escalaNotas; // '1 a 7' o '0 a 100'

  final int minutosAntesClase;
  final int horasAntesEvaluacion;

  SettingsState({
    required this.isDarkMode,
    required this.escalaNotas,
    required this.minutosAntesClase,
    required this.horasAntesEvaluacion,
  });

  SettingsState copyWith({
    bool? isDarkMode,
    String? escalaNotas,
    int? minutosAntesClase,
    int? horasAntesEvaluacion,
  }) {
    return SettingsState(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      escalaNotas: escalaNotas ?? this.escalaNotas,
      minutosAntesClase: minutosAntesClase ?? this.minutosAntesClase,
      horasAntesEvaluacion: horasAntesEvaluacion ?? this.horasAntesEvaluacion,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _darkModeKey = 'isDarkMode';
  static const _escalaKey = 'escalaNotas';
  static const _minClaseKey = 'minutosAntesClase';
  static const _hrsEvalKey = 'horasAntesEvaluacion';

  @override
  SettingsState build() {
    _loadSettings();
    return SettingsState(
      isDarkMode: false, 
      escalaNotas: '1 a 7',
      minutosAntesClase: 15,
      horasAntesEvaluacion: 24,
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkMode = prefs.getBool(_darkModeKey) ?? false;
    final escalaNotas = prefs.getString(_escalaKey) ?? '1 a 7';
    final minClase = prefs.getInt(_minClaseKey) ?? 15;
    final hrsEval = prefs.getInt(_hrsEvalKey) ?? 24;
    
    state = SettingsState(
      isDarkMode: isDarkMode, 
      escalaNotas: escalaNotas,
      minutosAntesClase: minClase,
      horasAntesEvaluacion: hrsEval,
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
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
