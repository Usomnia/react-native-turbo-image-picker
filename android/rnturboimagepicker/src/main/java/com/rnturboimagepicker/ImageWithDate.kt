package com.rnturboimagepicker

import android.net.Uri
import java.util.Date

/**
 * Data class to store image URI with its creation date
 */
data class ImageWithDate(
    val uri: Uri,
    val dateAdded: Long // Unix timestamp in seconds
) {
    val date: Date get() = Date(dateAdded * 1000) // Convert seconds to milliseconds
}

