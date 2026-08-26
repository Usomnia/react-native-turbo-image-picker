package com.rnturboimagepicker

import android.content.Context
import android.util.AttributeSet
import android.widget.FrameLayout

/**
 * A FrameLayout that maintains a square aspect ratio (width == height)
 * Height is automatically set to match the width
 */
class SquareFrameLayout @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {

    var verticalSpan: Int = 1
        set(value) {
            field = value
            requestLayout()
        }
        
    var verticalSpacing: Int = 0
        set(value) {
            field = value
            requestLayout()
        }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        // Height equals width * verticalSpan + spacing between spans
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val exactHeight = (width * verticalSpan) + (verticalSpacing * (verticalSpan - 1))
        val newHeightSpec = MeasureSpec.makeMeasureSpec(exactHeight, MeasureSpec.EXACTLY)
        super.onMeasure(widthMeasureSpec, newHeightSpec)
    }
}

