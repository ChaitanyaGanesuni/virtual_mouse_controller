package com.retroplay.app.domain.device

import com.retroplay.app.domain.model.ComparisonField
import com.retroplay.app.domain.model.ComparisonVerdict
import com.retroplay.app.domain.model.DisplayInfo
import com.retroplay.app.domain.model.MemorySnapshot
import com.retroplay.app.domain.model.ReferenceProfiles
import com.retroplay.app.testutil.TestProfiles
import com.retroplay.app.testutil.TestProfiles.GIB
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceProfileComparatorTest {

    private val reference = ReferenceProfiles.Pixel9

    private fun verdicts(profile: com.retroplay.app.domain.model.DeviceProfile) =
        DeviceProfileComparator.compare(profile, reference).associate { it.field to it.verdict }

    @Test fun pixel9LikeProfileMatchesEveryField() {
        val v = verdicts(TestProfiles.pixel9Like())
        assertEquals(ComparisonField.entries.toSet(), v.keys)
        assertTrue("Expected all MATCH but was $v", v.values.all { it == ComparisonVerdict.MATCH })
    }

    @Test fun differentDeviceReportsDifferencesAndUnavailableValues() {
        val v = verdicts(TestProfiles.midRangeOther())
        assertEquals(ComparisonVerdict.DIFFERENT, v[ComparisonField.MODEL])
        assertEquals(ComparisonVerdict.DIFFERENT, v[ComparisonField.ANDROID_VERSION])
        assertEquals(ComparisonVerdict.UNAVAILABLE, v[ComparisonField.SOC])
        assertEquals(ComparisonVerdict.UNAVAILABLE, v[ComparisonField.GPU])
        assertEquals(ComparisonVerdict.DIFFERENT, v[ComparisonField.CPU_ARCHITECTURE])
        assertEquals(ComparisonVerdict.DIFFERENT, v[ComparisonField.MEMORY])
        assertEquals(ComparisonVerdict.DIFFERENT, v[ComparisonField.RESOLUTION])
        assertEquals(ComparisonVerdict.DIFFERENT, v[ComparisonField.REFRESH_RATE])
    }

    @Test fun landscapeResolutionStillMatches() {
        val p = TestProfiles.pixel9Like().let { it.copy(display = it.display.copy(widthPx = 2424, heightPx = 1080)) }
        assertEquals(ComparisonVerdict.MATCH, verdicts(p)[ComparisonField.RESOLUTION])
    }

    @Test fun memoryToleranceBoundaries() {
        fun withTotal(bytes: Long) = TestProfiles.pixel9Like().let {
            it.copy(memory = MemorySnapshot(bytes, 0, 0, false, 0, 0))
        }
        val ref = reference.ramBytes.toDouble()
        assertEquals(ComparisonVerdict.MATCH, verdicts(withTotal((ref * 0.80).toLong() + 1))[ComparisonField.MEMORY])
        assertEquals(ComparisonVerdict.DIFFERENT, verdicts(withTotal((ref * 0.79).toLong()))[ComparisonField.MEMORY])
        assertEquals(ComparisonVerdict.DIFFERENT, verdicts(withTotal(16 * GIB))[ComparisonField.MEMORY])
        assertEquals(ComparisonVerdict.UNAVAILABLE, verdicts(withTotal(0))[ComparisonField.MEMORY])
    }

    @Test fun laterAndroidVersionsMeetTheTarget() {
        val p = TestProfiles.pixel9Like().let { it.copy(os = it.os.copy(release = "16", apiLevel = 36)) }
        assertEquals(ComparisonVerdict.MATCH, verdicts(p)[ComparisonField.ANDROID_VERSION])
    }

    @Test fun refreshRateUsesMaximumSupportedMode() {
        val p = TestProfiles.pixel9Like().copy(display = DisplayInfo(1080, 2424, 420, 60f, listOf(60f, 90f), false))
        assertEquals(ComparisonVerdict.DIFFERENT, verdicts(p)[ComparisonField.REFRESH_RATE])
    }

    @Test fun referenceValuesAreNeverReplacedByMeasurements() {
        val rows = DeviceProfileComparator.compare(TestProfiles.midRangeOther(), reference).associateBy { it.field }
        assertEquals("ARM Mali-G715 MC7", rows.getValue(ComparisonField.GPU).reference)
        assertEquals("Not obtainable", rows.getValue(ComparisonField.GPU).measured)
        assertEquals("1080 × 2424", rows.getValue(ComparisonField.RESOLUTION).reference)
        assertEquals("720 × 1600", rows.getValue(ComparisonField.RESOLUTION).measured)
    }
}
