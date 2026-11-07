package com.retroplay.app.compatibility.device

import com.retroplay.app.domain.model.CpuInfo
import com.retroplay.app.domain.model.DeviceIdentity
import com.retroplay.app.domain.model.DisplayInfo
import com.retroplay.app.domain.model.GpuInfo
import com.retroplay.app.domain.model.GraphicsApiSupport
import com.retroplay.app.domain.model.MemorySnapshot
import com.retroplay.app.domain.model.OsInfo
import com.retroplay.app.domain.model.StorageSnapshot
import com.retroplay.app.domain.model.ThermalStatus

/** Reads runtime device information from the platform. Calls may block; invoke off the main thread. */
interface DeviceInfoSource {
    fun identity(): DeviceIdentity
    fun os(): OsInfo
    fun cpu(): CpuInfo
    fun memory(): MemorySnapshot
    fun graphicsApis(): GraphicsApiSupport
    fun display(): DisplayInfo
    fun storage(): StorageSnapshot
    fun thermalStatus(): ThermalStatus
}

/** Queries the GPU driver strings. Implementations must never throw; failures map to [GpuInfo.unavailable]. */
fun interface GpuInfoProvider {
    fun queryGpuInfo(): GpuInfo
}
