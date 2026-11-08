package com.retroplay.app.data.local.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import com.retroplay.app.data.local.entity.GameInstallationEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface InstallationDao {
    @Query("SELECT * FROM game_installations WHERE gameId = :gameId")
    fun observe(gameId: String): Flow<GameInstallationEntity?>

    @Query("SELECT * FROM game_installations WHERE gameId = :gameId")
    suspend fun get(gameId: String): GameInstallationEntity?

    @Upsert
    suspend fun upsert(entity: GameInstallationEntity)

    @Query("DELETE FROM game_installations WHERE gameId = :gameId")
    suspend fun delete(gameId: String)

    @Query("SELECT COUNT(*) FROM game_installations WHERE folderUri = :folderUri")
    suspend fun countUsingFolder(folderUri: String): Int
}
