package com.retroplay.app.domain.repository

import com.retroplay.app.domain.model.GameInstallation
import kotlinx.coroutines.flow.Flow

interface InstallationRepository {
    fun observe(gameId: String): Flow<GameInstallation?>
    suspend fun get(gameId: String): GameInstallation?
    suspend fun upsert(installation: GameInstallation)
    /** Removes the metadata record only. Never touches the files themselves. */
    suspend fun delete(gameId: String)
    suspend fun countUsingFolder(folderUri: String): Int
}
