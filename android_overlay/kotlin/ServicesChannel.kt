package __PKG__

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Storage, sound, and Android permissions for the Dart side. */
class ServicesChannel(private val activity: Activity, engine: FlutterEngine) : MethodChannel.MethodCallHandler {
    private val ctx = activity.applicationContext
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "chess3d/services")
    private var networkPermissionRequest: MethodChannel.Result? = null
    private val prefs = ctx.getSharedPreferences("chess3d", Context.MODE_PRIVATE)
    private val sounds = HashMap<String, Int>()
    private val pool: SoundPool = SoundPool.Builder()
        .setMaxStreams(4)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        )
        .build()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "storeGetAll" -> {
                    val out = HashMap<String, String>()
                    for ((k, v) in prefs.all) if (v is String) out[k] = v
                    result.success(out)
                }
                "storeSet" -> {
                    prefs.edit().putString(call.argument<String>("key"), call.argument<String>("value")).apply()
                    result.success(null)
                }
                "storeRemove" -> {
                    prefs.edit().remove(call.argument<String>("key")).apply()
                    result.success(null)
                }
                "requestLocalNetworkPermission" -> requestLocalNetworkPermission(result)
                "sfxLoad" -> {
                    val name = call.argument<String>("name") ?: throw IllegalArgumentException("name")
                    val wav = call.argument<ByteArray>("wav") ?: throw IllegalArgumentException("wav")
                    val isMp3 = wav.size > 2 && ((wav[0] == 0x49.toByte() && wav[1] == 0x44.toByte()) || (wav[0] == 0xFF.toByte() && (wav[1].toInt() and 0xE0) == 0xE0))
                    val f = File(ctx.cacheDir, if (isMp3) "sfx_$name.mp3" else "sfx_$name.wav")
                    f.writeBytes(wav)
                    sounds[name] = pool.load(f.absolutePath, 1)
                    result.success(null)
                }
                "deviceTier" -> {
                    val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val mi = ActivityManager.MemoryInfo()
                    am.getMemoryInfo(mi)
                    val gb = mi.totalMem / 1.0e9
                    val tier = when {
                        am.isLowRamDevice || gb < 3.0 || Build.VERSION.SDK_INT < 26 -> "low"
                        gb < 6.0 -> "medium"
                        else -> "high"
                    }
                    result.success(tier)
                }
                "sfxPlay" -> {
                    val id = sounds[call.argument<String>("name")]
                    if (id != null) pool.play(id, 1f, 1f, 1, 0, 1f)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("services", e.message, null)
        }
    }

    private fun requestLocalNetworkPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 37 ||
            activity.checkSelfPermission(Manifest.permission.ACCESS_LOCAL_NETWORK) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (networkPermissionRequest != null) {
            result.error("permission_in_progress", "Local network permission is already being requested.", null)
            return
        }
        networkPermissionRequest = result
        try {
            activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_LOCAL_NETWORK), LOCAL_NETWORK_REQUEST)
        } catch (e: Exception) {
            networkPermissionRequest = null
            throw e
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != LOCAL_NETWORK_REQUEST) return
        val pending = networkPermissionRequest
        networkPermissionRequest = null
        pending?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
    }

    fun dispose() {
        networkPermissionRequest?.success(false)
        networkPermissionRequest = null
        channel.setMethodCallHandler(null)
        pool.release()
    }

    private companion object {
        const val LOCAL_NETWORK_REQUEST = 3701
    }
}
