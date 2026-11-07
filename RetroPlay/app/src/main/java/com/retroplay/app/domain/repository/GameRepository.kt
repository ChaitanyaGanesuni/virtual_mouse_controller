package com.retroplay.app.domain.repository

import com.retroplay.app.domain.model.Game
import kotlinx.coroutines.flow.Flow

interface GameRepository {
    /** All library games, ordered by catalogue order. */
    fun observeGames(): Flow<List<Game>>
    fun observeGame(id: String): Flow<Game?>
    suspend fun setFavorite(id: String, favorite: Boolean)
    suspend fun updateNotes(id: String, notes: String)
}
