package com.retroplay.app.storage

import com.retroplay.app.domain.model.ImportValidity
import javax.inject.Inject

sealed interface ValidationOutcome {
    data class Valid(val sizeBytes: Long) : ValidationOutcome
    data class Invalid(val validity: ImportValidity, val message: String) : ValidationOutcome
}

/**
 * Checks that a selected executable is still reachable and looks like a Windows program.
 * It only reads the first two bytes (the "MZ" DOS header). Files are never executed or modified.
 */
class ExecutableValidator @Inject constructor(
    private val reader: DocumentTreeReader,
    private val access: PersistedFolderAccess,
) {
    fun validate(treeUri: String, relativePath: String): ValidationOutcome {
        if (!access.has(treeUri)) {
            return ValidationOutcome.Invalid(
                ImportValidity.PERMISSION_LOST,
                "RetroPlay no longer has access to this folder. Select it again to restore access.",
            )
        }
        if (!hasExeExtension(relativePath)) {
            return ValidationOutcome.Invalid(ImportValidity.INVALID_EXECUTABLE, "The selected file is not an .exe file.")
        }
        return try {
            val entry = resolve(treeUri, relativePath)
                ?: return ValidationOutcome.Invalid(
                    ImportValidity.EXECUTABLE_MISSING,
                    "$relativePath was not found in the folder. It may have been moved, renamed or deleted.",
                )
            when {
                entry.isDirectory -> ValidationOutcome.Invalid(ImportValidity.INVALID_EXECUTABLE, "$relativePath is a folder, not a file.")
                entry.sizeBytes == 0L -> ValidationOutcome.Invalid(ImportValidity.INVALID_EXECUTABLE, "$relativePath is empty.")
                !isWindowsExecutable(reader.readHeader(treeUri, entry.documentId, 2)) -> ValidationOutcome.Invalid(
                    ImportValidity.INVALID_EXECUTABLE,
                    "$relativePath does not look like a Windows executable (missing MZ header).",
                )
                else -> ValidationOutcome.Valid(entry.sizeBytes)
            }
        } catch (e: FolderAccessLostException) {
            ValidationOutcome.Invalid(ImportValidity.PERMISSION_LOST, e.message ?: "Access to the folder was revoked.")
        } catch (e: DocumentNotFoundException) {
            ValidationOutcome.Invalid(ImportValidity.FOLDER_MISSING, "The folder could not be found. It may have been moved, deleted or is on removed storage.")
        }
    }

    /** Walks [relativePath] segment by segment (case-insensitive, like Windows). */
    private fun resolve(treeUri: String, relativePath: String): DocumentEntry? {
        var docId = reader.rootDocumentId(treeUri)
        val segments = relativePath.split('/').filter { it.isNotEmpty() }
        var found: DocumentEntry? = null
        segments.forEachIndexed { index, segment ->
            val match = reader.listChildren(treeUri, docId).firstOrNull { it.name.equals(segment, ignoreCase = true) }
                ?: return null
            if (index < segments.lastIndex && !match.isDirectory) return null
            docId = match.documentId
            found = match
        }
        return found
    }

    companion object {
        fun hasExeExtension(name: String): Boolean = name.endsWith(".exe", ignoreCase = true)

        fun isWindowsExecutable(header: ByteArray): Boolean =
            header.size >= 2 && header[0] == 'M'.code.toByte() && header[1] == 'Z'.code.toByte()
    }
}
