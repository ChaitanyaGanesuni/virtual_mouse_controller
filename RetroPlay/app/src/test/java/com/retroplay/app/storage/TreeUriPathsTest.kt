package com.retroplay.app.storage

import org.junit.Assert.assertEquals
import org.junit.Test

class TreeUriPathsTest {
    @Test fun internalStorage() {
        assertEquals(
            "Internal storage/Games/Vice City",
            TreeUriPaths.displayPath("content://com.android.externalstorage.documents/tree/primary%3AGames%2FVice%20City"),
        )
        assertEquals("Internal storage", TreeUriPaths.displayPath("content://com.android.externalstorage.documents/tree/primary%3A"))
    }

    @Test fun sdCard() {
        assertEquals(
            "SD card (1A2B-3C4D)/PC",
            TreeUriPaths.displayPath("content://com.android.externalstorage.documents/tree/1A2B-3C4D%3APC"),
        )
    }

    @Test fun otherProvidersAndMalformedUris() {
        assertEquals(
            "Games (via com.example.cloud)",
            TreeUriPaths.displayPath("content://com.example.cloud/tree/acc%3AGames"),
        )
        assertEquals("content://weird", TreeUriPaths.displayPath("content://weird"))
    }
}
