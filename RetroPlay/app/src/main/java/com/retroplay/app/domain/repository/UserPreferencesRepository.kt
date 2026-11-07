package com.retroplay.app.domain.repository

import kotlinx.coroutines.flow.Flow

data class UserPreferences(
    val showReferenceComparison: Boolean = true,
    /** The user's chosen external Windows compatibility app (package + label as shown when chosen). */
    val externalAppPackage: String? = null,
    val externalAppLabel: String? = null,
)

interface UserPreferencesRepository {
    val preferences: Flow<UserPreferences>
    suspend fun setShowReferenceComparison(enabled: Boolean)
    /** Pass null to clear. */
    suspend fun setExternalApp(packageName: String?, label: String?)
}
