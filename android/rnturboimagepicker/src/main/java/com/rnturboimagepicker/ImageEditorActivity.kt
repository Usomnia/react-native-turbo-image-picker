package com.rnturboimagepicker

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.ImageButton
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentActivity
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.adapter.FragmentStateAdapter
import androidx.viewpager2.widget.ViewPager2

import android.graphics.Bitmap
import android.widget.SeekBar
import android.widget.FrameLayout
import android.view.ViewGroup
import java.io.File
import java.io.FileOutputStream
import com.bumptech.glide.Glide
import com.bumptech.glide.request.target.CustomTarget
import com.bumptech.glide.request.transition.Transition
import java.util.concurrent.Executors
import java.util.concurrent.ExecutorService

/**
 * ImageEditorActivity
 *
 * iOS ImageEditorViewController에 대응하는 전체화면 편집 Activity.
 *
 * 구성:
 * - ViewPager2 수평 스와이프로 이미지 탐색
 * - 상단 오버레이: [◁] [N/M] [전송]
 * - 하단 툴바: 5개 아이콘 (✨ ✂ Aa 😊 ✏)
 *
 * 리팩토링 내용:
 * - URI 목록을 Intent extras 대신 EditorDataHolder(in-memory singleton)로 수신
 *   → TransactionTooLargeException 위험 완전 제거
 * - LruCache 제거 → Glide 내장 메모리 캐시 사용
 * - WindowInsets → ViewCompat.setOnApplyWindowInsetsListener + WindowInsetsCompat
 * - onBackPressed() → OnBackPressedDispatcher (Android 13+ 권장)
 * - offscreenPageLimit = 1 (메모리 최적화, 양쪽 1페이지만 선로드)
 */
class ImageEditorActivity : AppCompatActivity(), TextStickerView.OnStickerInteractionListener {

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
        const val EXTRA_START_INDEX = "extra_start_index"
        const val EXTRA_RESULT_URI = "extra_result_uri"
        const val EXTRA_RESULT_URIS = "extra_result_uris"
        const val EXTRA_ORIGINAL_URIS = "extra_original_uris"
        const val EXTRA_RESULT_SELECTED_URIS = "extra_result_selected_uris"
        const val EXTRA_THEME_COLOR = "extra_theme_color"
        const val EXTRA_SINGLE_PHOTO_MODE = "extra_single_photo_mode"
        const val EXTRA_DISABLE_CROP = "extra_disable_crop"
        const val EXTRA_MAX_WIDTH = "extra_max_width"
        const val EXTRA_MAX_HEIGHT = "extra_max_height"

        /**
         * EditorDataHolder에 URI 목록을 저장한 뒤 Intent를 반환.
         * Intent에는 시작 인덱스만 전달 (URI 목록은 메모리로 공유).
         */
        fun createIntent(activity: Activity, uris: List<Uri>, startIndex: Int, themeColor: String? = null, selectedUris: LinkedHashSet<Uri> = LinkedHashSet(), editedUris: Map<String, Uri> = emptyMap(), singlePhotoMode: Boolean = false, disableCrop: Boolean = false, maxWidth: Int = 0, maxHeight: Int = 0): Intent {
            EditorDataHolder.set(uris, selectedUris, editedUris)
            return Intent(activity, ImageEditorActivity::class.java).apply {
                putExtra(EXTRA_START_INDEX, startIndex)
                putExtra(EXTRA_THEME_COLOR, themeColor)
                putExtra(EXTRA_SINGLE_PHOTO_MODE, singlePhotoMode)
                putExtra(EXTRA_DISABLE_CROP, disableCrop)
                putExtra(EXTRA_MAX_WIDTH, maxWidth)
                putExtra(EXTRA_MAX_HEIGHT, maxHeight)
            }
        }
    }

    // ─────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────

    private var uris: MutableList<Uri> = mutableListOf()
    private var initialUris: List<Uri> = listOf()
    private var originalUris: List<Uri> = listOf()
    private var selectedUris: LinkedHashSet<Uri> = LinkedHashSet()
    private var currentIndex: Int = 0
    private var singlePhotoMode: Boolean = false
    private var disableCrop: Boolean = false
    var maxWidth: Int = 0
    var maxHeight: Int = 0

    // Filter properties
    private lateinit var filterContainerView: View
    private lateinit var sliderBackgroundView: View
    private lateinit var intensitySlider: SeekBar
    private lateinit var filterRecyclerView: RecyclerView
    private lateinit var toolEffect: ImageButton
    private lateinit var toolCrop: ImageButton
    private lateinit var toolText: ImageButton
    private lateinit var toolEmoji: ImageButton
    private lateinit var toolDrawing: ImageButton
    
    // Text Mode Views
    private lateinit var topBarOverlay: View
    private lateinit var editorBottomBar: View
    private lateinit var textModeTopBar: View
    
    // Thumbnail Bar (iOS Parity)
    private var thumbnailRecyclerView: RecyclerView? = null
    private lateinit var thumbnailAdapter: EditorThumbnailAdapter
    
    // Selection Badge
    private lateinit var editorSelectionBadge: View
    private lateinit var editorSelectionBorder: View
    private lateinit var editorSelectionNumber: TextView
    private lateinit var textModeBottomBar: View
    private lateinit var textModeCancelButton: View
    private lateinit var textModeConfirmButton: View
    private lateinit var textModeDeleteAllButton: View
    private lateinit var textModeAddButton: View

    private lateinit var effectModeBottomBar: View
    private lateinit var effectModeCancelButton: View
    private lateinit var effectModeConfirmButton: View
    private lateinit var effectModeNavBarSpacer: View
    private var backupFilterState: FilterState? = null
    
    private val filterStates = mutableMapOf<Int, FilterState>()
    private var isFilterActive = false
    private lateinit var filterAdapter: FilterThumbnailAdapter
    private var parsedThemeColor: Int = android.graphics.Color.parseColor("#FFEB3B")

    // Text Mode State
    var isTextModeActive = false
    data class StickerState(val text: String, val textColor: Int, val scaleX: Float, val scaleY: Float, val rotation: Float, val transX: Float, val transY: Float, val isEmojiSticker: Boolean = false)

    val stickersByIndex = mutableMapOf<Int, MutableList<StickerState>>()
    private val preTextModeStickerStates = mutableMapOf<TextStickerView, StickerState>()
    private val preTextModeStickerList = mutableListOf<TextStickerView>()

    // Emoji Mode State
    var isEmojiModeActive = false
    private val preEmojiModeStickerStates = mutableMapOf<TextStickerView, StickerState>()
    private val preEmojiModeStickerList = mutableListOf<TextStickerView>()
    private lateinit var emojiPicker: EmojiPickerView

    fun getFilterState(index: Int): FilterState? {
        return filterStates[index]
    }

    private var thumbnailTarget: CustomTarget<Bitmap>? = null
    private val executorService: ExecutorService = Executors.newSingleThreadExecutor()
    
    private fun setPullToDismissEnabled(enabled: Boolean) {
        val layout = findViewById<PullToDismissLayout>(R.id.pullToDismissLayout)
        layout?.isPullEnabled = enabled
    }

    private val cropLauncher = registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.StartActivityForResult()) { result ->
        setPullToDismissEnabled(true)
        if (result.resultCode == Activity.RESULT_OK) {
            val uriStr = result.data?.getStringExtra(CropActivity.EXTRA_CROPPED_URI)
            if (uriStr != null) {
                val croppedUri = android.net.Uri.parse(uriStr)
                // Update stored URI for this page
                replaceUri(currentIndex, croppedUri)
                // Reload the fragment so it shows the cropped image
                currentFragment?.reloadImage(croppedUri)
                autoSelectCurrentPhoto()
                updateSendButtonState()
            }
        }
    }

    private val drawingLauncher = registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.StartActivityForResult()) { result ->
        setPullToDismissEnabled(true)
        if (result.resultCode == Activity.RESULT_OK) {
            val uriStr = result.data?.getStringExtra(DrawingActivity.EXTRA_RESULT_URI)
            if (uriStr != null) {
                val drawnUri = android.net.Uri.parse(uriStr)
                replaceUri(currentIndex, drawnUri)
                currentFragment?.reloadImage(drawnUri)
                autoSelectCurrentPhoto()
            }
        }
    }

    // ─────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────

    private lateinit var viewPager: ViewPager2
    private lateinit var backButton: ImageButton
    private lateinit var counterLabel: TextView
    private lateinit var sendButton: TextView
    private lateinit var statusBarSpacer: View
    private lateinit var navBarSpacer: View
    private lateinit var textModeStatusBarSpacer: View
    private lateinit var textModeNavBarSpacer: View

    // ─────────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Edge-to-edge setup (AndroidX — safe on all API levels)
        setupEdgeToEdge()

        if (TransitionHelper.sourceRect != null && TransitionHelper.thumbnailBitmap != null) {
            if (android.os.Build.VERSION.SDK_INT >= 34) {
                overrideActivityTransition(android.app.Activity.OVERRIDE_TRANSITION_OPEN, 0, 0)
            }
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
        }

        setContentView(R.layout.activity_image_editor)
        
        val rootView = findViewById<android.view.ViewGroup>(android.R.id.content)
        
        val sourceRect = TransitionHelper.sourceRect
        val thumbnailBitmap = TransitionHelper.thumbnailBitmap
        
        if (sourceRect != null && thumbnailBitmap != null) {
            // Fade in the background and UI
            // Fade in only the background and toolbars, NOT the image overlay
            val editorRootLayout = rootView.getChildAt(0) as android.view.ViewGroup
            
            // Hide toolbars initially and animate them
            val localTopBar = findViewById<android.view.View>(R.id.topBarOverlay)
            val localBottomBar = findViewById<android.view.View>(R.id.editorBottomBar)
            localTopBar.alpha = 0f
            localBottomBar.alpha = 0f
            localTopBar.animate().alpha(1f).setDuration(200).start()
            localBottomBar.animate().alpha(1f).setDuration(200).start()
            
            // Fade background from transparent to black
            val colorAnim = android.animation.ValueAnimator.ofInt(0, 255)
            colorAnim.addUpdateListener { animator ->
                val alpha = animator.animatedValue as Int
                editorRootLayout.setBackgroundColor(android.graphics.Color.argb(alpha, 0, 0, 0))
            }
            colorAnim.duration = 250
            colorAnim.start()
            
            // Hide ViewPager2 during animation to prevent double image rendering
            val pullToDismissLayout = findViewById<android.view.View>(R.id.pullToDismissLayout)
            pullToDismissLayout.visibility = android.view.View.VISIBLE
            val localViewPager = findViewById<androidx.viewpager2.widget.ViewPager2>(R.id.editorViewPager)
            localViewPager.visibility = android.view.View.INVISIBLE
            
            // Create temporary overlay view for zero-layout high-performance animation
            val overlayView = object : android.view.View(this) {
                var animatedBounds = android.graphics.RectF(sourceRect.left.toFloat(), sourceRect.top.toFloat(), sourceRect.right.toFloat(), sourceRect.bottom.toFloat())
                private val paint = android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG)
                
                override fun onDraw(canvas: android.graphics.Canvas) {
                    if (animatedBounds.isEmpty) return
                    
                    val scale: Float
                    val dx: Float
                    val dy: Float
                    
                    val bw = thumbnailBitmap.width.toFloat()
                    val bh = thumbnailBitmap.height.toFloat()
                    val vw = animatedBounds.width()
                    val vh = animatedBounds.height()
                    
                    if (bw * vh > vw * bh) {
                        scale = vh / bh
                        dx = (vw - bw * scale) * 0.5f
                        dy = 0f
                    } else {
                        scale = vw / bw
                        dx = 0f
                        dy = (vh - bh * scale) * 0.5f
                    }
                    
                    canvas.save()
                    canvas.translate(animatedBounds.left, animatedBounds.top)
                    canvas.clipRect(0f, 0f, vw, vh)
                    val matrix = android.graphics.Matrix()
                    matrix.setScale(scale, scale)
                    matrix.postTranslate(dx, dy)
                    canvas.drawBitmap(thumbnailBitmap, matrix, paint)
                    canvas.restore()
                }
            }
            overlayView.tag = "transition_overlay"
            val innerFrame = (pullToDismissLayout as android.view.ViewGroup).getChildAt(0) as android.view.ViewGroup
            innerFrame.addView(overlayView, 1, android.widget.FrameLayout.LayoutParams(
                android.widget.FrameLayout.LayoutParams.MATCH_PARENT, 
                android.widget.FrameLayout.LayoutParams.MATCH_PARENT
            ))
            
            // Calculate target bounds (center, fit width)
            rootView.viewTreeObserver.addOnPreDrawListener(object : android.view.ViewTreeObserver.OnPreDrawListener {
                override fun onPreDraw(): Boolean {
                    rootView.viewTreeObserver.removeOnPreDrawListener(this)
                    
                    val screenWidth = rootView.width.toFloat()
                    val screenHeight = rootView.height.toFloat()
                    
                    // Target is FIT_CENTER
                    val bw = thumbnailBitmap.width.toFloat()
                    val bh = thumbnailBitmap.height.toFloat()
                    
                    val targetWidth: Float
                    val targetHeight: Float
                    
                    if (bw * screenHeight > screenWidth * bh) {
                        targetWidth = screenWidth
                        targetHeight = screenWidth * bh / bw
                    } else {
                        targetHeight = screenHeight
                        targetWidth = screenHeight * bw / bh
                    }
                    
                    val targetLeft = (screenWidth - targetWidth) / 2f
                    val targetTop = (screenHeight - targetHeight) / 2f
                    val targetRight = targetLeft + targetWidth
                    val targetBottom = targetTop + targetHeight
                    
                    val startLeft = sourceRect.left.toFloat()
                    val startTop = sourceRect.top.toFloat()
                    val startRight = sourceRect.right.toFloat()
                    val startBottom = sourceRect.bottom.toFloat()
                    
                    val animator = android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
                        duration = 200 // Speed up animation
                        interpolator = androidx.interpolator.view.animation.FastOutSlowInInterpolator()
                        addUpdateListener { anim ->
                            val progress = anim.animatedValue as Float
                            overlayView.animatedBounds.set(
                                startLeft + (targetLeft - startLeft) * progress,
                                startTop + (targetTop - startTop) * progress,
                                startRight + (targetRight - startRight) * progress,
                                startBottom + (targetBottom - startBottom) * progress
                            )
                            overlayView.invalidate()
                        }
                        addListener(object : android.animation.AnimatorListenerAdapter() {
                            override fun onAnimationEnd(animation: android.animation.Animator) {
                                animationDone = true
                                checkAndHideOverlay()
                            }
                        })
                    }
                    animator.start()
                        
                    return true
                }
            })
        }
        
        onBackPressedDispatcher.addCallback(this, object : androidx.activity.OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                finish()
            }
        })

        val themeColorStr = intent.getStringExtra(EXTRA_THEME_COLOR)
        parsedThemeColor = try {
            if (!themeColorStr.isNullOrEmpty()) {
                try {
                    android.graphics.Color.parseColor(themeColorStr)
                } catch (e: IllegalArgumentException) {
                    android.graphics.Color.parseColor(if (!themeColorStr.startsWith("#")) "#$themeColorStr" else themeColorStr)
                }
            } else {
                android.graphics.Color.parseColor("#FF6B35")
            }
        } catch (e: Exception) {
            android.graphics.Color.parseColor("#FF6B35")
        }


        // Receive URI list from in-memory holder (no Binder size limit)
        val inputUris = EditorDataHolder.get()
        originalUris = ArrayList(inputUris)
        
        val editedUris = EditorDataHolder.getEdited()
        uris = inputUris.map { uri ->
            editedUris[uri.toString()] ?: uri
        }.toMutableList()
        initialUris = ArrayList(uris)
        
        selectedUris = LinkedHashSet(EditorDataHolder.getSelected())
        singlePhotoMode = intent.getBooleanExtra(EXTRA_SINGLE_PHOTO_MODE, false)
        disableCrop = intent.getBooleanExtra(EXTRA_DISABLE_CROP, false)
        maxWidth = intent.getIntExtra(EXTRA_MAX_WIDTH, 0)
        maxHeight = intent.getIntExtra(EXTRA_MAX_HEIGHT, 0)
        val startIndex = intent.getIntExtra(EXTRA_START_INDEX, 0)
        
        if (uris.isNotEmpty() && startIndex >= 0 && startIndex < uris.size) {
            initialUriStr = uris[startIndex].toString()
        }
        
        currentIndex = startIndex.coerceIn(0, (uris.size - 1).coerceAtLeast(0))

        if (uris.isEmpty()) {
            finish()
            return
        }

        bindViews()
        setupEdgeToEdgeInsets()
        setupButtons()
        
        val hasAnimation = TransitionHelper.sourceRect != null && TransitionHelper.thumbnailBitmap != null
        if (hasAnimation) {
            val rootView = findViewById<android.view.ViewGroup>(android.R.id.content)
            rootView.post {
                if (isDestroyed || isFinishing) return@post
                setupViewPager()
                setupThumbnailBar()
                updateCounter()
                updateSelectionBadge()
                updateSendButtonState()
            }
        } else {
            setupViewPager()
            setupThumbnailBar()
            updateCounter()
            updateSelectionBadge()
            updateSendButtonState()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        executorService.shutdown()
        // Clear in-memory URI list to release references
        EditorDataHolder.clear()
    }

    // ─────────────────────────────────────────────
    // Edge-to-edge
    // ─────────────────────────────────────────────

    private fun setupEdgeToEdge() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        val isLightMode = (resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_NO
        // 라이트 모드: 상태바/내비바 아이콘을 어두운 색으로
        // 다크 모드: 상태바/내비바 아이콘을 밝은 색으로
        controller.isAppearanceLightStatusBars = isLightMode
        controller.isAppearanceLightNavigationBars = isLightMode
        window.statusBarColor = android.graphics.Color.TRANSPARENT
        // nav bar 색상은 테마(@color/editor_nav_bar)에서 자동 적용됨
    }

    private fun bindViews() {
        viewPager = findViewById(R.id.editorViewPager)
        val pullToDismissLayout = findViewById<PullToDismissLayout>(R.id.pullToDismissLayout)
        val rootLayout = findViewById<android.view.ViewGroup>(android.R.id.content).getChildAt(0)
        pullToDismissLayout.onDismiss = {
            finish()
        }
        pullToDismissLayout.onDragProgress = { progress ->
            rootLayout.setBackgroundColor(android.graphics.Color.argb(((1f - progress) * 255).toInt(), 0, 0, 0))
        }
        backButton = findViewById(R.id.editorBackButton)
        counterLabel = findViewById(R.id.editorCounterLabel)
        sendButton = findViewById(R.id.editorSendButton)
        statusBarSpacer = findViewById(R.id.statusBarSpacer)
        navBarSpacer = findViewById(R.id.navBarSpacer)
        textModeStatusBarSpacer = findViewById(R.id.textModeStatusBarSpacer)
        textModeNavBarSpacer = findViewById(R.id.textModeNavBarSpacer)
        
        filterContainerView = findViewById(R.id.filterContainerView)
        sliderBackgroundView = findViewById(R.id.sliderBackgroundView)
        intensitySlider = findViewById(R.id.intensitySlider)
        filterRecyclerView = findViewById(R.id.filterRecyclerView)
        toolEffect = findViewById(R.id.toolEffect)
        toolCrop = findViewById(R.id.toolCrop)
        toolText = findViewById(R.id.toolText)
        toolEmoji = findViewById(R.id.toolEmoji)
        toolDrawing = findViewById(R.id.toolDrawing)
        
        if (disableCrop) {
            toolCrop.isEnabled = false
            toolCrop.alpha = 0.3f
        }
        
        editorSelectionBadge = findViewById(R.id.editorSelectionBadge)
        editorSelectionBorder = findViewById(R.id.editorSelectionBorder)
        editorSelectionNumber = findViewById(R.id.editorSelectionNumber)

        topBarOverlay = findViewById(R.id.topBarOverlay)
        editorBottomBar = findViewById(R.id.editorBottomBar)
        textModeTopBar = findViewById(R.id.textModeTopBar)
        textModeBottomBar = findViewById(R.id.textModeBottomBar)
        // thumbnailRecyclerView = findViewById(R.id.editorThumbnailRecyclerView)
        thumbnailRecyclerView = null
        textModeCancelButton = findViewById(R.id.textModeCancelButton)
        textModeConfirmButton = findViewById(R.id.textModeConfirmButton)
        textModeDeleteAllButton = findViewById(R.id.textModeDeleteAllButton)
        textModeAddButton = findViewById(R.id.textModeAddButton)
        
        effectModeBottomBar = findViewById(R.id.effectModeBottomBar)
        effectModeCancelButton = findViewById(R.id.effectModeCancelButton)
        effectModeConfirmButton = findViewById(R.id.effectModeConfirmButton)
        effectModeNavBarSpacer = findViewById(R.id.effectModeNavBarSpacer)
        
        emojiPicker = findViewById(R.id.emojiPicker)
        emojiPicker.themeColor = parsedThemeColor
        emojiPicker.onEmojiSelected = { emoji ->
            val fragment = currentFragment
            if (fragment != null) {
                fragment.placeEmojiSticker(emoji)
            }
        }
        emojiPicker.onCancel = {
            cancelEmojiMode()
        }
        emojiPicker.onDone = {
            confirmEmojiMode()
        }
    }

    private fun setupEdgeToEdgeInsets() {
        // ViewCompat API: unified, no SDK_INT branching needed
        ViewCompat.setOnApplyWindowInsetsListener(window.decorView) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())

            statusBarSpacer.layoutParams.height = bars.top
            statusBarSpacer.requestLayout()
            
            textModeStatusBarSpacer.layoutParams.height = bars.top
            textModeStatusBarSpacer.requestLayout()

            navBarSpacer.layoutParams.height = bars.bottom
            navBarSpacer.requestLayout()
            
            textModeNavBarSpacer.layoutParams.height = bars.bottom
            textModeNavBarSpacer.requestLayout()
            
            effectModeNavBarSpacer.layoutParams.height = bars.bottom
            effectModeNavBarSpacer.requestLayout()
            
            // Fix cutoff: bottom margin should be exactly the bottom bar height + nav bar height
            val dp56 = (56 * resources.displayMetrics.density).toInt()
            val params = filterContainerView.layoutParams as FrameLayout.LayoutParams
            params.bottomMargin = dp56 + bars.bottom
            filterContainerView.layoutParams = params

            // Adjust selection badge position (iOS style: 60dp below safe area)
            val badgeParams = editorSelectionBadge.layoutParams as FrameLayout.LayoutParams
            badgeParams.topMargin = bars.top + (60 * resources.displayMetrics.density).toInt()
            editorSelectionBadge.layoutParams = badgeParams

            insets
        }
    }

    // ─────────────────────────────────────────────
    // ViewPager2
    // ─────────────────────────────────────────────

    private fun setupViewPager() {
        val adapter = EditorPagerAdapter(this, uris)
        viewPager.adapter = adapter
        // offscreenPageLimit = 1: preload 1 page each side (balanced memory vs. smoothness)
        viewPager.offscreenPageLimit = 1
        viewPager.setCurrentItem(currentIndex, false)
        if (singlePhotoMode) {
            viewPager.isUserInputEnabled = false
        }

        viewPager.registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
            override fun onPageSelected(position: Int) {
                saveStickersForCurrentIndex()
                currentIndex = position
                updateCounter()
                updateSelectionBadge()
                // Sync thumbnail bar
                if (::thumbnailAdapter.isInitialized) {
                    thumbnailAdapter.setSelectedIndex(position)
                    thumbnailRecyclerView?.smoothScrollToPosition(position)
                }
                uris.getOrNull(position)?.toString()?.let { uriStr ->
                    TransitionHelper.onPageChanged?.invoke(uriStr)
                }
            }
            override fun onPageScrollStateChanged(state: Int) {
                if (state == androidx.viewpager2.widget.ViewPager2.SCROLL_STATE_DRAGGING) {
                    if (animationDone && !imageLoaded) {
                        imageLoaded = true
                        checkAndHideOverlay()
                    }
                }
            }
        })

        // Disable over-scroll glow
        (viewPager.getChildAt(0) as? RecyclerView)?.overScrollMode = RecyclerView.OVER_SCROLL_NEVER
    }

    private fun setupThumbnailBar() {
        if (uris.size <= 1) {
            thumbnailRecyclerView?.visibility = View.GONE
            return
        }

        thumbnailRecyclerView?.visibility = View.VISIBLE
        thumbnailRecyclerView?.layoutManager = androidx.recyclerview.widget.LinearLayoutManager(this, RecyclerView.HORIZONTAL, false)
        thumbnailAdapter = EditorThumbnailAdapter(uris) { position ->
            viewPager.currentItem = position
        }
        thumbnailAdapter.setSelectedIndex(currentIndex)
        thumbnailRecyclerView?.adapter = thumbnailAdapter
        thumbnailRecyclerView?.scrollToPosition(currentIndex)
    }

    // ─────────────────────────────────────────────
    // Buttons & Back
    // ─────────────────────────────────────────────

    private fun resetFilterButton() {
        isFilterActive = false
        filterContainerView.visibility = View.GONE
        effectModeBottomBar.visibility = View.GONE
        editorBottomBar.visibility = View.VISIBLE
        topBarOverlay.visibility = View.VISIBLE
        toolEffect.alpha = 1.0f
        toolEffect.clearColorFilter()
        toolEffect.animate().scaleX(1.0f).scaleY(1.0f).setDuration(200).start()
        if (uris.size > 1) {
            thumbnailRecyclerView?.visibility = View.VISIBLE
        }
    }

    private fun closeEffectMode() {
        isFilterActive = false
        filterContainerView.visibility = View.GONE
        effectModeBottomBar.visibility = View.GONE
        editorBottomBar.visibility = View.VISIBLE
        topBarOverlay.visibility = View.VISIBLE
        toolEffect.clearColorFilter()
        toolEffect.animate().scaleX(1.0f).scaleY(1.0f).setDuration(200).start()
        updateSelectionBadge()
        if (uris.size > 1) {
            thumbnailRecyclerView?.visibility = View.VISIBLE
        }
    }

    private fun setupButtons() {
        backButton.setOnClickListener { finish() }
        sendButton.setOnClickListener { onSendTapped() }
        editorSelectionBadge.setOnClickListener { toggleSelection() }
        
        toolEffect.setOnClickListener {
            if (isFilterActive) return@setOnClickListener
            setPullToDismissEnabled(false)
            isFilterActive = true
            backupFilterState = filterStates[currentIndex]?.copy() ?: FilterState()
            
            filterContainerView.visibility = View.VISIBLE
            editorBottomBar.visibility = View.GONE
            effectModeBottomBar.visibility = View.VISIBLE
            topBarOverlay.visibility = View.GONE
            thumbnailRecyclerView?.visibility = View.GONE
            updateSelectionBadge()
            
            toolEffect.setColorFilter(parsedThemeColor, android.graphics.PorterDuff.Mode.SRC_IN)
            toolEffect.animate().scaleX(1.2f).scaleY(1.2f).setDuration(200).start()
            
            autoSelectCurrentPhoto()
            generateThumbnailsForCurrent()
            val state = filterStates[currentIndex] ?: FilterState()
            intensitySlider.progress = (state.intensity * 100).toInt()
            sliderBackgroundView.visibility = if (state.filterId == "original") View.GONE else View.VISIBLE
        }
        
        toolCrop.setOnClickListener {
            setPullToDismissEnabled(false)
            autoSelectCurrentPhoto()
            resetFilterButton()
            bakeCurrentModifications { uri ->
                val intent = Intent(this, CropActivity::class.java)
                intent.putExtra(CropActivity.EXTRA_SOURCE_URI, uri.toString())
                intent.putExtra(CropActivity.EXTRA_THEME_COLOR, this@ImageEditorActivity.intent.getStringExtra(ImageEditorActivity.EXTRA_THEME_COLOR))
                cropLauncher.launch(intent)
            }
        }

        toolEmoji.setOnClickListener {
            autoSelectCurrentPhoto()
            resetFilterButton()
            openEmojiPicker()
        }

        toolText.setOnClickListener {
            autoSelectCurrentPhoto()
            resetFilterButton()
            beginTextMode()
            // Always open text input when entering Text Mode
            openTextInput()
        }

        toolDrawing.setOnClickListener {
            setPullToDismissEnabled(false)
            autoSelectCurrentPhoto()
            resetFilterButton()
            bakeCurrentModifications { uri ->
                val intent = DrawingActivity.createIntent(this, uri,
                    intent.getStringExtra(EXTRA_THEME_COLOR))
                drawingLauncher.launch(intent)
            }
        }

        textModeCancelButton.setOnClickListener { textCancelTapped() }
        textModeConfirmButton.setOnClickListener { textConfirmTapped() }
        textModeDeleteAllButton.setOnClickListener { textTrashTapped() }
        textModeAddButton.setOnClickListener {
            deselectAllStickers()
            openTextInput()
        }
        
        effectModeCancelButton.setOnClickListener {
            backupFilterState?.let { backup ->
                filterStates[currentIndex] = backup.copy()
                val fragment = currentFragment
                fragment?.applyFilter(backup)
                filterAdapter.updateSelection(backup)
                intensitySlider.progress = (backup.intensity * 100).toInt()
                sliderBackgroundView.visibility = if (backup.filterId == "original") View.GONE else View.VISIBLE
            }
            closeEffectMode()
            setPullToDismissEnabled(true)
        }

        effectModeConfirmButton.setOnClickListener {
            closeEffectMode()
            setPullToDismissEnabled(true)
            bakeCurrentModifications {
                if (uris.size > 1) {
                    thumbnailAdapter.notifyItemChanged(currentIndex)
                }
            }
        }

        intensitySlider.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) {
                    val state = filterStates[currentIndex] ?: FilterState()
                    state.intensity = progress / 100f
                    filterStates[currentIndex] = state
                    filterAdapter.updateSelection(state)
                    
                    val fragment = currentFragment
                    fragment?.applyFilter(state)
                }
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {
                autoSelectCurrentPhoto()
            }
        })

        filterAdapter = FilterThumbnailAdapter(FilterManager.instance.getFilters(this), parsedThemeColor) { filter, _ ->
            val state = filterStates[currentIndex] ?: FilterState()
            state.filterId = filter.id
            state.intensity = 1.0f
            filterStates[currentIndex] = state
            
            intensitySlider.progress = 100
            sliderBackgroundView.visibility = if (filter.id == "original") View.GONE else View.VISIBLE
            filterAdapter.updateSelection(state)
            
            val fragment = currentFragment
            fragment?.applyFilter(state)
            autoSelectCurrentPhoto()
        }
        filterRecyclerView.layoutManager = androidx.recyclerview.widget.LinearLayoutManager(this, RecyclerView.HORIZONTAL, false)
        filterRecyclerView.adapter = filterAdapter
        
        // Apply theme color to slider progress
        intensitySlider.progressTintList = android.content.res.ColorStateList.valueOf(parsedThemeColor)
        
        // Apply theme color to slider background dots
        val sliderContainer = sliderBackgroundView as? ViewGroup
        if (sliderContainer != null && sliderContainer.childCount > 0) {
            val linearLayout = sliderContainer.getChildAt(0) as? ViewGroup
            if (linearLayout != null) {
                for (i in 0 until linearLayout.childCount) {
                    val child = linearLayout.getChildAt(i)
                    if (child.layoutParams.width == (2 * resources.displayMetrics.density).toInt() || child.layoutParams.width == 2) {
                        child.setBackgroundColor(parsedThemeColor)
                    } else if (i % 2 == 1) {
                        // Fallback: the dots are at indices 1, 3, 5
                        child.setBackgroundColor(parsedThemeColor)
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────
    // Text Mode Actions
    // ─────────────────────────────────────────────

    private fun beginTextMode() {
        if (!isTextModeActive) {
            setPullToDismissEnabled(false)
            isTextModeActive = true
            isFilterActive = false
            filterContainerView.visibility = View.GONE
            topBarOverlay.visibility = View.GONE
            editorBottomBar.visibility = View.GONE
            textModeTopBar.visibility = View.VISIBLE
            textModeBottomBar.visibility = View.VISIBLE
            thumbnailRecyclerView?.visibility = View.GONE
            updateSelectionBadge()

            // snapshot state
            preTextModeStickerStates.clear()
            preTextModeStickerList.clear()
            val fragment = currentFragment
            fragment?.stickerContainer?.let { container ->
                for (i in 0 until container.childCount) {
                    val view = container.getChildAt(i)
                    if (view is TextStickerView) {
                        preTextModeStickerList.add(view)
                        preTextModeStickerStates[view] = StickerState(
                            view.text, view.textColor, view.intrinsicScaleX, view.intrinsicScaleY, view.rotation, view.translationX, view.translationY, view.isEmojiSticker
                        )
                    }
                }
            }
            viewPager.isUserInputEnabled = false
            setAllStickersEditingMode(true)
        }
    }

    private fun endTextMode() {
        preTextModeStickerStates.clear()
        preTextModeStickerList.clear()
        deselectAllStickers()
        isTextModeActive = false
        topBarOverlay.visibility = View.VISIBLE
        editorBottomBar.visibility = View.VISIBLE
        textModeTopBar.visibility = View.GONE
        textModeBottomBar.visibility = View.GONE
        if (uris.size > 1) {
            thumbnailRecyclerView?.visibility = View.VISIBLE
        }
        viewPager.isUserInputEnabled = !singlePhotoMode
        updateSelectionBadge()
        setAllStickersEditingMode(false)
    }

    private fun textCancelTapped() {
        val fragment = currentFragment
        fragment?.stickerContainer?.let { container ->
            val toRemove = mutableListOf<View>()
            for (i in 0 until container.childCount) {
                val view = container.getChildAt(i)
                if (view is TextStickerView) {
                    val state = preTextModeStickerStates[view]
                    if (state != null) {
                        view.text = state.text
                        view.textColor = state.textColor
                        view.intrinsicScaleX = state.scaleX
                        view.intrinsicScaleY = state.scaleY
                        view.rotation = state.rotation
                        view.translationX = state.transX
                        view.translationY = state.transY
                        view.isEmojiSticker = state.isEmojiSticker
                        view.scaleX = state.scaleX
                        view.scaleY = state.scaleY
                        view.requestLayout()
                    } else {
                        toRemove.add(view)
                    }
                }
            }
            toRemove.forEach { container.removeView(it) }

            preTextModeStickerList.forEach { sticker ->
                if (sticker.parent == null) {
                    container.addView(sticker)
                    val state = preTextModeStickerStates[sticker]
                    if (state != null) {
                        sticker.text = state.text
                        sticker.textColor = state.textColor
                        sticker.scaleX = state.scaleX
                        sticker.scaleY = state.scaleY
                        sticker.rotation = state.rotation
                        sticker.translationX = state.transX
                        sticker.translationY = state.transY
                        sticker.requestLayout()
                    }
                }
            }
        }
        endTextMode()
        setPullToDismissEnabled(true)
    }

    private fun textConfirmTapped() {
        endTextMode()
        setPullToDismissEnabled(true)
        bakeCurrentModifications {
            if (uris.size > 1) {
                thumbnailAdapter.notifyItemChanged(currentIndex)
            }
        }
        currentFragment?.resetZoomWithAnimation()
        autoSelectCurrentPhoto()
    }

    private fun textTrashTapped() {
        val fragment = currentFragment
        fragment?.stickerContainer?.removeAllViews()
    }

    private fun deselectAllStickers() {
        currentFragment?.stickerContainer?.let { container ->
            for (i in 0 until container.childCount) {
                val view = container.getChildAt(i)
                if (view is TextStickerView) {
                    view.isActive = false
                }
            }
        }
    }

    fun saveStickersForCurrentIndex() {
        val fragment = currentFragment ?: return
        val container = fragment.stickerContainer ?: return
        val list = mutableListOf<StickerState>()
        for (i in 0 until container.childCount) {
            val view = container.getChildAt(i) as? TextStickerView ?: continue
            list.add(StickerState(
                view.text, view.textColor, view.intrinsicScaleX, view.intrinsicScaleY, view.rotation, view.translationX, view.translationY, view.isEmojiSticker
            ))
        }
        if (list.isEmpty()) {
            stickersByIndex.remove(currentIndex)
        } else {
            stickersByIndex[currentIndex] = list
        }
    }

    fun setAllStickersEditingMode(editing: Boolean) {
        val fragment = currentFragment ?: return
        val container = fragment.stickerContainer ?: return
        for (i in 0 until container.childCount) {
            val view = container.getChildAt(i) as? TextStickerView ?: continue
            view.isEditingMode = editing
        }
    }

    private fun openEmojiPicker() {
        if (isTextModeActive || isEmojiModeActive || isFilterActive) return
        setPullToDismissEnabled(false)
        beginEmojiMode()
        emojiPicker.showGrid(true)
        emojiPicker.visibility = View.VISIBLE
        emojiPicker.alpha = 0f
        emojiPicker.animate().alpha(1f).setDuration(200).start()
    }

    private fun beginEmojiMode() {
        isEmojiModeActive = true
        // Hide standard UI elements
        backButton.visibility = View.GONE
        counterLabel.visibility = View.GONE
        sendButton.visibility = View.GONE
        editorBottomBar.visibility = View.GONE
        filterContainerView.visibility = View.GONE
        updateSelectionBadge()
        thumbnailRecyclerView?.visibility = View.GONE
        
        saveEmojiStickerStates()
        setAllStickersEditingMode(true)
        
        viewPager.isUserInputEnabled = false
        
        val fragment = currentFragment
    }

    private fun cancelEmojiMode() {
        restoreEmojiStickerStates()
        endEmojiMode()
        setPullToDismissEnabled(true)
    }

    private fun confirmEmojiMode() {
        saveStickersForCurrentIndex()
        endEmojiMode()
        setPullToDismissEnabled(true)
        currentFragment?.resetZoomWithAnimation()
        autoSelectCurrentPhoto()
        bakeCurrentModifications {
            if (uris.size > 1) {
                thumbnailAdapter.notifyItemChanged(currentIndex)
            }
        }
    }

    private fun endEmojiMode() {
        isEmojiModeActive = false
        emojiPicker.animate().alpha(0f).setDuration(200).withEndAction {
            emojiPicker.visibility = View.GONE
        }.start()
        
        deselectAllStickers()
        setAllStickersEditingMode(false)
        
        // Show standard UI elements
        backButton.visibility = View.VISIBLE
        counterLabel.visibility = if (singlePhotoMode) View.GONE else View.VISIBLE
        sendButton.visibility = View.VISIBLE
        editorBottomBar.visibility = View.VISIBLE
        viewPager.isUserInputEnabled = !singlePhotoMode
        if (uris.size > 1) {
            thumbnailRecyclerView?.visibility = View.VISIBLE
        }
        updateSelectionBadge()
    }

    private fun saveEmojiStickerStates() {
        preEmojiModeStickerStates.clear()
        preEmojiModeStickerList.clear()
        val fragment = currentFragment ?: return
        val container = fragment.stickerContainer ?: return
        for (i in 0 until container.childCount) {
            val view = container.getChildAt(i) as? TextStickerView ?: continue
            preEmojiModeStickerList.add(view)
            preEmojiModeStickerStates[view] = StickerState(
                view.text, view.textColor, view.intrinsicScaleX, view.intrinsicScaleY, view.rotation, view.translationX, view.translationY, view.isEmojiSticker
            )
        }
    }

    private fun restoreEmojiStickerStates() {
        val fragment = currentFragment ?: return
        val container = fragment.stickerContainer ?: return
        
        // Remove stickers added during emoji mode
        for (i in container.childCount - 1 downTo 0) {
            val view = container.getChildAt(i) as? TextStickerView ?: continue
            if (!preEmojiModeStickerList.contains(view)) {
                container.removeView(view)
            }
        }
        
        // Restore properties
        for ((view, state) in preEmojiModeStickerStates) {
            view.text = state.text
            view.textColor = state.textColor
            view.intrinsicScaleX = state.scaleX
            view.intrinsicScaleY = state.scaleY
            view.rotation = state.rotation
            view.translationX = state.transX
            view.translationY = state.transY
            view.isEmojiSticker = state.isEmojiSticker
            view.scaleX = state.scaleX
            view.scaleY = state.scaleY
            view.isActive = false
        }
        saveStickersForCurrentIndex()
    }

    // MARK: - Shared Helpers

    /** Returns the currently visible EditorPageFragment, if any. */
    private val currentFragment: EditorPageFragment?
        get() = supportFragmentManager.fragments.firstOrNull { 
            it is EditorPageFragment && it.pageIndex == currentIndex
        } as? EditorPageFragment

    /**
     * Bakes stickers into the image and saves to a JPEG cache file.
     * Returns the Uri of the baked file, or null if there are no stickers.
     */
    private fun bakeStickersToCacheFile(): Uri? {
        val fragment = currentFragment ?: return null
        val bitmap = fragment.bakeStickersToImageAndGetBitmap() ?: return null
        val file = java.io.File(cacheDir, "baked_${System.currentTimeMillis()}.jpg")
        java.io.FileOutputStream(file).use { out ->
            bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 95, out)
        }
        return Uri.fromFile(file)
    }

    private fun openTextInput(initialText: String = "", stickerToEdit: TextStickerView? = null) {
        val dialog = TextInputDialog.newInstance(initialText, stickerToEdit?.textColor ?: android.graphics.Color.WHITE)
        dialog.onConfirmListener = { text, color ->
            beginTextMode()
            val fragment = currentFragment
            fragment?.stickerContainer?.let { container ->
                if (stickerToEdit != null) {
                    stickerToEdit.text = text
                    stickerToEdit.textColor = color
                    stickerToEdit.isActive = true
                } else {
                    val newSticker = TextStickerView(this)
                    newSticker.text = text
                    newSticker.textColor = color
                    newSticker.listener = this
                    newSticker.isActive = true
                    newSticker.isEditingMode = true
                    container.addView(newSticker, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
                        gravity = android.view.Gravity.CENTER
                    })
                }
            }
        }
        dialog.onCancelListener = {
            val fragment = currentFragment
            val count = fragment?.stickerContainer?.childCount ?: 0
            if (count == 0) {
                endTextMode()
            }
        }
        dialog.show(supportFragmentManager, "TextInputDialog")
    }

    override fun onEditRequest(sticker: TextStickerView) {
        if (!isTextModeActive) return
        openTextInput(sticker.text, sticker)
    }

    override fun onDeleteRequest(sticker: TextStickerView) {
        (sticker.parent as? ViewGroup)?.removeView(sticker)
        updateSendButtonState()
    }

    override fun onStickerSelected(sticker: TextStickerView) {
        if (sticker.isEmojiSticker && !isEmojiModeActive) {
            return
        }
        if (!sticker.isEmojiSticker && !isTextModeActive) {
            return
        }
        deselectAllStickers()
        sticker.isActive = true
    }

    private fun createStickerOverlayBitmap(stickers: List<StickerState>?, containerWidth: Int, containerHeight: Int): Bitmap? {
        if (stickers.isNullOrEmpty() || containerWidth <= 0 || containerHeight <= 0) return null
        
        val stickerOverlay = android.graphics.Bitmap.createBitmap(containerWidth, containerHeight, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(stickerOverlay)
        
        val container = FrameLayout(this)
        container.layoutParams = ViewGroup.LayoutParams(containerWidth, containerHeight)
        container.measure(View.MeasureSpec.makeMeasureSpec(containerWidth, View.MeasureSpec.EXACTLY),
                          View.MeasureSpec.makeMeasureSpec(containerHeight, View.MeasureSpec.EXACTLY))
        container.layout(0, 0, containerWidth, containerHeight)
        
        for (state in stickers) {
            val sticker = TextStickerView(this)
            sticker.text = state.text
            sticker.textColor = state.textColor
            sticker.scaleX = state.scaleX
            sticker.scaleY = state.scaleY
            sticker.rotation = state.rotation
            sticker.translationX = state.transX
            sticker.translationY = state.transY
            sticker.isEmojiSticker = state.isEmojiSticker
            sticker.isActive = false
            sticker.isEditingMode = false
            container.addView(sticker, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
                gravity = android.view.Gravity.CENTER
            })
        }
        
        container.measure(View.MeasureSpec.makeMeasureSpec(containerWidth, View.MeasureSpec.EXACTLY),
                          View.MeasureSpec.makeMeasureSpec(containerHeight, View.MeasureSpec.EXACTLY))
        container.layout(0, 0, containerWidth, containerHeight)
        
        container.draw(canvas)
        return stickerOverlay
    }

    private fun processImageWithOverlays(
        uri: Uri,
        index: Int,
        state: FilterState?,
        stickerBmp: Bitmap?,
        inMemoryBmp: Bitmap?,
        containerWidth: Int,
        containerHeight: Int,
        filePrefix: String,
        keepResultBmp: Boolean = false
    ): Pair<Uri, Bitmap?> {
        android.util.Log.e("TurboImageEditor", "processImageWithOverlays START index=$index, inMemoryBmp=${inMemoryBmp != null}")
        val startTime = System.currentTimeMillis()
        if ((state == null || state.filterId == "original") && stickerBmp == null) {
            if (keepResultBmp) {
                val loadedBmp = inMemoryBmp ?: run {
                    val overrideWidth = if (this@ImageEditorActivity.maxWidth > 0) this@ImageEditorActivity.maxWidth else 2048
                    val overrideHeight = if (this@ImageEditorActivity.maxHeight > 0) this@ImageEditorActivity.maxHeight else 2048
                    Glide.with(this@ImageEditorActivity)
                        .asBitmap()
                        .load(uri)
                        .override(overrideWidth, overrideHeight)
                        .submit()
                        .get()
                }
                val safeBmp = loadedBmp?.copy(loadedBmp.config ?: android.graphics.Bitmap.Config.ARGB_8888, false)
                return Pair(uri, safeBmp)
            }
            return Pair(uri, null)
        }

        var future: com.bumptech.glide.request.FutureTarget<Bitmap>? = null
        val baseBmp = inMemoryBmp ?: run {
            android.util.Log.e("TurboImageEditor", "Falling back to Glide load!")
            val loadStart = System.currentTimeMillis()
            val overrideWidth = if (this@ImageEditorActivity.maxWidth > 0) this@ImageEditorActivity.maxWidth else 2048
            val overrideHeight = if (this@ImageEditorActivity.maxHeight > 0) this@ImageEditorActivity.maxHeight else 2048
            
            future = Glide.with(this@ImageEditorActivity)
                .asBitmap()
                .load(uri)
                .override(overrideWidth, overrideHeight)
                .submit()
            val result = future?.get()
            android.util.Log.e("TurboImageEditor", "Glide load took ${System.currentTimeMillis() - loadStart}ms")
            result
        } ?: return Pair(uri, null)
        
        val drawStart = System.currentTimeMillis()

        val resultBmp = android.graphics.Bitmap.createBitmap(baseBmp.width, baseBmp.height, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(resultBmp)
        val paint = android.graphics.Paint()
        
        if (state != null && state.filterId != "original") {
            val filter = FilterManager.instance.getFilters(this).firstOrNull { it.id == state.filterId }
            if (filter != null) {
                paint.colorFilter = android.graphics.ColorMatrixColorFilter(filter.apply(state.intensity))
            }
        }
        canvas.drawBitmap(baseBmp, 0f, 0f, paint)

        if (stickerBmp != null) {
            val imageRect = android.graphics.RectF(0f, 0f, baseBmp.width.toFloat(), baseBmp.height.toFloat())
            val viewRect = android.graphics.RectF(0f, 0f, containerWidth.toFloat(), containerHeight.toFloat())
            val matrix = android.graphics.Matrix()
            matrix.setRectToRect(imageRect, viewRect, android.graphics.Matrix.ScaleToFit.CENTER)
            
            val invMatrix = android.graphics.Matrix()
            if (matrix.invert(invMatrix)) {
                canvas.concat(invMatrix)
                canvas.drawBitmap(stickerBmp, 0f, 0f, null)
            }
        }

        val ext = contentResolver.getType(uri)?.let { mime ->
            android.webkit.MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)
        } ?: "jpg"
        val file = java.io.File(cacheDir, "${filePrefix}_${System.currentTimeMillis()}_$index.$ext")
        val out = java.io.FileOutputStream(file)
        val format = if (ext.equals("png", true)) android.graphics.Bitmap.CompressFormat.PNG else android.graphics.Bitmap.CompressFormat.JPEG
        
        android.util.Log.e("TurboImageEditor", "Drawing took ${System.currentTimeMillis() - drawStart}ms")
        val saveStart = System.currentTimeMillis()
        
        resultBmp.compress(format, 95, out)
        out.close()

        val finalReturnedBmp = if (keepResultBmp) resultBmp else null
        if (!keepResultBmp && resultBmp != baseBmp) resultBmp.recycle()
        future?.let { Glide.with(this@ImageEditorActivity).clear(it) }
        
        android.util.Log.e("TurboImageEditor", "Save took ${System.currentTimeMillis() - saveStart}ms. Total: ${System.currentTimeMillis() - startTime}ms")
        return Pair(Uri.fromFile(file), finalReturnedBmp)
    }

    private fun onSendTapped() {
        android.util.Log.e("TurboImageEditor", "onSendTapped START")
        val sendStart = System.currentTimeMillis()
        
        if (currentIndex < 0 || currentIndex >= uris.size) return

        // Save current page's stickers to states
        saveStickersForCurrentIndex()

        val containerWidth = viewPager.width
        val containerHeight = viewPager.height

        val targetIndices = if (singlePhotoMode || uris.size <= 1) {
            listOf(currentIndex)
        } else if (selectedUris.isEmpty()) {
            listOf(currentIndex)
        } else {
            selectedUris.map { originalUris.indexOf(it) }.filter { it != -1 }
        }

        val stickerBmps = mutableMapOf<Int, Bitmap>()
        val inMemoryBmps = mutableMapOf<Int, Bitmap>()
        for (index in targetIndices) {
            val stickers = stickersByIndex[index]
            val state = filterStates[index]
            
            val hasStickers = !stickers.isNullOrEmpty()
            val hasFilter = state != null && state.filterId != "original"
            
            if (!hasStickers && !hasFilter) {
                // Skip expensive UI thread prep for unedited images
                continue
            }

            val overlay = createStickerOverlayBitmap(stickers, containerWidth, containerHeight)
            if (overlay != null) {
                stickerBmps[index] = overlay
            }
            
            val fragment = supportFragmentManager.fragments.firstOrNull { 
                it is EditorPageFragment && it.arguments?.getInt("arg_index") == index 
            } as? EditorPageFragment
            val iv = fragment?.imageView
            val drawable = iv?.drawable
            val bmp = (drawable as? android.graphics.drawable.BitmapDrawable)?.bitmap
            
            if (bmp != null) {
                inMemoryBmps[index] = bmp
            }
        }
        
        android.util.Log.e("TurboImageEditor", "UI Thread Prep took ${System.currentTimeMillis() - sendStart}ms")

        executorService.execute {
            try {
                val resultList = ArrayList<String>()
                val originalList = ArrayList<String>()

                // Process all target URIs
                for (index in targetIndices) {
                    val currentUri = uris[index]
                    val originalUri = originalUris[index]
                    
                    val resultPair = processImageWithOverlays(
                        currentUri,
                        index,
                        filterStates[index],
                        stickerBmp = stickerBmps[index],
                        inMemoryBmp = inMemoryBmps[index],
                        containerWidth = containerWidth,
                        containerHeight = containerHeight,
                        filePrefix = "edited",
                        keepResultBmp = (index == currentIndex)
                    )
                    
                    val resultUri = resultPair.first
                    if (index == currentIndex && resultPair.second != null) {
                        TransitionHelper.editedBitmap = resultPair.second
                    }
                    
                    if (resultUri != currentUri) {
                        uris[index] = resultUri
                    }
                    resultList.add(resultUri.toString())
                    originalList.add(originalUri.toString())
                }

                // Determine the single result URI (for legacy support / current focus)
                val finalCurrentUriStr = if (targetIndices.contains(currentIndex)) {
                    val idx = targetIndices.indexOf(currentIndex)
                    if (idx != -1 && idx < resultList.size) resultList[idx] else uris[currentIndex].toString()
                } else {
                    uris[currentIndex].toString()
                }

                runOnUiThread {
                    isApplying = true
                    setResult(Activity.RESULT_OK, Intent().apply {
                        putExtra(EXTRA_RESULT_URI, finalCurrentUriStr)
                        putStringArrayListExtra(EXTRA_RESULT_URIS, resultList)
                        putStringArrayListExtra(EXTRA_ORIGINAL_URIS, originalList)
                        putStringArrayListExtra(EXTRA_RESULT_SELECTED_URIS, ArrayList(selectedUris.map { it.toString() }))
                    })
                    android.util.Log.e("TurboImageEditor", "Calling finish() on main thread")
                    finish()
                }
            } catch (e: Exception) {
                android.util.Log.e("TurboImageEditor", "Executor Error", e)
                e.printStackTrace()
                runOnUiThread { finish() }
            }
        }
    }

    private fun bakeCurrentModifications(onComplete: (Uri) -> Unit) {
        // Save current UI state of stickers to the state map
        saveStickersForCurrentIndex()

        val index = currentIndex
        val uri = uris.getOrNull(index) ?: return
        val state = filterStates[index]
        val stickers = stickersByIndex[index]

        // If nothing to bake, return immediately with current URI
        if ((state == null || state.filterId == "original") && stickers.isNullOrEmpty()) {
            onComplete(uri)
            return
        }

        val containerWidth = viewPager.width
        val containerHeight = viewPager.height

        val stickerBmp = createStickerOverlayBitmap(stickers, containerWidth, containerHeight)
        
        val fragment = supportFragmentManager.fragments.firstOrNull { 
            it is EditorPageFragment && it.arguments?.getInt("arg_index") == index 
        } as? EditorPageFragment
        val iv = fragment?.imageView
        val drawable = iv?.drawable
        val bmp = (drawable as? android.graphics.drawable.BitmapDrawable)?.bitmap

        executorService.execute {
            try {
                val resultPair = processImageWithOverlays(
                    uri,
                    index,
                    state,
                    stickerBmp,
                    bmp,
                    containerWidth,
                    containerHeight,
                    "baked"
                )
                val finalUri = resultPair.first
                
                stickerBmp?.recycle()

                runOnUiThread {
                    if (finalUri != uri) {
                        replaceUri(index, finalUri)
                        stickersByIndex.remove(index)
                        filterStates.remove(index)
                        
                        val bakedFragment = supportFragmentManager.findFragmentByTag("f$index") as? EditorPageFragment
                        if (bakedFragment != null) {
                            bakedFragment.reloadImage(finalUri) {
                                bakedFragment.removeAllStickersAndFilter()
                            }
                        }
                        
                        if (index == currentIndex) {
                            filterAdapter.updateSelection(FilterState())
                            generateThumbnailsForCurrent()
                            intensitySlider.progress = 50
                            sliderBackgroundView.visibility = View.GONE
                        }
                    }
                    onComplete(finalUri)
                }
            } catch (e: Exception) {
                e.printStackTrace()
                runOnUiThread {
                    onComplete(uri)
                }
            }
        }
    }

    private fun updateSelectionBadge() {
        if (singlePhotoMode || uris.size <= 1 || isFilterActive || isTextModeActive || isEmojiModeActive) {
            editorSelectionBadge.visibility = View.GONE
            return
        }
        editorSelectionBadge.visibility = View.VISIBLE
        val currentOriginalUri = originalUris[currentIndex]
        val isSelected = selectedUris.contains(currentOriginalUri)

        if (parsedThemeColor != null) {
            val bg = editorSelectionNumber.background as? android.graphics.drawable.GradientDrawable
            bg?.setColor(parsedThemeColor!!)
            // Border is now circle_border_white_thin, keep it white as requested
        }

        if (isSelected) {
            editorSelectionBorder.visibility = View.GONE
            editorSelectionNumber.visibility = View.VISIBLE
            val index = selectedUris.toList().indexOf(currentOriginalUri) + 1
            editorSelectionNumber.text = index.toString()
        } else {
            editorSelectionBorder.visibility = View.VISIBLE
            editorSelectionNumber.visibility = View.GONE
        }
    }

    private fun toggleSelection() {
        if (uris.size <= 1) return
        val currentOriginalUri = originalUris[currentIndex]
        
        val hasFilter = filterStates.containsKey(currentIndex)
        val hasStickers = stickersByIndex.containsKey(currentIndex) && stickersByIndex[currentIndex]!!.isNotEmpty()
        val isCropped = uris[currentIndex] != originalUris[currentIndex]
        val isEdited = hasFilter || hasStickers || isCropped
        
        if (selectedUris.contains(currentOriginalUri)) {
            if (isEdited) {
                android.app.AlertDialog.Builder(this)
                    .setMessage(R.string.delete_edits_message)
                    .setPositiveButton(R.string.yes) { _, _ ->
                        // Revert edits
                        filterStates.remove(currentIndex)
                        stickersByIndex.remove(currentIndex)
                        val origUri = originalUris[currentIndex]
                        
                        if (uris[currentIndex] != origUri) {
                            replaceUri(currentIndex, origUri)
                        }
                        
                        currentFragment?.reloadImage(origUri) {
                            currentFragment?.removeAllStickersAndFilter()
                        }
                        
                        selectedUris.remove(currentOriginalUri)
                        updateSelectionBadge()
                        thumbnailAdapter.notifyItemChanged(currentIndex)
                    }
                    .setNegativeButton(R.string.no, null)
                    .show()
                return
            } else {
                selectedUris.remove(currentOriginalUri)
            }
        } else {
            selectedUris.add(currentOriginalUri)
        }
        updateSelectionBadge()
    }

    private fun autoSelectCurrentPhoto() {
        if (uris.size > 1) {
            val currentOriginalUri = originalUris[currentIndex]
            if (!selectedUris.contains(currentOriginalUri)) {
                selectedUris.add(currentOriginalUri)
                updateSelectionBadge()
            }
        }
        updateSendButtonState()
    }

    fun updateSendButtonState() {
        if (singlePhotoMode) {
            sendButton.visibility = View.VISIBLE
            sendButton.setText(R.string.turbo_send)
            return
        }

        var hasAnyEdits = false
        if (filterStates.isNotEmpty()) hasAnyEdits = true
        if (!hasAnyEdits && stickersByIndex.values.any { it.isNotEmpty() }) hasAnyEdits = true
        if (!hasAnyEdits && uris.indices.any { uris[it] != originalUris[it] }) hasAnyEdits = true
        if (!hasAnyEdits) {
            for (i in 0 until (viewPager.adapter?.itemCount ?: 0)) {
                val frag = supportFragmentManager.findFragmentByTag("f$i") as? EditorPageFragment
                if ((frag?.stickerContainer?.childCount ?: 0) > 0) {
                    hasAnyEdits = true
                    break
                }
            }
        }

        if (hasAnyEdits) {
            sendButton.visibility = View.VISIBLE
            sendButton.setText(R.string.editor_apply)
        } else {
            sendButton.visibility = View.GONE
        }
    }

    // ─────────────────────────────────────────────
    // Counter
    // ─────────────────────────────────────────────

    private fun updateCounter() {
        if (singlePhotoMode) {
            counterLabel.visibility = View.GONE
            return
        }
        counterLabel.visibility = View.VISIBLE
        counterLabel.text = "${currentIndex + 1} / ${uris.size}"
        if (isFilterActive) {
            val state = filterStates[currentIndex] ?: FilterState()
            filterAdapter.updateSelection(state)
            intensitySlider.progress = (state.intensity * 100).toInt()
            sliderBackgroundView.visibility = if (state.filterId == "original") View.GONE else View.VISIBLE
            generateThumbnailsForCurrent()
        }
    }

    private fun generateThumbnailsForCurrent() {
        if (currentIndex < 0 || currentIndex >= uris.size) return
        val uri = uris[currentIndex]
        
        thumbnailTarget?.let { Glide.with(this).clear(it) }
        
        val target = object : CustomTarget<Bitmap>() {
            override fun onResourceReady(resource: Bitmap, transition: Transition<in Bitmap>?) {
                filterAdapter.updateOriginalThumbnail(resource)
                
                executorService.execute {
                    val map = mutableMapOf<String, Bitmap>()
                    for (filter in FilterManager.instance.getFilters(applicationContext)) {
                        if (filter.id == "original") continue
                        val bmp = Bitmap.createBitmap(resource.width, resource.height, Bitmap.Config.ARGB_8888)
                        val canvas = android.graphics.Canvas(bmp)
                        val paint = android.graphics.Paint()
                        paint.colorFilter = android.graphics.ColorMatrixColorFilter(filter.apply(1.0f))
                        canvas.drawBitmap(resource, 0f, 0f, paint)
                        map[filter.id] = bmp
                    }
                    runOnUiThread {
                        filterAdapter.setThumbnails(map)
                    }
                }
            }
            override fun onLoadCleared(placeholder: android.graphics.drawable.Drawable?) {}
        }
        thumbnailTarget = target
        Glide.with(this)
            .asBitmap()
            .load(uri)
            .override(150, 150)
            .centerCrop()
            .into(target)
    }

    private fun replaceUri(index: Int, newUri: Uri) {
        uris[index] = newUri
    }

    var imageLoaded = false
    var animationDone = false
    private var initialUriStr: String? = null

    fun hideTransitionOverlay(loadedUri: android.net.Uri? = null) {
        if (loadedUri != null && initialUriStr != null) {
            if (loadedUri.toString() != initialUriStr) {
                // Ignore if it's not the initial animated image
                return
            }
        }
        imageLoaded = true
        checkAndHideOverlay()
    }

    private fun checkAndHideOverlay() {
        val rootView = findViewById<android.view.ViewGroup>(android.R.id.content)
        val pullToDismissLayout = findViewById<android.view.View>(R.id.pullToDismissLayout)
        val topBarOverlay = findViewById<android.view.View>(R.id.topBarOverlay)
        val editorBottomBar = findViewById<android.view.View>(R.id.editorBottomBar)
        val overlayImage = rootView.findViewWithTag<android.view.View>("transition_overlay")

        if (animationDone) {
            viewPager.visibility = android.view.View.VISIBLE
            // toolbars already faded in during animateEntry, overlay already in innerFrame
        }
        
        if (imageLoaded && animationDone) {
            if (overlayImage != null && overlayImage.alpha > 0f) {
                overlayImage.animate().alpha(0f).setDuration(150).withEndAction {
                    (overlayImage.parent as? android.view.ViewGroup)?.removeView(overlayImage)
                }.start()
                overlayImage.tag = null
            }
        }
    }

    private var isApplying = false

    override fun finish() {
        if (!isApplying) {
            val returnIntent = android.content.Intent()
            
            val uneditedSelectedUris = selectedUris.filter { uri ->
                val index = originalUris.indexOf(uri)
                if (index == -1) {
                    true
                } else {
                    val hasFilter = filterStates.containsKey(index)
                    val hasStickers = (stickersByIndex[index]?.isNotEmpty() == true) || 
                                      ((supportFragmentManager.findFragmentByTag("f$index") as? EditorPageFragment)?.stickerContainer?.childCount ?: 0) > 0
                    val isCropped = uris[index] != initialUris.getOrNull(index)
                    val isEdited = hasFilter || hasStickers || isCropped
                    !isEdited
                }
            }
            
            returnIntent.putStringArrayListExtra(EXTRA_RESULT_SELECTED_URIS, ArrayList(uneditedSelectedUris.map { it.toString() }))
            setResult(android.app.Activity.RESULT_CANCELED, returnIntent)
        }

        val rootView = findViewById<android.view.ViewGroup>(android.R.id.content)
        if (rootView.tag == "animating") return
        rootView.tag = "animating"
        
        val currentUriStr = uris.getOrNull(viewPager.currentItem)?.toString()
        val origUriStr = originalUris.getOrNull(viewPager.currentItem)?.toString()
        var sourceRect = origUriStr?.let { TransitionHelper.requestThumbnailRect?.invoke(it) }
        
        if (sourceRect == null && TransitionHelper.sourceRect != null) {
            // Fallback for when the first opened image is still current but requestThumbnailRect failed for some reason
            val initialUriStr = uris.getOrNull(intent.getIntExtra(EXTRA_START_INDEX, 0))?.toString()
            if (initialUriStr == currentUriStr) {
                sourceRect = TransitionHelper.sourceRect
            }
        }
        
        var thumbnailBitmap = filterAdapter.originalThumbnail
        val initialUriStr = uris.getOrNull(intent.getIntExtra(EXTRA_START_INDEX, 0))?.toString()
        if (initialUriStr == currentUriStr && TransitionHelper.thumbnailBitmap != null) {
            thumbnailBitmap = TransitionHelper.thumbnailBitmap
        }
        
        // Try to grab the actual displayed bitmap from the exact current fragment
        val currentFragment = this.currentFragment
        
        val displayedBitmap = currentFragment?.view?.findViewById<android.widget.ImageView>(R.id.editorImageView)?.drawable?.let {
            if (it is android.graphics.drawable.BitmapDrawable) it.bitmap else null
        }
        val isSaved = TransitionHelper.editedBitmap != null
        if (TransitionHelper.editedBitmap != null) {
            // Prefer the final fully-rendered bitmap (with stickers) if it was saved during onSendTapped
            thumbnailBitmap = TransitionHelper.editedBitmap
        } else if (displayedBitmap != null) {
            thumbnailBitmap = displayedBitmap
        }
        
        if (sourceRect == null || thumbnailBitmap == null) {
            val editorRootLayout = rootView.getChildAt(0) as android.view.ViewGroup
            val pullToDismissLayout = findViewById<android.view.View>(R.id.pullToDismissLayout)
            val pullChild = (pullToDismissLayout as? android.view.ViewGroup)?.getChildAt(0)
            
            val ty = pullChild?.translationY ?: 0f
            val slideAnim = android.animation.ValueAnimator.ofFloat(ty, editorRootLayout.height.toFloat())
            slideAnim.addUpdateListener { anim ->
                pullChild?.translationY = anim.animatedValue as Float
            }
            
            val currentAlpha = (editorRootLayout.background as? android.graphics.drawable.ColorDrawable)?.alpha ?: 255
            val colorAnim = android.animation.ValueAnimator.ofInt(currentAlpha, 0)
            colorAnim.addUpdateListener { anim ->
                val alpha = anim.animatedValue as Int
                editorRootLayout.setBackgroundColor(android.graphics.Color.argb(alpha, 0, 0, 0))
            }
            
            val topBarOverlay = findViewById<android.view.View>(R.id.topBarOverlay)
            val editorBottomBar = findViewById<android.view.View>(R.id.editorBottomBar)
            topBarOverlay.animate().alpha(0f).setDuration(200).start()
            editorBottomBar.animate().alpha(0f).setDuration(200).start()
            
            val set = android.animation.AnimatorSet()
            set.playTogether(slideAnim, colorAnim)
            set.duration = 200
            set.interpolator = androidx.interpolator.view.animation.FastOutSlowInInterpolator()
            set.addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    super@ImageEditorActivity.finish()
                    if (android.os.Build.VERSION.SDK_INT >= 34) {
                        overrideActivityTransition(android.app.Activity.OVERRIDE_TRANSITION_CLOSE, 0, 0)
                    }
                    @Suppress("DEPRECATION")
                    overridePendingTransition(0, 0)
                    TransitionHelper.sourceRect = null
                    TransitionHelper.thumbnailBitmap = null
                }
            })
            
            origUriStr?.let { TransitionHelper.onEditingFinished?.invoke(it, thumbnailBitmap, isSaved) }
            set.start()
            return
        }
        
        val editorRootLayout = rootView.getChildAt(0) as android.view.ViewGroup
        val pullToDismissLayout = findViewById<android.view.View>(R.id.pullToDismissLayout)
        pullToDismissLayout.animate().alpha(0f).setDuration(250).start()
        viewPager.visibility = android.view.View.INVISIBLE
        
        val topBarOverlay = findViewById<android.view.View>(R.id.topBarOverlay)
        val editorBottomBar = findViewById<android.view.View>(R.id.editorBottomBar)
        topBarOverlay.animate().alpha(0f).setDuration(200).start()
        editorBottomBar.animate().alpha(0f).setDuration(200).start()
        
        val currentAlpha = (editorRootLayout.background as? android.graphics.drawable.ColorDrawable)?.alpha ?: 255
        val colorAnim = android.animation.ValueAnimator.ofInt(currentAlpha, 0)
        colorAnim.addUpdateListener { animator ->
            val alpha = animator.animatedValue as Int
            editorRootLayout.setBackgroundColor(android.graphics.Color.argb(alpha, 0, 0, 0))
        }
        colorAnim.duration = 200
        colorAnim.start()
        
        val screenWidth = rootView.width.toFloat()
        val screenHeight = rootView.height.toFloat()
        
        val bw = thumbnailBitmap.width.toFloat()
        val bh = thumbnailBitmap.height.toFloat()
        
        val startWidth: Float
        val startHeight: Float
        
        if (bw * screenHeight > screenWidth * bh) {
            startWidth = screenWidth
            startHeight = screenWidth * bh / bw
        } else {
            startHeight = screenHeight
            startWidth = screenHeight * bw / bh
        }
        
        val pullChild = (pullToDismissLayout as? android.view.ViewGroup)?.getChildAt(0)
        val pScale = pullChild?.scaleX ?: 1f
        val pTy = pullChild?.translationY ?: 0f
        
        val actualStartWidth = startWidth * pScale
        val actualStartHeight = startHeight * pScale
        
        val startLeft = (screenWidth - actualStartWidth) / 2f
        val startTop = (screenHeight - actualStartHeight) / 2f + pTy
        val startRight = startLeft + actualStartWidth
        val startBottom = startTop + actualStartHeight
        
        val targetLeft = sourceRect.left.toFloat()
        val targetTop = sourceRect.top.toFloat()
        val targetRight = sourceRect.right.toFloat()
        val targetBottom = sourceRect.bottom.toFloat()
        
        val overlayView = object : android.view.View(this) {
            var animatedBounds = android.graphics.RectF(startLeft, startTop, startRight, startBottom)
            private val paint = android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG)
            
            override fun onDraw(canvas: android.graphics.Canvas) {
                if (animatedBounds.isEmpty) return
                
                val scale: Float
                val dx: Float
                val dy: Float
                
                val vw = animatedBounds.width()
                val vh = animatedBounds.height()
                
                if (bw * vh > vw * bh) {
                    scale = vh / bh
                    dx = (vw - bw * scale) * 0.5f
                    dy = 0f
                } else {
                    scale = vw / bw
                    dx = 0f
                    dy = (vh - bh * scale) * 0.5f
                }
                
                canvas.save()
                canvas.translate(animatedBounds.left, animatedBounds.top)
                canvas.clipRect(0f, 0f, vw, vh)
                val matrix = android.graphics.Matrix()
                matrix.setScale(scale, scale)
                matrix.postTranslate(dx, dy)
                canvas.drawBitmap(thumbnailBitmap, matrix, paint)
                canvas.restore()
            }
        }
        
        editorRootLayout.addView(overlayView, 1, android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT, 
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT
        ))
        
        val animator = android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 200
            interpolator = androidx.interpolator.view.animation.FastOutSlowInInterpolator()
            addUpdateListener { anim ->
                val progress = anim.animatedValue as Float
                overlayView.animatedBounds.set(
                    startLeft + (targetLeft - startLeft) * progress,
                    startTop + (targetTop - startTop) * progress,
                    startRight + (targetRight - startRight) * progress,
                    startBottom + (targetBottom - startBottom) * progress
                )
                overlayView.invalidate()
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    super@ImageEditorActivity.finish()
                    if (android.os.Build.VERSION.SDK_INT >= 34) {
                        overrideActivityTransition(android.app.Activity.OVERRIDE_TRANSITION_CLOSE, 0, 0)
                    }
                    @Suppress("DEPRECATION")
                    overridePendingTransition(0, 0)
                    TransitionHelper.sourceRect = null
                                        TransitionHelper.thumbnailBitmap = null
                }
            })
        }
        
        // Notify the bottom sheet to update the grid cell immediately BEFORE the animation starts
        // This prevents a brief flash of the original image when the animation completes
        origUriStr?.let { TransitionHelper.onEditingFinished?.invoke(it, thumbnailBitmap, isSaved) }
        
        animator.start()
    }

}

// ─────────────────────────────────────────────
// ViewPager2 Adapter
// ─────────────────────────────────────────────

private class EditorPagerAdapter(
    activity: FragmentActivity,
    private val uris: List<Uri>
) : FragmentStateAdapter(activity) {

    override fun getItemCount(): Int = uris.size

    override fun createFragment(position: Int): Fragment {
        return EditorPageFragment.newInstance(uris[position], position)
    }
}
