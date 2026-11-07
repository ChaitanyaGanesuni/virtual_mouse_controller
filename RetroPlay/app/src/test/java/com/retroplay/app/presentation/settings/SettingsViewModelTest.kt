package com.retroplay.app.presentation.settings

import com.retroplay.app.testutil.FakeGameLaunchManager
import com.retroplay.app.testutil.FakeUserPreferencesRepository
import com.retroplay.app.testutil.MainDispatcherRule
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SettingsViewModelTest {

    @get:Rule val mainDispatcherRule = MainDispatcherRule()

    @Test fun toggleUpdatesPreference() = runTest {
        val vm = SettingsViewModel(FakeUserPreferencesRepository(), FakeGameLaunchManager())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.preferences.collect() }

        assertTrue(vm.preferences.value.showReferenceComparison)
        vm.setShowReferenceComparison(false)
        assertFalse(vm.preferences.value.showReferenceComparison)
    }

    @Test fun choosingAndClearingCompatibilityApp() = runTest {
        val vm = SettingsViewModel(FakeUserPreferencesRepository(), FakeGameLaunchManager())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.preferences.collect() }

        vm.showExternalAppPicker()
        val picker = vm.picker.value!!
        assertFalse(picker.isLoading)
        assertEquals("winlator", picker.suggestLabel)

        vm.onExternalAppPicked(picker.apps.first())
        assertNull(vm.picker.value)
        assertEquals("Windows Runner", vm.preferences.value.externalAppLabel)

        vm.clearExternalApp()
        assertNull(vm.preferences.value.externalAppPackage)
        assertNull(vm.preferences.value.externalAppLabel)
    }
}
