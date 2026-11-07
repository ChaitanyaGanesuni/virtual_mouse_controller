package com.retroplay.app.presentation.deviceinfo

import com.retroplay.app.core.util.Formatters
import com.retroplay.app.domain.model.DeviceProfile

enum class SectionKind { DEVICE, ANDROID, CPU, MEMORY, GPU, GRAPHICS_APIS, DISPLAY, STORAGE, THERMAL }

data class InfoSection(val kind: SectionKind, val title: String, val rows: List<Pair<String, String>>)

/** Maps a measured profile to display rows. Values that the platform does not expose are labelled as such. */
object DeviceInfoSections {
    private const val NOT_REPORTED = "Not reported"

    fun from(p: DeviceProfile): List<InfoSection> = listOf(
        InfoSection(
            SectionKind.DEVICE, "Device",
            listOf(
                "Model" to p.identity.model,
                "Manufacturer" to p.identity.manufacturer,
                "Brand" to p.identity.brand,
                "Codename" to p.identity.deviceCodename,
                "System on chip" to (listOfNotNull(p.identity.socManufacturer, p.identity.socModel)
                    .joinToString(" ").ifEmpty { NOT_REPORTED }),
            ),
        ),
        InfoSection(
            SectionKind.ANDROID, "Android",
            listOf(
                "Version" to "Android ${p.os.release}",
                "API level" to p.os.apiLevel.toString(),
                "Security patch" to (p.os.securityPatch ?: NOT_REPORTED),
                "Build" to p.os.buildDisplayId,
            ),
        ),
        InfoSection(
            SectionKind.CPU, "CPU",
            listOf(
                "Primary ABI" to (p.cpu.primaryAbi ?: NOT_REPORTED),
                "Supported ABIs" to p.cpu.supportedAbis.joinToString(", ").ifEmpty { NOT_REPORTED },
                "64-bit capable" to Formatters.yesNo(p.cpu.is64BitCapable),
                "Cores" to p.cpu.coreCount.toString(),
                "Max core clocks" to p.cpu.coreMaxFrequenciesKhz.distinct().sorted()
                    .joinToString(" / ") { Formatters.khzToGhz(it) }
                    .ifEmpty { "Not readable on this device" },
            ),
        ),
        InfoSection(
            SectionKind.MEMORY, "Memory",
            listOf(
                "Total (OS-visible)" to Formatters.bytes(p.memory.totalBytes, binary = true),
                "Available" to Formatters.bytes(p.memory.availableBytes, binary = true),
                "Low-memory threshold" to Formatters.bytes(p.memory.lowMemoryThresholdBytes, binary = true),
                "Low-memory state" to Formatters.yesNo(p.memory.isLowMemory),
                "App heap (standard / large)" to "${p.memory.appMemoryClassMb} MB / ${p.memory.largeAppMemoryClassMb} MB",
            ),
        ),
        InfoSection(
            SectionKind.GPU, "GPU",
            if (p.gpu.isAvailable) {
                listOf(
                    "Renderer" to (p.gpu.renderer ?: NOT_REPORTED),
                    "Vendor" to (p.gpu.vendor ?: NOT_REPORTED),
                    "OpenGL ES driver" to (p.gpu.glVersion ?: NOT_REPORTED),
                    "GLSL ES" to (p.gpu.glslVersion ?: NOT_REPORTED),
                    "EGL" to (p.gpu.eglVersion ?: NOT_REPORTED),
                )
            } else {
                listOf("Renderer" to "Not obtainable (${p.gpu.errorMessage ?: "unknown reason"})")
            },
        ),
        InfoSection(
            SectionKind.GRAPHICS_APIS, "Graphics APIs",
            listOf(
                "OpenGL ES" to (p.graphicsApis.openGlEsVersion ?: NOT_REPORTED),
                "Android Extension Pack" to Formatters.yesNo(p.graphicsApis.hasAndroidExtensionPack),
                "Vulkan" to (p.graphicsApis.vulkanApiVersion ?: NOT_REPORTED),
                "Vulkan hardware level" to (p.graphicsApis.vulkanHardwareLevel?.toString() ?: NOT_REPORTED),
            ),
        ),
        InfoSection(
            SectionKind.DISPLAY, "Display",
            listOf(
                "Resolution" to "${minOf(p.display.widthPx, p.display.heightPx)} × ${maxOf(p.display.widthPx, p.display.heightPx)} px",
                "Density" to "${p.display.densityDpi} dpi",
                "Current refresh rate" to Formatters.refreshRate(p.display.currentRefreshRateHz),
                "Max refresh rate" to Formatters.refreshRate(p.display.maxRefreshRateHz),
                "Supported refresh rates" to p.display.supportedRefreshRatesHz
                    .joinToString(", ") { Formatters.refreshRate(it) }.ifEmpty { NOT_REPORTED },
                "HDR" to Formatters.yesNo(p.display.isHdrCapable),
            ),
        ),
        InfoSection(
            SectionKind.STORAGE, "Internal storage",
            listOf(
                "Available" to Formatters.bytes(p.storage.availableBytes, binary = false),
                "Total" to Formatters.bytes(p.storage.totalBytes, binary = false),
            ),
        ),
        InfoSection(
            SectionKind.THERMAL, "Thermal",
            listOf("Status" to p.thermalStatus.label),
        ),
    )
}
