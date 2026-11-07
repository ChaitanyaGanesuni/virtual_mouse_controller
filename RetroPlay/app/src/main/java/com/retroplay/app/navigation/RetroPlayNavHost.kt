package com.retroplay.app.navigation

import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.retroplay.app.presentation.compatibility.CompatibilityReportScreen
import com.retroplay.app.presentation.deviceinfo.DeviceInfoScreen
import com.retroplay.app.presentation.discover.DiscoverScreen
import com.retroplay.app.presentation.favorites.FavoritesScreen
import com.retroplay.app.presentation.gamedetail.GameDetailScreen
import com.retroplay.app.presentation.library.LibraryScreen
import com.retroplay.app.presentation.home.HomeScreen
import com.retroplay.app.presentation.settings.SettingsScreen

@Composable
fun RetroPlayNavHost(navController: NavHostController, modifier: Modifier = Modifier) {
    NavHost(
        navController = navController,
        startDestination = HomeRoute,
        modifier = modifier,
        enterTransition = { fadeIn(tween(220)) + slideInHorizontally(tween(220)) { it / 12 } },
        exitTransition = { fadeOut(tween(160)) },
        popEnterTransition = { fadeIn(tween(220)) },
        popExitTransition = { fadeOut(tween(160)) + slideOutHorizontally(tween(220)) { it / 12 } },
    ) {
        val openGame: (String) -> Unit = { id -> navController.navigate(GameDetailRoute(id)) }
        composable<HomeRoute> {
            HomeScreen(
                onOpenGame = openGame,
                onOpenLibrary = { navController.navigateToTopLevel(TopLevelDestination.LIBRARY) },
                onOpenDeviceInfo = { navController.navigate(DeviceInfoRoute) },
            )
        }
        composable<LibraryRoute> { LibraryScreen(onOpenGame = openGame) }
        composable<DiscoverRoute> { DiscoverScreen(onOpenGame = openGame) }
        composable<FavoritesRoute> { FavoritesScreen(onOpenGame = openGame) }
        composable<SettingsRoute> {
            SettingsScreen(
                onOpenDeviceInfo = { navController.navigate(DeviceInfoRoute) },
                onOpenCompatibilityReport = { navController.navigate(CompatibilityReportRoute) },
            )
        }
        composable<DeviceInfoRoute> {
            DeviceInfoScreen(onBack = { navController.popBackStack() })
        }
        composable<CompatibilityReportRoute> {
            CompatibilityReportScreen(onBack = { navController.popBackStack() }, onOpenGame = openGame)
        }
        composable<GameDetailRoute> {
            GameDetailScreen(onBack = { navController.popBackStack() })
        }
    }
}

fun NavHostController.navigateToTopLevel(destination: TopLevelDestination) {
    navigate(destination.route) {
        popUpTo(graph.findStartDestination().id) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}
