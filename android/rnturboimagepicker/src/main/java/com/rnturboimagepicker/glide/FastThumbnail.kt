package com.rnturboimagepicker.glide

import android.net.Uri

/**
 * Wrapper class for Uri that tells our custom Glide Module to use 
 * Android's native hardware-accelerated MediaStore thumbnails.
 */
data class FastThumbnail(val uri: Uri, val targetSize: Int = 400)
