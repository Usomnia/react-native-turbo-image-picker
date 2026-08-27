package com.rnturboimagepicker

import android.graphics.Bitmap
import android.graphics.drawable.Drawable
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.bumptech.glide.request.RequestOptions
import com.bumptech.glide.request.target.CustomTarget
import com.bumptech.glide.request.transition.Transition
import com.bumptech.glide.load.model.GlideUrl
import android.net.Uri

class SafeGlideUrl(private val originalUrl: String, private val safeCacheKey: String) : GlideUrl(originalUrl) {
    override fun getCacheKey(): String = safeCacheKey
    override fun equals(other: Any?): Boolean {
        if (other is GlideUrl) {
            return safeCacheKey == other.cacheKey
        }
        return false
    }
    override fun hashCode(): Int {
        return safeCacheKey.hashCode()
    }
}

fun getSafeGlideUrl(url: String): Any {
    if (!url.startsWith("http")) return url
    val cacheKey = try {
        val uri = Uri.parse(url)
        if (uri.isHierarchical) {
            val builder = uri.buildUpon().clearQuery()
            uri.queryParameterNames.forEach { key ->
                if (key != "auth" && key != "secret" && key != "apikey") {
                    builder.appendQueryParameter(key, uri.getQueryParameter(key))
                }
            }
            builder.build().toString()
        } else url
    } catch (e: Exception) {
        url
    }
    return SafeGlideUrl(url, cacheKey)
}
class ImageViewerActivity : AppCompatActivity() {

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
        const val EXTRA_IMAGES = "extra_images"
        const val EXTRA_INITIAL_INDEX = "extra_initial_index"
        const val EXTRA_TITLE = "extra_title"
        var currentInstance: java.lang.ref.WeakReference<ImageViewerActivity>? = null
    }

    private lateinit var viewPager: ViewPager2
    private lateinit var tvCounter: TextView
    private lateinit var btnClose: ImageView
    private lateinit var rvThumbnails: RecyclerView

    private var images: List<String> = emptyList()
    private var currentIndex: Int = 0
    
    private var sourceBorderRadius: Float = 0f
    private var sourceBorderCorners: List<String> = emptyList()

    private var parsedThemeColor: Int = android.graphics.Color.parseColor("#FF6B35")
    private lateinit var thumbnailAdapter: ThumbnailAdapter

    private var isDismissedByPull = false
    
    private var startX = -1f
    private var startY = -1f
    private var startWidth = -1f
    private var startHeight = -1f
    
    private val coordinateReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
            if (intent?.action == "com.rnturboimagepicker.UPDATE_COORDINATES") {
                val newX = intent.getFloatExtra("startX", -1f)
                val newY = intent.getFloatExtra("startY", -1f)
                val newW = intent.getFloatExtra("startWidth", -1f)
                val newH = intent.getFloatExtra("startHeight", -1f)
                if (newX != -1f && newY != -1f && newW != -1f && newH != -1f) {
                    startX = newX
                    startY = newY
                    startWidth = newW
                    startHeight = newH
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        currentInstance = java.lang.ref.WeakReference(this)
        
        startX = intent.getFloatExtra("startX", -1f)
        startY = intent.getFloatExtra("startY", -1f)
        startWidth = intent.getFloatExtra("startWidth", -1f)
        startHeight = intent.getFloatExtra("startHeight", -1f)
        sourceBorderRadius = intent.getFloatExtra("sourceBorderRadius", 0f)
        sourceBorderCorners = intent.getStringArrayListExtra("sourceBorderCorners") ?: listOf("topLeft", "topRight", "bottomLeft", "bottomRight")
        
        val animationType = intent.getStringExtra("animationType") ?: "slide"
        
        androidx.localbroadcastmanager.content.LocalBroadcastManager.getInstance(this)
            .registerReceiver(coordinateReceiver, android.content.IntentFilter("com.rnturboimagepicker.UPDATE_COORDINATES"))
        
        @Suppress("DEPRECATION")
        if (animationType == "slide" || (animationType == "zoom" && startX == -1f)) {
            overridePendingTransition(R.anim.slide_in_bottom, R.anim.no_animation)
        } else if (animationType == "fade") {
            overridePendingTransition(R.anim.fade_in, R.anim.fade_out)
        }
        
        WindowCompat.setDecorFitsSystemWindows(window, false)
        setContentView(R.layout.activity_image_viewer)
        
        val pullToDismissLayout = findViewById<PullToDismissLayout>(R.id.pullToDismissLayout)
        val activityRoot = findViewById<android.widget.FrameLayout>(R.id.activityRoot)
        
        val bgColor = androidx.core.content.ContextCompat.getColor(this, R.color.viewer_background)
        val bgR = android.graphics.Color.red(bgColor)
        val bgG = android.graphics.Color.green(bgColor)
        val bgB = android.graphics.Color.blue(bgColor)
        
        // 초기 배경색 명시적 설정 (투명화 방지 또는 애니메이션 처리)
        if (animationType == "zoom" && startX != -1f) {
            val rootView = findViewById<View>(R.id.rootView)
            rootView.setBackgroundColor(android.graphics.Color.TRANSPARENT)
            activityRoot.setBackgroundColor(android.graphics.Color.TRANSPARENT)
            images = intent.getStringArrayListExtra(EXTRA_IMAGES) ?: emptyList()
            val viewPager = findViewById<View>(R.id.viewPager)
            val topBar = findViewById<View>(R.id.topBar)
            val bottomBar = findViewById<View>(R.id.bottomBar)
            
            topBar.alpha = 0f
            bottomBar.alpha = 0f
            viewPager.alpha = 0f
            
            var currentRadius = 0f
            val dummyView = android.widget.ImageView(this@ImageViewerActivity)
            dummyView.scaleType = android.widget.ImageView.ScaleType.CENTER_CROP
            dummyView.layoutParams = android.widget.FrameLayout.LayoutParams(
                Math.round(startWidth),
                Math.round(startHeight)
            )
            dummyView.translationX = startX
            dummyView.translationY = startY
            
            dummyView.outlineProvider = object : android.view.ViewOutlineProvider() {
                override fun getOutline(view: View, outline: android.graphics.Outline) {
                    val w = if (view.layoutParams.width > 0) view.layoutParams.width else view.width
                    val h = if (view.layoutParams.height > 0) view.layoutParams.height else view.height
                    outline.setRoundRect(0, 0, w, h, currentRadius)
                }
            }
            dummyView.clipToOutline = true
            
            dummyView.visibility = View.INVISIBLE
            (rootView as android.view.ViewGroup).addView(dummyView, 0)
            
            val initialIndex = intent.getIntExtra(EXTRA_INITIAL_INDEX, 0)
            Glide.with(this@ImageViewerActivity)
                .load(getSafeGlideUrl(images[initialIndex]))
                .apply(RequestOptions()
                    .override(com.bumptech.glide.request.target.Target.SIZE_ORIGINAL)
                    .priority(com.bumptech.glide.Priority.IMMEDIATE))
                .listener(object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                    override fun onLoadFailed(e: com.bumptech.glide.load.engine.GlideException?, model: Any?, target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>, isFirstResource: Boolean): Boolean {
                        dummyView.visibility = View.GONE
                        viewPager.alpha = 1f
                        topBar.alpha = 1f
                        bottomBar.alpha = 1f
                        activityRoot.setBackgroundColor(android.graphics.Color.argb(255, bgR, bgG, bgB))
                        findViewById<View>(R.id.rootView).setBackgroundColor(android.graphics.Color.argb(255, bgR, bgG, bgB))
                        return false
                    }
                    override fun onResourceReady(resource: android.graphics.drawable.Drawable, model: Any, target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>?, dataSource: com.bumptech.glide.load.DataSource, isFirstResource: Boolean): Boolean {
                        activityRoot.post {
                            val imgW = resource.intrinsicWidth.toFloat()
                            val imgH = resource.intrinsicHeight.toFloat()
                            val ratio = if (imgH > 0) imgW / imgH else 1f
                            val screenWidth = viewPager.width.toFloat()
                            val screenHeight = viewPager.height.toFloat()
                            val screenRatio = if (screenHeight > 0) screenWidth / screenHeight else 1f
                            
                            val finalWidth: Float
                            val finalHeight: Float
                            val finalX: Float
                            val finalY: Float
                            if (ratio > screenRatio) {
                                finalWidth = screenWidth
                                finalHeight = screenWidth / ratio
                                finalX = 0f
                                finalY = (screenHeight - finalHeight) / 2f
                            } else {
                                finalHeight = screenHeight
                                finalWidth = screenHeight * ratio
                                finalX = (screenWidth - finalWidth) / 2f
                                finalY = 0f
                            }
                            
                            currentRadius = sourceBorderRadius
                            dummyView.invalidateOutline()
                            
                            dummyView.visibility = View.VISIBLE
                            
                            val animator = android.animation.ValueAnimator.ofFloat(0f, 1f)
                            animator.duration = 250
                            animator.interpolator = android.view.animation.DecelerateInterpolator()
                            animator.addUpdateListener { anim ->
                                val p = anim.animatedValue as Float
                                activityRoot.setBackgroundColor(android.graphics.Color.argb((255 * p).toInt().coerceIn(0, 255), bgR, bgG, bgB))
                                findViewById<View>(R.id.rootView).setBackgroundColor(android.graphics.Color.argb((255 * p).toInt().coerceIn(0, 255), bgR, bgG, bgB))
                                
                                val currentX = startX + (finalX - startX) * p
                                val currentY = startY + (finalY - startY) * p
                                val currentW = startWidth + (finalWidth - startWidth) * p
                                val currentH = startHeight + (finalHeight - startHeight) * p
                                
                                dummyView.layoutParams.width = Math.round(currentW)
                                dummyView.layoutParams.height = Math.round(currentH)
                                dummyView.translationX = currentX
                                dummyView.translationY = currentY
                                dummyView.requestLayout()
                                
                                currentRadius = sourceBorderRadius * (1f - p)
                                dummyView.invalidateOutline()
                            }
                            animator.addListener(object: android.animation.AnimatorListenerAdapter() {
                                override fun onAnimationEnd(animation: android.animation.Animator) {
                                    dummyView.visibility = View.GONE
                                    viewPager.alpha = 1f
                                }
                            })
                            animator.start()
                            topBar.animate().alpha(1f).setDuration(250).start()
                            bottomBar.animate().alpha(1f).setDuration(250).start()
                        }
                        return false
                    }
                })
                .into(dummyView)
        } else {
            activityRoot.setBackgroundColor(android.graphics.Color.argb(255, bgR, bgG, bgB))
            findViewById<View>(R.id.rootView).setBackgroundColor(android.graphics.Color.argb(255, bgR, bgG, bgB))
        }
        
        pullToDismissLayout.onDismiss = {
            if (startX != -1f) {
                isDismissedByPull = true
                finish()
            } else {
                val child = pullToDismissLayout.getChildAt(0)
                val startTy = child.translationY
                val startTx = child.translationX
                val targetTy = pullToDismissLayout.height.toFloat()
                val targetTx = startTx + (startTx * 0.5f)
                
                val startProgress = (startTy * 2f / pullToDismissLayout.height).coerceIn(0f, 1f)
                val currentBgAlpha = ((1f - startProgress) * 255).toInt().coerceIn(0, 255)
                
                val animator = android.animation.ValueAnimator.ofFloat(0f, 1f)
                animator.duration = 200
                animator.addUpdateListener { anim ->
                    val p = anim.animatedValue as Float
                    child.translationY = startTy + (targetTy - startTy) * p
                    child.translationX = startTx + (targetTx - startTx) * p
                    
                    val bgAlpha = (currentBgAlpha * (1f - p)).toInt().coerceIn(0, 255)
                    activityRoot.setBackgroundColor(android.graphics.Color.argb(bgAlpha, bgR, bgG, bgB))
                    findViewById<View>(R.id.rootView).setBackgroundColor(android.graphics.Color.argb(bgAlpha, bgR, bgG, bgB))
                }
                animator.addListener(object : android.animation.AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: android.animation.Animator) {
                        isDismissedByPull = true
                        finish()
                    }
                })
                animator.start()
            }
        }
        
        val tvTitle = findViewById<TextView>(R.id.tvTitle)
        val titleText = intent.getStringExtra(EXTRA_TITLE)
        if (!titleText.isNullOrEmpty()) {
            tvTitle.text = titleText
            tvTitle.visibility = View.VISIBLE
        } else {
            tvTitle.visibility = View.GONE
        }
        
        pullToDismissLayout.onDragProgress = { progress ->
            activityRoot.setBackgroundColor(android.graphics.Color.argb(((1f - progress) * 255).toInt(), bgR, bgG, bgB))
            findViewById<View>(R.id.rootView).setBackgroundColor(android.graphics.Color.argb(((1f - progress) * 255).toInt(), bgR, bgG, bgB))
            val topBar = findViewById<View>(R.id.topBar)
            val bottomBar = findViewById<View>(R.id.bottomBar)
            val barAlpha = (1f - progress * 2f).coerceIn(0f, 1f)
            topBar.alpha = barAlpha
            bottomBar.alpha = barAlpha
        }

        val themeColorStr = intent.getStringExtra("EXTRA_THEME_COLOR")
        if (!themeColorStr.isNullOrEmpty()) {
            try {
                parsedThemeColor = android.graphics.Color.parseColor(if (!themeColorStr.startsWith("#")) "#$themeColorStr" else themeColorStr)
            } catch (e: Exception) {
                // Ignore
            }
        }

        images = intent.getStringArrayListExtra(EXTRA_IMAGES) ?: emptyList()
        currentIndex = intent.getIntExtra(EXTRA_INITIAL_INDEX, 0)

        viewPager = findViewById(R.id.viewPager)
        tvCounter = findViewById(R.id.tvCounter)
        btnClose = findViewById(R.id.btnClose)
        rvThumbnails = findViewById(R.id.rvThumbnails)
        
        val topBar = findViewById<View>(R.id.topBar)
        val bottomBar = findViewById<View>(R.id.bottomBar)

        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.rootView)) { view, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            topBar.setPadding(
                topBar.paddingLeft, 
                systemBars.top + (16 * resources.displayMetrics.density).toInt(), 
                topBar.paddingRight, 
                topBar.paddingBottom
            )
            bottomBar.setPadding(
                bottomBar.paddingLeft, 
                bottomBar.paddingTop, 
                bottomBar.paddingRight, 
                systemBars.bottom
            )
            insets
        }

        btnClose.setOnClickListener {
            finish()
        }

        val adapter = ImageViewerAdapter(images)
        val vp = findViewById<androidx.viewpager2.widget.ViewPager2>(R.id.viewPager)
        vp.adapter = adapter
        vp.setCurrentItem(currentIndex, false)
        
        setupThumbnails()
        updateCounter(currentIndex)
        preloadAdjacentImages(currentIndex)
        
        vp.registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
            override fun onPageSelected(position: Int) {
                super.onPageSelected(position)
                currentIndex = position
                updateCounter(position)
                val intent = android.content.Intent("com.rnturboimagepicker.PAGE_CHANGED")
                intent.putExtra("index", position)
                androidx.localbroadcastmanager.content.LocalBroadcastManager.getInstance(this@ImageViewerActivity).sendBroadcast(intent)
                thumbnailAdapter.notifyDataSetChanged()
                centerThumbnail(position, true)
                preloadAdjacentImages(position)
                TransitionHelper.onViewerPageChanged?.invoke(position)
                
                // Zoom reset
                for (i in 0 until viewPager.childCount) {
                    val child = viewPager.getChildAt(i)
                    if (child is RecyclerView) {
                        for (j in 0 until child.childCount) {
                            val itemView = child.getChildAt(j)
                            val zoomableView = itemView.findViewById<ZoomableImageView>(R.id.zoomableImageView)
                            zoomableView?.resetZoom()
                        }
                    }
                }
            }
        })
    }

    private fun setupThumbnails() {
        thumbnailAdapter = ThumbnailAdapter(images)
        rvThumbnails.layoutManager = LinearLayoutManager(this, LinearLayoutManager.HORIZONTAL, false)
        rvThumbnails.adapter = thumbnailAdapter
        centerThumbnail(currentIndex, false)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (currentInstance?.get() == this) {
            currentInstance = null
        }
        androidx.localbroadcastmanager.content.LocalBroadcastManager.getInstance(this).unregisterReceiver(coordinateReceiver)
    }

    fun updateSourceRect(x: Float, y: Float, width: Float, height: Float) {
        intent.putExtra("startX", x)
        intent.putExtra("startY", y)
        intent.putExtra("startWidth", width)
        intent.putExtra("startHeight", height)
    }

    private fun centerThumbnail(position: Int, smooth: Boolean) {
        val layoutManager = rvThumbnails.layoutManager as? LinearLayoutManager ?: return
        if (smooth) {
            val smoothScroller = object : androidx.recyclerview.widget.LinearSmoothScroller(this) {
                override fun calculateDtToFit(viewStart: Int, viewEnd: Int, boxStart: Int, boxEnd: Int, snapPreference: Int): Int {
                    return (boxStart + (boxEnd - boxStart) / 2) - (viewStart + (viewEnd - viewStart) / 2)
                }
                
                override fun calculateSpeedPerPixel(displayMetrics: android.util.DisplayMetrics): Float {
                    // Default is 25f. 150f makes it slower and smoother (around 200-250ms for typical scroll).
                    return 150f / displayMetrics.densityDpi
                }
            }
            smoothScroller.targetPosition = position
            layoutManager.startSmoothScroll(smoothScroller)
        } else {
            rvThumbnails.post {
                val screenWidth = rvThumbnails.width
                val itemWidth = (58 * resources.displayMetrics.density).toInt()
                val offset = (screenWidth / 2) - (itemWidth / 2)
                layoutManager.scrollToPositionWithOffset(position, offset)
            }
        }
    }

    private fun updateCounter(position: Int) {
        if (images.isNotEmpty()) {
            tvCounter.text = getString(R.string.viewer_counter, position + 1, images.size)
        } else {
            tvCounter.text = getString(R.string.viewer_zero)
        }
    }

    inner class ThumbnailAdapter(private val items: List<String>) : RecyclerView.Adapter<ThumbnailAdapter.ViewHolder>() {

        inner class ViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
            val thumbnailImage: ImageView = itemView.findViewById(R.id.thumbnailImage)
            val thumbnailProgress: android.widget.ProgressBar = itemView.findViewById(R.id.thumbnailProgress)
            val selectionBorder: View = itemView.findViewById(R.id.selectionBorder)
            
            init {
                itemView.setOnClickListener {
                    val pos = adapterPosition
                    if (pos != RecyclerView.NO_POSITION) {
                        viewPager.setCurrentItem(pos, true)
                    }
                }
            }
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val view = LayoutInflater.from(parent.context).inflate(R.layout.item_editor_thumbnail, parent, false)
            return ViewHolder(view)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            val url = items[position]
            
            val isRemoteUrl = url.startsWith("http://") || url.startsWith("https://")
            holder.thumbnailProgress.visibility = if (isRemoteUrl) View.VISIBLE else View.GONE
            
            Glide.with(this@ImageViewerActivity)
                .load(getSafeGlideUrl(url))
                .apply(RequestOptions()
                    .diskCacheStrategy(DiskCacheStrategy.ALL)
                    .override(200)
                    .skipMemoryCache(false))
                .centerCrop()
                .listener(object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                    override fun onLoadFailed(
                        e: com.bumptech.glide.load.engine.GlideException?, 
                        model: Any?, 
                        target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>, 
                        isFirstResource: Boolean
                    ): Boolean {
                        holder.thumbnailProgress.visibility = View.GONE
                        return false
                    }

                    override fun onResourceReady(
                        resource: android.graphics.drawable.Drawable, 
                        model: Any, 
                        target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>?, 
                        dataSource: com.bumptech.glide.load.DataSource, 
                        isFirstResource: Boolean
                    ): Boolean {
                        holder.thumbnailProgress.visibility = View.GONE
                        return false
                    }
                })
                .into(holder.thumbnailImage)
                
            if (position == currentIndex) {
                holder.selectionBorder.visibility = View.VISIBLE
                val strokeWidth = (2 * holder.itemView.context.resources.displayMetrics.density).toInt()
                val cornerRadius = 8f * holder.itemView.context.resources.displayMetrics.density
                val border = android.graphics.drawable.GradientDrawable()
                border.setStroke(strokeWidth, parsedThemeColor)
                border.setColor(android.graphics.Color.TRANSPARENT)
                border.cornerRadius = cornerRadius
                holder.selectionBorder.background = border
            } else {
                holder.selectionBorder.visibility = View.GONE
            }
        }

        override fun getItemCount(): Int = items.size
    }

    inner class ImageViewerAdapter(private val items: List<String>) : RecyclerView.Adapter<ImageViewerAdapter.ViewHolder>() {

        inner class ViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
            val zoomableImageView: ZoomableImageView = itemView.findViewById(R.id.zoomableImageView)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val view = LayoutInflater.from(parent.context).inflate(R.layout.item_image_viewer, parent, false)
            return ViewHolder(view)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            val url = items[position]
            
            val thumbnailRequest = Glide.with(this@ImageViewerActivity)
                .asBitmap()
                .load(getSafeGlideUrl(url))
                .apply(RequestOptions()
                    .diskCacheStrategy(DiskCacheStrategy.ALL)
                    .override(200))

            Glide.with(this@ImageViewerActivity)
                .asBitmap()
                .load(getSafeGlideUrl(url))
                .thumbnail(thumbnailRequest)
                .apply(RequestOptions()
                    .diskCacheStrategy(DiskCacheStrategy.ALL)
                    .priority(if (position == currentIndex) com.bumptech.glide.Priority.IMMEDIATE else com.bumptech.glide.Priority.NORMAL)
                    .skipMemoryCache(false))
                .into(holder.zoomableImageView)
        }

        override fun getItemCount(): Int = items.size

        private fun blurBitmap(bitmap: Bitmap): Bitmap {
            val scale = 0.02f
            val width = Math.max(1, Math.round(bitmap.width * scale))
            val height = Math.max(1, Math.round(bitmap.height * scale))
            val scaled = Bitmap.createScaledBitmap(bitmap, width, height, false)
            return Bitmap.createScaledBitmap(scaled, bitmap.width, bitmap.height, true)
        }

        private fun addTextToBitmap(bitmap: Bitmap, text: String): Bitmap {
            val mutableBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, true)
            val canvas = android.graphics.Canvas(mutableBitmap)
            
            val textPaint = android.text.TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                color = android.graphics.Color.WHITE
                textSize = Math.min(bitmap.width, bitmap.height) / 20f
                setShadowLayer(5f, 2f, 2f, android.graphics.Color.BLACK)
            }
            
            val textLayout = android.text.StaticLayout.Builder.obtain(text, 0, text.length, textPaint, bitmap.width - (bitmap.width / 10))
                .setAlignment(android.text.Layout.Alignment.ALIGN_CENTER)
                .build()
                
            canvas.save()
            canvas.translate((bitmap.width - textLayout.width) / 2f, (bitmap.height - textLayout.height) / 2f)
            textLayout.draw(canvas)
            canvas.restore()
            
            return mutableBitmap
        }
    }

    private fun preloadAdjacentImages(index: Int) {
        val preloadIndices = listOf(index - 1, index + 1)
        for (i in preloadIndices) {
            if (i >= 0 && i < images.size) {
                Glide.with(this)
                    .asBitmap()
                    .load(getSafeGlideUrl(images[i]))
                    .apply(RequestOptions()
                        .diskCacheStrategy(DiskCacheStrategy.ALL)
                        .priority(com.bumptech.glide.Priority.LOW)
                        .skipMemoryCache(false))
                    .preload()
            }
        }
    }

    private var isFinishingAnimated = false

    override fun finish() {
        if (isFinishingAnimated) return
        
        val animationType = intent.getStringExtra("animationType") ?: "slide"
        val closeAnimationType = intent.getStringExtra("closeAnimationType") ?: animationType
        
        if ((closeAnimationType == "zoom" || isDismissedByPull) && startX != -1f) {
            isFinishingAnimated = true
            val activityRoot = findViewById<android.widget.FrameLayout>(R.id.activityRoot)
            val pullToDismissLayout = findViewById<PullToDismissLayout>(R.id.pullToDismissLayout)
            val rootView = findViewById<View>(R.id.rootView)
            val viewPager = findViewById<androidx.viewpager2.widget.ViewPager2>(R.id.viewPager)
            val topBar = findViewById<View>(R.id.topBar)
            val bottomBar = findViewById<View>(R.id.bottomBar)
            
            // No longer redeclaring startY, startWidth, startHeight locally.
            // We want to use the updated class fields startX, startY, startWidth, startHeight.
            
            val bgColor = androidx.core.content.ContextCompat.getColor(this, R.color.viewer_background)
            val bgR = android.graphics.Color.red(bgColor)
            val bgG = android.graphics.Color.green(bgColor)
            val bgB = android.graphics.Color.blue(bgColor)
            rootView.setBackgroundColor(android.graphics.Color.TRANSPARENT)
            
            var currentRadius = 0f
            val dummyView = android.widget.ImageView(this@ImageViewerActivity)
            dummyView.scaleType = android.widget.ImageView.ScaleType.CENTER_CROP
            dummyView.layoutParams = android.widget.FrameLayout.LayoutParams(
                android.widget.FrameLayout.LayoutParams.WRAP_CONTENT,
                android.widget.FrameLayout.LayoutParams.WRAP_CONTENT
            )
            
            dummyView.outlineProvider = object : android.view.ViewOutlineProvider() {
                override fun getOutline(view: View, outline: android.graphics.Outline) {
                    val w = if (view.layoutParams.width > 0) view.layoutParams.width else view.width
                    val h = if (view.layoutParams.height > 0) view.layoutParams.height else view.height
                    outline.setRoundRect(0, 0, w, h, currentRadius)
                }
            }
            dummyView.clipToOutline = true
            
            dummyView.visibility = View.INVISIBLE
            activityRoot.addView(dummyView)
            
            Glide.with(this@ImageViewerActivity)
                .load(getSafeGlideUrl(images[viewPager.currentItem]))
                .apply(RequestOptions()
                    .override(com.bumptech.glide.request.target.Target.SIZE_ORIGINAL)
                    .priority(com.bumptech.glide.Priority.IMMEDIATE))
                .listener(object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                    override fun onLoadFailed(e: com.bumptech.glide.load.engine.GlideException?, model: Any?, target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>, isFirstResource: Boolean): Boolean {
                        super@ImageViewerActivity.finish()
                        overridePendingTransition(0, 0)
                        return false
                    }
                    override fun onResourceReady(resource: android.graphics.drawable.Drawable, model: Any, target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>?, dataSource: com.bumptech.glide.load.DataSource, isFirstResource: Boolean): Boolean {
                        activityRoot.post {
                            val imgW = resource.intrinsicWidth.toFloat()
                            val imgH = resource.intrinsicHeight.toFloat()
                            val ratio = if (imgH > 0) imgW / imgH else 1f
                            val screenWidth = viewPager.width.toFloat()
                            val screenHeight = viewPager.height.toFloat()
                            val screenRatio = if (screenHeight > 0) screenWidth / screenHeight else 1f
                            
                            // Current displayed frame (aspect-fit)
                            val initialWidth: Float
                            val initialHeight: Float
                            val initialX: Float
                            val initialY: Float
                            if (ratio > screenRatio) {
                                initialWidth = screenWidth
                                initialHeight = screenWidth / ratio
                                initialX = 0f
                                initialY = (screenHeight - initialHeight) / 2f
                            } else {
                                initialHeight = screenHeight
                                initialWidth = screenHeight * ratio
                                initialX = (screenWidth - initialWidth) / 2f
                                initialY = 0f
                            }
                            
                            var startAnimX = initialX
                            var startAnimY = initialY
                            var startAnimW = initialWidth
                            var startAnimH = initialHeight
                            
                            var currentBgAlpha = 255
                            
                            if (isDismissedByPull) {
                                val child = pullToDismissLayout.getChildAt(0)
                                val S = child.scaleX
                                val TX = child.translationX
                                val TY = child.translationY
                                val pivotX = child.width / 2f
                                val pivotY = child.height / 2f
                                
                                startAnimX = pivotX + (initialX - pivotX) * S + TX
                                startAnimY = pivotY + (initialY - pivotY) * S + TY
                                startAnimW = initialWidth * S
                                startAnimH = initialHeight * S
                                
                                val startProgress = (TY * 2f / pullToDismissLayout.height).coerceIn(0f, 1f)
                                currentBgAlpha = ((1f - startProgress) * 255).toInt().coerceIn(0, 255)
                            }
                            
                            dummyView.layoutParams.width = Math.round(startAnimW)
                            dummyView.layoutParams.height = Math.round(startAnimH)
                            dummyView.translationX = startAnimX
                            dummyView.translationY = startAnimY
                            dummyView.requestLayout()
                            
                            currentRadius = 0f
                            dummyView.invalidateOutline()
                            
                            dummyView.setImageDrawable(resource)
                            
                            dummyView.visibility = View.VISIBLE
                            viewPager.visibility = View.INVISIBLE
                            topBar.animate().alpha(0f).setDuration(200).start()
                            bottomBar.animate().alpha(0f).setDuration(200).start()
                            
                            val animator = android.animation.ValueAnimator.ofFloat(0f, 1f)
                            animator.duration = 200
                            animator.interpolator = android.view.animation.DecelerateInterpolator()
                            animator.addUpdateListener { anim ->
                                val p = anim.animatedValue as Float
                                val bgAlpha = (currentBgAlpha * (1f - p)).toInt().coerceIn(0, 255)
                                activityRoot.setBackgroundColor(android.graphics.Color.argb(bgAlpha, bgR, bgG, bgB))
                                findViewById<View>(R.id.rootView).setBackgroundColor(android.graphics.Color.argb(bgAlpha, bgR, bgG, bgB))
                                
                                val currentX = startAnimX + (startX - startAnimX) * p
                                val currentY = startAnimY + (startY - startAnimY) * p
                                val currentW = startAnimW + (startWidth - startAnimW) * p
                                val currentH = startAnimH + (startHeight - startAnimH) * p
                                
                                dummyView.layoutParams.width = Math.round(currentW)
                                dummyView.layoutParams.height = Math.round(currentH)
                                dummyView.translationX = currentX
                                dummyView.translationY = currentY
                                dummyView.requestLayout()
                                
                                currentRadius = sourceBorderRadius * p
                                dummyView.invalidateOutline()
                            }
                            animator.addListener(object: android.animation.AnimatorListenerAdapter() {
                                override fun onAnimationEnd(animation: android.animation.Animator) {
                                    super@ImageViewerActivity.finish()
                                    @Suppress("DEPRECATION")
                                    overridePendingTransition(0, 0)
                                }
                            })
                            animator.start()
                        }
                        return false
                    }
                })
                .into(dummyView)
            return
        }

        super.finish()
        if (isDismissedByPull) {
            @Suppress("DEPRECATION")
            overridePendingTransition(0, android.R.anim.fade_out)
        } else {
            val animType = intent.getStringExtra("animationType") ?: "slide"
            val closeAnimType = intent.getStringExtra("closeAnimationType") ?: animType
            @Suppress("DEPRECATION")
            if (closeAnimType == "fade") {
                overridePendingTransition(R.anim.no_animation, R.anim.fade_out)
            } else if (closeAnimType == "slide") {
                overridePendingTransition(R.anim.no_animation, R.anim.slide_out_bottom)
            } else {
                overridePendingTransition(0, 0)
            }
        }
    }
}
