package com.travelease.travelease

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "travelease/speech_env"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getSpeechEnvironment") {
                    result.success(speechEnvironment())
                } else {
                    result.notImplemented()
                }
            }
    }

    /// Reports the raw OS-level speech environment so Flutter can decide
    /// between system TTS/ASR and HMS ML Kit. No assumptions are made:
    /// every value is read or queried from the running OS.
    private fun speechEnvironment(): Map<String, Any?> {
        val pm = packageManager

        val out = mutableMapOf<String, Any?>()
        out["deviceModel"] = "${Build.MANUFACTURER} ${Build.MODEL}"
        out["deviceProduct"] = Build.PRODUCT
        out["osRelease"] = Build.VERSION.RELEASE
        out["osSdkInt"] = Build.VERSION.SDK_INT
        out["harmonyVersion"] = getSystemProperty("ro.build.version.harmony")

        // Default engines configured in Settings > Text-to-speech output /
        // voice input. Reading Secure settings needs no permission.
        out["defaultTtsEngine"] =
            Settings.Secure.getString(contentResolver, Settings.Secure.TTS_DEFAULT_SYNTH)
        out["defaultRecognitionService"] =
            Settings.Secure.getString(contentResolver, "voice_recognition_service")

        out["recognizerAvailable"] = try {
            SpeechRecognizer.isRecognitionAvailable(this)
        } catch (t: Throwable) {
            "error: ${t.message}"
        }

        // Every installed RecognitionService (the ASR backend of speech_to_text).
        out["recognitionServices"] = queryServices("android.speech.RecognitionService", pm)
            .plus(legacyRecognitionActivities(pm))

        // Every installed TTS engine service.
        out["ttsServices"] = queryServices("android.intent.action.TTS_SERVICE", pm)

        // Relevant Huawei packages. Reported with installed flags instead of
        // assumed - presence decides capability.
        out["packages"] = listOf(
            "com.huawei.android.hwid",      // HMS Core (APK) - required by ML Kit
            "com.huawei.hwid",              // HUAWEI ID
            "com.huawei.appmarket",         // AppGallery (HMS Core updates)
            "com.baidu.input_huawei",       // Celia Keyboard
            "com.touchtype.swiftkey",       // SwiftKey
            "com.huawei.vassistant",        // AI Voice / 小艺 (CN builds)
            "com.huawei.hiassistantoversea" // Celia Assistant (overseas builds)
        ).associateWith { packageInfo(it, pm) }

        return out
    }

    private fun queryServices(action: String, pm: PackageManager): List<Map<String, String?>> {
        val services = mutableListOf<Map<String, String?>>()
        try {
            val infos = pm.queryIntentServices(Intent(action), PackageManager.GET_META_DATA)
            for (ri in infos) {
                services.add(
                    mapOf(
                        "package" to ri.serviceInfo.packageName,
                        "label" to ri.loadLabel(pm).toString(),
                        "className" to ri.serviceInfo.name
                    )
                )
            }
        } catch (_: Exception) {
            // Package visibility restrictions - report what we can.
        }
        return services
    }

    /// Older ROMs expose recognizers as activities handling
    /// RecognizerIntent.ACTION_RECOGNIZE_SPEECH rather than services.
    private fun legacyRecognitionActivities(pm: PackageManager): List<Map<String, String?>> {
        val activities = mutableListOf<Map<String, String?>>()
        try {
            val intent = Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .addCategory(Intent.CATEGORY_DEFAULT)
            for (ri in pm.queryIntentActivities(intent, 0)) {
                activities.add(
                    mapOf(
                        "package" to ri.activityInfo.packageName,
                        "label" to ri.loadLabel(pm).toString(),
                        "className" to ri.activityInfo.name,
                        "kind" to "activity"
                    )
                )
            }
        } catch (_: Exception) {
        }
        return activities
    }

    private fun packageInfo(name: String, pm: PackageManager): Map<String, Any?> {
        return try {
            val pi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageInfo(name, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(name, 0)
            }
            mapOf(
                "installed" to true,
                "versionName" to pi.versionName,
                "versionCode" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    pi.longVersionCode
                } else {
                    @Suppress("DEPRECATION") pi.versionCode.toLong()
                },
                "label" to pi.applicationInfo?.let { pm.getApplicationLabel(it) }.toString()
            )
        } catch (_: Exception) {
            mapOf<String, Any?>("installed" to false)
        }
    }

    private fun getSystemProperty(key: String): String? {
        return try {
            Class.forName("android.os.SystemProperties")
                .getMethod("get", String::class.java)
                .invoke(null, key) as? String
        } catch (_: Exception) {
            null
        }
    }
}
