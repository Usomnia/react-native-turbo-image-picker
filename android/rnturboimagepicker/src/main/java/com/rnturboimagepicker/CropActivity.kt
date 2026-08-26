package com.rnturboimagepicker

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Matrix
import android.graphics.RectF
import android.net.Uri
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import com.bumptech.glide.Glide
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class CropActivity : AppCompatActivity() {

    override fun attachBaseContext(newBase: android.content.Context) {
        super.attachBaseContext(TurboImagePickerConfig.attachBaseContext(newBase))
    }

    override fun applyOverrideConfiguration(overrideConfiguration: android.content.res.Configuration?) {
        val config = overrideConfiguration ?: android.content.res.Configuration()
        val locale = java.util.Locale(TurboImagePickerConfig.languageCode)
        config.setLocale(locale)
        super.applyOverrideConfiguration(config)
    }



    companion object {
        const val EXTRA_SOURCE_URI = "source_uri"
        const val EXTRA_CROPPED_URI = "cropped_uri"
        const val EXTRA_THEME_COLOR = "extra_theme_color"
    }

    private lateinit var zoomableImageView: ZoomableImageView
    private lateinit var cropOverlayView: CropOverlayView
    private lateinit var ratioContainer: LinearLayout
    private lateinit var btnCancel: ImageButton
    private lateinit var btnConfirm: ImageButton
    private lateinit var btnRotate: ImageButton
    private lateinit var btnFlip: ImageButton

    private lateinit var sourceUri: Uri
    private var workingBitmap: Bitmap? = null
    
    private var flipH = false
    private var rotations = 0 // 0..3, each +90 deg clockwise
    private var currentRatio: Float? = null // null means freeform
    
    private val executor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_crop)
        
        setupEdgeToEdgeInsets()
        bindViews()
        
        val uriStr = intent.getStringExtra(EXTRA_SOURCE_URI)
        if (uriStr == null) {
            finish()
            return
        }
        sourceUri = Uri.parse(uriStr)
        
        loadSourceImage()
        setupButtons()
        setupRatioButtons()
        
        zoomableImageView.onMatrixChanged = { matrix ->
            updateImageDisplayRect()
        }
        
        cropOverlayView.listener = object : CropOverlayView.Listener {
            override fun onCropRectChanged(rect: RectF) {
                // Not strictly needed since we poll it on confirm
            }
            override fun onCropInteractionEnded() {
                // Not strictly needed
            }
        }
    }

    private fun setupEdgeToEdgeInsets() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        val isLightMode = (resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_NO
        controller.isAppearanceLightStatusBars = isLightMode
        controller.isAppearanceLightNavigationBars = isLightMode
        window.statusBarColor = android.graphics.Color.TRANSPARENT
        // nav bar 색상은 테마(@color/editor_nav_bar)에서 자동 적용됨

        val statusBarSpacer = findViewById<View>(R.id.statusBarSpacer)
        val navBarSpacer = findViewById<View>(R.id.navBarSpacer)
        
        ViewCompat.setOnApplyWindowInsetsListener(window.decorView) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            statusBarSpacer.layoutParams.height = bars.top
            navBarSpacer.layoutParams.height = bars.bottom
            insets
        }
    }

    private fun bindViews() {
        zoomableImageView = findViewById(R.id.zoomableImageView)
        cropOverlayView = findViewById(R.id.cropOverlayView)
        ratioContainer = findViewById(R.id.ratioContainer)
        btnCancel = findViewById(R.id.btnCancel)
        btnConfirm = findViewById(R.id.btnConfirm)
        btnRotate = findViewById(R.id.btnRotate)
        btnFlip = findViewById(R.id.btnFlip)
    }

    private fun loadSourceImage() {
        executor.execute {
            try {
                // Cap the working resolution to 4096 to avoid performance issues
                val bmp = Glide.with(this).asBitmap().load(sourceUri).submit().get()
                workingBitmap = bmp
                runOnUiThread {
                    applyTransforms(animated = false)
                }
            } catch (e: Exception) {
                e.printStackTrace()
                runOnUiThread { finish() }
            }
        }
    }

    /**
     * Applies rotation (in 90° steps) and optional horizontal flip to a Bitmap.
     * Uses a step-by-step loop — each 90° rotation creates a correctly-sized intermediate,
     * which is the only reliable way to handle non-square images with Bitmap.createBitmap.
     */
    private fun applyBitmapTransforms(src: Bitmap): Bitmap {
        var img = src
        val m = Matrix()
        if (rotations > 0) {
            m.postRotate(rotations * 90f)
        }
        if (flipH) {
            m.postScale(-1f, 1f, src.width / 2f, src.height / 2f)
        }
        
        if (!m.isIdentity) {
            img = Bitmap.createBitmap(src, 0, 0, src.width, src.height, m, true)
        }
        return img
    }

    private fun applyTransforms(animated: Boolean, isFlip: Boolean = false) {
        val bmp = workingBitmap ?: return

        executor.execute {
            val img = applyBitmapTransforms(bmp)

            runOnUiThread {
                if (animated) {
                    if (isFlip) {
                        zoomableImageView.animate().rotationYBy(180f).setDuration(300).withEndAction {
                            zoomableImageView.rotationY = 0f
                            zoomableImageView.setImageBitmap(img)
                            resetCropToImage()
                        }.start()
                    } else {
                        zoomableImageView.animate().rotationBy(90f).setDuration(300).withEndAction {
                            zoomableImageView.rotation = 0f
                            zoomableImageView.setImageBitmap(img)
                            resetCropToImage()
                        }.start()
                    }
                } else {
                    zoomableImageView.setImageBitmap(img)
                    // We need to wait for layout to get proper view bounds
                    zoomableImageView.post {
                        resetCropToImage()
                    }
                }
            }
        }
    }

    private fun updateImageDisplayRect() {
        val d = zoomableImageView.drawable ?: return
        val rect = RectF(0f, 0f, d.intrinsicWidth.toFloat(), d.intrinsicHeight.toFloat())
        zoomableImageView.imageMatrix.mapRect(rect)
        
        // Convert to CropOverlayView coordinates. 
        // Since both ZoomableImageView and CropOverlayView are the same size in the same FrameLayout, 
        // the coordinates are 1:1 identical.
        cropOverlayView.imageDisplayRect = rect
        cropOverlayView.invalidate()
    }

    private fun resetCropToImage() {
        updateImageDisplayRect()
        val rect = cropOverlayView.imageDisplayRect
        if (!rect.isEmpty) {
            cropOverlayView.cropRect = RectF(rect)
        }
    }

    private fun setupButtons() {
        btnCancel.setOnClickListener { finish() }
        
        btnRotate.setOnClickListener {
            rotations = if (flipH) (rotations + 3) % 4 else (rotations + 1) % 4
            setRatio(null) // freeform
            applyTransforms(animated = true, isFlip = false)
        }
        
        btnFlip.setOnClickListener {
            flipH = !flipH
            applyTransforms(animated = true, isFlip = true)
        }
        
        btnConfirm.setOnClickListener {
            performCrop()
        }
    }

    private fun setupRatioButtons() {
        val ratios = listOf(
            Pair(getString(R.string.crop_freeform), null),
            Pair("1:1", 1f),
            Pair("3:4", 3f/4f),
            Pair("4:3", 4f/3f),
            Pair("9:16", 9f/16f),
            Pair("16:9", 16f/9f)
        )
        
        for ((title, value) in ratios) {
            val btn = Button(this)
            btn.text = title
            btn.tag = value
            btn.textSize = 13f
            btn.isAllCaps = false
            btn.minWidth = 0
            btn.minimumWidth = 0
            btn.minHeight = 0
            btn.minimumHeight = 0
            btn.setPadding(36, 12, 36, 12)
            btn.setOnClickListener { v -> setRatio(v.tag as Float?) }
            
            val params = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            params.marginEnd = 24
            ratioContainer.addView(btn, params)
        }
        setRatio(null)
    }

    private fun setRatio(ratio: Float?) {
        currentRatio = ratio
        cropOverlayView.fixedAspectRatio = ratio
        
        for (i in 0 until ratioContainer.childCount) {
            val btn = ratioContainer.getChildAt(i) as Button
            val r = btn.tag as Float?
            if (r == ratio) {
                btn.setBackgroundResource(R.drawable.bg_crop_ratio_selected)
                btn.setTextColor(getColor(R.color.crop_ratio_btn_selected_text))
            } else {
                btn.setBackgroundResource(R.drawable.bg_crop_ratio_unselected)
                btn.setTextColor(getColor(R.color.crop_ratio_btn_normal_text))
            }
        }
        
        // If a fixed ratio is selected, we should automatically adjust cropRect to fit that ratio
        if (ratio != null) {
            val dRect = cropOverlayView.imageDisplayRect
            val cRect = cropOverlayView.cropRect
            
            var newW = cRect.width()
            var newH = newW / ratio
            
            if (newH > dRect.height()) {
                newH = dRect.height()
                newW = newH * ratio
            }
            
            if (newW > dRect.width()) {
                newW = dRect.width()
                newH = newW / ratio
            }
            
            val cx = cRect.centerX()
            val cy = cRect.centerY()
            
            var left = cx - newW / 2
            var top = cy - newH / 2
            var right = cx + newW / 2
            var bottom = cy + newH / 2
            
            if (left < dRect.left) {
                right += dRect.left - left
                left = dRect.left
            }
            if (right > dRect.right) {
                left -= right - dRect.right
                right = dRect.right
            }
            if (top < dRect.top) {
                bottom += dRect.top - top
                top = dRect.top
            }
            if (bottom > dRect.bottom) {
                top -= bottom - dRect.bottom
                bottom = dRect.bottom
            }
            
            cropOverlayView.cropRect = RectF(left, top, right, bottom)
        }
    }

    private fun performCrop() {
        val d = zoomableImageView.drawable ?: return
        val imgDisplayRect = cropOverlayView.imageDisplayRect
        val cropR = cropOverlayView.cropRect
        
        if (imgDisplayRect.isEmpty || cropR.isEmpty) return
        
        val scaleX = d.intrinsicWidth / imgDisplayRect.width()
        val scaleY = d.intrinsicHeight / imgDisplayRect.height()
        
        val relX = cropR.left - imgDisplayRect.left
        val relY = cropR.top - imgDisplayRect.top
        
        val pixelRect = android.graphics.Rect(
            (relX * scaleX).toInt(),
            (relY * scaleY).toInt(),
            ((relX + cropR.width()) * scaleX).toInt(),
            ((relY + cropR.height()) * scaleY).toInt()
        )
        
        executor.execute {
            try {
                val originalBmp = workingBitmap!!
                // Apply rotation/flip using the same step-by-step helper used by applyTransforms
                val img = applyBitmapTransforms(originalBmp)
                
                // Ensure pixelRect is within img bounds
                val safeRect = android.graphics.Rect(
                    Math.max(0, pixelRect.left),
                    Math.max(0, pixelRect.top),
                    Math.min(img.width, pixelRect.right),
                    Math.min(img.height, pixelRect.bottom)
                )
                
                val croppedBmp = Bitmap.createBitmap(img, safeRect.left, safeRect.top, safeRect.width(), safeRect.height())
                
                val cacheFile = File(cacheDir, "cropped_${System.currentTimeMillis()}.jpg")
                val out = FileOutputStream(cacheFile)
                croppedBmp.compress(Bitmap.CompressFormat.JPEG, 100, out)
                out.flush()
                out.close()
                
                runOnUiThread {
                    setResult(Activity.RESULT_OK, Intent().apply {
                        putExtra(EXTRA_CROPPED_URI, Uri.fromFile(cacheFile).toString())
                    })
                    finish()
                }
            } catch (e: Exception) {
                e.printStackTrace()
                runOnUiThread { finish() }
            }
        }
    }
}
