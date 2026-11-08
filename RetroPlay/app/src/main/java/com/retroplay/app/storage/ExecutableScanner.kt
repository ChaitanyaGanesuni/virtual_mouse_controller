package com.retroplay.app.storage

import javax.inject.Inject

data class ExecutableCandidate(val relativePath: String, val sizeBytes: Long)

data class ScanResult(
    val candidates: List<ExecutableCandidate>,
    val entriesVisited: Int,
    /** True when the depth or entry limit stopped the scan early. */
    val truncated: Boolean,
)

/** Finds .exe files in a document tree, breadth-first, within depth and size limits. Read-only. */
class ExecutableScanner @Inject constructor(private val reader: DocumentTreeReader) {

    fun scan(treeUri: String, maxDepth: Int = DEFAULT_MAX_DEPTH, maxEntries: Int = DEFAULT_MAX_ENTRIES): ScanResult {
        val candidates = mutableListOf<ExecutableCandidate>()
        val queue = ArrayDeque<Triple<String, String, Int>>() // documentId, relative path prefix, depth
        queue += Triple(reader.rootDocumentId(treeUri), "", 0)
        var visited = 0
        var truncated = false
        while (queue.isNotEmpty()) {
            val (docId, prefix, depth) = queue.removeFirst()
            for (entry in reader.listChildren(treeUri, docId)) {
                if (visited >= maxEntries) {
                    truncated = true
                    break
                }
                visited++
                val path = prefix + entry.name
                if (entry.isDirectory) {
                    if (depth + 1 <= maxDepth) queue += Triple(entry.documentId, "$path/", depth + 1) else truncated = true
                } else if (ExecutableValidator.hasExeExtension(entry.name)) {
                    candidates += ExecutableCandidate(path, entry.sizeBytes)
                }
            }
            if (visited >= maxEntries && queue.isNotEmpty()) {
                truncated = true
                break
            }
        }
        // Shallow files first: the main game executable is usually near the top of the folder.
        val sorted = candidates.sortedWith(compareBy({ it.relativePath.count { c -> c == '/' } }, { it.relativePath.lowercase() }))
        return ScanResult(sorted, visited, truncated)
    }

    companion object {
        const val DEFAULT_MAX_DEPTH = 4
        const val DEFAULT_MAX_ENTRIES = 5_000
    }
}
