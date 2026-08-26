package com.rnturboimagepicker.glide

import android.content.Context
import android.graphics.Bitmap
import com.bumptech.glide.Glide
import com.bumptech.glide.GlideBuilder
import com.bumptech.glide.Registry
import com.bumptech.glide.module.GlideModule

@Suppress("DEPRECATION")
class TurboImagePickerGlideModule : GlideModule {
    override fun applyOptions(context: Context, builder: GlideBuilder) {
        // No options needed
    }

    override fun registerComponents(context: Context, glide: Glide, registry: Registry) {
        registry.prepend(
            FastThumbnail::class.java,
            Bitmap::class.java,
            FastThumbnailModelLoader.Factory(context)
        )
    }
}
