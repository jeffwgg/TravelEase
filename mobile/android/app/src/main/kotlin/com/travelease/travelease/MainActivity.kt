package com.travelease.travelease

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "travelease/accessibility_alerts"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "vibrate" -> vibrate(call.argument<String>("strength") ?: "medium", result)
                    "flash" -> flash(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun vibrate(strength: String, result: MethodChannel.Result) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (!vibrator.hasVibrator()) {
            result.error("UNAVAILABLE", "This device does not have a vibrator.", null)
            return
        }
        val (duration, amplitude) = when (strength) {
            "light" -> 120L to 80
            "strong" -> 500L to 255
            else -> 250L to 160
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(duration, amplitude))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(duration)
        }
        result.success(null)
    }

    private fun flash(result: MethodChannel.Result) {
        try {
            val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraId = manager.cameraIdList.firstOrNull { id ->
                manager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            } ?: run {
                result.error("UNAVAILABLE", "This device does not have a camera flash.", null)
                return
            }
            manager.setTorchMode(cameraId, true)
            window.decorView.postDelayed({
                try { manager.setTorchMode(cameraId, false) } catch (_: Exception) {}
            }, 1000)
            result.success(null)
        } catch (error: SecurityException) {
            result.error("PERMISSION", "Camera permission is required to test the flash.", null)
        } catch (error: Exception) {
            result.error("UNAVAILABLE", "The flashlight is currently unavailable.", null)
        }
    }
}
