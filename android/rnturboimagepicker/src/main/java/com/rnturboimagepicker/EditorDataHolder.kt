package com.rnturboimagepicker

import android.net.Uri

/**
 * EditorDataHolder — in-memory singleton for passing URI list to ImageEditorActivity.
 *
 * Why: Intent extras are limited to ~1MB (Binder transaction limit).
 * Passing hundreds of URI strings via Intent can throw TransactionTooLargeException.
 * Instead, we store the list in-memory and pass only the start index via Intent.
 *
 * Lifecycle: set() before launching the Activity, clear() in onDestroy of the Activity.
 */
data class EditorData(
    val uris: List<Uri>, 
    val selectedUris: LinkedHashSet<Uri>,
    val editedUris: Map<String, Uri>
)

object EditorDataHolder {

    @Volatile
    private var data: EditorData = EditorData(emptyList(), LinkedHashSet(), emptyMap())

    fun set(list: List<Uri>, selected: LinkedHashSet<Uri> = LinkedHashSet(), edited: Map<String, Uri> = emptyMap()) {
        data = EditorData(list, selected, edited)
    }

    fun get(): List<Uri> = data.uris

    fun getSelected(): LinkedHashSet<Uri> = data.selectedUris
    
    fun getEdited(): Map<String, Uri> = data.editedUris

    fun clear() {
        data = EditorData(emptyList(), LinkedHashSet(), emptyMap())
    }
}
