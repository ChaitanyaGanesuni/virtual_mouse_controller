package com.retroplay.app.presentation.deviceinfo

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.retroplay.app.core.designsystem.theme.RetroPlayTheme
import com.retroplay.app.domain.device.DeviceProfileComparator
import com.retroplay.app.domain.model.ReferenceProfiles
import com.retroplay.app.testutil.TestProfiles
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class DeviceInfoContentTest {

    @get:Rule val composeRule = createComposeRule()

    private fun ready(showComparison: Boolean) = TestProfiles.pixel9Like().let { p ->
        DeviceInfoUiState.Ready(
            profile = p,
            sections = DeviceInfoSections.from(p),
            reference = ReferenceProfiles.Pixel9,
            comparison = DeviceProfileComparator.compare(p, ReferenceProfiles.Pixel9),
            showComparison = showComparison,
        )
    }

    @Test fun showsMeasuredHardwareAndReferenceComparison() {
        composeRule.setContent { RetroPlayTheme { DeviceInfoContent(ready(true), {}, {}) } }

        composeRule.onNodeWithText("Google Pixel 9").assertIsDisplayed()
        composeRule.onNodeWithTag(DEVICE_INFO_LIST_TAG).performScrollToNode(hasText("Google Pixel 9 reference"))
        composeRule.onNodeWithText("Reference: ARM Mali-G715 MC7").assertExists()
        composeRule.onNodeWithTag(DEVICE_INFO_LIST_TAG).performScrollToNode(hasText("Internal storage"))
        composeRule.onNodeWithText("Internal storage").assertIsDisplayed()
    }

    @Test fun hidesComparisonWhenDisabled() {
        composeRule.setContent { RetroPlayTheme { DeviceInfoContent(ready(false), {}, {}) } }
        composeRule.onNodeWithText("Google Pixel 9 reference").assertDoesNotExist()
    }

    @Test fun errorStateOffersRetryAndBackWorks() {
        var retries = 0
        var backs = 0
        composeRule.setContent {
            RetroPlayTheme { DeviceInfoContent(DeviceInfoUiState.Error("boom"), { backs++ }, { retries++ }) }
        }
        composeRule.onNodeWithText("boom").assertIsDisplayed()
        composeRule.onNodeWithText("Retry").performClick()
        composeRule.onNodeWithContentDescription("Back").performClick()
        assertEquals(1, retries)
        assertEquals(1, backs)
    }
}
