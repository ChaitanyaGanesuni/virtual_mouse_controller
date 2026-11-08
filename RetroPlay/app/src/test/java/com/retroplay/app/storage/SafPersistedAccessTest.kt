package com.retroplay.app.storage

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Storage permission handling: persisted SAF read grants are taken, detected and released. */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class SafPersistedAccessTest {

    private val tree = "content://com.android.externalstorage.documents/tree/primary%3AGames"

    @Test fun takeHasAndReleaseReadPermission() {
        val access = SafDocumentTreeReader(ApplicationProvider.getApplicationContext<Context>())
        assertFalse(access.has(tree))
        assertTrue(access.take(tree).isSuccess)
        assertTrue(access.has(tree))
        access.release(tree)
        assertFalse(access.has(tree))
        // Releasing twice is harmless.
        access.release(tree)
    }

    @Test fun rootDocumentIdComesFromTreeUri() {
        val reader = SafDocumentTreeReader(ApplicationProvider.getApplicationContext<Context>())
        assertTrue(reader.rootDocumentId(tree) == "primary:Games")
    }
}
