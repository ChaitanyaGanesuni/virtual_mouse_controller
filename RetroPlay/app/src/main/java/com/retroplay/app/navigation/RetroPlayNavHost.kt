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
import com.retroplay.app.presentation.deviceinfo.DeviceInfoScreen
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
        composable<HomeRoute> {
            HomeScreen(onOpenDeviceInfo = { navController.navigate(DeviceInfoRoute) })
        }
        composable<SettingsRoute> {
            SettingsScreen(onOpenDeviceInfo = { navController.navigate(DeviceInfoRoute) })
        }
        composable<DeviceInfoRoute> {
            DeviceInfoScreen(onBack = { navController.popBackStack() })
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
