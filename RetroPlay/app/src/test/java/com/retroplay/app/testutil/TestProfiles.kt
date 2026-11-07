package com.retroplay.app.testutil

import com.retroplay.app.domain.model.CpuInfo
import com.retroplay.app.domain.model.DeviceIdentity
import com.retroplay.app.domain.model.DeviceProfile
import com.retroplay.app.domain.model.DisplayInfo
import com.retroplay.app.domain.model.GpuInfo
import com.retroplay.app.domain.model.GraphicsApiSupport
import com.retroplay.app.domain.model.MemorySnapshot
import com.retroplay.app.domain.model.OsInfo
import com.retroplay.app.domain.model.StorageSnapshot
import com.retroplay.app.domain.model.ThermalStatus

/** Synthetic fixtures for tests. These are NOT real measurements of any device. */
object TestProfiles {
    const val GIB = 1024L * 1024L * 1024L

    fun pixel9Like(): DeviceProfile = DeviceProfile(
        capturedAtEpochMillis = 1_700_000_000_000L,
        identity = DeviceIdentity("Google", "google", "Pixel 9", "tokay", "Google", "Tensor G4"),
        os = OsInfo("15", 35, "2025-01-05", "TEST.BUILD"),
        cpu = CpuInfo(listOf("arm64-v8a"), true, 8, listOf(1_950_000, 2_600_000, 2_600_000, 3_100_000)),
        memory = MemorySnapshot((11.2 * GIB).toLong(), 5 * GIB, GIB / 4, false, 256, 512),
        gpu = GpuInfo("Mali-G715", "ARM", "OpenGL ES 3.2 v1.r00", "OpenGL ES GLSL ES 3.20", "1.5"),
        graphicsApis = GraphicsApiSupport("3.2", true, "1.3", 1),
        display = DisplayInfo(1080, 2424, 420, 60f, listOf(60f, 120f), true),
        storage = StorageSnapshot(64_000_000_000L, 128_000_000_000L),
        thermalStatus = ThermalStatus.NONE,
    )

    fun midRangeOther(): DeviceProfile = pixel9Like().copy(
        identity = DeviceIdentity("Acme", "acme", "Phone X", "phonex", null, null),
        os = OsInfo("14", 34, null, "OTHER"),
        cpu = CpuInfo(listOf("armeabi-v7a", "armeabi"), false, 4, emptyList()),
        memory = MemorySnapshot(4 * GIB, GIB, GIB / 8, true, 128, 256),
        gpu = GpuInfo.unavailable("No EGL display"),
        graphicsApis = GraphicsApiSupport("3.0", false, null, null),
        display = DisplayInfo(720, 1600, 320, 60f, listOf(60f), false),
    )
}
