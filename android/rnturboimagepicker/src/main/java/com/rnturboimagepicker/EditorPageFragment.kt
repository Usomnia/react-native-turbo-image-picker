package com.rnturboimagepicker

import android.graphics.Bitmap
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.fragment.app.Fragment
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.bumptech.glide.request.target.CustomTarget
import com.bumptech.glide.request.transition.Transition

/**
 * EditorPageFragment
 *
 * ViewPager2의 각 페이지. Glide asBitmap()으로 이미지를 로드하여 ZoomableImageView에 표시.
 * setImageBitmap()이 오버라이드되어 있어 setupInitialMatrix()가 자동 호출됨.
 */
class EditorPageFragment : Fragment() {

    companion object {
        private const val ARG_URI = "arg_uri"
        private const val ARG_INDEX = "arg_index"

        fun newInstance(uri: Uri, index: Int): EditorPageFragment {
            return EditorPageFragment().apply {
                arguments = Bundle().apply {
                    putString(ARG_URI, uri.toString())
                    putInt(ARG_INDEX, index)
                }
            }
        }
    }

    var imageView: ZoomableImageView? = null
    var stickerContainer: FrameLayout? = null
        private set
    private var uriString: String? = null
    private var glideTarget: CustomTarget<Bitmap>? = null
    private var currentState: FilterState? = null
    
    val pageIndex: Int
        get() = arguments?.getInt(ARG_INDEX, -1) ?: -1

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        uriString = arguments?.getString(ARG_URI)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        return inflater.inflate(R.layout.fragment_editor_page, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        imageView = view.findViewById(R.id.editorImageView)
        stickerContainer = view.findViewById<FrameLayout>(R.id.stickerContainer)
        
        val index = arguments?.getInt(ARG_INDEX) ?: 0
        (activity as? ImageEditorActivity)?.getFilterState(index)?.let {
            currentState = it
        }
        updateFilter()
        loadImage()

        // Restore stickers
        (activity as? ImageEditorActivity)?.let { editor ->
            val stickers = editor.stickersByIndex[index] ?: return@let
            for (state in stickers) {
                val sticker = TextStickerView(requireContext())
                sticker.text = state.text
                sticker.textColor = state.textColor
                sticker.scaleX = state.scaleX
                sticker.scaleY = state.scaleY
                sticker.rotation = state.rotation
                sticker.translationX = state.transX
                sticker.translationY = state.transY
                sticker.listener = editor
                sticker.isActive = false
                sticker.isEditingMode = editor.isTextModeActive
                stickerContainer?.addView(sticker, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
                    gravity = android.view.Gravity.CENTER
                })
            }
        }
    }

    fun applyFilter(state: FilterState) {
        currentState = state
        updateFilter()
    }

    private fun updateFilter() {
        val state = currentState ?: return
        val filter = FilterManager.instance.getFilters(requireContext()).find { it.id == state.filterId } ?: return
        imageView?.colorFilter = android.graphics.ColorMatrixColorFilter(filter.apply(state.intensity))
    }

    private fun loadImage() {
        val uriStr = uriString ?: return
        val uri = Uri.parse(uriStr)
        loadImageFromUri(uri)
    }

    /**
     * Reload the displayed image from a new URI (e.g. after crop).
     * Clears the Glide disk cache for this URI so the fresh file is always read.
     */
    fun reloadImage(newUri: Uri, onLoaded: (() -> Unit)? = null) {
        uriString = newUri.toString()
        loadImageFromUri(newUri, onLoaded)
    }

    fun removeAllStickersAndFilter() {
        stickerContainer?.removeAllViews()
        currentState = null
        imageView?.colorFilter = null
    }

    private fun loadImageFromUri(uri: Uri, onLoaded: (() -> Unit)? = null) {
        // Clear previous target if it exists to allow Glide to clean up old resources
        glideTarget?.let { Glide.with(this).clear(it) }

        val target = object : CustomTarget<Bitmap>() {
            override fun onResourceReady(resource: Bitmap, transition: Transition<in Bitmap>?) {
                imageView?.setImageBitmap(resource)
                onLoaded?.invoke()
                
                (activity as? ImageEditorActivity)?.hideTransitionOverlay(uri)
                
                imageView?.onMatrixChanged = { matrix ->
                    if (stickerContainer != null) {
                        val view = imageView
                        if (view != null) {
                            val m0 = view.initialImageMatrix
                            val invM0 = android.graphics.Matrix()
                            if (m0.invert(invM0)) {
                                val userTransform = android.graphics.Matrix(invM0)
                                userTransform.postConcat(matrix)
                                
                                val values = FloatArray(9)
                                userTransform.getValues(values)
                                
                                val currentScaleX = values[android.graphics.Matrix.MSCALE_X]
                                val currentScaleY = values[android.graphics.Matrix.MSCALE_Y]
                                
                                stickerContainer?.pivotX = 0f
                                stickerContainer?.pivotY = 0f
                                stickerContainer?.scaleX = currentScaleX
                                stickerContainer?.scaleY = currentScaleY
                                stickerContainer?.translationX = values[android.graphics.Matrix.MTRANS_X]
                                stickerContainer?.translationY = values[android.graphics.Matrix.MTRANS_Y]
                                
                                val sc = stickerContainer
                                if (sc != null) {
                                    val zoomScale = currentScaleX
                                    for (i in 0 until sc.childCount) {
                                        val child = sc.getChildAt(i)
                                        if (child is TextStickerView) {
                                            child.setContainerZoom(zoomScale)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            override fun onLoadCleared(placeholder: Drawable?) {
                // Do not set imageView?.setImageBitmap(null) here to prevent blinking 
                // when reloading a baked image. The old image will stay until the new one is ready.
                imageView?.onMatrixChanged = null
            }
        }
        glideTarget = target

        if (TransitionHelper.thumbnailBitmap != null && imageView?.drawable == null) {
            imageView?.setImageDrawable(android.graphics.drawable.BitmapDrawable(resources, TransitionHelper.thumbnailBitmap))
        }

        val editorActivity = activity as? ImageEditorActivity
        val overrideWidth = if (editorActivity != null && editorActivity.maxWidth > 0) editorActivity.maxWidth else 2048
        val overrideHeight = if (editorActivity != null && editorActivity.maxHeight > 0) editorActivity.maxHeight else 2048

        Glide.with(this)
            .asBitmap()
            .load(uri)
            .override(overrideWidth, overrideHeight)
            .into(target)
    }

    fun onEditingModeChanged(isEditing: Boolean) {
        val sc = stickerContainer ?: return
        for (i in 0 until sc.childCount) {
            val child = sc.getChildAt(i)
            if (child is TextStickerView) {
                child.isEditingMode = isEditing
            }
        }
    }

    fun deselectAllStickers() {
        val sc = stickerContainer ?: return
        for (i in 0 until sc.childCount) {
            val child = sc.getChildAt(i)
            if (child is TextStickerView) {
                child.isActive = false
            }
        }
    }

    fun placeEmojiSticker(emoji: String) {
        val sc = stickerContainer ?: return
        deselectAllStickers()

        val iv = imageView ?: return
        val cx = sc.width / 2f
        val cy = sc.height / 2f

        // Create sticker
        val sticker = TextStickerView(requireContext())
        sticker.isEmojiSticker = true
        sticker.text = emoji
        sticker.listener = activity as? ImageEditorActivity
        
        sc.addView(sticker, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
            gravity = android.view.Gravity.CENTER
        })
        
        // Initial positioning to center of screen considering container's transform
        val zoom = sc.scaleX
        val tx = sc.translationX
        val ty = sc.translationY

        if (zoom != 0f) {
            sticker.translationX = (cx - cx * zoom - tx) / zoom
            sticker.translationY = (cy - cy * zoom - ty) / zoom
            sticker.intrinsicScaleX = 1.0f / zoom
            sticker.intrinsicScaleY = 1.0f / zoom
            sticker.setContainerZoom(zoom)
        }
        
        sticker.isEditingMode = true
        sticker.isActive = true
    }

    override fun onDestroyView() {
        super.onDestroyView()
        glideTarget?.let { target ->
            context?.applicationContext?.let { appCtx ->
                Glide.with(appCtx).clear(target)
            }
        }
        glideTarget = null
        imageView?.resetZoom()
        imageView = null
    }

    fun bakeStickersToImageAndGetBitmap(): Bitmap? {
        val iv = imageView ?: return null
        val sc = stickerContainer ?: return null
        if (sc.childCount == 0) return null

        val drawable = iv.drawable ?: return null
        val originalBmp = (drawable as? android.graphics.drawable.BitmapDrawable)?.bitmap ?: return null
        
        // Skip Bitmap.copy if original is already mutable (common with Glide-decoded bitmaps)
        val mutableBmp = if (originalBmp.isMutable) originalBmp
                         else originalBmp.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = android.graphics.Canvas(mutableBmp)

        // Prepare canvas matrix to map from screen to bitmap
        val m = iv.initialImageMatrix
        val invM = android.graphics.Matrix()
        if (!m.invert(invM)) return null
        canvas.concat(invM)

        // 3. Temporarily reset container to unzoomed state (M0 state)
        val oldScaleX = sc.scaleX
        val oldScaleY = sc.scaleY
        val oldTx = sc.translationX
        val oldTy = sc.translationY

        sc.scaleX = 1f
        sc.scaleY = 1f
        sc.translationX = 0f
        sc.translationY = 0f

        // Deselect all stickers before baking
        for (i in 0 until sc.childCount) {
            val view = sc.getChildAt(i)
            if (view is TextStickerView) {
                view.isActive = false
                view.isEditingMode = false
            }
        }

        // 4. Draw
        sc.draw(canvas)

        // 5. Restore container state
        sc.scaleX = oldScaleX
        sc.scaleY = oldScaleY
        sc.translationX = oldTx
        sc.translationY = oldTy
        
        return mutableBmp
    }

    fun resetZoomWithAnimation() {
        imageView?.resetZoomWithAnimation()
    }
}
