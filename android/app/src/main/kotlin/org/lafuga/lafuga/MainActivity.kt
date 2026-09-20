package org.lafuga.lafuga

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Activité principale.
 *
 * Elle expose à Dart les trois gestes que l'app Kivy fait par jnius
 * (`_android_notif_permission_granted`, `_android_request_notif_permission`,
 * `_android_open_notif_settings`) : savoir si les notifications sont
 * autorisées, les demander, et ouvrir les réglages du téléphone.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "org.lafuga/notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "granted" -> result.success(notificationsGranted())
                    "request" -> { requestNotifications(); result.success(null) }
                    "openSettings" -> { openNotificationSettings(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    /** Vrai avant Android 13, où la permission n'existe pas encore. */
    private fun notificationsGranted(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return checkSelfPermission("android.permission.POST_NOTIFICATIONS") == 0
    }

    private fun requestNotifications() {
        if (Build.VERSION.SDK_INT < 33) return
        if (notificationsGranted()) return
        requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 0)
    }

    /** Écran des notifications de l'appli ; à défaut, sa fiche détaillée. */
    private fun openNotificationSettings() {
        try {
            val intent = Intent("android.settings.APP_NOTIFICATION_SETTINGS")
            intent.putExtra("android.provider.extra.APP_PACKAGE", packageName)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            val intent = Intent("android.settings.APPLICATION_DETAILS_SETTINGS")
            intent.data = Uri.parse("package:$packageName")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        }
    }
}
