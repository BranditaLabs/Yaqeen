package com.yaqinbrand.yaqeen

import android.content.Intent
import android.hardware.GeomagneticField
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity (a FlutterActivity) keeps one engine for UI and background playback.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Small device calls with no plugin of their own (core/platform/*.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.yaqinbrand.yaqeen/device").setMethodCallHandler { call, result ->
            when (call.method) {
                // Magnetic declination (WMM) at the saved place: flutter_compass reports magnetic
                // north on Android, the Qibla bearing is a true bearing.
                "declination" -> {
                    val lat = call.argument<Double>("lat")
                    val lng = call.argument<Double>("lng")
                    if (lat == null || lng == null) {
                        result.error("bad_args", "lat and lng are required", null)
                    } else {
                        val field = GeomagneticField(lat.toFloat(), lng.toFloat(), 0f, System.currentTimeMillis())
                        result.success(field.declination.toDouble())
                    }
                }
                // «افتح الإعدادات» after notifications were denied: this app's notification page.
                "openNotificationSettings" -> {
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                    }
                    try {
                        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("unavailable", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
