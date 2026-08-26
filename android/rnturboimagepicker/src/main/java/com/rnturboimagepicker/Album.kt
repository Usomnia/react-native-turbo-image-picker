package com.rnturboimagepicker

import android.net.Uri

data class Album(
    val bucketId: String,
    val bucketName: String,
    val coverImageUri: Uri?,
    val imageCount: Int
)

