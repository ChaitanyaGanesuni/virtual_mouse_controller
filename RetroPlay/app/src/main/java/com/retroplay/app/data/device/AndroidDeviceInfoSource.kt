package com.retroplay.app.data.device

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.view.Display
import com.retroplay.app.compatibility.device.DeviceInfoSource
import com.retroplay.app.domain.model.CpuInfo
import com.retroplay.app.domain.model.DeviceIdentity
import com.retroplay.app.domain.model.DisplayInfo
import com.retroplay.app.domain.model.GraphicsApiSupport
import com.retroplay.app.domain.model.MemorySnapshot
import com.retroplay.app.domain.model.OsInfo
import com.retroplay.app.domain.model.StorageSnapshot
import com.retroplay.app.domain.model.ThermalStatus
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/** [DeviceInfoSource] backed by public, permission-free Android APIs. */
@Singleton
class AndroidDeviceInfoSource @Inject constructor(
    @ApplicationContext private val context: Context,
) : DeviceInfoSource {

    private val activityManager: ActivityManager
        get() = context.getSystemService(ActivityManager::class.java)

    override fun identity() = DeviceIdentity(
        manufacturer = Build.MANUFACTURER,
        brand = Build.BRAND,
        model = Build.MODEL,
        deviceCodename = Build.DEVICE,
        socManufacturer = Build.SOC_MANUFACTURER.knownOrNull(),
        socModel = Build.SOC_MODEL.knownOrNull(),
    )

    override fun os() = OsInfo(
        release = Build.VERSION.RELEASE,
        apiLevel = Build.VERSION.SDK_INT,
        securityPatch = Build.VERSION.SECURITY_PATCH.knownOrNull(),
        buildDisplayId = Build.DISPLAY,
    )

    override fun cpu(): CpuInfo {
        val cores = Runtime.getRuntime().availableProcessors()
        return CpuInfo(
            supportedAbis = Build.SUPPORTED_ABIS.toList(),
            is64BitCapable = Build.SUPPORTED_64_BIT_ABIS.isNotEmpty(),
            coreCount = cores,
            coreMaxFrequenciesKhz = (0 until cores).mapNotNull { readCpuMaxFrequencyKhz(it) },
        )
    }

    override fun memory(): MemorySnapshot {
        val am = activityManager
        val info = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        return MemorySnapshot(
            totalBytes = info.totalMem,
            availableBytes = info.availMem,
            lowMemoryThresholdBytes = info.threshold,
            isLowMemory = info.lowMemory,
            appMemoryClassMb = am.memoryClass,
            largeAppMemoryClassMb = am.largeMemoryClass,
        )
    }

    override fun graphicsApis(): GraphicsApiSupport {
        val pm = context.packageManager
        // Platform type: may be null on some builds, so treat it as nullable.
        val features: Array<android.content.pm.FeatureInfo>? = pm.systemAvailableFeatures
        return GraphicsApiSupport(
            openGlEsVersion = activityManager.deviceConfigurationInfo?.glEsVersion,
            hasAndroidExtensionPack = pm.hasSystemFeature(PackageManager.FEATURE_OPENGLES_EXTENSION_PACK),
            vulkanApiVersion = detectVulkanVersion(pm),
            vulkanHardwareLevel = features?.firstOrNull { it.name == PackageManager.FEATURE_VULKAN_HARDWARE_LEVEL }?.version,
        )
    }

    override fun display(): DisplayInfo {
        val display = context.getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
        val metrics = context.resources.displayMetrics
        if (display == null) {
            return DisplayInfo(metrics.widthPixels, metrics.heightPixels, metrics.densityDpi, 0f, emptyList(), false)
        }
        val mode = display.mode
        // Refresh rates offered at the current physical resolution.
        val rates = display.supportedModes
            .filter { it.physicalWidth == mode.physicalWidth && it.physicalHeight == mode.physicalHeight }
            .map { it.refreshRate }
            .distinct()
            .sorted()
        return DisplayInfo(
            widthPx = mode.physicalWidth,
            heightPx = mode.physicalHeight,
            densityDpi = metrics.densityDpi,
            currentRefreshRateHz = display.refreshRate,
            supportedRefreshRatesHz = rates,
            isHdrCapable = display.isHdr,
        )
    }

    override fun storage(): StorageSnapshot {
        val stat = StatFs(Environment.getDataDirectory().path)
        return StorageSnapshot(availableBytes = stat.availableBytes, totalBytes = stat.totalBytes)
    }

    override fun thermalStatus(): ThermalStatus {
        val pm = context.getSystemService(PowerManager::class.java) ?: return ThermalStatus.UNKNOWN
        return when (pm.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE -> ThermalStatus.NONE
            PowerManager.THERMAL_STATUS_LIGHT -> ThermalStatus.LIGHT
            PowerManager.THERMAL_STATUS_MODERATE -> ThermalStatus.MODERATE
            PowerManager.THERMAL_STATUS_SEVERE -> ThermalStatus.SEVERE
            PowerManager.THERMAL_STATUS_CRITICAL -> ThermalStatus.CRITICAL
            PowerManager.THERMAL_STATUS_EMERGENCY -> ThermalStatus.EMERGENCY
            PowerManager.THERMAL_STATUS_SHUTDOWN -> ThermalStatus.SHUTDOWN
            else -> ThermalStatus.UNKNOWN
        }
    }

    private fun detectVulkanVersion(pm: PackageManager): String? {
        // FEATURE_VULKAN_HARDWARE_VERSION encodes VK_MAKE_API_VERSION(0, major, minor, 0).
        for (minor in MAX_VULKAN_MINOR downTo 0) {
            val encoded = (1 shl 22) or (minor shl 12)
            if (pm.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION, encoded)) return "1.$minor"
        }
        return null
    }

    private fun readCpuMaxFrequencyKhz(core: Int): Long? = try {
        File("/sys/devices/system/cpu/cpu$core/cpufreq/cpuinfo_max_freq").readText().trim().toLongOrNull()
    } catch (_: Exception) {
        null // Not readable under this device's SELinux policy.
    }

    private fun String?.knownOrNull(): String? = this?.takeIf { it.isNotBlank() && it != Build.UNKNOWN }

    private companion object {
        const val MAX_VULKAN_MINOR = 4
    }
}
