package com.retroplay.app.storage

import com.retroplay.app.core.coroutines.IoDispatcher
import com.retroplay.app.core.time.Clock
import com.retroplay.app.domain.model.GameInstallation
import com.retroplay.app.domain.model.ImportValidity
import com.retroplay.app.domain.model.InstallationStatus
import com.retroplay.app.domain.repository.GameRepository
import com.retroplay.app.domain.repository.InstallationRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

sealed interface ScanStep {
    data class Found(val treeUri: String, val folderDisplayPath: String, val result: ScanResult) : ScanStep
    data class Failed(val message: String) : ScanStep
}

sealed interface ImportOutcome {
    data class Imported(val installation: GameInstallation) : ImportOutcome
    data class Failed(val message: String) : ImportOutcome
}

/**
 * Coordinates importing user-selected game files. It only records metadata: files are never copied,
 * executed, modified or deleted, and folder access is released when no library entry uses it any more.
 */
@Singleton
class GameImportManager @Inject constructor(
    private val access: PersistedFolderAccess,
    private val scanner: ExecutableScanner,
    private val validator: ExecutableValidator,
    private val games: GameRepository,
    private val installations: InstallationRepository,
    private val clock: Clock,
    @IoDispatcher private val io: CoroutineDispatcher,
) {
    /** Step 1: keep access to the picked folder and list the .exe files in it. */
    suspend fun scanFolder(gameId: String, treeUri: String): ScanStep = withContext(io) {
        access.take(treeUri).onFailure {
            return@withContext ScanStep.Failed(
                "Android did not let RetroPlay keep access to this folder (${it.message ?: "permission refused"}). " +
                    "Try picking the folder again.",
            )
        }
        val display = TreeUriPaths.displayPath(treeUri)
        val result = try {
            scanner.scan(treeUri)
        } catch (e: FolderAccessLostException) {
            releaseIfUnused(treeUri)
            return@withContext ScanStep.Failed(e.message ?: "Access to the folder was lost.")
        } catch (e: DocumentNotFoundException) {
            releaseIfUnused(treeUri)
            return@withContext ScanStep.Failed("The folder could not be read. It may have been moved or removed.")
        }
        if (result.candidates.isEmpty()) {
            releaseIfUnused(treeUri)
            val limit = if (result.truncated) " (stopped after ${result.entriesVisited} items; pick a more specific folder)" else ""
            ScanStep.Failed("No .exe files were found in $display$limit.")
        } else {
            ScanStep.Found(treeUri, display, result)
        }
    }

    /** Step 2: validate the chosen executable and record the import. */
    suspend fun completeImport(gameId: String, treeUri: String, executable: ExecutableCandidate): ImportOutcome = withContext(io) {
        when (val outcome = validator.validate(treeUri, executable.relativePath)) {
            is ValidationOutcome.Invalid -> {
                releaseIfUnused(treeUri)
                ImportOutcome.Failed(outcome.message)
            }
            is ValidationOutcome.Valid -> {
                val previous = installations.get(gameId)
                val now = clock.nowMillis()
                val installation = GameInstallation(
                    gameId = gameId,
                    folderUri = treeUri,
                    folderDisplayPath = TreeUriPaths.displayPath(treeUri),
                    executableRelativePath = executable.relativePath,
                    executableSizeBytes = outcome.sizeBytes,
                    importedAtEpochMillis = now,
                    lastValidatedAtEpochMillis = now,
                    validity = ImportValidity.VALID,
                    message = null,
                )
                installations.upsert(installation)
                games.updateInstallationStatus(gameId, InstallationStatus.IMPORTED)
                if (previous != null && previous.folderUri != treeUri) releaseIfUnused(previous.folderUri)
                ImportOutcome.Imported(installation)
            }
        }
    }

    /** Called when the user cancels after scanning: drop access we took if nothing uses it. */
    suspend fun cancelImport(gameId: String, treeUri: String) = withContext(io) {
        releaseIfUnused(treeUri)
    }

    /** Re-checks a stored import and records the result. */
    suspend fun revalidate(gameId: String): GameInstallation? = withContext(io) {
        val existing = installations.get(gameId) ?: return@withContext null
        val outcome = validator.validate(existing.folderUri, existing.executableRelativePath)
        val updated = when (outcome) {
            is ValidationOutcome.Valid -> existing.copy(
                executableSizeBytes = outcome.sizeBytes,
                validity = ImportValidity.VALID,
                message = null,
                lastValidatedAtEpochMillis = clock.nowMillis(),
            )
            is ValidationOutcome.Invalid -> existing.copy(
                validity = outcome.validity,
                message = outcome.message,
                lastValidatedAtEpochMillis = clock.nowMillis(),
            )
        }
        installations.upsert(updated)
        games.updateInstallationStatus(
            gameId,
            if (updated.validity == ImportValidity.VALID) InstallationStatus.IMPORTED else InstallationStatus.MISSING,
        )
        updated
    }

    /** Forgets the imported files. The files themselves are left exactly where they are. */
    suspend fun removeImport(gameId: String) = withContext(io) {
        val existing = installations.get(gameId) ?: return@withContext
        installations.delete(gameId)
        games.updateInstallationStatus(gameId, InstallationStatus.NOT_IMPORTED)
        releaseIfUnused(existing.folderUri)
    }

    /** Removes a user-registered game entry; its files are not touched. */
    suspend fun removeCustomGame(gameId: String): Boolean = withContext(io) {
        val folder = installations.get(gameId)?.folderUri
        val removed = games.removeCustomGame(gameId)
        if (removed && folder != null) releaseIfUnused(folder)
        removed
    }

    /** Releases persisted access to a folder once no library entry refers to it. */
    private suspend fun releaseIfUnused(treeUri: String) {
        if (installations.countUsingFolder(treeUri) == 0) access.release(treeUri)
    }
}
