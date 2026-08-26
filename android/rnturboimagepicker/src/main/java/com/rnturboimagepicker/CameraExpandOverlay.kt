package com.rnturboimagepicker

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.view.PreviewView

@SuppressLint("ViewConstructor")
class CameraExpandOverlay(
    context: Context,
    private val sourceRect: Rect,
    private val previewView: PreviewView,
    private val initialBitmap: android.graphics.Bitmap?,
    private val onDismiss: (android.graphics.Bitmap?) -> Unit,
    private val onCapture: () -> Unit,
    private val onSwitchCamera: () -> Unit,
    private val onFlashToggle: () -> Int,
    private val lifecycleOwner: androidx.lifecycle.LifecycleOwner,
    private val getCamera: () -> Camera?
) : FrameLayout(context) {

    val cameraContainer = FrameLayout(context)
    private val dimView = View(context)
    private val captureButton = View(context)
    private val switchButton = ImageView(context)
    private val flashButton = ImageView(context)
    private val modeLabel = android.widget.TextView(context)

    private var isAnimating = false
    private var panStartY = 0f
    private var isDragging = false
    private var wasPinching = false
    
    // Zoom Support
    private val zoomContainer = android.widget.LinearLayout(context)
    private val zoomSlider = android.widget.SeekBar(context)
    private var scaleGestureDetector: android.view.ScaleGestureDetector? = null
    
    // Drag State
    private var dragSnapshotBitmap: android.graphics.Bitmap? = null
    private var initialY = 0f
    private var currentZoomRatio = 1f
    private var minZoomRatio = 1f
    private var maxZoomRatio = 1f
    
    // Corner Radius
    private var currentCornerRadius = 0f
        set(value) {
            field = value
            cameraContainer.invalidateOutline()
        }

    // SoundPool for softer shutter sound
    private var soundPool: android.media.SoundPool? = null
    private var shutterSoundId: Int = 0

    private val Int.dp: Int
        get() = (this * resources.displayMetrics.density).toInt()

    init {
        setupSoundPool()
        setupViews()
        post { startExpandAnimation() }
    }
    
    private fun setupSoundPool() {
        val attrs = android.media.AudioAttributes.Builder()
            .setUsage(android.media.AudioAttributes.USAGE_ALARM) // Alarm stream bypasses mute but respects volume control!
            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
            
        soundPool = android.media.SoundPool.Builder()
            .setMaxStreams(1)
            .setAudioAttributes(attrs)
            .build()
            
        try {
            // Restore the original camera click sound
            shutterSoundId = soundPool?.load("/system/media/audio/ui/camera_click.ogg", 1) ?: 0
        } catch (e: Exception) {
            // fallback
            shutterSoundId = soundPool?.load(context, R.raw.shutter, 1) ?: 0
        }
    }

    private fun setupViews() {
        // Dim background
        dimView.setBackgroundColor(Color.BLACK)
        dimView.alpha = 0f
        addView(dimView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        cameraContainer.outlineProvider = object : android.view.ViewOutlineProvider() {
            override fun getOutline(view: android.view.View, outline: android.graphics.Outline) {
                outline.setRoundRect(0, 0, view.width, view.height, currentCornerRadius)
            }
        }
        cameraContainer.clipToOutline = true
        
        setupZoomUI()

        // Camera Container
        cameraContainer.setBackgroundColor(Color.BLACK)
        // Set initial bounds
        val lp = LayoutParams(sourceRect.width(), sourceRect.height())
        lp.leftMargin = sourceRect.left
        lp.topMargin = sourceRect.top
        addView(cameraContainer, lp)

        // Detach previewView from old parent and add to container
        (previewView.parent as? ViewGroup)?.removeView(previewView)
        cameraContainer.addView(previewView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        
        if (initialBitmap != null) {
            val coverView = ImageView(context).apply {
                setImageBitmap(initialBitmap)
                scaleType = ImageView.ScaleType.CENTER_CROP
            }
            cameraContainer.addView(coverView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
            
            // Since we are physically moving the view, the surface recreates very fast (50-100ms).
            // CameraX might not even change the StreamState. So we just use a small fixed delay.
            coverView.postDelayed({
                coverView.animate().alpha(0f).setDuration(200).withEndAction {
                    cameraContainer.removeView(coverView)
                }.start()
            }, 150)
        }

        // Handle back button to shrink
        isFocusableInTouchMode = true
        requestFocus()
        setOnKeyListener { _, keyCode, event ->
            if (keyCode == android.view.KeyEvent.KEYCODE_BACK && event.action == android.view.KeyEvent.ACTION_UP) {
                if (!isAnimating) startShrinkAnimation()
                true
            } else {
                false
            }
        }

        // Capture Button (White Circle)
        val captureDrawable = createCaptureButtonDrawable()
        captureButton.background = captureDrawable
        captureButton.alpha = 0f
        val captureLp = LayoutParams(72.dp, 72.dp)
        captureLp.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        captureLp.bottomMargin = 80.dp
        addView(captureButton, captureLp)

        val innerDrawable = (captureDrawable as android.graphics.drawable.LayerDrawable).getDrawable(1)
        
        captureButton.setOnTouchListener { v, event ->
            when (event.action) {
                android.view.MotionEvent.ACTION_DOWN -> {
                    v.animate().scaleX(1.05f).scaleY(1.05f).setDuration(150).start()
                    android.animation.ObjectAnimator.ofInt(innerDrawable, "alpha", 0, 255).apply {
                        duration = 150
                        start()
                    }
                    true
                }
                android.view.MotionEvent.ACTION_UP -> {
                    v.animate().scaleX(1f).scaleY(1f).setDuration(150).start()
                    android.animation.ObjectAnimator.ofInt(innerDrawable, "alpha", 255, 0).apply {
                        duration = 150
                        start()
                    }
                    playSoftShutterSound()
                    
                    // Visual feedback: Screen flash and subtle bounce
                    val flashView = android.view.View(context).apply {
                        setBackgroundColor(android.graphics.Color.BLACK)
                        alpha = 0.7f
                    }
                    cameraContainer.addView(flashView, android.widget.FrameLayout.LayoutParams(
                        android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
                        android.widget.FrameLayout.LayoutParams.MATCH_PARENT
                    ))
                    flashView.animate()
                        .alpha(0f)
                        .setDuration(150)
                        .withEndAction { cameraContainer.removeView(flashView) }
                        .start()
                        
                    cameraContainer.animate()
                        .scaleX(0.97f)
                        .scaleY(0.97f)
                        .setDuration(70)
                        .withEndAction {
                            cameraContainer.animate()
                                .scaleX(1f)
                                .scaleY(1f)
                                .setDuration(100)
                                .start()
                        }
                        .start()

                    onCapture()
                    true
                }
                android.view.MotionEvent.ACTION_CANCEL -> {
                    v.animate().scaleX(1f).scaleY(1f).setDuration(150).start()
                    android.animation.ObjectAnimator.ofInt(innerDrawable, "alpha", 255, 0).apply {
                        duration = 150
                        start()
                    }
                    true
                }
                else -> false
            }
        }

        // Flash Button
        flashButton.setImageResource(R.drawable.light_off)
        flashButton.setPadding(6.dp, 6.dp, 6.dp, 6.dp)
        flashButton.imageAlpha = 255
        flashButton.alpha = 0f
        val flashLp = LayoutParams(44.dp, 44.dp)
        flashLp.gravity = Gravity.BOTTOM or Gravity.START
        flashLp.bottomMargin = 94.dp
        flashLp.leftMargin = 40.dp
        addView(flashButton, flashLp)

        flashButton.setOnClickListener {
            val newMode = onFlashToggle()
            animateFlashIconChange(newMode)
        }

        // Switch Camera Button
        switchButton.setImageResource(R.drawable.ic_camera_flip)
        switchButton.setPadding(6.dp, 6.dp, 6.dp, 6.dp)
        switchButton.imageAlpha = 255
        switchButton.alpha = 0f
        val switchLp = LayoutParams(44.dp, 44.dp)
        switchLp.gravity = Gravity.BOTTOM or Gravity.END
        switchLp.bottomMargin = 94.dp
        switchLp.rightMargin = 40.dp
        addView(switchButton, switchLp)

        switchButton.setOnClickListener {
            onSwitchCamera()
        }

        // Mode Label
        modeLabel.text = "사진은 짧게, 동영상은 길게 누르세요"
        modeLabel.setTextColor(Color.WHITE)
        modeLabel.textSize = 14f
        modeLabel.typeface = android.graphics.Typeface.DEFAULT_BOLD
        modeLabel.gravity = Gravity.CENTER
        modeLabel.setShadowLayer(4f, 0f, 2f, Color.parseColor("#99000000"))
        modeLabel.alpha = 0f
        val modeLp = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
        modeLp.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        modeLp.bottomMargin = 30.dp
        addView(modeLabel, modeLp)
        
        setupZoomController()
    }
    
    private fun setupZoomUI() {
        zoomContainer.orientation = android.widget.LinearLayout.HORIZONTAL
        zoomContainer.gravity = Gravity.CENTER_VERTICAL
        zoomContainer.alpha = 0f
        
        val minusLabel = android.widget.TextView(context).apply {
            text = "-"
            setTextColor(Color.WHITE)
            textSize = 20f
            setShadowLayer(4f, 0f, 2f, Color.parseColor("#80000000"))
        }
        
        val plusLabel = android.widget.TextView(context).apply {
            text = "+"
            setTextColor(Color.WHITE)
            textSize = 20f
            setShadowLayer(4f, 0f, 2f, Color.parseColor("#80000000"))
        }
        
        // Setup slider
        zoomSlider.progressDrawable.setTint(Color.WHITE)
        zoomSlider.thumb.setTint(Color.WHITE)
        zoomSlider.max = 100
        val sliderLp = android.widget.LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        sliderLp.leftMargin = 12.dp
        sliderLp.rightMargin = 12.dp
        
        zoomContainer.addView(minusLabel)
        zoomContainer.addView(zoomSlider, sliderLp)
        zoomContainer.addView(plusLabel)
        
        val zLp = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
        zLp.gravity = Gravity.BOTTOM
        zLp.bottomMargin = 200.dp
        zLp.leftMargin = 40.dp
        zLp.rightMargin = 40.dp
        addView(zoomContainer, zLp)
    }
    
    private fun setupZoomController() {
        val camera = getCamera() ?: return
        
        camera.cameraInfo.zoomState.observe(lifecycleOwner) { state ->
            minZoomRatio = state.minZoomRatio
            maxZoomRatio = state.maxZoomRatio
            currentZoomRatio = state.zoomRatio
            
            // Update slider without triggering listener
            val range = maxZoomRatio - minZoomRatio
            if (range > 0) {
                val progress = ((currentZoomRatio - minZoomRatio) / range * 100).toInt()
                zoomSlider.progress = progress
            }
        }
        
        zoomSlider.setOnSeekBarChangeListener(object : android.widget.SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: android.widget.SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) {
                    val ratio = minZoomRatio + (maxZoomRatio - minZoomRatio) * (progress / 100f)
                    getCamera()?.cameraControl?.setZoomRatio(ratio)
                }
            }
            override fun onStartTrackingTouch(seekBar: android.widget.SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: android.widget.SeekBar?) {}
        })
        
        scaleGestureDetector = android.view.ScaleGestureDetector(context, object : android.view.ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(detector: android.view.ScaleGestureDetector): Boolean {
                val cameraControl = getCamera()?.cameraControl ?: return false
                // Amplify the scale factor difference by 3x to make pinch zoom much more sensitive
                val delta = detector.scaleFactor - 1f
                val newZoom = currentZoomRatio * (1f + (delta * 3f))
                cameraControl.setZoomRatio(newZoom.coerceIn(minZoomRatio, maxZoomRatio))
                return true
            }
        })
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (isAnimating) return true
        
        scaleGestureDetector?.onTouchEvent(event)
        
        // Don't process pull-to-dismiss if pinching
        if (event.pointerCount > 1) {
            wasPinching = true
            isDragging = false
            return true
        }

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                wasPinching = false
                panStartY = event.rawY
                dragSnapshotBitmap = previewView.bitmap // Capture BEFORE any transformations!
                isDragging = false
            }
            MotionEvent.ACTION_MOVE -> {
                if (wasPinching) return true
                
                val dy = event.rawY - panStartY
                if (dy > 30f && !isDragging) {
                    isDragging = true
                }

                if (isDragging && dy > 0) {
                    val progress = dy / height
                    val scale = maxOf(0.7f, 1f - (progress * 0.5f))
                    cameraContainer.scaleX = scale
                    cameraContainer.scaleY = scale
                    cameraContainer.translationY = dy * 0.7f
                    
                    val maxRadius = 32.dp.toFloat()
                    currentCornerRadius = progress * 2f * maxRadius
                    
                    val fadeAlpha = maxOf(0f, 1f - progress * 2)
                    dimView.alpha = fadeAlpha
                    captureButton.alpha = fadeAlpha
                    flashButton.alpha = fadeAlpha
                    switchButton.alpha = fadeAlpha
                    modeLabel.alpha = fadeAlpha
                    zoomContainer.alpha = fadeAlpha
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (isDragging) {
                    val dy = event.rawY - panStartY
                    if (dy > height * 0.2f) {
                        cameraContainer.animate()
                            .scaleX(1f)
                            .scaleY(1f)
                            .translationY(0f)
                            .setDuration(300)
                            .setInterpolator(DecelerateInterpolator(1.5f))
                            .start()
                        startShrinkAnimation()
                    } else {
                        cameraContainer.animate()
                            .scaleX(1f).scaleY(1f)
                            .translationY(0f)
                            .setDuration(250)
                            .start()
                            
                        android.animation.ValueAnimator.ofFloat(currentCornerRadius, 0f).apply {
                            duration = 250
                            addUpdateListener { anim -> currentCornerRadius = anim.animatedValue as Float }
                            start()
                        }
                            
                        dimView.animate().alpha(1f).setDuration(250).start()
                        captureButton.animate().alpha(1f).setDuration(250).start()
                        flashButton.animate().alpha(1f).setDuration(250).start()
                        switchButton.animate().alpha(1f).setDuration(250).start()
                        modeLabel.animate().alpha(1f).setDuration(250).start()
                        zoomContainer.animate().alpha(1f).setDuration(250).start()
                    }
                    isDragging = false
                }
            }
        }
        return true
    }

    private fun startExpandAnimation() {
        isAnimating = true
        val targetWidth = width
        val targetHeight = height

        val startBounds = sourceRect
        val lp = cameraContainer.layoutParams as LayoutParams

        val animator = ValueAnimator.ofFloat(0f, 1f)
        animator.duration = 350
        animator.interpolator = DecelerateInterpolator(1.5f)
        animator.addUpdateListener { anim ->
            val fraction = anim.animatedValue as Float
            lp.width = (startBounds.width() + (targetWidth - startBounds.width()) * fraction).toInt()
            lp.height = (startBounds.height() + (targetHeight - startBounds.height()) * fraction).toInt()
            lp.leftMargin = (startBounds.left * (1 - fraction)).toInt()
            lp.topMargin = (startBounds.top * (1 - fraction)).toInt()
            cameraContainer.layoutParams = lp
            cameraContainer.requestLayout()
            
            val targetRadius = 0f
            currentCornerRadius = targetRadius * (1f - fraction)

            dimView.alpha = fraction
            captureButton.alpha = fraction
            switchButton.alpha = fraction
            flashButton.alpha = fraction
            modeLabel.alpha = fraction
            zoomContainer.alpha = fraction
        }
        animator.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: Animator) {
                isAnimating = false
            }
        })
        animator.start()
    }

    fun startShrinkAnimation() {
        if (isAnimating) return
        isAnimating = true

        val targetWidth = width
        val targetHeight = height

        val startBounds = sourceRect
        val lp = cameraContainer.layoutParams as LayoutParams
        val initialRadius = currentCornerRadius
        
        // Try to capture the absolute latest frame, fallback to drag snapshot if it fails
        val snapshotBitmap = previewView.bitmap ?: dragSnapshotBitmap

        val animator = ValueAnimator.ofFloat(1f, 0f)
        animator.duration = 300
        animator.interpolator = DecelerateInterpolator(1.5f)
        animator.addUpdateListener { anim ->
            val fraction = anim.animatedValue as Float
            lp.width = (startBounds.width() + (targetWidth - startBounds.width()) * fraction).toInt()
            lp.height = (startBounds.height() + (targetHeight - startBounds.height()) * fraction).toInt()
            lp.leftMargin = (startBounds.left * (1 - fraction)).toInt()
            lp.topMargin = (startBounds.top * (1 - fraction)).toInt()
            cameraContainer.layoutParams = lp
            cameraContainer.requestLayout()
            
            currentCornerRadius = initialRadius * fraction

            dimView.alpha = fraction
            captureButton.alpha = fraction
            switchButton.alpha = fraction
            flashButton.alpha = fraction
            modeLabel.alpha = fraction
            zoomContainer.alpha = fraction
        }
        animator.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: Animator) {
                isAnimating = false
                // Take a final snapshot when the view has reached its final small bounds
                // This perfectly matches the live feed's aspect ratio, preventing any zoom jump
                val finalSnapshot = previewView.bitmap ?: snapshotBitmap
                onDismiss(finalSnapshot)
                (parent as? ViewGroup)?.removeView(this@CameraExpandOverlay)
            }
        })
        animator.start()
    }

    private fun animateFlashIconChange(newMode: Int) {
        val newResId = when (newMode) {
            androidx.camera.core.ImageCapture.FLASH_MODE_ON -> R.drawable.light_on
            androidx.camera.core.ImageCapture.FLASH_MODE_AUTO -> R.drawable.light_auto
            else -> R.drawable.light_off
        }

        // Create a temporary view for the old icon
        val oldIcon = ImageView(context)
        oldIcon.setImageDrawable(flashButton.drawable)
        oldIcon.setPadding(6.dp, 6.dp, 6.dp, 6.dp)
        oldIcon.imageAlpha = 204
        val lp = LayoutParams(40.dp, 40.dp)
        lp.gravity = Gravity.BOTTOM or Gravity.START
        lp.bottomMargin = 130.dp
        lp.leftMargin = 40.dp
        addView(oldIcon, lp)

        // Set the new icon on flashButton and prepare for animation
        flashButton.setImageResource(newResId)
        flashButton.translationY = -40.dp.toFloat()
        flashButton.imageAlpha = 0 // start transparent

        // Animate old icon sliding down and fading out
        oldIcon.animate()
            .translationY(40.dp.toFloat())
            .alpha(0f)
            .setDuration(250)
            .withEndAction { removeView(oldIcon) }

        // Animate new icon sliding up and fading in
        flashButton.animate()
            .translationY(0f)
            .alpha(1f) // 255 alpha equivalent
            .setDuration(250)
            .setUpdateListener {
                flashButton.imageAlpha = (flashButton.alpha * 255).toInt()
            }
            .start()
    }

    private fun createCaptureButtonDrawable(): android.graphics.drawable.Drawable {
        val outer = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.OVAL
            setStroke(3.dp, android.graphics.Color.WHITE)
            setColor(android.graphics.Color.TRANSPARENT)
        }
        val inner = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.OVAL
            setColor(android.graphics.Color.WHITE)
            alpha = 0 // Initially hidden
        }
        val layerDrawable = android.graphics.drawable.LayerDrawable(arrayOf(outer, inner))
        layerDrawable.setLayerInset(1, 6.dp, 6.dp, 6.dp, 6.dp)
        return layerDrawable
    }
    
    private fun playSoftShutterSound() {
        try {
            if (shutterSoundId != 0) {
                // Play with 40% volume (0.4f). Adjust as needed.
                soundPool?.play(shutterSoundId, 0.4f, 0.4f, 1, 0, 1f)
            } else {
                val sound = android.media.MediaActionSound()
                sound.play(android.media.MediaActionSound.SHUTTER_CLICK)
            }
        } catch (e: Exception) {
            // Ignore
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        soundPool?.release()
        soundPool = null
    }
}
