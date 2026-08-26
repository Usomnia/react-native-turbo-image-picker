package com.rnturboimagepicker

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.RectF
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.ImageButton
import android.widget.TextView
import android.content.res.ColorStateList
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import com.bumptech.glide.Glide
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class ProfileCropActivity : AppCompatActivity() {

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
        const val EXTRA_MAX_WIDTH = "extra_max_width"
        const val EXTRA_MAX_HEIGHT = "extra_max_height"
        const val EXTRA_DISABLE_CROP = "extra_disable_crop"
    }

    private lateinit var zoomableImageView: ZoomableImageView
    private lateinit var circleOverlayView: CircleDashedOverlayView
    private lateinit var btnCancel: TextView
    private lateinit var btnConfirm: TextView
    private lateinit var btnRotate: ImageButton

    private lateinit var sourceUri: Uri
    private var workingBitmap: Bitmap? = null
    
    private var currentRotationDegrees = 0f
    private var maxWidth: Int = 1024
    private var maxHeight: Int = 1024
    private var isRotating = false
    
    private val executor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_profile_crop)
        
        onBackPressedDispatcher.addCallback(this, object : androidx.activity.OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                finish()
            }
        })
        
        setupEdgeToEdgeInsets()
        bindViews()
        
        val uriStr = intent.getStringExtra(EXTRA_SOURCE_URI)
        if (uriStr == null) {
            finish()
            return
        }
        sourceUri = Uri.parse(uriStr)
        maxWidth = intent.getIntExtra(EXTRA_MAX_WIDTH, 1024)
        maxHeight = intent.getIntExtra(EXTRA_MAX_HEIGHT, 1024)
        
        val themeColorStr = intent.getStringExtra(EXTRA_THEME_COLOR)
        if (!themeColorStr.isNullOrEmpty()) {
            try {
                val color = android.graphics.Color.parseColor(if (!themeColorStr.startsWith("#")) "#$themeColorStr" else themeColorStr)
                val bg = btnConfirm.background.mutate() as? android.graphics.drawable.GradientDrawable
                bg?.setColor(color)
            } catch (e: Exception) {}
        }
        
        // Circular profile crop should aspect fill
        zoomableImageView.isAspectFill = true
        
        loadSourceImage()
        setupButtons()
    }

    private fun setupEdgeToEdgeInsets() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        val isLightMode = (resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_NO
        controller.isAppearanceLightStatusBars = isLightMode
        controller.isAppearanceLightNavigationBars = isLightMode
        window.statusBarColor = Color.TRANSPARENT

        // Only keep navBarSpacer — cropContainer now extends behind the status bar
        val navBarSpacer = findViewById<View>(R.id.navBarSpacer)
        
        ViewCompat.setOnApplyWindowInsetsListener(window.decorView) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            navBarSpacer.layoutParams.height = bars.bottom
            insets
        }
    }

    private fun bindViews() {
        zoomableImageView = findViewById(R.id.zoomableImageView)
        circleOverlayView = findViewById(R.id.circleOverlayView)
        btnCancel = findViewById(R.id.btnCancel)
        btnConfirm = findViewById(R.id.btnConfirm)
        btnRotate = findViewById(R.id.btnRotate)
        
        val pullToDismissLayout = findViewById<PullToDismissLayout>(R.id.pullToDismissLayout)
        pullToDismissLayout.onDismiss = {
            finish()
        }
        pullToDismissLayout.onDragProgress = { progress ->
            pullToDismissLayout.setBackgroundColor(android.graphics.Color.argb(((1f - progress) * 255).toInt(), 0, 0, 0))
        }
    }

    private fun loadSourceImage() {
        executor.execute {
            try {
                val bmp = Glide.with(this).asBitmap().load(sourceUri).submit().get()
                workingBitmap = bmp
                runOnUiThread {
                    zoomableImageView.setImageBitmap(bmp)
                }
            } catch (e: Exception) {
                e.printStackTrace()
                runOnUiThread { finish() }
            }
        }
    }

    private fun setupButtons() {
        btnCancel.setOnClickListener { finish() }

        btnRotate.setOnClickListener {
            if (isRotating) return@setOnClickListener
            isRotating = true

            val doRotate: () -> Unit = doRotate@{
                val src = workingBitmap ?: run { isRotating = false; return@doRotate }
                
                var rotatedImage: Bitmap? = null
                val latch = java.util.concurrent.CountDownLatch(1)
                
                // 1. Generate rotated bitmap concurrently in background
                executor.execute {
                    val mat = Matrix().apply { postRotate(90f) }
                    rotatedImage = Bitmap.createBitmap(src, 0, 0, src.width, src.height, mat, true)
                    latch.countDown()
                }

                // 2. Visually animate the matrix directly
                zoomableImageView.animateMatrixRotation(90f, 300) {
                    // 3. Once animation finishes, wait for bitmap if needed and swap instantly
                    executor.execute {
                        latch.await()
                        val rotated = rotatedImage ?: return@execute
                        workingBitmap = rotated
                        currentRotationDegrees += 90f
                        runOnUiThread {
                            zoomableImageView.applyRotatedBitmap(rotated) // Load and map matrix
                            isRotating = false
                        }
                    }
                }
            }

            doRotate()
        }

        btnConfirm.setOnClickListener {
            performCrop()
        }
    }

    private fun performCrop() {
        val d = zoomableImageView.drawable ?: return
        val viewWidth  = zoomableImageView.width.toFloat()
        val viewHeight = zoomableImageView.height.toFloat()
        
        if (viewWidth == 0f || viewHeight == 0f) return
        
        // 1. Get inverse matrix
        val inverseMatrix = Matrix()
        if (!zoomableImageView.imageMatrix.invert(inverseMatrix)) return
        
        // 2. Map the circle (crop guide) rect to image coordinates
        val r  = Math.min(viewWidth, viewHeight) / 2f
        val cx = viewWidth  / 2f
        val cy = viewHeight / 2f
        val circleRect = RectF(cx - r, cy - r, cx + r, cy + r)
        val imageRect  = RectF()
        inverseMatrix.mapRect(imageRect, circleRect)
        
        // 3. Perform crop on background thread
        executor.execute {
            try {
                val originalBmp = workingBitmap!!
                
                val safeRect = android.graphics.Rect(
                    Math.max(0, imageRect.left.toInt()),
                    Math.max(0, imageRect.top.toInt()),
                    Math.min(originalBmp.width,  imageRect.right.toInt()),
                    Math.min(originalBmp.height, imageRect.bottom.toInt())
                )
                if (safeRect.width() <= 0 || safeRect.height() <= 0) {
                    runOnUiThread { finish() }; return@execute
                }
                
                var croppedBmp = Bitmap.createBitmap(
                    originalBmp, safeRect.left, safeRect.top,
                    safeRect.width(), safeRect.height()
                )

                // No extra rotation needed — workingBitmap is already rotated
                
                // Resize if maxWidth or maxHeight is specified
                if (maxWidth > 0 && maxHeight > 0) {
                    val scale = Math.min(maxWidth.toFloat() / croppedBmp.width, maxHeight.toFloat() / croppedBmp.height)
                    if (scale < 1.0f) {
                        val scaledWidth = (croppedBmp.width * scale).toInt()
                        val scaledHeight = (croppedBmp.height * scale).toInt()
                        croppedBmp = Bitmap.createScaledBitmap(croppedBmp, scaledWidth, scaledHeight, true)
                    }
                }
                
                val cacheFile = File(cacheDir, "profile_cropped_${System.currentTimeMillis()}.jpg")
                val out = FileOutputStream(cacheFile)
                croppedBmp.compress(Bitmap.CompressFormat.JPEG, 100, out)
                out.flush()
                out.close()
                
                runOnUiThread {
                    val croppedUri = Uri.fromFile(cacheFile)
                    if (intent.getBooleanExtra("enable_editor", false)) {
                        val editorIntent = ImageEditorActivity.createIntent(
                            this@ProfileCropActivity,
                            listOf(croppedUri),
                            startIndex = 0,
                            themeColor = intent.getStringExtra(EXTRA_THEME_COLOR),
                            selectedUris = LinkedHashSet(listOf(croppedUri)),
                            singlePhotoMode = true,
                            disableCrop = true
                        )
                        editorIntent.addFlags(Intent.FLAG_ACTIVITY_FORWARD_RESULT)
                        startActivity(editorIntent)
                        overridePendingTransition(R.anim.slide_in_bottom, R.anim.no_animation)
                        super@ProfileCropActivity.finish()
                    } else {
                        setResult(Activity.RESULT_OK, Intent().apply {
                            putExtra(EXTRA_CROPPED_URI, croppedUri.toString())
                        })
                        finish()
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
                runOnUiThread { finish() }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 999) {
            if (resultCode == Activity.RESULT_OK) {
                val resultUriStr = data?.getStringExtra(ImageEditorActivity.EXTRA_RESULT_URI)
                setResult(Activity.RESULT_OK, Intent().apply {
                    putExtra(EXTRA_CROPPED_URI, resultUriStr)
                })
                finish()
            }
            // If cancelled, stay in ProfileCropActivity
        }
    }

    override fun finish() {
        val rootView = findViewById<android.view.ViewGroup>(android.R.id.content)
        if (rootView.tag == "animating") return
        rootView.tag = "animating"

        val pullToDismissLayout = findViewById<PullToDismissLayout>(R.id.pullToDismissLayout)
        val pullChild = pullToDismissLayout.getChildAt(0)
        
        val ty = pullChild?.translationY ?: 0f
        val slideAnim = android.animation.ValueAnimator.ofFloat(ty, rootView.height.toFloat())
        slideAnim.addUpdateListener { anim ->
            pullChild?.translationY = anim.animatedValue as Float
        }
        
        val currentAlpha = (pullToDismissLayout.background as? android.graphics.drawable.ColorDrawable)?.alpha ?: 255
        val colorAnim = android.animation.ValueAnimator.ofInt(currentAlpha, 0)
        colorAnim.addUpdateListener { anim ->
            val alpha = anim.animatedValue as Int
            pullToDismissLayout.setBackgroundColor(android.graphics.Color.argb(alpha, 0, 0, 0))
        }
        
        val bottomTools = findViewById<android.view.View>(R.id.bottomTools)
        bottomTools?.animate()?.alpha(0f)?.setDuration(200)?.start()
        
        val set = android.animation.AnimatorSet()
        set.playTogether(slideAnim, colorAnim)
        set.duration = 200
        set.interpolator = androidx.interpolator.view.animation.FastOutSlowInInterpolator()
        set.addListener(object : android.animation.AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: android.animation.Animator) {
                super@ProfileCropActivity.finish()
                if (android.os.Build.VERSION.SDK_INT >= 34) {
                    overrideActivityTransition(android.app.Activity.OVERRIDE_TRANSITION_CLOSE, 0, 0)
                }
                @Suppress("DEPRECATION")
                overridePendingTransition(0, 0)
            }
        })
        set.start()
    }
}
