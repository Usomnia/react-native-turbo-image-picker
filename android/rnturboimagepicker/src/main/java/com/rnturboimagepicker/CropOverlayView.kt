package com.rnturboimagepicker

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PointF
import android.graphics.RectF
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import kotlin.math.max
import kotlin.math.min

class CropOverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    interface Listener {
        fun onCropRectChanged(rect: RectF)
        fun onCropInteractionEnded()
    }

    var listener: Listener? = null
    var cropRect = RectF()
        set(value) {
            field.set(value)
            invalidate()
        }

    // Coordinates of the image in the parent View's coordinates.
    // The CropOverlayView must clamp cropRect to this area.
    var imageDisplayRect = RectF()
        set(value) {
            field.set(value)
            clampCropRectToBounds()
        }

    private fun clampCropRectToBounds() {
        if (cropRect.isEmpty) return
        val bounds = getClampingBounds()
        if (bounds.isEmpty) return
        
        val r = RectF(cropRect)
        
        // Ensure cropRect is not larger than bounds
        if (r.width() > bounds.width()) {
            r.right = r.left + bounds.width()
        }
        if (r.height() > bounds.height()) {
            r.bottom = r.top + bounds.height()
        }
        
        // Offset if outside
        var dx = 0f
        var dy = 0f
        if (r.left < bounds.left) dx = bounds.left - r.left
        if (r.right > bounds.right) dx = bounds.right - r.right
        if (r.top < bounds.top) dy = bounds.top - r.top
        if (r.bottom > bounds.bottom) dy = bounds.bottom - r.bottom
        
        r.offset(dx, dy)
        
        if (r != cropRect) {
            cropRect.set(r)
        }
    }

    private val dimPaint = Paint().apply {
        style = Paint.Style.FILL
    }
    
    private val borderPaint = Paint().apply {
        style = Paint.Style.STROKE
        strokeWidth = 4f
        isAntiAlias = true
    }
    
    private val cornerPaint = Paint().apply {
        style = Paint.Style.FILL
        isAntiAlias = true
    }

    // Reusable grid paint — only alpha is updated per frame
    private val gridPaint = Paint().apply {
        strokeWidth = 2f
        style = Paint.Style.STROKE
    }
    
    private val cornerSize = 40f
    private val cornerThickness = 12f
    private val minCropSize = 150f
    private val handleHitRadius = 100f
    
    // Cached resolved colors — refreshed on config change
    private var cachedDimColor = 0
    private var cachedBorderColor = 0
    private var cachedGridColor = 0
    
    private enum class Handle { TL, TR, BL, BR, NONE }
    private var activeHandle = Handle.NONE
    private var isDraggingCenter = false
    
    private var panStart = PointF()
    private var cropAtPanStart = RectF()
    
    // Grid fade animation state
    private var gridAlpha = 0f
    private var gridAnimator: ValueAnimator? = null
    
    // Configured by parent if aspect ratio is fixed (width/height)
    var fixedAspectRatio: Float? = null
    
    init {
        refreshColors()
    }
    
    /** Resolve theme-adaptive colors. Call after configuration changes. */
    fun refreshColors() {
        cachedDimColor = context.getColor(R.color.crop_dim_overlay)
        cachedBorderColor = context.getColor(R.color.crop_border)
        cachedGridColor = context.getColor(R.color.crop_grid_line)
        dimPaint.color = cachedDimColor
        borderPaint.color = cachedBorderColor
        cornerPaint.color = cachedBorderColor
        invalidate()
    }
    
    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        val pt = PointF(event.x, event.y)
        val ziv = (parent as? android.view.ViewGroup)?.findViewById<ZoomableImageView>(R.id.zoomableImageView)
        
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                activeHandle = getNearestHandle(pt)
                if (activeHandle != Handle.NONE) {
                    panStart.set(pt)
                    cropAtPanStart.set(cropRect)
                    animateGridAlpha(1f)
                    return true
                } else if (cropRect.contains(pt.x, pt.y)) {
                    isDraggingCenter = true
                    panStart.set(pt)
                    cropAtPanStart.set(cropRect)
                    animateGridAlpha(1f)
                    
                    // Forward DOWN to ziv, but disable pan
                    val wasPanEnabled = ziv?.isPanEnabled ?: true
                    ziv?.isPanEnabled = false
                    ziv?.onTouchEvent(event)
                    ziv?.isPanEnabled = wasPanEnabled
                    
                    return true
                }
                return false // Let ZoomableImageView handle pan/zoom outside crop
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                if (isDraggingCenter) {
                    isDraggingCenter = false // Abort crop rect dragging, switch to pinch
                    animateGridAlpha(0f)
                }
                if (activeHandle == Handle.NONE) {
                    ziv?.onTouchEvent(event)
                }
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (activeHandle != Handle.NONE) {
                    val dx = pt.x - panStart.x
                    val dy = pt.y - panStart.y
                    applyCropResize(activeHandle, dx, dy)
                    listener?.onCropRectChanged(cropRect)
                    invalidate()
                    return true
                } else if (isDraggingCenter) {
                    val dx = pt.x - panStart.x
                    val dy = pt.y - panStart.y
                    moveCropRect(dx, dy)
                    listener?.onCropRectChanged(cropRect)
                    invalidate()
                    return true
                } else {
                    // Pinching or panning image after pinch
                    ziv?.onTouchEvent(event)
                    return true
                }
            }
            MotionEvent.ACTION_POINTER_UP -> {
                if (activeHandle == Handle.NONE && !isDraggingCenter) {
                    ziv?.onTouchEvent(event)
                }
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (activeHandle != Handle.NONE) {
                    activeHandle = Handle.NONE
                    listener?.onCropInteractionEnded()
                    animateGridAlpha(0f)
                } else {
                    if (isDraggingCenter) {
                        isDraggingCenter = false
                        listener?.onCropInteractionEnded()
                        animateGridAlpha(0f)
                    }
                    ziv?.onTouchEvent(event)
                }
                return true
            }
        }
        return super.onTouchEvent(event)
    }
    
    private fun animateGridAlpha(target: Float) {
        gridAnimator?.cancel()
        gridAnimator = ValueAnimator.ofFloat(gridAlpha, target).apply {
            duration = 200
            addUpdateListener { anim ->
                gridAlpha = anim.animatedValue as Float
                invalidate()
            }
            start()
        }
    }
    
    private fun getNearestHandle(pt: PointF): Handle {
        val r = handleHitRadius
        // Inline distance checks — avoids Map allocation on every touch
        if (Math.hypot((pt.x - cropRect.left).toDouble(), (pt.y - cropRect.top).toDouble()) <= r) return Handle.TL
        if (Math.hypot((pt.x - cropRect.right).toDouble(), (pt.y - cropRect.top).toDouble()) <= r) return Handle.TR
        if (Math.hypot((pt.x - cropRect.left).toDouble(), (pt.y - cropRect.bottom).toDouble()) <= r) return Handle.BL
        if (Math.hypot((pt.x - cropRect.right).toDouble(), (pt.y - cropRect.bottom).toDouble()) <= r) return Handle.BR
        return Handle.NONE
    }
    
    private fun getClampingBounds(): RectF {
        val bounds = RectF(imageDisplayRect)
        bounds.left = max(bounds.left, 0f)
        bounds.top = max(bounds.top, 0f)
        bounds.right = min(bounds.right, width.toFloat())
        bounds.bottom = min(bounds.bottom, height.toFloat())
        return bounds
    }

    private fun moveCropRect(dx: Float, dy: Float) {
        val r = RectF(cropAtPanStart)
        r.offset(dx, dy)
        
        val bounds = getClampingBounds()
        
        // Clamp to bounds
        val maxX = max(bounds.left, bounds.right - r.width())
        val maxY = max(bounds.top, bounds.bottom - r.height())
        
        val clampedX = max(bounds.left, min(r.left, maxX))
        val clampedY = max(bounds.top, min(r.top, maxY))
        
        r.offsetTo(clampedX, clampedY)
        cropRect.set(r)
    }
    
    private fun applyCropResize(handle: Handle, dx: Float, dy: Float) {
        val r = RectF(cropAtPanStart)
        val bounds = getClampingBounds()
        
        when (handle) {
            Handle.TL -> {
                val newX = max(bounds.left, min(r.left + dx, r.right - minCropSize))
                val newY = max(bounds.top, min(r.top + dy, r.bottom - minCropSize))
                r.left = newX
                r.top = newY
            }
            Handle.TR -> {
                val newY = max(bounds.top, min(r.top + dy, r.bottom - minCropSize))
                val newRight = max(r.left + minCropSize, min(r.right + dx, bounds.right))
                r.top = newY
                r.right = newRight
            }
            Handle.BL -> {
                val newX = max(bounds.left, min(r.left + dx, r.right - minCropSize))
                val newBottom = max(r.top + minCropSize, min(r.bottom + dy, bounds.bottom))
                r.left = newX
                r.bottom = newBottom
            }
            Handle.BR -> {
                val newRight = max(r.left + minCropSize, min(r.right + dx, bounds.right))
                val newBottom = max(r.top + minCropSize, min(r.bottom + dy, bounds.bottom))
                r.right = newRight
                r.bottom = newBottom
            }
            else -> {}
        }
        
        // Apply aspect ratio
        fixedAspectRatio?.let { ratio ->
            when (handle) {
                Handle.TL, Handle.BL -> {
                    val expectedH = r.width() / ratio
                    val diff = expectedH - r.height()
                    if (handle == Handle.TL) {
                        r.top -= diff
                        if (r.top < bounds.top) {
                            r.top = bounds.top
                            r.left = r.right - (r.height() * ratio)
                        }
                    } else {
                        r.bottom += diff
                        if (r.bottom > bounds.bottom) {
                            r.bottom = bounds.bottom
                            r.left = r.right - (r.height() * ratio)
                        }
                    }
                }
                Handle.TR, Handle.BR -> {
                    val expectedH = r.width() / ratio
                    val diff = expectedH - r.height()
                    if (handle == Handle.TR) {
                        r.top -= diff
                        if (r.top < bounds.top) {
                            r.top = bounds.top
                            r.right = r.left + (r.height() * ratio)
                        }
                    } else {
                        r.bottom += diff
                        if (r.bottom > bounds.bottom) {
                            r.bottom = bounds.bottom
                            r.right = r.left + (r.height() * ratio)
                        }
                    }
                }
                else -> {}
            }
        }
        
        cropRect.set(r)
    }
    
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (cropRect.isEmpty) return

        // Colors are pre-cached in refreshColors(); no getColor() calls here
        
        // Draw dim background outside cropRect
        canvas.drawRect(0f, 0f, width.toFloat(), cropRect.top, dimPaint)
        canvas.drawRect(0f, cropRect.bottom, width.toFloat(), height.toFloat(), dimPaint)
        canvas.drawRect(0f, cropRect.top, cropRect.left, cropRect.bottom, dimPaint)
        canvas.drawRect(cropRect.right, cropRect.top, width.toFloat(), cropRect.bottom, dimPaint)
        
        // Draw border
        canvas.drawRect(cropRect, borderPaint)
        
        // Draw grid lines only when interacting (based on animated alpha)
        if (gridAlpha > 0f) {
            val gridLines = 3
            val colWidth = cropRect.width() / gridLines
            val rowHeight = cropRect.height() / gridLines
            
            // Reuse gridPaint — only update alpha
            val alphaInt = (android.graphics.Color.alpha(cachedGridColor) * gridAlpha).toInt()
            gridPaint.color = android.graphics.Color.argb(alphaInt,
                android.graphics.Color.red(cachedGridColor),
                android.graphics.Color.green(cachedGridColor),
                android.graphics.Color.blue(cachedGridColor))
            
            for (i in 1 until gridLines) {
                val x = cropRect.left + i * colWidth
                canvas.drawLine(x, cropRect.top, x, cropRect.bottom, gridPaint)
                val y = cropRect.top + i * rowHeight
                canvas.drawLine(cropRect.left, y, cropRect.right, y, gridPaint)
            }
        }
        
        // Draw corners
        drawCorner(canvas, cropRect.left, cropRect.top, 1f, 1f)
        drawCorner(canvas, cropRect.right, cropRect.top, -1f, 1f)
        drawCorner(canvas, cropRect.left, cropRect.bottom, 1f, -1f)
        drawCorner(canvas, cropRect.right, cropRect.bottom, -1f, -1f)
    }
    
    private fun drawCorner(canvas: Canvas, cx: Float, cy: Float, dirX: Float, dirY: Float) {
        // Horizontal rect
        canvas.drawRect(
            min(cx, cx + cornerSize * dirX),
            min(cy, cy + cornerThickness * dirY),
            max(cx, cx + cornerSize * dirX),
            max(cy, cy + cornerThickness * dirY),
            cornerPaint
        )
        // Vertical rect
        canvas.drawRect(
            min(cx, cx + cornerThickness * dirX),
            min(cy, cy + cornerSize * dirY),
            max(cx, cx + cornerThickness * dirX),
            max(cy, cy + cornerSize * dirY),
            cornerPaint
        )
    }
}
