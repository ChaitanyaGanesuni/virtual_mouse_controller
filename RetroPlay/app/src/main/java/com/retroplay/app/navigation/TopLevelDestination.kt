package com.retroplay.app.navigation

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.VideoLibrary
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavDestination
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavDestination.Companion.hierarchy
import com.retroplay.app.R

enum class TopLevelDestination(
    val route: Any,
    @StringRes val labelRes: Int,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector,
    private val matcher: (NavDestination) -> Boolean,
) {
    HOME(HomeRoute, R.string.nav_home, Icons.Filled.Home, Icons.Outlined.Home, { it.hasRoute<HomeRoute>() }),
    LIBRARY(LibraryRoute, R.string.nav_library, Icons.Filled.VideoLibrary, Icons.Outlined.VideoLibrary, { it.hasRoute<LibraryRoute>() }),
    DISCOVER(DiscoverRoute, R.string.nav_discover, Icons.Filled.Explore, Icons.Outlined.Explore, { it.hasRoute<DiscoverRoute>() }),
    FAVORITES(FavoritesRoute, R.string.nav_favorites, Icons.Filled.Favorite, Icons.Outlined.FavoriteBorder, { it.hasRoute<FavoritesRoute>() }),
    SETTINGS(SettingsRoute, R.string.nav_settings, Icons.Filled.Settings, Icons.Outlined.Settings, { it.hasRoute<SettingsRoute>() }),
    ;

    fun isSelected(destination: NavDestination?): Boolean =
        destination?.hierarchy?.any(matcher) == true
}
