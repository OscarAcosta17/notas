package com.example.notas

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Field

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.notas/sounds"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getRawSounds") {
                val sounds = mutableListOf<String>()
                val fields: Array<Field> = R.raw::class.java.fields
                for (field in fields) {
                    sounds.add(field.name)
                }
                result.success(sounds)
            } else {
                result.notImplemented()
            }
        }
    }
}
