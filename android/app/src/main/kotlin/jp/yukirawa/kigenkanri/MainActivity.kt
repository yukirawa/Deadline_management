package jp.yukirawa.kigenkanri

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UPDATE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "canRequestPackageInstalls" -> {
                        result.success(canRequestPackageInstalls())
                    }

                    "openInstallPermissionSettings" -> {
                        result.success(openInstallPermissionSettings())
                    }

                    "installApk" -> {
                        installApk(call)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            } catch (error: IllegalArgumentException) {
                result.error("invalid_args", error.message, null)
            } catch (error: IllegalStateException) {
                result.error("invalid_state", error.message, null)
            } catch (error: Exception) {
                result.error("install_failed", error.message, null)
            }
        }
    }

    private fun canRequestPackageInstalls(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return true
        }
        return packageManager.canRequestPackageInstalls()
    }

    private fun openInstallPermissionSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }

        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
            data = Uri.parse("package:$packageName")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        if (intent.resolveActivity(packageManager) == null) {
            return false
        }

        startActivity(intent)
        return true
    }

    private fun installApk(call: MethodCall) {
        val filePath = call.argument<String>("filePath")
            ?: throw IllegalArgumentException("filePath is required.")
        val apkFile = File(filePath)
        if (!apkFile.exists()) {
            throw IllegalStateException("APK file does not exist: $filePath")
        }

        val contentUri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apkFile,
        )
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(contentUri, "application/vnd.android.package-archive")
            flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK
            putExtra(Intent.EXTRA_RETURN_RESULT, false)
        }

        if (intent.resolveActivity(packageManager) == null) {
            throw IllegalStateException("No package installer is available.")
        }

        startActivity(intent)
    }
}

private const val UPDATE_CHANNEL = "jp.yukirawa.kigenkanri/app_updater"
