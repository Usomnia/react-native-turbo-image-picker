package com.rnturboimagepicker

import android.content.Context
import android.graphics.Bitmap

object ImageProcessor {

    /**
     * Checks license and applies evaluation watermark if license is invalid.
     * This method is intended to be called from the RN bridge layer.
     */
    @JvmStatic
    fun applyWatermarkIfNeeded(context: Context, bitmap: Bitmap): Bitmap {
        return if (!LicenseManager.isValidLicense(context)) {
            applyEvaluationWatermark(bitmap)
        } else {
            bitmap
        }
    }

    /**
     * Applies a repeating diagonal "Turbo Image Picker" watermark pattern.
     */
    @JvmStatic
    fun applyEvaluationWatermark(bitmap: Bitmap): Bitmap {
        val mutableBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = android.graphics.Canvas(mutableBitmap)

        val text = "Turbo Image Picker"
        val textPaint = android.text.TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.argb(80, 255, 255, 255) // ~31% white
            textSize = Math.max(14f, Math.min(bitmap.width, bitmap.height) / 20f)
            typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
            setShadowLayer(4f, 2f, 2f, android.graphics.Color.argb(40, 0, 0, 0)) // light shadow
        }

        val textWidth = textPaint.measureText(text)
        val textHeight = textPaint.descent() - textPaint.ascent()

        val diagonal = Math.hypot(bitmap.width.toDouble(), bitmap.height.toDouble()).toFloat()

        canvas.save()
        canvas.translate(bitmap.width / 2f, bitmap.height / 2f)
        canvas.rotate(-35f)
        canvas.translate(-diagonal / 2f, -diagonal / 2f)

        val stepX = textWidth * 1.5f
        val stepY = textHeight * 3.5f

        var y = 0f
        var row = 0
        while (y < diagonal + stepY) {
            var x = 0f
            val offset = if (row % 2 == 0) 0f else stepX / 2f
            while (x < diagonal + stepX) {
                canvas.drawText(text, x + offset, y, textPaint)
                x += stepX
            }
            y += stepY
            row++
        }

        canvas.restore()
        return mutableBitmap
    }
}
