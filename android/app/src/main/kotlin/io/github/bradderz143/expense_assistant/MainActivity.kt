package io.github.bradderz143.expense_assistant

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "sendToOneDrive") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path == null) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                try {
                    result.success(sendToOneDrive(File(path)))
                } catch (e: Exception) {
                    result.error("send_failed", e.message, null)
                }
            }
    }

    /** Hands the file straight to the OneDrive app. False if it is not installed. */
    private fun sendToOneDrive(source: File): Boolean {
        if (packageManager.getLaunchIntentForPackage(ONEDRIVE) == null) return false
        // Our documents folder is outside what FileProvider can serve, so copy
        // the file into the cache first.
        val dir = File(cacheDir, "onedrive").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val copy = File(dir, source.name)
        source.copyTo(copy, overwrite = true)
        val uri = FileProvider.getUriForFile(this, "$packageName.onedrive", copy)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = if (copy.name.endsWith(".zip")) "application/zip" else "*/*"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, copy.name)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            setPackage(ONEDRIVE)
        }
        if (intent.resolveActivity(packageManager) == null) return false
        startActivity(intent)
        return true
    }

    companion object {
        private const val CHANNEL = "expense_assistant/onedrive"
        private const val ONEDRIVE = "com.microsoft.skydrive"
    }
}
