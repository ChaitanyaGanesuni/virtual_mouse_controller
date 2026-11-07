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
import com.retroplay.app.testutil.TestProfiles
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Test

class DefaultDeviceProfileManagerTest {

    private val sample = TestProfiles.pixel9Like()

    private val source = object : DeviceInfoSource {
        override fun identity(): DeviceIdentity = sample.identity
        override fun os(): OsInfo = sample.os
        override fun cpu(): CpuInfo = sample.cpu
        override fun memory(): MemorySnapshot = sample.memory
        override fun graphicsApis(): GraphicsApiSupport = sample.graphicsApis
        override fun display(): DisplayInfo = sample.display
        override fun storage(): StorageSnapshot = sample.storage
        override fun thermalStatus(): ThermalStatus = sample.thermalStatus
    }

    @Test fun assemblesProfileFromSources() = runTest {
        val manager = DefaultDeviceProfileManager(source, { sample.gpu }, StandardTestDispatcher(testScheduler))
        val profile = manager.captureProfile()
        assertEquals(sample.copy(capturedAtEpochMillis = profile.capturedAtEpochMillis), profile)
        assertEquals("Google Pixel 9", manager.referenceProfile.displayName)
    }

    @Test fun successfulGpuQueryIsCached() = runTest {
        var calls = 0
        val manager = DefaultDeviceProfileManager(source, { calls++; sample.gpu }, StandardTestDispatcher(testScheduler))
        manager.captureProfile()
        manager.captureProfile()
        assertEquals(1, calls)
    }

    @Test fun gpuFailureIsReportedAsUnavailableAndRetried() = runTest {
        var calls = 0
        val manager = DefaultDeviceProfileManager(
            source,
            { calls++; throw IllegalStateException("driver error") },
            StandardTestDispatcher(testScheduler),
        )
        val profile = manager.captureProfile()
        assertFalse(profile.gpu.isAvailable)
        assertEquals("driver error", profile.gpu.errorMessage)
        manager.captureProfile()
        assertEquals(2, calls)
    }

    @Test fun unavailableGpuResultIsNotCached() = runTest {
        var calls = 0
        val manager = DefaultDeviceProfileManager(
            source,
            { calls++; GpuInfo.unavailable("no display") },
            StandardTestDispatcher(testScheduler),
        )
        manager.captureProfile()
        manager.captureProfile()
        assertEquals(2, calls)
    }

    @Test fun compareUsesPixel9Reference() = runTest {
        val manager = DefaultDeviceProfileManager(source, { sample.gpu }, StandardTestDispatcher(testScheduler))
        val rows = manager.compareWithReference(sample)
        assertSame(manager.referenceProfile.gpuName, rows.first { it.field.name == "GPU" }.reference)
    }
}
