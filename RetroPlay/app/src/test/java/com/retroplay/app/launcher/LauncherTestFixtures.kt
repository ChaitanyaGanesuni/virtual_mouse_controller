package com.retroplay.app.launcher

import com.retroplay.app.domain.game.GameCatalogue
import com.retroplay.app.domain.launch.InstalledApp

object LauncherTestFixtures {
    val pcGame = GameCatalogue.initialGames.first { it.id == "gta-vice-city" }
    val androidGame = GameCatalogue.initialGames.first { it.id == "gta-san-andreas-android" }
    val androidGameApp = InstalledApp("com.rockstargames.gtasa", "GTA: San Andreas")
    /** A user-chosen compatibility app. The package is test data, not a claim about any real app. */
    val compatApp = InstalledApp("com.example.windowsrunner", "Windows Runner")
}
