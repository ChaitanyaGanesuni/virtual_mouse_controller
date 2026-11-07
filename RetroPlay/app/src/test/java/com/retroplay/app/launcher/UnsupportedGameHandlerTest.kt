package com.retroplay.app.launcher

import com.retroplay.app.domain.model.CompatibilityStatus
import com.retroplay.app.domain.model.ExecutionType
import com.retroplay.app.launcher.LauncherTestFixtures.pcGame
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UnsupportedGameHandlerTest {
    private val handler = UnsupportedGameHandler()

    @Test fun catalogueGamesAreNotUnsupported() {
        assertFalse(handler.isUnsupported(pcGame))
    }

    @Test fun untestedUnsupportedGameSaysItWasNotTested() {
        val game = pcGame.copy(executionType = ExecutionType.UNSUPPORTED)
        val info = handler.explain(game)
        assertTrue(handler.isUnsupported(game))
        assertEquals(1, info.reasons.size)
        assertTrue(info.requiredEnvironment.startsWith("Windows PC"))
        assertTrue(info.testStatus.startsWith("Not tested"))
    }

    @Test fun testedUnsupportedGameCitesTheTest() {
        val info = handler.explain(pcGame.copy(compatibilityStatus = CompatibilityStatus.UNSUPPORTED))
        assertTrue(info.reasons.single().contains("compatibility test"))
        assertEquals("Tested on this device: Unsupported.", info.testStatus)
    }
}
