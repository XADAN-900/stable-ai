package com.xadan.stable_ai

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Kendini güncelleme: indirilen APK'yı sistem kurulum ekranında açar.
 * Dart tarafı: lib/installer.dart -> Installer.install()
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "stable_ai/install"
        private const val APK_MIME = "application/vnd.android.package-archive"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("BAD_PATH", "APK path is empty", null)
                    return@setMethodCallHandler
                }

                val apk = File(path)
                if (!apk.isFile) {
                    result.error("APK_NOT_FOUND", "No APK at: $path", null)
                    return@setMethodCallHandler
                }

                try {
                    // Android 8.0+: "Bu kaynaktan izin ver" kullanıcı ayarı.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !packageManager.canRequestPackageInstalls()
                    ) {
                        val settingsIntent = Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(settingsIntent)
                        result.success("permission_required")
                        return@setMethodCallHandler
                    }

                    val apkUri = FileProvider.getUriForFile(
                        this,
                        "$packageName.fileprovider",
                        apk
                    )

                    val installIntent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(apkUri, APK_MIME)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }

                    startActivity(installIntent)
                    result.success("installer_launched")
                } catch (e: Exception) {
                    result.error("INSTALL_LAUNCH_FAILED", e.message, null)
                }
            }
    }
}
