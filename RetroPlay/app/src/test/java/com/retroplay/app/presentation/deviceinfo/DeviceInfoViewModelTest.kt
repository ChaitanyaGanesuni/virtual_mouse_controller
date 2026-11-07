package com.retroplay.app.presentation.deviceinfo

import com.retroplay.app.domain.repository.UserPreferences
import com.retroplay.app.testutil.FakeDeviceProfileManager
import com.retroplay.app.testutil.FakeUserPreferencesRepository
import com.retroplay.app.testutil.MainDispatcherRule
import com.retroplay.app.testutil.TestProfiles
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DeviceInfoViewModelTest {

    @get:Rule val mainDispatcherRule = MainDispatcherRule()

    @Test fun readyStateContainsProfileSectionsAndComparison() = runTest {
        val vm = DeviceInfoViewModel(FakeDeviceProfileManager(), FakeUserPreferencesRepository())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }

        val state = vm.uiState.value as DeviceInfoUiState.Ready
        assertEquals("Pixel 9", state.profile.identity.model)
        assertEquals(SectionKind.entries.size, state.sections.size)
        assertEquals(8, state.comparison.size)
        assertTrue(state.showComparison)
    }

    @Test fun comparisonHiddenWhenPreferenceDisabled() = runTest {
        val prefs = FakeUserPreferencesRepository(UserPreferences(showReferenceComparison = false))
        val vm = DeviceInfoViewModel(FakeDeviceProfileManager(), prefs)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }

        assertFalse((vm.uiState.value as DeviceInfoUiState.Ready).showComparison)
        prefs.setShowReferenceComparison(true)
        assertTrue((vm.uiState.value as DeviceInfoUiState.Ready).showComparison)
    }

    @Test fun captureFailureProducesErrorState() = runTest {
        val manager = FakeDeviceProfileManager(failure = IllegalStateException("boom"))
        val vm = DeviceInfoViewModel(manager, FakeUserPreferencesRepository())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }

        assertEquals(DeviceInfoUiState.Error("boom"), vm.uiState.value)
    }

    @Test fun refreshRecapturesAndRecoversFromError() = runTest {
        val manager = FakeDeviceProfileManager(failure = IllegalStateException("boom"))
        val vm = DeviceInfoViewModel(manager, FakeUserPreferencesRepository())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { vm.uiState.collect() }

        manager.failure = null
        manager.nextProfile = TestProfiles.midRangeOther()
        vm.refresh()

        assertEquals(2, manager.captureCount)
        val state = vm.uiState.value as DeviceInfoUiState.Ready
        assertEquals("Phone X", state.profile.identity.model)
    }
}
