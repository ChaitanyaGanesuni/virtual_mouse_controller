package com.retroplay.app.domain.repository

import kotlinx.coroutines.flow.Flow

data class UserPreferences(
    val showReferenceComparison: Boolean = true,
)

interface UserPreferencesRepository {
    val preferences: Flow<UserPreferences>
    suspend fun setShowReferenceComparison(enabled: Boolean)
}
