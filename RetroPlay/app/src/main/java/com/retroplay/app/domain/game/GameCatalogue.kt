package com.retroplay.app.domain.game

import com.retroplay.app.domain.model.CompatibilityStatus
import com.retroplay.app.domain.model.ExecutionType
import com.retroplay.app.domain.model.Game
import com.retroplay.app.domain.model.GameCategory
import com.retroplay.app.domain.model.GamePlatform
import com.retroplay.app.domain.model.InstallationStatus

/**
 * The initial catalogue: metadata only. RetroPlay ships no game files, assets or executables.
 * Release years are those of the catalogued edition (Windows PC or Android). Every game starts as NOT_TESTED, because
 * compatibility is only recorded after a real test on the device (Phase 7).
 */
object GameCatalogue {

    val initialGames: List<Game> = listOf(
        pcGame(
            id = "ea-sports-cricket-07",
            title = "EA Sports Cricket 07",
            shortTitle = "07",
            category = GameCategory.CRICKET,
            releaseYear = 2006,
            description = "EA Sports' cricket simulation for Windows PC, with international teams, " +
                "tournaments and broadcast-style match presentation.",
            sortOrder = 0,
        ),
        pcGame(
            id = "gta-iii",
            title = "Grand Theft Auto III",
            shortTitle = "III",
            category = GameCategory.GTA,
            releaseYear = 2002,
            description = "The open-world crime game set in Liberty City that took the series into 3D. " +
                "This entry is the Windows PC edition.",
            sortOrder = 10,
        ),
        pcGame(
            id = "gta-vice-city",
            title = "Grand Theft Auto: Vice City",
            shortTitle = "VC",
            category = GameCategory.GTA,
            releaseYear = 2003,
            description = "A 1980s-themed open-world crime story set in the neon-lit Vice City. " +
                "This entry is the Windows PC edition.",
            sortOrder = 11,
        ),
        pcGame(
            id = "gta-san-andreas",
            title = "Grand Theft Auto: San Andreas",
            shortTitle = "SA",
            category = GameCategory.GTA,
            releaseYear = 2005,
            description = "An early-1990s crime epic spanning the cities and countryside of San Andreas. " +
                "This entry is the Windows PC edition.",
            sortOrder = 12,
        ),
        pcGame(
            id = "gta-iv",
            title = "Grand Theft Auto IV",
            shortTitle = "IV",
            category = GameCategory.GTA,
            releaseYear = 2008,
            description = "A story-driven return to a reimagined Liberty City. " +
                "This entry is the Windows PC edition.",
            sortOrder = 13,
        ),
        pcGame(
            id = "gta-v",
            title = "Grand Theft Auto V",
            shortTitle = "V",
            category = GameCategory.GTA,
            releaseYear = 2015,
            description = "An open-world crime game set in Los Santos, told through three playable protagonists. " +
                "This entry is the Windows PC edition.",
            sortOrder = 14,
        ),
        // Official Rockstar Games mobile editions. Package names are checked on the device at runtime;
        // a different edition (for example a subscription-service release) can be linked by the user.
        androidGame(
            id = "gta-iii-android",
            title = "Grand Theft Auto III (Android)",
            shortTitle = "III",
            releaseYear = 2011,
            packageName = "com.rockstargames.gta3",
            sortOrder = 20,
        ),
        androidGame(
            id = "gta-vice-city-android",
            title = "Grand Theft Auto: Vice City (Android)",
            shortTitle = "VC",
            releaseYear = 2012,
            packageName = "com.rockstargames.gtavc",
            sortOrder = 21,
        ),
        androidGame(
            id = "gta-san-andreas-android",
            title = "Grand Theft Auto: San Andreas (Android)",
            shortTitle = "SA",
            releaseYear = 2013,
            packageName = "com.rockstargames.gtasa",
            sortOrder = 22,
        ),
    )

    private fun androidGame(
        id: String,
        title: String,
        shortTitle: String,
        releaseYear: Int,
        packageName: String,
        sortOrder: Int,
    ) = Game(
        id = id,
        title = title,
        shortTitle = shortTitle,
        category = GameCategory.GTA,
        originalPlatform = GamePlatform.ANDROID,
        releaseYear = releaseYear,
        description = "Rockstar Games' official mobile edition. Install it from its app store; " +
            "RetroPlay launches the installed app and never installs anything itself.",
        artworkRef = "placeholder:$id",
        executionType = ExecutionType.ANDROID_NATIVE,
        installationStatus = InstallationStatus.NOT_INSTALLED,
        compatibilityStatus = CompatibilityStatus.NOT_TESTED,
        lastPlayedAtEpochMillis = null,
        userNotes = "",
        isFavorite = false,
        sortOrder = sortOrder,
        androidPackageName = packageName,
    )

    private fun pcGame(
        id: String,
        title: String,
        shortTitle: String,
        category: GameCategory,
        releaseYear: Int?,
        description: String,
        sortOrder: Int,
    ) = Game(
        id = id,
        title = title,
        shortTitle = shortTitle,
        category = category,
        originalPlatform = GamePlatform.WINDOWS_PC,
        releaseYear = releaseYear,
        description = description,
        artworkRef = "placeholder:$id",
        executionType = ExecutionType.EXTERNAL_EMULATOR,
        installationStatus = InstallationStatus.NOT_IMPORTED,
        compatibilityStatus = CompatibilityStatus.NOT_TESTED,
        lastPlayedAtEpochMillis = null,
        userNotes = "",
        isFavorite = false,
        sortOrder = sortOrder,
    )
}
