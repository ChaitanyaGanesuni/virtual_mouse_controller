package com.retroplay.app.domain.model

/**
 * A snapshot of the device's hardware and software, measured at runtime.
 * Nothing here is hard-coded: every value comes from Android platform APIs.
 * Nullable fields mean "not exposed by this device / OS".
 */
data class DeviceProfile(
    val capturedAtEpochMillis: Long,
    val identity: DeviceIdentity,
    val os: OsInfo,
    val cpu: CpuInfo,
    val memory: MemorySnapshot,
    val gpu: GpuInfo,
    val graphicsApis: GraphicsApiSupport,
    val display: DisplayInfo,
    val storage: StorageSnapshot,
    val thermalStatus: ThermalStatus,
)

data class DeviceIdentity(
    val manufacturer: String,
    val brand: String,
    val model: String,
    val deviceCodename: String,
    val socManufacturer: String?,
    val socModel: String?,
)

data class OsInfo(
    val release: String,
    val apiLevel: Int,
    val securityPatch: String?,
    val buildDisplayId: String,
)

data class CpuInfo(
    val supportedAbis: List<String>,
    val is64BitCapable: Boolean,
    val coreCount: Int,
    /** Per-core maximum frequency in kHz, empty when sysfs is not readable by apps. */
    val coreMaxFrequenciesKhz: List<Long>,
) {
    val primaryAbi: String? get() = supportedAbis.firstOrNull()
}

data class MemorySnapshot(
    /** Memory visible to the OS; lower than installed RAM because firmware/carve-outs reserve some. */
    val totalBytes: Long,
    val availableBytes: Long,
    val lowMemoryThresholdBytes: Long,
    val isLowMemory: Boolean,
    val appMemoryClassMb: Int,
    val largeAppMemoryClassMb: Int,
)

data class GpuInfo(
    val renderer: String?,
    val vendor: String?,
    val glVersion: String?,
    val glslVersion: String?,
    val eglVersion: String?,
    val errorMessage: String? = null,
) {
    val isAvailable: Boolean get() = renderer != null

    companion object {
        fun unavailable(reason: String) = GpuInfo(null, null, null, null, null, reason)
    }
}

data class GraphicsApiSupport(
    /** OpenGL ES version advertised by the device configuration, e.g. "3.2". */
    val openGlEsVersion: String?,
    val hasAndroidExtensionPack: Boolean,
    /** Highest Vulkan API version advertised via system features, e.g. "1.3"; null if none. */
    val vulkanApiVersion: String?,
    val vulkanHardwareLevel: Int?,
)

data class DisplayInfo(
    val widthPx: Int,
    val heightPx: Int,
    val densityDpi: Int,
    val currentRefreshRateHz: Float,
    val supportedRefreshRatesHz: List<Float>,
    val isHdrCapable: Boolean,
) {
    val maxRefreshRateHz: Float get() = supportedRefreshRatesHz.maxOrNull() ?: currentRefreshRateHz
}

data class StorageSnapshot(
    val availableBytes: Long,
    val totalBytes: Long,
)

enum class ThermalStatus(val label: String) {
    NONE("Normal"),
    LIGHT("Light throttling"),
    MODERATE("Moderate throttling"),
    SEVERE("Severe throttling"),
    CRITICAL("Critical"),
    EMERGENCY("Emergency"),
    SHUTDOWN("Shutdown imminent"),
    UNKNOWN("Unknown"),
}
