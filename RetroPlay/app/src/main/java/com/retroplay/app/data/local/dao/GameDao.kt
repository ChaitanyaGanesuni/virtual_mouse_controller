package com.retroplay.app.data.local.dao

import androidx.room.Dao
import androidx.room.Embedded
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.retroplay.app.data.local.entity.FavoriteEntity
import com.retroplay.app.data.local.entity.GameEntity
import kotlinx.coroutines.flow.Flow

data class GameWithFavorite(
    @Embedded val game: GameEntity,
    val isFavorite: Boolean,
)

@Dao
interface GameDao {

    @Query(
        """
        SELECT g.*, (f.gameId IS NOT NULL) AS isFavorite
        FROM games g LEFT JOIN favorites f ON f.gameId = g.id
        ORDER BY g.sortOrder, g.title
        """,
    )
    fun observeGames(): Flow<List<GameWithFavorite>>

    @Query(
        """
        SELECT g.*, (f.gameId IS NOT NULL) AS isFavorite
        FROM games g LEFT JOIN favorites f ON f.gameId = g.id
        WHERE g.id = :id
        """,
    )
    fun observeGame(id: String): Flow<GameWithFavorite?>

    /** Inserts catalogue rows without overwriting games that already exist (preserves user data). */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertIfAbsent(games: List<GameEntity>)

    @Query("UPDATE games SET userNotes = :notes WHERE id = :id")
    suspend fun updateNotes(id: String, notes: String): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun addFavorite(favorite: FavoriteEntity)

    @Query("DELETE FROM favorites WHERE gameId = :gameId")
    suspend fun removeFavorite(gameId: String)
}
