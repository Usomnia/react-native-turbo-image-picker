package com.rnturboimagepicker.glide

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import com.bumptech.glide.Priority
import com.bumptech.glide.load.DataSource
import com.bumptech.glide.load.data.DataFetcher
import java.io.IOException

class FastThumbnailDataFetcher(
    private val context: Context,
    private val model: FastThumbnail
) : DataFetcher<Bitmap> {

    private var isCancelled = false

    override fun loadData(priority: Priority, callback: DataFetcher.DataCallback<in Bitmap>) {
        if (isCancelled) return
        
        try {
            val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Native ultra-fast thumbnail loading on Android 10+
                context.contentResolver.loadThumbnail(model.uri, Size(model.targetSize, model.targetSize), null)
            } else {
                // Fallback for older Android versions
                val id = ContentUris.parseId(model.uri)
                MediaStore.Images.Thumbnails.getThumbnail(
                    context.contentResolver,
                    id,
                    MediaStore.Images.Thumbnails.MINI_KIND,
                    null
                )
            }
            
            if (bitmap != null && !isCancelled) {
                callback.onDataReady(bitmap)
            } else {
                callback.onLoadFailed(IOException("Failed to load thumbnail bitmap or cancelled"))
            }
        } catch (e: Exception) {
            callback.onLoadFailed(e)
        }
    }

    override fun cleanup() {
        // Nothing to clean up
    }

    override fun cancel() {
        isCancelled = true
    }

    override fun getDataClass(): Class<Bitmap> {
        return Bitmap::class.java
    }

    override fun getDataSource(): DataSource {
        return DataSource.LOCAL
    }
}
