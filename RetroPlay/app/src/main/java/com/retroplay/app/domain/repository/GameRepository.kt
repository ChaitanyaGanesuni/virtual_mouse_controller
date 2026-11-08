package com.retroplay.app.domain.repository

import com.retroplay.app.domain.launch.LaunchMethod
import com.retroplay.app.domain.model.Game
import com.retroplay.app.domain.model.InstallationStatus
import kotlinx.coroutines.flow.Flow

interface GameRepository {
    /** All library games, ordered by catalogue order. */
    fun observeGames(): Flow<List<Game>>
    fun observeGame(id: String): Flow<Game?>
    suspend fun setFavorite(id: String, favorite: Boolean)
    suspend fun updateNotes(id: String, notes: String)
    /** Links (or with null, unlinks) the installed Android app used to launch an ANDROID_NATIVE game. */
    suspend fun setAndroidPackage(id: String, packageName: String?)
    suspend fun updateInstallationStatus(id: String, status: InstallationStatus)
    /** Adds a play-history entry; only a real Android app launch updates "last played". */
    suspend fun recordLaunch(id: String, method: LaunchMethod, atEpochMillis: Long)
    /** Adds a user-registered Windows PC game (NOT_TESTED, NOT_IMPORTED) and returns it. */
    suspend fun registerCustomGame(title: String, category: com.retroplay.app.domain.model.GameCategory): Game
    /**
     * Removes a user-registered game and its RetroPlay records (favourite, history, file reference).
     * Catalogue games cannot be removed. Original game files are never deleted.
     * Returns false if the game is not a removable custom entry.
     */
    suspend fun removeCustomGame(id: String): Boolean
}
