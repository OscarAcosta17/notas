import 'package:flutter/services.dart';

class SoundService {
  static const MethodChannel _channel = MethodChannel('com.example.notas/sounds');

  static Future<List<String>> getAvailableSounds() async {
    try {
      final List<dynamic> result = await _channel.invokeMethod('getRawSounds');
      final List<String> sounds = result.cast<String>();
      // Filtramos algunos sonidos internos si los hubiera, pero en nuestro caso todos son nuestros
      return sounds;
    } catch (e) {
      print("Failed to get sounds: $e");
      // Fallback
      return ['clase_sound', 'eval_sound'];
    }
  }
}
