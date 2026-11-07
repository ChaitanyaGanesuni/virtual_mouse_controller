package com.retroplay.app.settings

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
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
                externalAppPackage = prefs[Keys.EXTERNAL_APP_PACKAGE],
                externalAppLabel = prefs[Keys.EXTERNAL_APP_LABEL],
            )
        }

    override suspend fun setShowReferenceComparison(enabled: Boolean) {
        dataStore.edit { it[Keys.SHOW_REFERENCE_COMPARISON] = enabled }
    }

    override suspend fun setExternalApp(packageName: String?, label: String?) {
        dataStore.edit {
            if (packageName == null) {
                it.remove(Keys.EXTERNAL_APP_PACKAGE)
                it.remove(Keys.EXTERNAL_APP_LABEL)
            } else {
                it[Keys.EXTERNAL_APP_PACKAGE] = packageName
                if (label != null) it[Keys.EXTERNAL_APP_LABEL] = label else it.remove(Keys.EXTERNAL_APP_LABEL)
            }
        }
    }

    private object Keys {
        val SHOW_REFERENCE_COMPARISON = booleanPreferencesKey("show_reference_comparison")
        val EXTERNAL_APP_PACKAGE = stringPreferencesKey("external_app_package")
        val EXTERNAL_APP_LABEL = stringPreferencesKey("external_app_label")
    }
}
