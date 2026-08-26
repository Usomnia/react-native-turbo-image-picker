package com.rnturboimagepicker

import com.bumptech.glide.request.RequestListener
import com.bumptech.glide.load.engine.GlideException
import com.bumptech.glide.request.target.Target
import android.graphics.drawable.Drawable
import com.bumptech.glide.load.DataSource

val x = object : RequestListener<Drawable> {
    override fun onLoadFailed(
        e: GlideException?,
        model: Any?,
        target: Target<Drawable>,
        isFirstResource: Boolean
    ): Boolean = false

    override fun onResourceReady(
        resource: Drawable,
        model: Any,
        target: Target<Drawable>?,
        dataSource: DataSource,
        isFirstResource: Boolean
    ): Boolean = false
}
