package com.retroplay.app.presentation.gamedetail

import androidx.lifecycle.SavedStateHandle
import com.retroplay.app.domain.launch.InstalledApp
import com.retroplay.app.domain.launch.LaunchMethod
import com.retroplay.app.domain.launch.LaunchPlan
import com.retroplay.app.domain.launch.LaunchResult
import com.retroplay.app.testutil.FakeGameLaunchManager
import com.retroplay.app.testutil.FakeGameRepository
import com.retroplay.app.testutil.FakeUserPreferencesRepository
import com.retroplay.app.testutil.MainDispatcherRule
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class GameDetailViewModelTest {
    @get:Rule val mainDispatcherRule = MainDispatcherRule()

    private val repo = FakeGameRepository()
    private val prefs = FakeUserPreferencesRepository()
    private val launcher = FakeGameLaunchManager()

    private fun vm(id: String) =
        GameDetailViewModel(SavedStateHandle(mapOf(GameDetailViewModel.GAME_ID_ARG to id)), repo, launcher, prefs)

    @Test fun loadsGameWithPlanAndUpdatesFavouriteAndNotes() = runTest {
        val vm = vm("ea-sports-cricket-07")
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }

        val ready = vm.uiState.value as GameDetailUiState.Ready
        assertEquals("EA Sports Cricket 07", ready.game.title)
        assertTrue(ready.launchPlan is LaunchPlan.ExternalNotConfigured)

        vm.setFavorite(true)
        assertTrue((vm.uiState.value as GameDetailUiState.Ready).game.isFavorite)

        vm.saveNotes("Needs 1280x720 ")
        assertEquals("Needs 1280x720", (vm.uiState.value as GameDetailUiState.Ready).game.userNotes)
    }

    @Test fun unknownIdIsNotFound() = runTest {
        val vm = vm("missing")
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }
        assertEquals(GameDetailUiState.NotFound, vm.uiState.value)
    }

    @Test fun launchOutcomesProduceHonestMessages() = runTest {
        val vm = vm("gta-iii")
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }

        vm.launch()
        assertEquals(listOf("gta-iii"), launcher.launched)
        assertTrue(vm.message.value!!.contains("can't be started"))
        vm.consumeMessage()

        val app = InstalledApp("com.example.windowsrunner", "Windows Runner")
        launcher.nextResult = LaunchResult.Started(app, LaunchMethod.EXTERNAL_APP_OPENED)
        vm.launch()
        assertEquals("Opened Windows Runner. Start the game from there.", vm.message.value)

        launcher.nextResult = LaunchResult.Failed("Could not open X: denied")
        vm.launch()
        assertEquals("Could not open X: denied", vm.message.value)
    }

    @Test fun refreshReplansAfterReturningToTheApp() = runTest {
        val vm = vm("gta-iii-android")
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }
        val before = launcher.planCalls
        launcher.nextPlan = LaunchPlan.AndroidReady(InstalledApp("com.rockstargames.gta3", "GTA III"))
        vm.refresh()
        assertTrue(launcher.planCalls > before)
        assertTrue((vm.uiState.value as GameDetailUiState.Ready).launchPlan is LaunchPlan.AndroidReady)
    }

    @Test fun linkingAnAndroidAppAndChoosingACompatibilityApp() = runTest {
        val vm = vm("gta-iii-android")
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }
        val app = InstalledApp("com.example.edition", "Another edition")
        launcher.apps = listOf(app)

        vm.showPicker(PickerPurpose.LINK_ANDROID_APP)
        assertEquals(listOf(app), vm.picker.value!!.second.apps)
        vm.onAppPicked(app)
        assertNull(vm.picker.value)
        assertEquals("com.example.edition", repo.observeGame("gta-iii-android").first()!!.androidPackageName)

        vm.showPicker(PickerPurpose.CHOOSE_EXTERNAL_APP)
        vm.onAppPicked(app)
        assertEquals("com.example.edition", prefs.preferences.first().externalAppPackage)
    }

    @Test fun missingStoreIsReported() = runTest {
        launcher.storeAvailable = false
        val vm = vm("gta-iii-android")
        vm.openStoreListing("com.rockstargames.gta3")
        assertEquals("No app store is available to open the listing.", vm.message.value)
    }
}
