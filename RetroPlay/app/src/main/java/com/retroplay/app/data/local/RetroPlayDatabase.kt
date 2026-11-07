package com.retroplay.app.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import com.retroplay.app.data.local.dao.GameDao
import com.retroplay.app.data.local.entity.FavoriteEntity
import com.retroplay.app.data.local.entity.GameEntity

@Database(
    entities = [GameEntity::class, FavoriteEntity::class],
    version = 1,
    exportSchema = true,
)
abstract class RetroPlayDatabase : RoomDatabase() {
    abstract fun gameDao(): GameDao

    companion object {
        const val NAME = "retroplay.db"
    }
}
