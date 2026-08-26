package com.rnturboimagepicker

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.AttributeSet
import android.view.Gravity
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.TextView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import kotlin.math.atan2
import kotlin.math.max
import kotlin.math.sqrt

class TextStickerView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null, defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {

    interface OnStickerInteractionListener {
        fun onEditRequest(sticker: TextStickerView)
        fun onDeleteRequest(sticker: TextStickerView)
        fun onStickerSelected(sticker: TextStickerView)
    }

    companion object {
        /** Cached typeface — loaded once per process, shared across all instances. */
        private var cachedTypeface: Typeface? = null

        private fun getTypeface(context: Context): Typeface {
            cachedTypeface?.let { return it }
            return try {
                Typeface.createFromAsset(context.assets, "fonts/Pretendard-SemiBold.otf").also {
                    cachedTypeface = it
                }
            } catch (e: Exception) {
                Typeface.DEFAULT_BOLD
            }
        }
    }

    var listener: OnStickerInteractionListener? = null
    var text: String
        get() = textView.text.toString()
        set(value) { 
            textView.text = value 
            if (isEmojiSticker) {
                Glide.with(context)
                    .load(getEmojiUrl(value))
                    .diskCacheStrategy(DiskCacheStrategy.ALL)
                    .into(emojiImageView)
            }
        }

    var textColor: Int
        get() = textView.currentTextColor
        set(value) { textView.setTextColor(value) }

    // Pre-built backgrounds — avoids GradientDrawable allocation on every isActive toggle
    private val activeBg: GradientDrawable
    private val inactiveBg: GradientDrawable

    private fun getEmojiUrl(emoji: String): String {
        val hex = emoji.codePoints().toArray().joinToString("_") { Integer.toHexString(it) }
        return "https://fonts.gstatic.com/s/e/notoemoji/latest/$hex/512.png"
    }

    var isEmojiSticker: Boolean = false
        set(value) {
            field = value
            if (value) {
                textView.visibility = View.GONE
                emojiImageView.visibility = View.VISIBLE
                resizeHandle.visibility = View.GONE
                
                // Load emoji image
                Glide.with(context)
                    .load(getEmojiUrl(textView.text.toString()))
                    .diskCacheStrategy(DiskCacheStrategy.ALL)
                    .into(emojiImageView)
            } else {
                textView.visibility = View.VISIBLE
                emojiImageView.visibility = View.GONE
            }
        }

    var isEditingMode: Boolean = true
        set(value) {
            field = value
            applyTransform()
        }

    var isActive: Boolean = false
        set(value) {
            field = value
            editHandle.visibility = if (value && !isEmojiSticker) View.VISIBLE else View.GONE
            deleteHandle.visibility = if (value) View.VISIBLE else View.GONE
            resizeHandle.visibility = if (value) View.VISIBLE else View.GONE
            textView.background = if (value) activeBg else inactiveBg
            emojiImageView.background = if (value) activeBg else inactiveBg
            if (value) bringToFront()
            applyTransform()
        }

    override fun dispatchTouchEvent(ev: MotionEvent?): Boolean {
        if (!isEditingMode) {
            // 비활성화 상태에서도 터치를 받기 위해 수정 (iOS와 동일)
            // 편집 모드가 아니면 터치를 받아서 선택할 수 있게 함
            return super.dispatchTouchEvent(ev)
        }
        return super.dispatchTouchEvent(ev)
    }

    private val textView: TextView
    private val emojiImageView: ImageView
    private val editHandle: ImageButton
    private val deleteHandle: ImageButton
    private val resizeHandle: ImageButton

    // Pre-computed pixel values (avoid repeated dpToPx calls)
    private val density = context.resources.displayMetrics.density
    private val handleSizePx = (26f * density).toInt()
    private val paddingSizePx = (6f * density).toInt()
    private val contentPaddingPx = (16f * density).toInt()
    private val cornerRadiusPx = 8f * density

    private var scaleDetector: ScaleGestureDetector? = null
    private var rotationDetector: RotationGestureDetector? = null

    init {
        // Build cached backgrounds
        activeBg = GradientDrawable().apply {
            setColor(Color.TRANSPARENT)
            val strokePx = max(1, (1.5f * density).toInt())
            setStroke(strokePx, Color.WHITE)
            cornerRadius = cornerRadiusPx
        }
        inactiveBg = GradientDrawable().apply {
            setColor(Color.TRANSPARENT)
            setStroke(0, Color.TRANSPARENT)
            cornerRadius = cornerRadiusPx
        }

        // TextView
        textView = TextView(context).apply {
            setTextColor(Color.WHITE)
            textSize = 32f
            setShadowLayer(4f, 0f, 2f, Color.parseColor("#80000000"))
            setPadding(contentPaddingPx, contentPaddingPx, contentPaddingPx, contentPaddingPx)
            gravity = Gravity.CENTER
            typeface = getTypeface(context)
            layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.CENTER
            }
        }
        addView(textView)

        // Emoji ImageView
        emojiImageView = ImageView(context).apply {
            visibility = View.GONE
            layoutParams = LayoutParams(
                (120f * density).toInt(), 
                (120f * density).toInt()
            ).apply {
                gravity = Gravity.CENTER
            }
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        addView(emojiImageView)

        clipChildren = false
        clipToPadding = false

        // Handles
        editHandle = createHandle(R.drawable.ic_pencil)
        deleteHandle = createHandle(R.drawable.ic_close_handle)
        resizeHandle = createHandle(R.drawable.ic_resize_handle)

        addView(editHandle)
        addView(deleteHandle)
        addView(resizeHandle)

        // Expand bounds so handles can receive touch events correctly
        val hs = handleSizePx / 2
        setPadding(hs, hs, hs, hs)

        setupListeners()
    }

    private fun createHandle(iconRes: Int): ImageButton {
        return ImageButton(context).apply {
            val bg = GradientDrawable()
            bg.shape = GradientDrawable.OVAL
            bg.setColor(Color.WHITE)
            background = bg
            alpha = 0.8f
            setImageResource(iconRes)
            scaleType = ImageView.ScaleType.FIT_CENTER
            setPadding(paddingSizePx, paddingSizePx, paddingSizePx, paddingSizePx)
            layoutParams = LayoutParams(handleSizePx, handleSizePx)
        }
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        
        val tw = if (isEmojiSticker) emojiImageView.width else textView.width
        val th = if (isEmojiSticker) emojiImageView.height else textView.height
        val cx = width / 2f
        val cy = height / 2f

        val halfTw = tw / 2f
        val halfTh = th / 2f

        // The corner is rounded with radius `cornerRadiusPx`.
        // The distance from the square corner to the curved corner along the diagonal is R * (1 - 1/sqrt(2))
        val inset = cornerRadiusPx * 0.293f

        layoutHandle(editHandle, cx - halfTw + inset, cy - halfTh + inset)
        layoutHandle(deleteHandle, cx + halfTw - inset, cy - halfTh + inset)
        layoutHandle(resizeHandle, cx + halfTw - inset, cy + halfTh - inset)
    }

    private fun layoutHandle(handle: View, cx: Float, cy: Float) {
        val hs = handleSizePx / 2
        handle.layout(
            (cx - hs).toInt(),
            (cy - hs).toInt(),
            (cx + hs).toInt(),
            (cy + hs).toInt()
        )
    }

    private var containerZoom: Float = 1.0f
    // Track last applied inverse scale to skip redundant work
    private var lastAppliedInverseScale: Float = 1f

    var intrinsicScaleX: Float = 1f
    var intrinsicScaleY: Float = 1f

    fun setContainerZoom(zoom: Float) {
        if (this.containerZoom != zoom) {
            this.containerZoom = zoom
            applyTransform()
            inverseScaleHandles()
        }
    }

    private fun applyTransform() {
        if (isEditingMode && isActive) {
            val cx = if (containerZoom != 0f) containerZoom else 1f
            super.setScaleX(intrinsicScaleX / cx)
            super.setScaleY(intrinsicScaleY / cx)
        } else {
            super.setScaleX(intrinsicScaleX)
            super.setScaleY(intrinsicScaleY)
        }
    }

    override fun setScaleX(scaleX: Float) {
        intrinsicScaleX = scaleX
        applyTransform()
        inverseScaleHandles()
    }

    override fun setScaleY(scaleY: Float) {
        intrinsicScaleY = scaleY
        applyTransform()
        inverseScaleHandles()
    }

    private fun inverseScaleHandles() {
        val totalScaleX = scaleX * containerZoom
        val totalScaleY = scaleY * containerZoom
        val scale = max(Math.abs(totalScaleX), Math.abs(totalScaleY))
        val inv = if (scale != 0f) 1f / scale else 1f

        // Skip if the computed inverse hasn't changed
        if (inv == lastAppliedInverseScale) return
        lastAppliedInverseScale = inv

        editHandle.scaleX = inv
        editHandle.scaleY = inv
        deleteHandle.scaleX = inv
        deleteHandle.scaleY = inv
        resizeHandle.scaleX = inv
        resizeHandle.scaleY = inv

        // 가이드라인(border) 두께가 화면에서 일정하게 보이도록 획 두께 조정
        val baseStroke = (1.5f * density).toInt() // 기본 1.5dp
        val strokeWidth = max(1, (baseStroke * inv).toInt())
        activeBg.setStroke(strokeWidth, Color.WHITE)
    }

    private fun setupListeners() {
        editHandle.setOnClickListener {
            listener?.onEditRequest(this)
        }
        deleteHandle.setOnClickListener {
            listener?.onDeleteRequest(this)
        }

        // Resize / Rotate Handle
        resizeHandle.setOnTouchListener(object : OnTouchListener {
            var initialDistance = 0f
            var initialAngle = 0f
            var initialIntrinsicScaleX = 1f
            var initialIntrinsicScaleY = 1f
            var initialRotation = 0f
            var cx = 0f
            var cy = 0f

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                val parent = parent as? ViewGroup ?: return false
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        listener?.onStickerSelected(this@TextStickerView)
                        
                        val parentLoc = IntArray(2)
                        parent.getLocationOnScreen(parentLoc)
                        
                        val localCx = this@TextStickerView.x + this@TextStickerView.width / 2f
                        val localCy = this@TextStickerView.y + this@TextStickerView.height / 2f
                        
                        cx = parentLoc[0] + localCx * parent.scaleX
                        cy = parentLoc[1] + localCy * parent.scaleY
                        
                        val dx = event.rawX - cx
                        val dy = event.rawY - cy
                        initialDistance = sqrt(dx * dx + dy * dy)
                        initialAngle = Math.toDegrees(atan2(dy.toDouble(), dx.toDouble())).toFloat()
                        initialIntrinsicScaleX = intrinsicScaleX
                        initialIntrinsicScaleY = intrinsicScaleY
                        initialRotation = rotation
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - cx
                        val dy = event.rawY - cy
                        val currentDistance = sqrt(dx * dx + dy * dy)
                        val currentAngle = Math.toDegrees(atan2(dy.toDouble(), dx.toDouble())).toFloat()

                        if (initialDistance > 0) {
                            val scale = currentDistance / initialDistance
                            intrinsicScaleX = initialIntrinsicScaleX * scale
                            intrinsicScaleY = initialIntrinsicScaleY * scale
                            applyTransform()
                            inverseScaleHandles()
                        }
                        
                        var angleDiff = currentAngle - initialAngle
                        if (angleDiff < -180f) angleDiff += 360f
                        if (angleDiff > 180f) angleDiff -= 360f
                        rotation = initialRotation + angleDiff
                        return true
                    }
                }
                return false
            }
        })

        // Main Body Pan / Pinch / Rotate
        scaleDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(detector: ScaleGestureDetector): Boolean {
                intrinsicScaleX *= detector.scaleFactor
                intrinsicScaleY *= detector.scaleFactor
                applyTransform()
                inverseScaleHandles()
                return true
            }
        })

        rotationDetector = RotationGestureDetector(object : RotationGestureDetector.OnRotationGestureListener {
            override fun onRotation(detector: RotationGestureDetector): Boolean {
                rotation += detector.angle
                return true
            }
        })

        setOnTouchListener(object : OnTouchListener {
            var startX = 0f
            var startY = 0f
            var initialTransX = 0f
            var initialTransY = 0f
            var activePointerId = MotionEvent.INVALID_POINTER_ID
            var isDrag = false

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                if (!isActive) {
                    if (event.action == MotionEvent.ACTION_DOWN) {
                        listener?.onStickerSelected(this@TextStickerView)
                    }
                    return false
                }

                scaleDetector?.onTouchEvent(event)
                rotationDetector?.onTouchEvent(event)

                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        listener?.onStickerSelected(this@TextStickerView)
                        activePointerId = event.getPointerId(0)
                        startX = event.rawX
                        startY = event.rawY
                        initialTransX = translationX
                        initialTransY = translationY
                        isDrag = false
                    }
                    MotionEvent.ACTION_MOVE -> {
                        if (event.pointerCount == 1 && activePointerId != MotionEvent.INVALID_POINTER_ID) {
                            val pointerIndex = event.findPointerIndex(activePointerId)
                            if (pointerIndex >= 0) {
                                val dxRaw = event.rawX - startX
                                val dyRaw = event.rawY - startY
                                if (Math.abs(dxRaw) > 10f || Math.abs(dyRaw) > 10f) {
                                    isDrag = true
                                }

                                val parentView = parent as? View
                                val parentScaleX = parentView?.scaleX ?: 1f
                                val parentScaleY = parentView?.scaleY ?: 1f
                                val dx = dxRaw / parentScaleX
                                val dy = dyRaw / parentScaleY
                                translationX = initialTransX + dx
                                translationY = initialTransY + dy
                            }
                        }
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        activePointerId = MotionEvent.INVALID_POINTER_ID
                    }
                    MotionEvent.ACTION_POINTER_UP -> {
                        val pointerIndex = event.actionIndex
                        val pointerId = event.getPointerId(pointerIndex)
                        if (pointerId == activePointerId) {
                            val newPointerIndex = if (pointerIndex == 0) 1 else 0
                            startX = event.rawX
                            startY = event.rawY
                            initialTransX = translationX
                            initialTransY = translationY
                            activePointerId = event.getPointerId(newPointerIndex)
                        }
                    }
                }
                return true
            }
        })
    }

    // getCenterOnScreen is no longer needed since we use parent coordinates directly
}
