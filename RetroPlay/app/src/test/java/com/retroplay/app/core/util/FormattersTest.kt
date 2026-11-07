package com.retroplay.app.core.util

import org.junit.Assert.assertEquals
import org.junit.Test

class FormattersTest {
    @Test fun binaryBytesUseBase1024() {
        assertEquals("12.0 GB", Formatters.bytes(12L * 1024 * 1024 * 1024, binary = true))
        assertEquals("1.5 KB", Formatters.bytes(1536, binary = true))
    }

    @Test fun decimalBytesUseBase1000() {
        assertEquals("128.0 GB", Formatters.bytes(128_000_000_000L, binary = false))
    }

    @Test fun smallAndNegativeValues() {
        assertEquals("512 B", Formatters.bytes(512, binary = true))
        assertEquals("Unknown", Formatters.bytes(-1, binary = true))
    }

    @Test fun refreshRateRoundsNearIntegers() {
        assertEquals("120 Hz", Formatters.refreshRate(120.00001f))
        assertEquals("59.9 Hz", Formatters.refreshRate(59.94f))
    }

    @Test fun khzToGhz() {
        assertEquals("3.10 GHz", Formatters.khzToGhz(3_100_000))
    }
}
