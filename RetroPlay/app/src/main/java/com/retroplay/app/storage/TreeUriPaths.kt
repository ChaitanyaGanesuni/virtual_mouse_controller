package com.retroplay.app.storage

import java.net.URLDecoder

/** Turns a SAF tree URI into a readable location for the user. Pure string handling, no I/O. */
object TreeUriPaths {
    private const val EXTERNAL_STORAGE_AUTHORITY = "com.android.externalstorage.documents"

    fun displayPath(treeUri: String): String {
        val authority = treeUri.removePrefix("content://").substringBefore('/')
        val encodedId = treeUri.substringAfter("/tree/", missingDelimiterValue = "").substringBefore('/')
        if (encodedId.isEmpty()) return treeUri
        val treeId = URLDecoder.decode(encodedId, "UTF-8")
        if (authority != EXTERNAL_STORAGE_AUTHORITY) {
            return "${treeId.substringAfterLast(':').substringAfterLast('/').ifEmpty { treeId }} (via $authority)"
        }
        val volume = treeId.substringBefore(':')
        val path = treeId.substringAfter(':', missingDelimiterValue = "")
        val root = if (volume == "primary") "Internal storage" else "SD card ($volume)"
        return if (path.isEmpty()) root else "$root/$path"
    }
}
