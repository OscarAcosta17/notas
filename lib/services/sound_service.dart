import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SoundService {
  static const MethodChannel _channel = MethodChannel('com.example.notas/sounds');

  static Future<List<String>> getAvailableSounds() async {
    if (!Platform.isAndroid) {
      return ['clase_sound', 'eval_sound'];
    }
    try {
      final List<dynamic> result = await _channel.invokeMethod('getRawSounds');
      final List<String> sounds = result.cast<String>();
      return sounds;
    } catch (e) {
      debugPrint('Failed to get sounds: $e');
      return ['clase_sound', 'eval_sound'];
    }
  }
}
