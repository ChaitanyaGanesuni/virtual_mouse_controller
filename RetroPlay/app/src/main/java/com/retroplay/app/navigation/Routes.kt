package com.retroplay.app.navigation

import kotlinx.serialization.Serializable

@Serializable data object HomeRoute
@Serializable data object LibraryRoute
@Serializable data object DiscoverRoute
@Serializable data object FavoritesRoute
@Serializable data object SettingsRoute
@Serializable data object DeviceInfoRoute
@Serializable data object CompatibilityReportRoute

/** `gameId` must match GameDetailViewModel.GAME_ID_ARG. */
@Serializable data class GameDetailRoute(val gameId: String)
