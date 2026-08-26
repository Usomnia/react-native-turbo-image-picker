package com.rnturboimagepicker.glide

import android.content.Context
import android.graphics.Bitmap
import com.bumptech.glide.load.Options
import com.bumptech.glide.load.model.ModelLoader
import com.bumptech.glide.load.model.ModelLoaderFactory
import com.bumptech.glide.load.model.MultiModelLoaderFactory
import com.bumptech.glide.signature.ObjectKey

class FastThumbnailModelLoader(private val context: Context) : ModelLoader<FastThumbnail, Bitmap> {

    override fun buildLoadData(
        model: FastThumbnail,
        width: Int,
        height: Int,
        options: Options
    ): ModelLoader.LoadData<Bitmap>? {
        return ModelLoader.LoadData(
            ObjectKey(model),
            FastThumbnailDataFetcher(context, model)
        )
    }

    override fun handles(model: FastThumbnail): Boolean {
        return true
    }

    class Factory(private val context: Context) : ModelLoaderFactory<FastThumbnail, Bitmap> {
        override fun build(multiFactory: MultiModelLoaderFactory): ModelLoader<FastThumbnail, Bitmap> {
            return FastThumbnailModelLoader(context)
        }

        override fun teardown() {
            // Nothing to tear down
        }
    }
}
