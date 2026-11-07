package com.retroplay.app.presentation.discover

import com.retroplay.app.domain.game.GameCatalogue
import com.retroplay.app.domain.model.CompatibilityStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class DiscoverViewModelTest {
    @Test fun buildsCollectionsFromCatalogue() {
        val collections = DiscoverViewModel.collectionsFor(GameCatalogue.initialGames).associateBy { it.title }
        assertEquals(
            listOf("gta-iii", "gta-vice-city", "gta-san-andreas", "gta-iv", "gta-v"),
            collections.getValue("Grand Theft Auto").games.map { it.id },
        )
        assertEquals(1, collections.getValue("Cricket").games.size)
        // 2002–2008 PC editions; GTA V (2015) is excluded.
        assertEquals(5, collections.getValue("2000s PC classics").games.size)
        assertEquals(6, collections.getValue("Awaiting a compatibility test").games.size)
    }

    @Test fun emptyCollectionsAreOmitted() {
        val tested = GameCatalogue.initialGames.map { it.copy(compatibilityStatus = CompatibilityStatus.UNSTABLE) }
        assertFalse(DiscoverViewModel.collectionsFor(tested).any { it.title == "Awaiting a compatibility test" })
    }
}
