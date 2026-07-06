import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final bool isDarkMode;
  final String escalaNotas; // '1 a 7' o '0 a 100'

  SettingsState({
    required this.isDarkMode,
    required this.escalaNotas,
  });

  SettingsState copyWith({
    bool? isDarkMode,
    String? escalaNotas,
  }) {
    return SettingsState(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      escalaNotas: escalaNotas ?? this.escalaNotas,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _darkModeKey = 'isDarkMode';
  static const _escalaKey = 'escalaNotas';

  @override
  SettingsState build() {
    // Initial state before loading
    _loadSettings();
    return SettingsState(isDarkMode: false, escalaNotas: '1 a 7');
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkMode = prefs.getBool(_darkModeKey) ?? false;
    final escalaNotas = prefs.getString(_escalaKey) ?? '1 a 7';
    state = SettingsState(isDarkMode: isDarkMode, escalaNotas: escalaNotas);
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
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
