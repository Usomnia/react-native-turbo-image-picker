package com.rnturboimagepicker

import android.graphics.Bitmap
import android.graphics.Rect

object TransitionHelper {
    var thumbnailBitmap: Bitmap? = null
    var editedBitmap: Bitmap? = null
    var sourceRect: Rect? = null
    var requestThumbnailRect: ((String) -> Rect?)? = null
    var onPageChanged: ((String) -> Unit)? = null
    var onViewerPageChanged: ((Int) -> Unit)? = null
    var onEditingFinished: ((String, Bitmap?, Boolean) -> Unit)? = null
}
