package com.retroplay.app.domain.model

enum class GameCategory(val label: String) {
    CRICKET("Cricket"),
    GTA("Grand Theft Auto"),
}

enum class GamePlatform(val label: String) {
    WINDOWS_PC("Windows PC"),
    ANDROID("Android"),
}

/** How RetroPlay would run the game. Launching itself is implemented in Phase 5. */
enum class ExecutionType(val label: String) {
    /** An official Android app installed from its store. */
    ANDROID_NATIVE("Android app"),
    /** A Windows PC game run through an external compatibility app the user installs and configures. */
    EXTERNAL_EMULATOR("External Windows compatibility app"),
    UNSUPPORTED("Unsupported"),
}

enum class InstallationStatus(val label: String) {
    /** No files or app have been registered with RetroPlay yet. */
    NOT_IMPORTED("Not imported"),
    /** An Android game whose app is not installed on this phone. */
    NOT_INSTALLED("Not installed"),
    IMPORTED("Files imported"),
    INSTALLED("Installed"),
    /** Previously registered, but the app or files are no longer present. */
    MISSING("Missing"),
}

enum class CompatibilityStatus(val label: String) {
    NOT_TESTED("Not tested"),
    EXPERIMENTAL("Experimental"),
    WORKING("Working"),
    PLAYABLE("Playable"),
    UNSTABLE("Unstable"),
    UNSUPPORTED("Unsupported"),
}

data class Game(
    val id: String,
    val title: String,
    /** Short monogram used by the generated placeholder artwork, e.g. "VC". */
    val shortTitle: String,
    val category: GameCategory,
    val originalPlatform: GamePlatform,
    /** Release year of the catalogued edition, only when verified; otherwise null. */
    val releaseYear: Int?,
    val description: String,
    /** Licensed artwork URI supplied by the user, or a `placeholder:` key for generated artwork. */
    val artworkRef: String,
    val executionType: ExecutionType,
    val installationStatus: InstallationStatus,
    val compatibilityStatus: CompatibilityStatus,
    val lastPlayedAtEpochMillis: Long?,
    val userNotes: String,
    val isFavorite: Boolean,
    val sortOrder: Int,
    /** Android package of the official app for ANDROID_NATIVE games (catalogue default or user-linked). */
    val androidPackageName: String? = null,
)
