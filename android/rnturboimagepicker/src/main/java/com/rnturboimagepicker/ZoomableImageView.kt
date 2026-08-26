package com.rnturboimagepicker

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Matrix
import android.graphics.PointF
import android.graphics.RectF
import android.util.AttributeSet
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.ViewConfiguration
import android.view.animation.DecelerateInterpolator
import androidx.appcompat.widget.AppCompatImageView
import kotlin.math.abs
import kotlin.math.min

/**
 * ZoomableImageView — 핀치줌 고도화
 *
 * 핵심 개선:
 * 1. ACTION_POINTER_UP 시 lastTouch 리셋 → 핀치 해제 후 팬 점프 제거
 * 2. 팬 중 즉시 경계 클램프 (gaps 발생 없음)
 * 3. 핀치 종료 후 경계 벗어난 경우만 animatedSnapToBounds
 * 4. 두 손가락 중앙(focal point) + 이동량 패닝 동시 적용
 */
class ZoomableImageView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : AppCompatImageView(context, attrs, defStyleAttr) {

    companion object {
        private const val MIN_ZOOM = 1.0f
        private const val MAX_ZOOM = 5.0f
        private const val DOUBLE_TAP_ZOOM = 2.5f
        private const val SNAP_ANIM_DURATION = 180L
        private const val ZOOM_ANIM_DURATION = 220L
    }

    // ─────────────────────────────────────────────
    // Matrix & state
    // ─────────────────────────────────────────────

    private val m = Matrix()
    private var baseScale = 1.0f
    private var currentZoom = 1.0f
    private var isReady = false

    // ─────────────────────────────────────────────
    // Gesture detectors
    // ─────────────────────────────────────────────

    private val scaleDetector = ScaleGestureDetector(context, PinchListener())
    private val gestureDetector = GestureDetector(context, TapListener())
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop

    // Pan state
    private val lastTouch = PointF()
    private var isDragging = false
    private var isScaling = false  // true while pinch is active

    // Active animator — tracked to prevent leaks and cancel before new animation
    private var currentAnimator: ValueAnimator? = null
    
    var onMatrixChanged: ((Matrix) -> Unit)? = null
    var isAspectFill: Boolean = false

    init {
        scaleType = ScaleType.MATRIX
    }


    // ─────────────────────────────────────────────
    // Layout & image
    // ─────────────────────────────────────────────

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w > 0 && h > 0 && drawable != null) setupInitialMatrix()
    }

    override fun setImageBitmap(bm: android.graphics.Bitmap?) {
        super.setImageBitmap(bm)
        isReady = false
        currentZoom = 1.0f
        if (width > 0 && height > 0) setupInitialMatrix()
    }

    val currentZoomFactor: Float get() = currentZoom
    val currentImageMatrix: Matrix get() = m
    val initialImageMatrix: Matrix = Matrix()

    private fun setupInitialMatrix() {
        val d = drawable ?: return
        val vw = width.toFloat()
        val vh = height.toFloat()
        if (vw == 0f || vh == 0f) return
        val dw = d.intrinsicWidth.toFloat()
        val dh = d.intrinsicHeight.toFloat()
        if (dw == 0f || dh == 0f) return

        val scale = if (isAspectFill) {
            // Fill the circle (square = min dimension), not the full non-square view
            val circleSize = min(vw, vh)
            kotlin.math.max(circleSize / dw, circleSize / dh)
        } else {
            min(vw / dw, vh / dh)
        }
        
        baseScale = scale
        currentZoom = 1.0f
        m.reset()
        m.setScale(scale, scale)
        m.postTranslate((vw - dw * scale) / 2f, (vh - dh * scale) / 2f)
        initialImageMatrix.set(m)
        imageMatrix = m
        onMatrixChanged?.invoke(m)
        isReady = true
    }

    fun setImageBitmapWithoutReset(bm: android.graphics.Bitmap?) {
        super.setImageBitmap(bm)
    }

    /**
     * Applies a 90-degree CW rotated bitmap while mathematically preserving the current zoom
     * and pan state. This prevents the image from snapping back to 1.0 scale after rotation.
     */
    fun applyRotatedBitmap(rotated: android.graphics.Bitmap) {
        val oldDh = (drawable?.intrinsicHeight ?: 0).toFloat()
        val vw = width.toFloat()
        val vh = height.toFloat()

        if (vw == 0f || vh == 0f || oldDh == 0f) {
            setImageBitmap(rotated)
            return
        }

        // M_new = R_view * M_old * R_bmp_inv
        val rBmpInv = Matrix()
        rBmpInv.postRotate(-90f)
        rBmpInv.postTranslate(0f, oldDh)

        val mNew = Matrix()
        mNew.set(rBmpInv)
        mNew.postConcat(m)

        val rView = Matrix()
        rView.postRotate(90f, vw / 2f, vh / 2f)
        mNew.postConcat(rView)

        val newDw = rotated.width.toFloat()
        val newDh = rotated.height.toFloat()

        val newBaseScale = if (isAspectFill) {
            val circleSize = min(vw, vh)
            kotlin.math.max(circleSize / newDw, circleSize / newDh)
        } else {
            min(vw / newDw, vh / newDh)
        }

        val values = FloatArray(9)
        mNew.getValues(values)
        val actualScaleX = values[Matrix.MSCALE_X]
        val newCurrentZoom = actualScaleX / newBaseScale

        setImageBitmapWithoutReset(rotated)

        baseScale = newBaseScale
        currentZoom = newCurrentZoom
        m.set(mNew)
        imageMatrix = m

        initialImageMatrix.reset()
        initialImageMatrix.setScale(newBaseScale, newBaseScale)
        initialImageMatrix.postTranslate((vw - newDw * newBaseScale) / 2f, (vh - newDh * newBaseScale) / 2f)

        onMatrixChanged?.invoke(m)
        isReady = true
    }

    var isAnimating = false

    fun animateMatrixRotation(degrees: Float, durationMs: Long, onEnd: () -> Unit) {
        if (isAnimating) return
        isAnimating = true

        val startMatrix = Matrix(m)
        val vw = width.toFloat()
        val vh = height.toFloat()

        val animator = android.animation.ValueAnimator.ofFloat(0f, degrees)
        animator.duration = durationMs
        animator.interpolator = android.view.animation.AccelerateDecelerateInterpolator()
        animator.addUpdateListener { anim ->
            val angle = anim.animatedValue as Float
            val tempMatrix = Matrix(startMatrix)
            tempMatrix.postRotate(angle, vw / 2f, vh / 2f)
            imageMatrix = tempMatrix
        }
        animator.addListener(object : android.animation.AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: android.animation.Animator) {
                isAnimating = false
                onEnd()
            }
        })
        animator.start()
    }

    // ─────────────────────────────────────────────
    var isPanEnabled = true

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!isReady || isAnimating) return false

        var handled = scaleDetector.onTouchEvent(event)
        handled = gestureDetector.onTouchEvent(event) || handled

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                lastTouch.set(event.x, event.y)
                isDragging = false
                parent?.requestDisallowInterceptTouchEvent(currentZoom > 1.0f || isAspectFill)
            }

            MotionEvent.ACTION_POINTER_DOWN -> {
                // Multi-touch start — disable single-finger pan
                isScaling = true
                isDragging = false
            }

            MotionEvent.ACTION_POINTER_UP -> {
                // A finger lifted — reset lastTouch to the REMAINING finger
                // so the next ACTION_MOVE doesn't produce a giant jump
                val upIndex = event.actionIndex
                val remainIndex = if (upIndex == 0) 1 else 0
                if (remainIndex < event.pointerCount) {
                    lastTouch.set(event.getX(remainIndex), event.getY(remainIndex))
                }
                isDragging = false
                // Keep isScaling = true until ACTION_UP to absorb remaining moves
            }

            MotionEvent.ACTION_MOVE -> {
                // Only pan with single finger, not during pinch
                if (isPanEnabled && !scaleDetector.isInProgress && !isScaling && event.pointerCount == 1 && (currentZoom > 1.0f || isAspectFill)) {
                    val dx = event.x - lastTouch.x
                    val dy = event.y - lastTouch.y
                    if (!isDragging && (abs(dx) > touchSlop || abs(dy) > touchSlop)) {
                        isDragging = true
                    }
                    if (isDragging) {
                        val delegate = shouldDelegateToParent(dx, dy)
                        parent?.requestDisallowInterceptTouchEvent(!delegate)
                        if (!delegate) {
                            applyConstrainedPan(dx, dy)
                            handled = true
                        }
                    }
                }
                lastTouch.set(event.x, event.y)
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                isScaling = false
                isDragging = false
                parent?.requestDisallowInterceptTouchEvent(false)
            }
        }

        return handled || super.onTouchEvent(event)
    }

    // ─────────────────────────────────────────────
    // Pan — immediate boundary clamp (no gaps)
    // ─────────────────────────────────────────────

    private fun applyConstrainedPan(dx: Float, dy: Float) {
        val bounds = getImageBounds()
        val vw = width.toFloat()
        val vh = height.toFloat()

        var cdx = dx
        var cdy = dy

        if (isAspectFill) {
            // Circle-based constraint: image must always cover the circle.
            // Circle center = (vw/2, vh/2), radius = min(vw,vh)/2
            val r = min(vw, vh) / 2f
            val cx = vw / 2f
            val cy = vh / 2f
            val circleLeft  = cx - r
            val circleRight = cx + r
            val circleTop   = cy - r
            val circleBottom = cy + r

            // Horizontal: image right edge must reach circleRight, left edge must be <= circleLeft
            if (bounds.width() < r * 2f) {
                cdx = 0f  // image narrower than circle (shouldn't happen after aspect-fill)
            } else {
                if (bounds.left + cdx > circleLeft)  cdx = circleLeft  - bounds.left
                if (bounds.right + cdx < circleRight) cdx = circleRight - bounds.right
            }

            // Vertical: same logic
            if (bounds.height() < r * 2f) {
                cdy = 0f
            } else {
                if (bounds.top  + cdy > circleTop)    cdy = circleTop    - bounds.top
                if (bounds.bottom + cdy < circleBottom) cdy = circleBottom - bounds.bottom
            }
        } else {
            if (bounds.width() <= vw) cdx = 0f
            else {
                if (bounds.left + cdx > 0f) cdx = -bounds.left
                else if (bounds.right + cdx < vw) cdx = vw - bounds.right
            }
            if (bounds.height() <= vh) cdy = 0f
            else {
                if (bounds.top + cdy > 0f) cdy = -bounds.top
                else if (bounds.bottom + cdy < vh) cdy = vh - bounds.bottom
            }
        }

        m.postTranslate(cdx, cdy)
        imageMatrix = m
        onMatrixChanged?.invoke(m)
    }

    // ─────────────────────────────────────────────
    // Boundary helpers
    // ─────────────────────────────────────────────

    private fun getImageBounds(): RectF {
        val d = drawable ?: return RectF()
        val rect = RectF(0f, 0f, d.intrinsicWidth.toFloat(), d.intrinsicHeight.toFloat())
        m.mapRect(rect)
        return rect
    }

    private fun shouldDelegateToParent(dx: Float, dy: Float): Boolean {
        val bounds = getImageBounds()
        val isVerticalSwipe = abs(dy) > abs(dx)
        
        if (isVerticalSwipe) {
            val topBound = if (isAspectFill) {
                val vh = height.toFloat()
                val vw = width.toFloat()
                (vh / 2f) - (min(vw, vh) / 2f)
            } else {
                0f
            }
            val atTop = bounds.top >= topBound - 1f
            return atTop && dy > 0
        } else {
            val atLeft = bounds.left >= -1f
            val atRight = bounds.right <= width.toFloat() + 1f
            return (atLeft && dx > 0) || (atRight && dx < 0)
        }
    }

    /**
     * Only snaps if actually out of bounds; animates the correction.
     */
    private fun animatedSnapToBounds() {
        val bounds = getImageBounds()
        val vw = width.toFloat()
        val vh = height.toFloat()
        var snapDx = 0f
        var snapDy = 0f

        if (isAspectFill) {
            val r = min(vw, vh) / 2f
            val cx = vw / 2f; val cy = vh / 2f
            val cL = cx - r; val cR = cx + r
            val cT = cy - r; val cB = cy + r
            if (bounds.width() >= r * 2f) {
                if (bounds.left > cL) snapDx = cL - bounds.left
                else if (bounds.right < cR) snapDx = cR - bounds.right
            } else {
                snapDx = cx - (bounds.left + bounds.width() / 2f)
            }
            if (bounds.height() >= r * 2f) {
                if (bounds.top > cT) snapDy = cT - bounds.top
                else if (bounds.bottom < cB) snapDy = cB - bounds.bottom
            } else {
                snapDy = cy - (bounds.top + bounds.height() / 2f)
            }
        } else {
            if (bounds.width() <= vw) {
                snapDx = (vw - bounds.width()) / 2f - bounds.left
            } else {
                if (bounds.left > 0f) snapDx = -bounds.left
                else if (bounds.right < vw) snapDx = vw - bounds.right
            }
            if (bounds.height() <= vh) {
                snapDy = (vh - bounds.height()) / 2f - bounds.top
            } else {
                if (bounds.top > 0f) snapDy = -bounds.top
                else if (bounds.bottom < vh) snapDy = vh - bounds.bottom
            }
        }

        if (snapDx == 0f && snapDy == 0f) {
            imageMatrix = m
        onMatrixChanged?.invoke(m)
            return
        }

        currentAnimator?.cancel()
        var lastFrac = 0f
        currentAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = SNAP_ANIM_DURATION
            interpolator = DecelerateInterpolator(2f)
            addUpdateListener { va ->
                val frac = va.animatedValue as Float
                val dFrac = frac - lastFrac
                lastFrac = frac
                m.postTranslate(snapDx * dFrac, snapDy * dFrac)
                imageMatrix = m
        onMatrixChanged?.invoke(m)
            }
            start()
        }
    }

    // ─────────────────────────────────────────────
    // Double tap zoom
    // ─────────────────────────────────────────────

    private fun handleDoubleTap(x: Float, y: Float) {
        val target = if (currentZoom > 1.01f) 1.0f else DOUBLE_TAP_ZOOM
        animateZoomTo(target, x, y)
    }

    private fun animateZoomTo(targetZoom: Float, pivotX: Float, pivotY: Float) {
        val startZoom = currentZoom
        currentAnimator?.cancel()
        currentAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = ZOOM_ANIM_DURATION
            interpolator = DecelerateInterpolator()
            addUpdateListener { va ->
                val t = va.animatedValue as Float
                val zoom = startZoom + (targetZoom - startZoom) * t
                val factor = zoom / currentZoom
                currentZoom = zoom
                m.postScale(factor, factor, pivotX, pivotY)
                // Inline snap during animation to avoid gaps
                snapToBoundsImmediate()
                imageMatrix = m
        onMatrixChanged?.invoke(m)
            }
            start()
        }
    }

    /** Instant snap — used only inside animations where incremental correction is OK */
    private fun snapToBoundsImmediate() {
        val bounds = getImageBounds()
        val vw = width.toFloat()
        val vh = height.toFloat()
        var dx = 0f; var dy = 0f

        if (isAspectFill) {
            val r = min(vw, vh) / 2f
            val cx = vw / 2f; val cy = vh / 2f
            val cL = cx - r; val cR = cx + r
            val cT = cy - r; val cB = cy + r
            if (bounds.width() >= r * 2f) {
                if (bounds.left > cL) dx = cL - bounds.left
                else if (bounds.right < cR) dx = cR - bounds.right
            } else {
                dx = cx - (bounds.left + bounds.width() / 2f)
            }
            if (bounds.height() >= r * 2f) {
                if (bounds.top > cT) dy = cT - bounds.top
                else if (bounds.bottom < cB) dy = cB - bounds.bottom
            } else {
                dy = cy - (bounds.top + bounds.height() / 2f)
            }
        } else {
            if (bounds.width() <= vw) dx = (vw - bounds.width()) / 2f - bounds.left
            else { if (bounds.left > 0) dx = -bounds.left else if (bounds.right < vw) dx = vw - bounds.right }
            if (bounds.height() <= vh) dy = (vh - bounds.height()) / 2f - bounds.top
            else { if (bounds.top > 0) dy = -bounds.top else if (bounds.bottom < vh) dy = vh - bounds.bottom }
        }

        if (dx != 0f || dy != 0f) m.postTranslate(dx, dy)
    }

    // ─────────────────────────────────────────────
    // Reset
    // ─────────────────────────────────────────────

    fun resetZoom() {
        currentAnimator?.cancel()
        currentAnimator = null
        currentZoom = 1.0f
        setupInitialMatrix()
    }

    /** Minimum zoom — always 1.0. setupInitialMatrix() already scales the image to
     *  fill the circle at zoom=1.0, regardless of view rotation. */
    private fun minZoomToCoverCircle(): Float = MIN_ZOOM


    fun resetZoomWithAnimation() {
        if (currentZoom <= 1.0f) return
        val pivotX = width / 2f
        val pivotY = height / 2f
        animateZoomTo(1.0f, pivotX, pivotY)
    }

    fun resetZoomAndPanWithAnimation() {
        currentAnimator?.cancel()
        
        val startValues = FloatArray(9)
        m.getValues(startValues)
        
        val endValues = FloatArray(9)
        initialImageMatrix.getValues(endValues)
        
        // If already identical, just return
        var isDifferent = false
        for (i in 0..8) {
            if (Math.abs(startValues[i] - endValues[i]) > 0.01f) {
                isDifferent = true
                break
            }
        }
        if (!isDifferent) return

        val startZoom = currentZoom
        
        currentAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = ZOOM_ANIM_DURATION
            interpolator = DecelerateInterpolator()
            addUpdateListener { va ->
                val t = va.animatedValue as Float
                
                val currentValues = FloatArray(9)
                for (i in 0..8) {
                    currentValues[i] = startValues[i] + (endValues[i] - startValues[i]) * t
                }
                
                m.setValues(currentValues)
                currentZoom = startZoom + (1.0f - startZoom) * t
                
                imageMatrix = m
                onMatrixChanged?.invoke(m)
            }
            start()
        }
    }

    fun isModified(): Boolean {
        val currentValues = FloatArray(9)
        m.getValues(currentValues)
        
        val initialValues = FloatArray(9)
        initialImageMatrix.getValues(initialValues)
        
        for (i in 0..8) {
            if (Math.abs(currentValues[i] - initialValues[i]) > 0.01f) {
                return true
            }
        }
        return false
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        currentAnimator?.cancel()
        currentAnimator = null
    }

    // ─────────────────────────────────────────────
    // Pinch Listener
    // ─────────────────────────────────────────────

    private inner class PinchListener : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        private var lastFocusX = 0f
        private var lastFocusY = 0f

        override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
            parent?.requestDisallowInterceptTouchEvent(true)
            lastFocusX = detector.focusX
            lastFocusY = detector.focusY
            return true
        }

        override fun onScale(detector: ScaleGestureDetector): Boolean {
            val focusX = detector.focusX
            val focusY = detector.focusY

            // Scale around focal point, strictly clamped
            val minAllowed = minZoomToCoverCircle()
            val maxAllowed = MAX_ZOOM
            val newZoom = (currentZoom * detector.scaleFactor).coerceIn(minAllowed, maxAllowed)
            val factor = newZoom / currentZoom
            currentZoom = newZoom
            m.postScale(factor, factor, focusX, focusY)

            // Pan-during-pinch: translate by focal point movement
            m.postTranslate(focusX - lastFocusX, focusY - lastFocusY)

            // Snap to keep circle covered
            snapToBoundsImmediate()

            lastFocusX = focusX
            lastFocusY = focusY

            imageMatrix = m
            onMatrixChanged?.invoke(m)
            return true
        }

        override fun onScaleEnd(detector: ScaleGestureDetector) {
            isScaling = false
            // Animate back to bounds only if out of bounds
            animatedSnapToBounds()
        }
    }

    // ─────────────────────────────────────────────
    // Tap Listener
    // ─────────────────────────────────────────────

    private inner class TapListener : GestureDetector.SimpleOnGestureListener() {
        override fun onDoubleTap(e: MotionEvent): Boolean {
            handleDoubleTap(e.x, e.y)
            return true
        }
        override fun onDown(e: MotionEvent): Boolean = true
    }
}
