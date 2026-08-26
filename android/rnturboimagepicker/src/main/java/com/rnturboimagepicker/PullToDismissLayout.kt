package com.rnturboimagepicker

import android.content.Context
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.widget.FrameLayout
import kotlin.math.abs

class PullToDismissLayout @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null, defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {

    var onDismiss: (() -> Unit)? = null
    var onDragProgress: ((Float) -> Unit)? = null
    var isPullEnabled: Boolean = true

    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var initialY = 0f
    private var initialX = 0f
    private var isDragging = false
    private var isDisallowed = false

    override fun requestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {
        super.requestDisallowInterceptTouchEvent(disallowIntercept)
        isDisallowed = disallowIntercept
    }

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        if (!isPullEnabled || ev.pointerCount > 1) return false
        
        if (ev.actionMasked == MotionEvent.ACTION_DOWN) {
            isDisallowed = false
        }
        
        if (isDisallowed) {
            initialY = ev.y
            initialX = ev.x
            return false
        }
        
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                initialY = ev.y
                initialX = ev.x
                isDragging = false
            }
            MotionEvent.ACTION_MOVE -> {
                val dy = ev.y - initialY
                val dx = ev.x - initialX
                if (dy > touchSlop && dy > abs(dx) * 1.5f) {
                    isDragging = true
                    initialY = ev.y
                    initialX = ev.x
                    return true
                }
            }
        }
        return super.onInterceptTouchEvent(ev)
    }

    override fun onTouchEvent(ev: MotionEvent): Boolean {
        if (!isPullEnabled) return super.onTouchEvent(ev)
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                initialY = ev.y
                isDragging = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dy = ev.y - initialY
                val dx = ev.x - initialX
                if (isDragging) {
                    val progress = (dy / height).coerceIn(0f, 1f)
                    val scale = 1f - (progress * 0.3f) // scale down to 0.7x
                    val ty = dy * 0.7f // Make it follow finger a bit closer
                    val tx = dx * 0.7f 
                    
                    val child = getChildAt(0)
                    child?.translationX = tx
                    child?.translationY = ty
                    child?.scaleX = scale
                    child?.scaleY = scale
                    
                    val radius = 120f * progress
                    child?.outlineProvider = object : android.view.ViewOutlineProvider() {
                        override fun getOutline(view: android.view.View, outline: android.graphics.Outline) {
                            outline.setRoundRect(0, 0, view.width, view.height, radius)
                        }
                    }
                    child?.clipToOutline = true
                    
                    onDragProgress?.invoke(progress)
                    return true
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (isDragging) {
                    val dy = ev.y - initialY
                    if (dy > height * 0.2f) { // dismiss threshold
                        onDismiss?.invoke()
                    } else {
                        // snap back
                        val child = getChildAt(0)
                        val startTy = child?.translationY ?: 0f
                        val startTx = child?.translationX ?: 0f
                        val startScale = child?.scaleX ?: 1f
                        val startProgress = (startTy / height * 2f).coerceIn(0f, 1f)
                        val animator = android.animation.ValueAnimator.ofFloat(1f, 0f)
                        animator.duration = 200
                        animator.addUpdateListener { anim ->
                            val p = anim.animatedValue as Float
                            child?.translationY = startTy * p
                            child?.translationX = startTx * p
                            child?.scaleX = 1f - (1f - startScale) * p
                            child?.scaleY = 1f - (1f - startScale) * p
                            
                            val currentProgress = startProgress * p
                            onDragProgress?.invoke(currentProgress)
                            
                            val radius = 120f * currentProgress
                            child?.outlineProvider = object : android.view.ViewOutlineProvider() {
                                override fun getOutline(view: android.view.View, outline: android.graphics.Outline) {
                                    outline.setRoundRect(0, 0, view.width, view.height, radius)
                                }
                            }
                            child?.clipToOutline = true
                        }
                        animator.start()
                    }
                    isDragging = false
                }
                isDisallowed = false
            }
        }
        return super.onTouchEvent(ev)
    }
}
