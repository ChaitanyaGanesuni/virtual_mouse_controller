package com.retroplay.app.presentation.deviceinfo

import com.retroplay.app.testutil.TestProfiles
import org.junit.Assert.assertEquals
import org.junit.Test

class DeviceInfoSectionsTest {

    private fun rows(kind: SectionKind, profile: com.retroplay.app.domain.model.DeviceProfile) =
        DeviceInfoSections.from(profile).first { it.kind == kind }.rows.toMap()

    @Test fun mapsMeasuredValues() {
        val p = TestProfiles.pixel9Like()
        assertEquals("Mali-G715", rows(SectionKind.GPU, p)["Renderer"])
        assertEquals("1080 × 2424 px", rows(SectionKind.DISPLAY, p)["Resolution"])
        assertEquals("120 Hz", rows(SectionKind.DISPLAY, p)["Max refresh rate"])
        assertEquals("1.3", rows(SectionKind.GRAPHICS_APIS, p)["Vulkan"])
        assertEquals("1.95 GHz / 2.60 GHz / 3.10 GHz", rows(SectionKind.CPU, p)["Max core clocks"])
        assertEquals("Google Tensor G4", rows(SectionKind.DEVICE, p)["System on chip"])
    }

    @Test fun labelsValuesThePlatformDoesNotExpose() {
        val p = TestProfiles.midRangeOther()
        assertEquals("Not obtainable (No EGL display)", rows(SectionKind.GPU, p)["Renderer"])
        assertEquals("Not reported", rows(SectionKind.GRAPHICS_APIS, p)["Vulkan"])
        assertEquals("Not readable on this device", rows(SectionKind.CPU, p)["Max core clocks"])
        assertEquals("Not reported", rows(SectionKind.DEVICE, p)["System on chip"])
        assertEquals("Not reported", rows(SectionKind.ANDROID, p)["Security patch"])
    }
}
