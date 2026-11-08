package com.retroplay.app.domain.model

enum class ImportValidity(val label: String) {
    VALID("Valid"),
    /** The folder is still accessible but the selected executable is gone or renamed. */
    EXECUTABLE_MISSING("Executable missing"),
    /** The folder itself can no longer be found (deleted, moved or storage removed). */
    FOLDER_MISSING("Folder missing"),
    /** Android no longer grants RetroPlay access to the folder. */
    PERMISSION_LOST("Access lost"),
    /** The file exists but does not look like a Windows executable. */
    INVALID_EXECUTABLE("Not a Windows executable"),
}

/**
 * Metadata about user-selected game files. RetroPlay stores only a reference (a Storage Access Framework
 * folder URI and a relative path); it never copies, modifies, executes or deletes the files.
 */
data class GameInstallation(
    val gameId: String,
    /** Persisted SAF tree URI (content://…/tree/…). Readable by RetroPlay only, not by other apps. */
    val folderUri: String,
    val folderDisplayPath: String,
    /** Path of the executable relative to the folder, using '/' separators, e.g. "bin/game.exe". */
    val executableRelativePath: String,
    val executableSizeBytes: Long,
    val importedAtEpochMillis: Long,
    val lastValidatedAtEpochMillis: Long,
    val validity: ImportValidity,
    val message: String?,
)
