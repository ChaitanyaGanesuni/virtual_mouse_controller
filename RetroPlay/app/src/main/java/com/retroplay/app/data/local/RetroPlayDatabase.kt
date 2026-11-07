package com.retroplay.app.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.retroplay.app.data.local.dao.GameDao
import com.retroplay.app.data.local.entity.FavoriteEntity
import com.retroplay.app.data.local.entity.GameEntity
import com.retroplay.app.data.local.entity.PlayHistoryEntity

@Database(
    entities = [GameEntity::class, FavoriteEntity::class, PlayHistoryEntity::class],
    version = 2,
    exportSchema = true,
)
abstract class RetroPlayDatabase : RoomDatabase() {
    abstract fun gameDao(): GameDao

    companion object {
        const val NAME = "retroplay.db"

        /** v2: Android package link for native games, and play history. Keeps all existing user data. */
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE `games` ADD COLUMN `androidPackageName` TEXT")
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `play_history` (" +
                        "`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `gameId` TEXT NOT NULL, " +
                        "`launchedAt` INTEGER NOT NULL, `method` TEXT NOT NULL, " +
                        "FOREIGN KEY(`gameId`) REFERENCES `games`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_play_history_gameId` ON `play_history` (`gameId`)")
            }
        }

        val ALL_MIGRATIONS = arrayOf(MIGRATION_1_2)
    }
}
