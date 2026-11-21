package com.example.notas

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.webkit.CookieManager
import android.webkit.MimeTypeMap
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.reflect.Field
import java.security.KeyStore
import java.security.MessageDigest
import java.util.TimeZone
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.notas/sounds"
    private val APP_ICON_CHANNEL = "com.example.notas/app_icon"
    private val AULA_COOKIE_CHANNEL = "com.example.notas/aula_cookies"
    private val AULA_STORAGE_CHANNEL = "cl.usm.aulascrapt/storage"
    private val TIMEZONE_CHANNEL = "com.example.notas/timezone"
    private val SECURE_STORAGE_CHANNEL = "com.example.notas/secure_storage"

    private val pickDirRequestCode = 9412
    private val notifPermRequestCode = 9413
    private var pendingDirResult: MethodChannel.Result? = null
    private var pendingNotifPermResult: MethodChannel.Result? = null
    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        private const val KEY_ALIAS = "notas_secure_cred_key"
        private const val ENC_PREFIX = "enc_v1:"
        private const val GCM_IV_LEN = 12
        private const val GCM_TAG_BITS = 128
    }

    private fun isTrustedAulaUrl(rawUrl: String): Boolean {
        return try {
            val uri = Uri.parse(rawUrl)
            val scheme = uri.scheme?.lowercase() ?: return false
            val host = uri.host?.lowercase() ?: return false
            scheme == "https" && (host == "aula.usm.cl" || host.endsWith(".aula.usm.cl"))
        } catch (_: Exception) {
            false
        }
    }

    @Synchronized
    private fun getOrCreateAesKey(): SecretKey? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        val existing = keyStore.getKey(KEY_ALIAS, null)
        if (existing is SecretKey) return existing

        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }

    private fun encryptCredential(plainText: String): String? {
        val secretKey = getOrCreateAesKey() ?: return null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        val iv = cipher.iv
        val cipherBytes = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
        val combined = ByteArray(iv.size + cipherBytes.size)
        System.arraycopy(iv, 0, combined, 0, iv.size)
        System.arraycopy(cipherBytes, 0, combined, iv.size, cipherBytes.size)
        return ENC_PREFIX + Base64.encodeToString(combined, Base64.NO_WRAP)
    }

    private fun decryptCredential(encoded: String): String? {
        if (!encoded.startsWith(ENC_PREFIX)) return null
        val secretKey = getOrCreateAesKey() ?: return null
        val combined = Base64.decode(encoded.substring(ENC_PREFIX.length), Base64.DEFAULT)
        if (combined.size <= GCM_IV_LEN) return null
        val iv = combined.copyOfRange(0, GCM_IV_LEN)
        val cipherBytes = combined.copyOfRange(GCM_IV_LEN, combined.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(GCM_TAG_BITS, iv))
        val plainBytes = cipher.doFinal(cipherBytes)
        return String(plainBytes, Charsets.UTF_8)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TIMEZONE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getLocalTimezone" -> result.success(TimeZone.getDefault().id)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "encrypt" -> {
                    val value = call.argument<String>("value")
                    if (value == null) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(encryptCredential(value))
                    } catch (e: Exception) {
                        result.error("ENCRYPT_ERROR", e.localizedMessage, null)
                    }
                }
                "decrypt" -> {
                    val value = call.argument<String>("value")
                    if (value == null) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(decryptCredential(value))
                    } catch (e: Exception) {
                        result.error("DECRYPT_ERROR", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AULA_COOKIE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookies" -> {
                    val url = call.argument<String>("url") ?: "https://aula.usm.cl"
                    if (!isTrustedAulaUrl(url)) {
                        result.error("INVALID_URL", "Host no autorizado para leer cookies.", null)
                        return@setMethodCallHandler
                    }
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AULA_STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSdkInt" -> result.success(Build.VERSION.SDK_INT)
                "getExternalRoot" -> result.success(Environment.getExternalStorageDirectory().absolutePath)
                "getSystemSeedColor" -> result.success(readSystemAccentColor())
                "getAppInfo" -> result.success(readAppInfo())
                "clearWebViewCookies" -> {
                    CookieManager.getInstance().removeAllCookies {
                        CookieManager.getInstance().flush()
                        result.success(true)
                    }
                }
                "computeFileSha256" -> {
                    val filePath = call.argument<String>("path")
                    ioExecutor.execute {
                        val digest = computeSha256(filePath)
                        mainHandler.post { result.success(digest) }
                    }
                }
                "openLocalFile" -> {
                    val filePath = call.argument<String>("path")
                    openLocalFile(filePath, result)
                }
                "hasNotificationPermission" -> {
                    result.success(hasPostNotificationPermission())
                }
                "requestNotificationPermission" -> {
                    requestPostNotificationPermission(result)
                }
                "showNativeNotification" -> {
                    val id = call.argument<Int>("id")
                    val title = call.argument<String>("title") ?: "Aula-Scrapt"
                    val body = call.argument<String>("body") ?: ""
                    val channelId = call.argument<String>("channelId") ?: "aula_updates"
                    result.success(showAulaNotification(id, title, body, channelId))
                }
                "scheduleBackgroundSync" -> {
                    result.success(true)
                }
                "scanQrCode" -> {
                    result.error(
                        "SCANNER_UNAVAILABLE",
                        "Escáner QR nativo no incluido; ingresa la IP y PIN manualmente.",
                        null,
                    )
                }
                "pickDirectory" -> {
                    if (pendingDirResult != null) {
                        result.error("BUSY", "Selector ya abierto", null)
                        return@setMethodCallHandler
                    }
                    pendingDirResult = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                        intent.addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                        )
                        startActivityForResult(intent, pickDirRequestCode)
                    } catch (e: Exception) {
                        pendingDirResult = null
                        result.error("PICKER_ERROR", e.message, null)
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
            "classic" to "$packageName.MainActivityAlias",
            "icon2" to "$packageName.Icon2",
            "icon3" to "$packageName.Icon3",
            "icon4" to "$packageName.Icon4",
            "icon5" to "$packageName.Icon5",
            "icon6" to "$packageName.Icon6"
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

    private fun readSystemAccentColor(): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return try {
            resources.getColor(android.R.color.system_accent1_500, theme)
        } catch (_: Exception) {
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun readAppInfo(): Map<String, Any?> {
        val pkgInfo: PackageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            packageManager.getPackageInfo(packageName, 0)
        }
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            pkgInfo.longVersionCode
        } else {
            pkgInfo.versionCode.toLong()
        }
        return mapOf(
            "versionName" to (pkgInfo.versionName ?: "1.3.1"),
            "versionCode" to versionCode,
            "packageName" to packageName,
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "sdkInt" to Build.VERSION.SDK_INT,
        )
    }

    private fun computeSha256(filePath: String?): String? {
        if (filePath.isNullOrBlank()) return null
        val file = File(filePath)
        if (!file.exists() || !file.isFile) return null
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(65536)
                var read: Int
                while (input.read(buffer).also { read = it } != -1) {
                    digest.update(buffer, 0, read)
                }
            }
            digest.digest().joinToString("") { "%02x".format(it) }
        } catch (_: Exception) {
            null
        }
    }

    override fun onDestroy() {
        ioExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun openLocalFile(filePath: String?, result: MethodChannel.Result) {
        if (filePath.isNullOrBlank()) {
            result.error("INVALID_PATH", "Ruta vacía", null)
            return
        }
        val file = File(filePath)
        if (!file.exists() || !file.isFile) {
            result.error("NOT_FOUND", "El archivo ya no existe en disco", null)
            return
        }
        try {
            val canonicalFile = file.canonicalPath
            val dataDirCanonical = File(applicationInfo.dataDir).canonicalPath
            if (canonicalFile == dataDirCanonical ||
                canonicalFile.startsWith("$dataDirCanonical${File.separator}")
            ) {
                result.error("FORBIDDEN_PATH", "No se permite abrir archivos internos privados de la app", null)
                return
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val ext = file.extension.lowercase()
            val detectedMime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*"
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, detectedMime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(Intent.createChooser(intent, "Abrir ${file.name}"))
            result.success(true)
        } catch (e: Exception) {
            result.error("OPEN_ERROR", e.message ?: "No hay app para abrir este archivo", null)
        }
    }

    private fun hasPostNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestPostNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || hasPostNotificationPermission()) {
            result.success(true)
            return
        }
        if (pendingNotifPermResult != null) {
            result.error("BUSY", "Solicitud de permiso pendiente", null)
            return
        }
        pendingNotifPermResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notifPermRequestCode,
        )
    }

    private fun ensureAulaNotificationChannels(requestedChannelId: String? = null) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channels = mutableListOf(
            NotificationChannel(
                "aula_new_files",
                "Nuevos archivos de Aula",
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
            NotificationChannel(
                "aula_deadlines",
                "Entregas y cuestionarios",
                NotificationManager.IMPORTANCE_HIGH,
            ),
            NotificationChannel(
                "aula_downloads",
                "Descargas completadas",
                NotificationManager.IMPORTANCE_LOW,
            ),
            NotificationChannel(
                "aula_updates",
                "Actualizaciones",
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
        if (!requestedChannelId.isNullOrBlank() && channels.none { it.id == requestedChannelId }) {
            channels.add(
                NotificationChannel(
                    requestedChannelId,
                    "Notificaciones Aula USM",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        channels.forEach { manager.createNotificationChannel(it) }
    }

    private fun showAulaNotification(id: Int?, title: String, body: String, channelId: String): Boolean {
        val effectiveChannel = channelId.ifBlank { "aula_updates" }
        ensureAulaNotificationChannels(effectiveChannel)
        if (!hasPostNotificationPermission()) return false

        val notifId = id ?: ((System.currentTimeMillis() and 0x7FFFFFFF).toInt())
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val pendingIntent = PendingIntent.getActivity(this, notifId, launchIntent, pendingFlags)

        val builder = NotificationCompat.Builder(this, effectiveChannel)
            .setSmallIcon(android.R.drawable.stat_notify_more)
            .setContentTitle(title.ifBlank { "Aula-Scrapt USM" })
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setPriority(
                if (effectiveChannel == "aula_deadlines") NotificationCompat.PRIORITY_HIGH
                else NotificationCompat.PRIORITY_DEFAULT,
            )

        return try {
            NotificationManagerCompat.from(this).notify(notifId, builder.build())
            true
        } catch (_: Exception) {
            false
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == notifPermRequestCode) {
            val res = pendingNotifPermResult
            pendingNotifPermResult = null
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            res?.success(granted)
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == pickDirRequestCode) {
            val res = pendingDirResult
            pendingDirResult = null
            if (res == null) return
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                res.success(null)
                return
            }
            val treeUri: Uri = data.data!!
            try {
                contentResolver.takePersistableUriPermission(
                    treeUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            } catch (_: Exception) {}
            val resolved = resolveTreeUriToPath(treeUri)
            val validPath = resolved?.takeIf { path ->
                val f = File(path)
                f.exists() && f.isDirectory
            }
            res.success(validPath)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun resolveTreeUriToPath(uri: Uri): String? {
        return try {
            val docId = DocumentsContract.getTreeDocumentId(uri) ?: return null
            val parts = docId.split(":", limit = 2)
            val type = parts[0]
            val relPath = if (parts.size > 1) parts[1] else ""
            if (type.equals("primary", ignoreCase = true)) {
                val base = Environment.getExternalStorageDirectory().absolutePath
                if (relPath.isEmpty()) base else "$base/$relPath"
            } else {
                if (relPath.isEmpty()) "/storage/$type" else "/storage/$type/$relPath"
            }
        } catch (_: Exception) {
            null
        }
    }
}
