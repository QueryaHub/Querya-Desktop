package `in`.qoder.refresh_rate

import android.app.Activity
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.PowerManager
import android.view.Display
import android.view.Surface
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import `in`.qoder.refresh_rate.generated.DisplayInfoMessage
import `in`.qoder.refresh_rate.generated.RefreshRateFlutterApi
import `in`.qoder.refresh_rate.generated.RefreshRateHostApi

class RefreshRatePlugin : FlutterPlugin, ActivityAware, RefreshRateHostApi {

    private var activity: Activity? = null
    private var context: Context? = null
    private var flutterApi: RefreshRateFlutterApi? = null
    private var displayListener: DisplayManager.DisplayListener? = null

    // ─── FlutterPlugin ──────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        RefreshRateHostApi.setUp(binding.binaryMessenger, this)
        flutterApi = RefreshRateFlutterApi(binding.binaryMessenger)
        registerDisplayListener()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        RefreshRateHostApi.setUp(binding.binaryMessenger, null)
        unregisterDisplayListener()
        flutterApi = null
    }

    // ─── ActivityAware ──────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }

    // ─── RefreshRateHostApi ─────────────────────────────────────

    override fun getDisplayInfo(): DisplayInfoMessage {
        val display = getDisplay()
        val currentRate = display?.refreshRate?.toDouble() ?: 60.0
        val modes = display?.supportedModes ?: emptyArray()
        val supportedRates = modes.map { it.refreshRate.toDouble() }.distinct().sorted()
        val maxRate = supportedRates.maxOrNull() ?: 60.0
        val minRate = supportedRates.minOrNull() ?: 60.0
        val isVRR = (maxRate - minRate > 30) && modes.size <= 4
        val pm = context?.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val thermalIndex: Long? = if (Build.VERSION.SDK_INT >= 29) {
            when (pm?.currentThermalStatus) {
                PowerManager.THERMAL_STATUS_NONE -> 0L
                PowerManager.THERMAL_STATUS_LIGHT, PowerManager.THERMAL_STATUS_MODERATE -> 1L
                PowerManager.THERMAL_STATUS_SEVERE -> 2L
                PowerManager.THERMAL_STATUS_CRITICAL,
                PowerManager.THERMAL_STATUS_EMERGENCY,
                PowerManager.THERMAL_STATUS_SHUTDOWN -> 3L
                else -> null
            }
        } else null

        // hasArrSupport() is API 36+ — fall back to VRR heuristic for now
        val hasArr = isVRR

        return DisplayInfoMessage(
            currentRate = currentRate,
            maxRate = maxRate,
            minRate = minRate,
            supportedRates = supportedRates,
            isVariableRefreshRate = isVRR,
            engineTargetRate = currentRate,
            androidApiLevel = Build.VERSION.SDK_INT.toLong(),
            isLowPowerMode = pm?.isPowerSaveMode,
            thermalStateIndex = thermalIndex,
            hasAdaptiveRefreshRate = hasArr,
            iosProMotionEnabled = null,
            displayServer = null,
            monitorCount = null,
        )
    }

    override fun enable() = setDeviceDefault()
    override fun disable() = resetToDefault()
    override fun preferMax() = setDeviceDefault()
    override fun preferDefault() = resetToDefault()

    override fun matchContent(fps: Double) {
        if (Build.VERSION.SDK_INT >= 30) {
            setSurfaceFrameRate(fps.toFloat(), Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE, forceAlways = true)
        } else if (Build.VERSION.SDK_INT >= 23) {
            setPreferredDisplayMode(fps.toFloat())
        }
    }

    override fun boost(durationMs: Long) {
        val display = getDisplay() ?: return
        val maxRate = display.supportedModes.maxByOrNull { it.refreshRate }?.refreshRate ?: 60f
        if (Build.VERSION.SDK_INT >= 35) {
            try { activity?.window?.decorView?.setRequestedFrameRate(View.REQUESTED_FRAME_RATE_CATEGORY_HIGH.toFloat()) } catch (_: Exception) {}
        }
        setSurfaceFrameRate(maxRate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT, forceAlways = true)
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ resetToDefault() }, durationMs)
    }

    override fun setCategory(categoryIndex: Long) {
        if (Build.VERSION.SDK_INT < 35) {
            when (categoryIndex.toInt()) {
                3 -> setDeviceDefault()
                0, 1 -> resetToDefault()
                else -> {}
            }
            return
        }
        try {
            val categoryFloat = when (categoryIndex.toInt()) {
                0 -> 0f
                1 -> View.REQUESTED_FRAME_RATE_CATEGORY_LOW.toFloat()
                2 -> View.REQUESTED_FRAME_RATE_CATEGORY_NORMAL.toFloat()
                3 -> View.REQUESTED_FRAME_RATE_CATEGORY_HIGH.toFloat()
                else -> View.REQUESTED_FRAME_RATE_CATEGORY_HIGH.toFloat()
            }
            activity?.window?.decorView?.setRequestedFrameRate(categoryFloat)
        } catch (_: Exception) {}
    }

    override fun setTouchBoost(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= 35) {
            try { activity?.window?.setFrameRateBoostOnTouchEnabled(enabled) } catch (_: Exception) {}
        }
    }

    override fun isSupported(): Boolean = Build.VERSION.SDK_INT >= 23

    // ─── Private helpers ────────────────────────────────────────

    private fun setDeviceDefault() {
        val display = getDisplay() ?: return
        val maxRate = display.supportedModes.maxByOrNull { it.refreshRate }?.refreshRate ?: 60f
        if (Build.VERSION.SDK_INT >= 35) {
            try {
                val window = activity?.window
                window?.decorView?.setRequestedFrameRate(View.REQUESTED_FRAME_RATE_CATEGORY_HIGH.toFloat())
                window?.setFrameRateBoostOnTouchEnabled(true)
            } catch (_: Exception) {}
            setSurfaceFrameRate(maxRate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        } else if (Build.VERSION.SDK_INT >= 30) {
            setSurfaceFrameRate(maxRate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        } else if (Build.VERSION.SDK_INT >= 23) {
            setPreferredDisplayMode(maxRate)
        }
    }

    private fun resetToDefault() {
        if (Build.VERSION.SDK_INT >= 35) {
            try {
                val window = activity?.window
                window?.decorView?.setRequestedFrameRate(0f)
                window?.setFrameRateBoostOnTouchEnabled(false)
            } catch (_: Exception) {}
            setSurfaceFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        } else if (Build.VERSION.SDK_INT >= 30) {
            setSurfaceFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        } else if (Build.VERSION.SDK_INT >= 23) {
            try {
                val params = activity?.window?.attributes ?: return
                params.preferredDisplayModeId = 0
                activity?.window?.attributes = params
            } catch (_: Exception) {}
        }
    }

    private fun setSurfaceFrameRate(frameRate: Float, compatibility: Int, forceAlways: Boolean = false): Boolean {
        if (Build.VERSION.SDK_INT < 30) return false
        return try {
            val window = activity?.window ?: return false
            val strategy = if (Build.VERSION.SDK_INT >= 31) {
                if (forceAlways) Surface.CHANGE_FRAME_RATE_ALWAYS
                else Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS
            } else -1
            val params = window.attributes
            params.preferredRefreshRate = frameRate
            val display = getDisplay()
            if (display != null && frameRate > 0) {
                val targetMode = display.supportedModes
                    .filter { it.refreshRate >= frameRate - 1f }
                    .minByOrNull { Math.abs(it.refreshRate - frameRate) }
                if (targetMode != null) params.preferredDisplayModeId = targetMode.modeId
            } else if (frameRate == 0f) {
                params.preferredDisplayModeId = 0
                params.preferredRefreshRate = 0f
            }
            window.attributes = params
            true
        } catch (e: Exception) { false }
    }

    private fun setPreferredDisplayMode(targetRate: Float): Boolean {
        if (Build.VERSION.SDK_INT < 23) return false
        return try {
            val window = activity?.window ?: return false
            val display = getDisplay() ?: return false
            val currentMode = display.mode
            val targetMode = display.supportedModes
                .filter { it.physicalWidth == currentMode.physicalWidth && it.physicalHeight == currentMode.physicalHeight }
                .minByOrNull { Math.abs(it.refreshRate - targetRate) }
            if (targetMode != null) {
                val params = window.attributes
                params.preferredDisplayModeId = targetMode.modeId
                window.attributes = params
                true
            } else false
        } catch (e: Exception) { false }
    }

    private fun registerDisplayListener() {
        val dm = context?.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager ?: return
        displayListener = object : DisplayManager.DisplayListener {
            override fun onDisplayChanged(displayId: Int) {
                activity?.runOnUiThread { flutterApi?.onDisplayInfoChanged(getDisplayInfo()) {} }
            }
            override fun onDisplayAdded(displayId: Int) {}
            override fun onDisplayRemoved(displayId: Int) {}
        }
        dm.registerDisplayListener(displayListener, null)
    }

    private fun unregisterDisplayListener() {
        val dm = context?.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager ?: return
        displayListener?.let { dm.unregisterDisplayListener(it) }
        displayListener = null
    }

    @Suppress("DEPRECATION")
    private fun getDisplay(): Display? = if (Build.VERSION.SDK_INT >= 30) {
        activity?.display
    } else {
        (context?.getSystemService(Context.WINDOW_SERVICE) as? WindowManager)?.defaultDisplay
    }
}
