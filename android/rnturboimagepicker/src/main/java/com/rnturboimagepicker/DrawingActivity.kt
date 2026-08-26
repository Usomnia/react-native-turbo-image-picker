package com.rnturboimagepicker

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import com.bumptech.glide.Glide
import com.bumptech.glide.request.target.CustomTarget
import com.bumptech.glide.request.transition.Transition
import java.io.FileOutputStream

/**
 * DrawingActivity
 *
 * iOS DrawingViewController에 대응하는 Android Activity.
 *
 * 기능:
 * - 펜 / 모자이크 / 지우개 도구
 * - Undo / Redo / 전체 지우기
 * - 세로 브러시 슬라이더 (좌측, 반반 숨김/표시 애니메이션)
 * - 브러시 미리보기 원 (슬라이딩 중에만 표시)
 * - 가로 스크롤 색상 팔레트 (19색)
 * - 2손가락 핀치 줌/팬
 * - 확인 시 드로잉 합성 비트맵을 파일로 저장하고 URI 반환
 */
class DrawingActivity : AppCompatActivity() {

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
        const val EXTRA_SOURCE_URI = "extra_source_uri"
        const val EXTRA_RESULT_URI = "extra_result_uri"
        const val EXTRA_THEME_COLOR = "extra_theme_color"

        fun createIntent(activity: Activity, sourceUri: Uri, themeColor: String? = null): Intent {
            return Intent(activity, DrawingActivity::class.java).apply {
                putExtra(EXTRA_SOURCE_URI, sourceUri.toString())
                putExtra(EXTRA_THEME_COLOR, themeColor)
            }
        }
    }

    // ─── Color palette (matches iOS exactly) ──────────────
    private val colors = listOf(
        Color.WHITE,
        Color.LTGRAY,
        Color.GRAY,
        Color.DKGRAY,
        Color.BLACK,
        Color.parseColor("#FF3B30"), // systemRed
        Color.parseColor("#FF9500"), // systemOrange
        Color.parseColor("#FFCC00"), // systemYellow  ← default
        Color.parseColor("#34C759"), // systemGreen
        Color.parseColor("#5AC8FA"), // systemTeal
        Color.parseColor("#007AFF"), // systemBlue
        Color.parseColor("#AF52DE"), // systemPurple
        Color.parseColor("#FF2D55"), // systemPink
        Color.parseColor("#FFCCCC"), // Pastel Pink
        Color.parseColor("#FFE099"), // Pastel Orange
        Color.parseColor("#FFF599"), // Pastel Yellow
        Color.parseColor("#C0F0C0"), // Pastel Green
        Color.parseColor("#B3D9FF"), // Pastel Blue
        Color.parseColor("#D9BFFF")  // Pastel Purple
    )
    private var selectedColorIndex = 0 // White default
    private val prefs by lazy { getSharedPreferences("drawing_prefs", MODE_PRIVATE) }
    private val colorButtons = mutableListOf<View>()

    // ─── Views ────────────────────────────────────────────
    private lateinit var imageContainer: FrameLayout
    private lateinit var imageView: ImageView
    private lateinit var canvasView: DrawingCanvasView
    private lateinit var undoBtn: ImageButton
    private lateinit var redoBtn: ImageButton
    private lateinit var trashBtn: ImageButton
    private lateinit var cancelBtn: ImageButton
    private lateinit var confirmBtn: ImageButton
    private lateinit var penBtn: ImageButton
    private lateinit var mosaicBtn: ImageButton
    private lateinit var eraserBtn: ImageButton
    private lateinit var colorScrollView: View
    private lateinit var colorContainer: ViewGroup
    private lateinit var brushSizeSlider: BrushSizeSliderView
    private lateinit var brushPreviewCircle: View
    private lateinit var drawingStatusBarSpacer: View
    private lateinit var drawingNavBarSpacer: View

    private var themeColor: Int = Color.parseColor("#FFCC00")
    private var sourceUri: Uri? = null

    // ─── Lifecycle ────────────────────────────────────────
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT

        setContentView(R.layout.activity_drawing)
        bindViews()
        setupInsets()
        setupColorPicker()
        setupButtons()
        setupBrushSlider()

        val themeStr = intent.getStringExtra(EXTRA_THEME_COLOR)
        if (!themeStr.isNullOrEmpty()) {
            themeColor = try { Color.parseColor(themeStr) } catch (e: Exception) { themeColor }
        }

        val uriStr = intent.getStringExtra(EXTRA_SOURCE_URI)
        if (uriStr == null) { finish(); return }
        sourceUri = Uri.parse(uriStr)

        loadImage(sourceUri!!)
    }

    private fun bindViews() {
        imageContainer = findViewById(R.id.drawingImageContainer)
        undoBtn = findViewById(R.id.drawingUndoBtn)
        redoBtn = findViewById(R.id.drawingRedoBtn)
        trashBtn = findViewById(R.id.drawingTrashBtn)
        cancelBtn = findViewById(R.id.drawingCancelBtn)
        confirmBtn = findViewById(R.id.drawingConfirmBtn)
        penBtn = findViewById(R.id.drawingPenBtn)
        mosaicBtn = findViewById(R.id.drawingMosaicBtn)
        eraserBtn = findViewById(R.id.drawingEraserBtn)
        colorScrollView = findViewById(R.id.drawingColorScrollView)
        colorContainer = findViewById(R.id.drawingColorContainer)
        brushSizeSlider = findViewById(R.id.brushSizeSlider)
        brushPreviewCircle = findViewById(R.id.brushPreviewCircle)
        drawingStatusBarSpacer = findViewById(R.id.drawingStatusBarSpacer)
        drawingNavBarSpacer = findViewById(R.id.drawingNavBarSpacer)
    }

    // ─── Zoom and Pan ─────────────────────────────────────
    private var scaleFactor = 1f
    private var posX = 0f
    private var posY = 0f
    private var isMultiTouch = false
    private var lastPanX = 0f
    private var lastPanY = 0f
    private lateinit var scaleDetector: android.view.ScaleGestureDetector

    private fun setupInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(window.decorView) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            drawingStatusBarSpacer.layoutParams.height = bars.top
            drawingStatusBarSpacer.requestLayout()
            drawingNavBarSpacer.layoutParams.height = bars.bottom
            drawingNavBarSpacer.requestLayout()
            insets
        }
        setupZoomAndPan()
    }

    private fun setupZoomAndPan() {
        imageContainer.pivotX = 0f
        imageContainer.pivotY = 0f

        scaleDetector = android.view.ScaleGestureDetector(this, object : android.view.ScaleGestureDetector.SimpleOnScaleGestureListener() {
            private var lastFocusX = 0f
            private var lastFocusY = 0f

            override fun onScaleBegin(detector: android.view.ScaleGestureDetector): Boolean {
                lastFocusX = detector.focusX
                lastFocusY = detector.focusY
                return true
            }

            override fun onScale(detector: android.view.ScaleGestureDetector): Boolean {
                val focusX = detector.focusX
                val focusY = detector.focusY

                val oldScale = scaleFactor
                scaleFactor = (scaleFactor * detector.scaleFactor).coerceIn(1.0f, 5.0f)
                val actualFactor = scaleFactor / oldScale

                // Focal point zoom: keep the pinch center stable
                posX = focusX - (focusX - posX) * actualFactor
                posY = focusY - (focusY - posY) * actualFactor

                // Pan-during-pinch
                posX += focusX - lastFocusX
                posY += focusY - lastFocusY

                lastFocusX = focusX
                lastFocusY = focusY

                clampPan()
                applyTransform()
                return true
            }

            override fun onScaleEnd(detector: android.view.ScaleGestureDetector) {
                if (scaleFactor <= 1.01f) {
                    scaleFactor = 1f
                    posX = 0f
                    posY = 0f
                    applyTransform()
                }
            }
        })
    }

    /**
     * Intercept touch events at Activity level — this runs BEFORE views receive them.
     * Raw screen coordinates are used so there's no coordinate distortion from scaled views.
     */
    override fun dispatchTouchEvent(ev: android.view.MotionEvent): Boolean {
        // Always feed the scale detector (uses raw screen coords at this level)
        scaleDetector.onTouchEvent(ev)

        when (ev.actionMasked) {
            android.view.MotionEvent.ACTION_DOWN -> {
                isMultiTouch = false
            }
            android.view.MotionEvent.ACTION_POINTER_DOWN -> {
                isMultiTouch = true
                // Cancel any in-progress drawing stroke
                if (::canvasView.isInitialized) {
                    canvasView.cancelCurrentPath()
                }
                // 핀치 줌 중에는 색상 팔레트 숨김
                colorScrollView.visibility = View.INVISIBLE
                // Record pan start position (average of all pointers)
                lastPanX = averageX(ev)
                lastPanY = averageY(ev)
            }
            android.view.MotionEvent.ACTION_MOVE -> {
                if (isMultiTouch && ev.pointerCount >= 2 && scaleFactor > 1f && !scaleDetector.isInProgress) {
                    // Two-finger pan when zoomed in (but not actively pinching)
                    val avgX = averageX(ev)
                    val avgY = averageY(ev)
                    posX += avgX - lastPanX
                    posY += avgY - lastPanY
                    lastPanX = avgX
                    lastPanY = avgY
                    clampPan()
                    applyTransform()
                }
            }
            android.view.MotionEvent.ACTION_POINTER_UP -> {
                // Recalculate pan anchor excluding the lifted finger
                val upIdx = ev.actionIndex
                var sx = 0f; var sy = 0f; var cnt = 0
                for (i in 0 until ev.pointerCount) {
                    if (i != upIdx) { sx += ev.getX(i); sy += ev.getY(i); cnt++ }
                }
                if (cnt > 0) { lastPanX = sx / cnt; lastPanY = sy / cnt }
            }
            android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> {
                isMultiTouch = false
                // 모든 손가락을 뗀 후 색상 팔레트 복원
                if (::canvasView.isInitialized) updateBottomTools()
            }
        }

        // If 2+ fingers active, consume the event — don't let views handle it
        if (isMultiTouch && ev.pointerCount >= 2) {
            return true
        }

        return super.dispatchTouchEvent(ev)
    }

    private fun averageX(ev: android.view.MotionEvent): Float {
        var sum = 0f
        for (i in 0 until ev.pointerCount) sum += ev.getX(i)
        return sum / ev.pointerCount
    }

    private fun averageY(ev: android.view.MotionEvent): Float {
        var sum = 0f
        for (i in 0 until ev.pointerCount) sum += ev.getY(i)
        return sum / ev.pointerCount
    }

    private fun clampPan() {
        val vw = imageContainer.width.toFloat()
        val vh = imageContainer.height.toFloat()
        val scaledW = vw * scaleFactor
        val scaledH = vh * scaleFactor

        posX = posX.coerceIn(vw - scaledW, 0f)
        posY = posY.coerceIn(vh - scaledH, 0f)
    }

    private fun applyTransform() {
        imageContainer.scaleX = scaleFactor
        imageContainer.scaleY = scaleFactor
        imageContainer.translationX = posX
        imageContainer.translationY = posY
    }

    // ─── Image loading ────────────────────────────────────
    private fun loadImage(uri: Uri) {
        Glide.with(this)
            .asBitmap()
            .load(uri)
            .into(object : CustomTarget<Bitmap>() {
                override fun onResourceReady(resource: Bitmap, transition: Transition<in Bitmap>?) {
                    setupImageAndCanvas(resource)
                }
                override fun onLoadCleared(placeholder: android.graphics.drawable.Drawable?) {}
            })
    }

    private fun setupImageAndCanvas(bitmap: Bitmap) {
        // ImageView
        imageView = ImageView(this).apply {
            setImageBitmap(bitmap)
            scaleType = ImageView.ScaleType.FIT_CENTER
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }
        imageContainer.addView(imageView)

        // Canvas overlay (exact same size as imageView, positioned after layout)
        canvasView = DrawingCanvasView(this).apply {
            currentColor = colors[selectedColorIndex]
            currentLineWidth = brushSizeSlider.value * resources.displayMetrics.density
            onStateChanged = { updateTopBarStates() }

            // 드로잉 중에는 색상 팔레트 숨기기 (레이아웃 유지 위해 INVISIBLE)
            onDrawingStarted = {
                colorScrollView.visibility = View.INVISIBLE
            }
            onDrawingEnded = {
                // 펜 모드일 때만 다시 표시 (지우개/모자이크는 원래 숨김)
                updateBottomTools()
            }
        }
        imageContainer.addView(canvasView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Set bitmap after layout so canvas dimensions are correct
        imageView.post {
            canvasView.originalBitmap = bitmap
            alignCanvasToImage(bitmap)
        }

        updateTopBarStates()
        updateBottomTools()
    }

    private fun alignCanvasToImage(bitmap: Bitmap) {
        val vw = imageContainer.width.toFloat()
        val vh = imageContainer.height.toFloat()
        if (vw <= 0 || vh <= 0) return

        val scale = minOf(vw / bitmap.width, vh / bitmap.height)
        val sw = bitmap.width * scale
        val sh = bitmap.height * scale
        val ox = (vw - sw) / 2f
        val oy = (vh - sh) / 2f

        canvasView.layoutParams = (canvasView.layoutParams as FrameLayout.LayoutParams).also {
            it.width = sw.toInt()
            it.height = sh.toInt()
            it.leftMargin = ox.toInt()
            it.topMargin = oy.toInt()
        }
        canvasView.requestLayout()
    }

    // ─── Color picker ─────────────────────────────────────
    private fun setupColorPicker() {
        val dp = resources.displayMetrics.density
        val size = (30 * dp).toInt()
        val margin = (8 * dp).toInt()

        colors.forEachIndexed { index, color ->
            val btn = View(this).apply {
                layoutParams = ViewGroup.MarginLayoutParams(size, size).also {
                    if (index > 0) it.leftMargin = margin
                }
                setBackgroundColor(color)
                tag = index
            }
            btn.background = makeColorCircleDrawable(color, index == selectedColorIndex)
            btn.setOnClickListener { onColorSelected(index) }
            colorContainer.addView(btn)
            colorButtons.add(btn)
        }
    }

    private fun makeColorCircleDrawable(color: Int, isSelected: Boolean): android.graphics.drawable.GradientDrawable {
        return android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.OVAL
            setColor(color)
            val borderColor = when {
                isSelected -> themeColor
                color == Color.BLACK || color == Color.DKGRAY -> Color.argb(80, 255, 255, 255)
                else -> Color.TRANSPARENT
            }
            setStroke((2 * resources.displayMetrics.density).toInt(), borderColor)
        }
    }

    private fun onColorSelected(index: Int) {
        if (index == selectedColorIndex) return

        // Deselect old
        val old = colorButtons[selectedColorIndex]
        old.background = makeColorCircleDrawable(colors[selectedColorIndex], false)

        selectedColorIndex = index
        prefs.edit().putInt("color_index", index).apply()
        canvasView.currentColor = colors[index]
        updateBrushPreviewColor()

        // Select new
        val new = colorButtons[index]
        new.background = makeColorCircleDrawable(colors[index], true)
    }

    // ─── Button setup ─────────────────────────────────────
    private fun setupButtons() {
        undoBtn.setOnClickListener { canvasView.undo() }
        redoBtn.setOnClickListener { canvasView.redo() }
        trashBtn.setOnClickListener { canvasView.clearAll() }

        cancelBtn.setOnClickListener { finish() }
        confirmBtn.setOnClickListener { onConfirmTapped() }

        penBtn.setOnClickListener { selectTool(DrawingToolType.PEN) }
        mosaicBtn.setOnClickListener { selectTool(DrawingToolType.MOSAIC) }
        eraserBtn.setOnClickListener { selectTool(DrawingToolType.ERASER) }
    }

    private fun selectTool(tool: DrawingToolType) {
        canvasView.currentTool = tool
        // 모자이크 툴 선택 시: 슬라이더 범위를 모자이크 강도용으로 변경
        if (tool == DrawingToolType.MOSAIC) {
            val savedMosaicSize = prefs.getFloat("mosaic_block_size", 6f)
            brushSizeSlider.minimumValue = 6f
            brushSizeSlider.maximumValue = 20f
            brushSizeSlider.value = savedMosaicSize
        } else {
            val savedBrushSize = prefs.getFloat("brush_size", 10f)
            brushSizeSlider.minimumValue = 2f
            brushSizeSlider.maximumValue = 50f
            brushSizeSlider.value = savedBrushSize
        }
        updateBottomTools()
        updateBrushPreviewColor()
    }

    private fun updateTopBarStates() {
        val hasStrokes = canvasView.paths.isNotEmpty()
        val hasUndone = canvasView.undonePaths.isNotEmpty()
        val disabledAlpha = 0.3f

        // reward = undo
        undoBtn.isEnabled = hasStrokes
        undoBtn.alpha = if (hasStrokes) 1f else disabledAlpha

        // forward = redo
        redoBtn.isEnabled = hasUndone
        redoBtn.alpha = if (hasUndone) 1f else disabledAlpha

        // delete = trash
        trashBtn.isEnabled = hasStrokes
        trashBtn.alpha = if (hasStrokes) 1f else disabledAlpha
    }

    private fun updateBottomTools() {
        // 커스텀 아이콘은 alpha로 활성/비활성 표현
        val activeAlpha = 1.0f
        val inactiveAlpha = 0.4f

        penBtn.alpha = if (canvasView.currentTool == DrawingToolType.PEN) activeAlpha else inactiveAlpha
        mosaicBtn.alpha = if (canvasView.currentTool == DrawingToolType.MOSAIC) activeAlpha else inactiveAlpha
        eraserBtn.alpha = if (canvasView.currentTool == DrawingToolType.ERASER) activeAlpha else inactiveAlpha

        colorScrollView.visibility =
            if (canvasView.currentTool == DrawingToolType.ERASER || canvasView.currentTool == DrawingToolType.MOSAIC)
                View.GONE else View.VISIBLE
    }

    private fun setTint(btn: ImageButton, color: Int) {
        btn.setColorFilter(color, android.graphics.PorterDuff.Mode.SRC_IN)
    }

    // ─── Brush slider ─────────────────────────────────────
    private fun setupBrushSlider() {
        // Restore saved brush size (default 10)
        val savedBrushSize = prefs.getFloat("brush_size", 10f)
        brushSizeSlider.minimumValue = 2f
        brushSizeSlider.maximumValue = 50f
        brushSizeSlider.value = savedBrushSize

        // Restore saved color index
        selectedColorIndex = prefs.getInt("color_index", 0)

        brushSizeSlider.listener = object : BrushSizeSliderView.Listener {
            override fun onValueChanged(value: Float) {
                if (::canvasView.isInitialized && canvasView.currentTool == DrawingToolType.MOSAIC) {
                    // 모자이크 툴: 모자이크 블록 크기 조절 (dp 단위 그대로)
                    canvasView.mosaicBlockSizeDp = value
                    prefs.edit().putFloat("mosaic_block_size", value).apply()
                    // 프리뷷: 사각형 모양으로 크기 시각화
                    val px = value * resources.displayMetrics.density
                    updateMosaicPreviewSize(px)
                } else {
                    val px = value * resources.displayMetrics.density
                    canvasView.currentLineWidth = px
                    updateBrushPreviewSize(px)
                    prefs.edit().putFloat("brush_size", value).apply()
                }
            }
            override fun onDragBegan() {
                showSlider()
                brushPreviewCircle.visibility = View.VISIBLE
            }
            override fun onDragEnded() {
                hideSlider()
                brushPreviewCircle.visibility = View.GONE
            }
        }
        // 초기 프리뷰 원 색상을 현재 선택된 브러시 색상으로 설정
        updateBrushPreviewColor()
    }

    private fun showSlider() {
        // XML has marginStart=-20dp (half hidden). Translate right by halfWidth to fully show.
        val halfWidth = brushSizeSlider.width / 2f
        brushSizeSlider.animate()
            .translationX(halfWidth)
            .setDuration(200)
            .start()
    }

    private fun hideSlider() {
        // Translate back to 0 → XML margin positions it half-visible (handle sticking out)
        brushSizeSlider.animate()
            .translationX(0f)
            .setDuration(200)
            .start()
    }

    private fun updateBrushPreviewSize(px: Float) {
        val scaledPx = px * scaleFactor
        val params = brushPreviewCircle.layoutParams
        params.width = scaledPx.toInt().coerceAtLeast(4)
        params.height = scaledPx.toInt().coerceAtLeast(4)
        brushPreviewCircle.layoutParams = params
        (brushPreviewCircle.background as? android.graphics.drawable.GradientDrawable)?.cornerRadius = scaledPx / 2f
        brushPreviewCircle.requestLayout()
    }

    private fun updateMosaicPreviewSize(px: Float) {
        // 모자이크 프리뷷: 사각형 모양으로 표시
        val scaledPx = px * scaleFactor
        val params = brushPreviewCircle.layoutParams
        params.width = scaledPx.toInt().coerceAtLeast(4)
        params.height = scaledPx.toInt().coerceAtLeast(4)
        brushPreviewCircle.layoutParams = params
        (brushPreviewCircle.background as? android.graphics.drawable.GradientDrawable)?.cornerRadius = 4f
        brushPreviewCircle.requestLayout()
    }

    private fun updateBrushPreviewColor() {
        (brushPreviewCircle.background as? android.graphics.drawable.GradientDrawable)
            ?.setColor(themeColor)
    }

    // ─── Confirm / save ───────────────────────────────────
    private fun onConfirmTapped() {
        val merged = canvasView.generateMergedBitmap()
        if (merged == null) {
            // No drawing → return original URI unchanged
            setResult(Activity.RESULT_OK, Intent().apply {
                putExtra(EXTRA_RESULT_URI, sourceUri.toString())
            })
            finish()
            return
        }

        val file = java.io.File(cacheDir, "drawing_${System.currentTimeMillis()}.jpg")
        FileOutputStream(file).use { out ->
            merged.compress(Bitmap.CompressFormat.JPEG, 95, out)
        }
        merged.recycle()

        setResult(Activity.RESULT_OK, Intent().apply {
            putExtra(EXTRA_RESULT_URI, Uri.fromFile(file).toString())
        })
        finish()
    }
}
