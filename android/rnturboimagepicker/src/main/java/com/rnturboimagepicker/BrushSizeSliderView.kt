package com.rnturboimagepicker

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import kotlin.math.roundToInt

/**
 * BrushSizeSliderView
 *
 * iOS BrushSizeSliderView에 대응하는 Android View.
 * 세로 방향 테이퍼형 슬라이더: 상단 넓고 하단 좁음.
 * 드래그/탭으로 값 변경. 콜백으로 외부에 알림.
 */
class BrushSizeSliderView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    interface Listener {
        fun onValueChanged(value: Float)
        fun onDragBegan()
        fun onDragEnded()
    }

    var listener: Listener? = null

    var minimumValue: Float = 2f
    var maximumValue: Float = 50f
    var value: Float = 10f
        set(v) {
            field = v.coerceIn(minimumValue, maximumValue)
            invalidate()
        }

    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(128, 255, 255, 255)
        style = Paint.Style.FILL
    }

    private val thumbPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
        setShadowLayer(8f, 0f, 0f, Color.argb(80, 0, 0, 0))
    }

    private val trackPath = Path()
    private val thumbSize = 30f.dpToPx()

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val w = width.toFloat()
        val h = height.toFloat()
        val midX = w / 2f
        val topWidth = 16f.dpToPx()
        val bottomWidth = 4f.dpToPx()

        // Draw tapered track
        trackPath.reset()
        trackPath.moveTo(midX - topWidth / 2f, topWidth / 2f)
        trackPath.arcTo(
            RectF(midX - topWidth / 2f, 0f, midX + topWidth / 2f, topWidth),
            180f, 180f
        )
        trackPath.lineTo(midX + bottomWidth / 2f, h - bottomWidth / 2f)
        trackPath.arcTo(
            RectF(midX - bottomWidth / 2f, h - bottomWidth, midX + bottomWidth / 2f, h),
            0f, 180f
        )
        trackPath.close()
        canvas.drawPath(trackPath, trackPaint)

        // Draw thumb
        val thumbY = thumbYFromValue()
        canvas.drawCircle(midX, thumbY, thumbSize / 2f, thumbPaint)
    }

    private fun thumbYFromValue(): Float {
        val topY = thumbSize / 2f
        val bottomY = height - thumbSize / 2f
        val pct = (value - minimumValue) / (maximumValue - minimumValue)
        return bottomY - pct * (bottomY - topY)
    }

    private fun valueFromY(y: Float): Float {
        val topY = thumbSize / 2f
        val bottomY = height - thumbSize / 2f
        val clamped = y.coerceIn(topY, bottomY)
        val pct = 1f - (clamped - topY) / (bottomY - topY)
        return minimumValue + pct * (maximumValue - minimumValue)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                value = valueFromY(event.y)
                listener?.onValueChanged(value)
                listener?.onDragBegan()
            }
            MotionEvent.ACTION_MOVE -> {
                value = valueFromY(event.y)
                listener?.onValueChanged(value)
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                listener?.onDragEnded()
            }
        }
        invalidate()
        return true
    }

    private fun Float.dpToPx(): Float {
        return this * context.resources.displayMetrics.density
    }

    init {
        setLayerType(LAYER_TYPE_SOFTWARE, null) // for shadow
    }
}
