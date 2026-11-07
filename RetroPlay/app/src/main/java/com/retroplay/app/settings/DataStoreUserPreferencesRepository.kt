package com.retroplay.app.settings

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import com.retroplay.app.domain.repository.UserPreferences
import com.retroplay.app.domain.repository.UserPreferencesRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DataStoreUserPreferencesRepository @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) : UserPreferencesRepository {

    override val preferences: Flow<UserPreferences> = dataStore.data
        .catch { e -> if (e is IOException) emit(emptyPreferences()) else throw e }
        .map { prefs ->
            UserPreferences(
                showReferenceComparison = prefs[Keys.SHOW_REFERENCE_COMPARISON] ?: true,
            )
        }

    override suspend fun setShowReferenceComparison(enabled: Boolean) {
        dataStore.edit { it[Keys.SHOW_REFERENCE_COMPARISON] = enabled }
    }

    private object Keys {
        val SHOW_REFERENCE_COMPARISON = booleanPreferencesKey("show_reference_comparison")
    }
}
