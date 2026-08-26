package com.rnturboimagepicker

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.util.AttributeSet
import android.view.View

class CircleDashedOverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb((255 * 0.6).toInt(), 0, 0, 0) // Black with 0.6 alpha
        style = Paint.Style.FILL
    }

    private val clearPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
    }

    private val dashPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 1.5f * context.resources.displayMetrics.density
        pathEffect = DashPathEffect(floatArrayOf(
            8f * context.resources.displayMetrics.density,
            4f * context.resources.displayMetrics.density
        ), 0f)
    }

    private val clipPath = Path()

    init {
        // We need hardware acceleration for CLEAR to work correctly on a View,
        // or we use a software layer. Software layer is safer for PorterDuff.Mode.CLEAR.
        setLayerType(LAYER_TYPE_SOFTWARE, null)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val w = width.toFloat()
        val h = height.toFloat()
        val radius = Math.min(w, h) / 2f
        val cx = w / 2f
        val cy = h / 2f

        // Draw the semi-transparent background
        canvas.drawRect(0f, 0f, w, h, bgPaint)

        // Clear the inner circle
        canvas.drawCircle(cx, cy, radius, clearPaint)

        // Draw the dashed stroke
        canvas.drawCircle(cx, cy, radius, dashPaint)
    }
}
