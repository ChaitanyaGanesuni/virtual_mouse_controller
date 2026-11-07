package com.retroplay.app.data.device

import android.app.ActivityManager
import android.content.Context
import android.os.Environment
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.retroplay.app.domain.model.ThermalStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowStatFs

/** Runs the real platform-reading code against Robolectric's simulated Android 15 framework. */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class AndroidDeviceInfoSourceTest {

    private lateinit var context: Context
    private lateinit var source: AndroidDeviceInfoSource

    @Before fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        source = AndroidDeviceInfoSource(context)
    }

    @Test fun reportsAndroidApiLevel() {
        assertEquals(35, source.os().apiLevel)
    }

    @Test fun reportsCpuArchitectureAndCores() {
        val cpu = source.cpu()
        assertTrue(cpu.supportedAbis.isNotEmpty())
        assertTrue(cpu.coreCount > 0)
    }

    @Test fun reportsMemoryFromActivityManager() {
        val am = context.getSystemService(ActivityManager::class.java)
        val info = ActivityManager.MemoryInfo().apply {
            totalMem = 11L * 1024 * 1024 * 1024
            availMem = 4L * 1024 * 1024 * 1024
            threshold = 256L * 1024 * 1024
            lowMemory = false
        }
        shadowOf(am).setMemoryInfo(info)

        val memory = source.memory()
        assertEquals(info.totalMem, memory.totalBytes)
        assertEquals(info.availMem, memory.availableBytes)
        assertFalse(memory.isLowMemory)
    }

    @Test fun reportsStorageFromStatFs() {
        ShadowStatFs.registerStats(Environment.getDataDirectory(), 1000, 400, 300)
        val storage = source.storage()
        assertEquals(1000L * 4096, storage.totalBytes)
        assertEquals(300L * 4096, storage.availableBytes)
    }

    @Test fun reportsDisplayMetrics() {
        val display = source.display()
        assertTrue(display.widthPx > 0 && display.heightPx > 0)
        assertTrue(display.currentRefreshRateHz > 0f)
        assertTrue(display.maxRefreshRateHz >= display.currentRefreshRateHz)
    }

    @Test fun reportsThermalStatusAndGraphicsApisWithoutCrashing() {
        assertEquals(ThermalStatus.NONE, source.thermalStatus())
        source.graphicsApis() // Vulkan/GLES feature flags are device-specific; must simply not throw.
    }
}
