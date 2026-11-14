package com.example.notas

import android.content.ComponentName
import android.content.pm.PackageManager
import android.webkit.CookieManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Field

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.notas/sounds"
    private val APP_ICON_CHANNEL = "com.example.notas/app_icon"
    private val AULA_COOKIE_CHANNEL = "com.example.notas/aula_cookies"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AULA_COOKIE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookies" -> {
                    val url = call.argument<String>("url") ?: "https://aula.usm.cl"
                    val cookies = CookieManager.getInstance().getCookie(url) ?: ""
                    result.success(cookies)
                }
                "clearCookies" -> {
                    CookieManager.getInstance().removeAllCookies {
                        CookieManager.getInstance().flush()
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
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

        val iconAliases = linkedMapOf(
            "classic" to "com.example.notas.MainActivityAlias",
            "icon2" to "com.example.notas.Icon2",
            "icon3" to "com.example.notas.Icon3",
            "icon4" to "com.example.notas.Icon4",
            "icon5" to "com.example.notas.Icon5",
            "icon6" to "com.example.notas.Icon6"
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_ICON_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAppIcon" -> {
                    val alias = call.argument<String>("alias") ?: "classic"
                    val targetClass = iconAliases[alias] ?: iconAliases.getValue("classic")

                    try {
                        packageManager.setComponentEnabledSetting(
                            ComponentName(packageName, targetClass),
                            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                            PackageManager.DONT_KILL_APP
                        )
                        for ((_, cls) in iconAliases) {
                            if (cls != targetClass) {
                                packageManager.setComponentEnabledSetting(
                                    ComponentName(packageName, cls),
                                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                    PackageManager.DONT_KILL_APP
                                )
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ICON_ERROR", e.localizedMessage, null)
                    }
                }
                "getAppIcon" -> {
                    var current = "classic"
                    for ((key, cls) in iconAliases) {
                        if (key == "classic") continue
                        val state = packageManager.getComponentEnabledSetting(ComponentName(packageName, cls))
                        if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                            current = key
                            break
                        }
                    }
                    result.success(current)
                }
                else -> result.notImplemented()
            }
        }
    }
}
