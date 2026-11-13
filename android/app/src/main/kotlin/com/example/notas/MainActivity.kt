package com.example.notas

import android.content.ComponentName
import android.content.pm.PackageManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Field

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.notas/sounds"
    private val APP_ICON_CHANNEL = "com.example.notas/app_icon"

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_ICON_CHANNEL).setMethodCallHandler { call, result ->
            val classicComponent = ComponentName(packageName, "com.example.notas.MainActivityAlias")
            val icon2Component = ComponentName(packageName, "com.example.notas.Icon2")

            when (call.method) {
                "setAppIcon" -> {
                    val alias = call.argument<String>("alias") ?: "classic"
                    val target = if (alias == "icon2") icon2Component else classicComponent
                    val other = if (alias == "icon2") classicComponent else icon2Component

                    try {
                        packageManager.setComponentEnabledSetting(
                            target,
                            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                            PackageManager.DONT_KILL_APP
                        )
                        packageManager.setComponentEnabledSetting(
                            other,
                            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                            PackageManager.DONT_KILL_APP
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ICON_ERROR", e.localizedMessage, null)
                    }
                }
                "getAppIcon" -> {
                    val icon2State = packageManager.getComponentEnabledSetting(icon2Component)
                    val current = if (icon2State == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                        "icon2"
                    } else {
                        "classic"
                    }
                    result.success(current)
                }
                else -> result.notImplemented()
            }
        }
    }
}
