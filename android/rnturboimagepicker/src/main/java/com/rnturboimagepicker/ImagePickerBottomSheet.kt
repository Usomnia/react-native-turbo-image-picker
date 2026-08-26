package com.rnturboimagepicker

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.content.res.Resources
import android.graphics.Color
import android.widget.Toast
import java.util.Locale
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.Window
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.view.animation.AlphaAnimation
import android.view.animation.Animation
import android.view.animation.DecelerateInterpolator
import android.view.animation.ScaleAnimation
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.fragment.app.FragmentManager
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.StaggeredGridLayoutManager
import android.widget.ImageView
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import com.google.android.material.shape.MaterialShapeDrawable
import com.google.android.material.shape.ShapeAppearanceModel
import kotlinx.coroutines.*
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.text.SimpleDateFormat
import java.util.*
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.camera.core.Camera
import android.graphics.Rect

class ImagePickerBottomSheet : BottomSheetDialogFragment() {

    companion object {
        private const val TAG = "ImagePickerBottomSheet"
        private const val ARG_MAX_SELECTION = "arg_max_selection"
        private const val ARG_LANGUAGE_CODE = "arg_language_code"
        private const val ARG_ENABLE_EDITOR = "arg_enable_editor"
        private const val ARG_PROFILE_MODE = "arg_profile_mode"
        private const val ARG_MAX_WIDTH = "arg_max_width"
        private const val ARG_MAX_HEIGHT = "arg_max_height"
        
        private const val ARG_THEME_COLOR = "arg_theme_color"

        // Dim amount for background (0.0f = transparent, 1.0f = fully opaque)
        // Adjust this value to control background darkness
        private const val MAX_DIM_AMOUNT = 0.2f
        
        // Cache to store the initial chunk of images loaded from the device.
        // This allows subsequent gallery openings to be instantaneous.
        var cachedInitialImages: List<Uri>? = null

        fun newInstance(
            maxSelection: Int,
            languageCode: String,
            enableEditor: Boolean,
            profileMode: Boolean,
            maxWidth: Int,
            maxHeight: Int,
            themeColor: String? = null
        ): com.rnturboimagepicker.ImagePickerBottomSheet {
            return ImagePickerBottomSheet().apply {
                arguments = Bundle().apply {
                    putInt(ARG_MAX_SELECTION, maxSelection)
                    putString(ARG_LANGUAGE_CODE, languageCode)
                    putBoolean(ARG_ENABLE_EDITOR, enableEditor)
                    putBoolean(ARG_PROFILE_MODE, profileMode)
                    putInt(ARG_MAX_WIDTH, maxWidth)
                    putInt(ARG_MAX_HEIGHT, maxHeight)
                    putString(ARG_THEME_COLOR, themeColor)
                }
            }
        }
    }

    private var maxSelection: Int = 1
    private var languageCode: String = "en"
    private var enableEditor: Boolean = true
    private var profileMode: Boolean = false
    private var maxWidth: Int = 1024
    private var maxHeight: Int = 1024
    
    private var lastEditorLaunchTime = 0L
    private var themeColor: Int? = null
    private var imageRecyclerView: RecyclerView? = null
    private var adapter: ImageGridAdapter? = null
    private var closeButton: ImageButton? = null
    private var albumTitleLayout: View? = null
    private var albumTitleText: TextView? = null
    private var tabContainer: FrameLayout? = null
    private var tabActiveIndicator: View? = null
    private var allTabButton: TextView? = null
    private var selectedCountTab: TextView? = null
    private var doneButton: TextView? = null
    private var selectedCountLayout: View? = null
    private var selectedCountText: TextView? = null
    private var loadingIndicator: View? = null
    
    private var selectedImages: List<Uri> = emptyList()
    private var editedImages = mutableMapOf<String, Uri>()
    private var onImagesSelected: ((List<Uri>) -> Unit)? = null
    private var onCancelled: (() -> Unit)? = null
    private var onDismissed: (() -> Unit)? = null
    private var isExplicitlyCancelled = false
    private var isShowingOnlySelected = false // Filter mode: showing only selected images
    private var isBehaviorInitialized = false
    
    private var behavior: BottomSheetBehavior<FrameLayout>? = null
    private var imagesLoaded = false
    private var bottomSheetView: FrameLayout? = null
    private var headerView: View? = null
    private var maxCornerRadius: Float = 0f
    private var rootContentView: View? = null // Root content view (from onCreateView)
    private var recyclerViewContainer: ViewGroup? = null // RecyclerView's parent FrameLayout
    
    // Store original padding values to restore correctly
    private var originalPadding: Int = 0
    private var currentTopPadding: Int = 0
    private var selectedCountHeight: Int = 0
    private var deviceStatusBarHeight: Int = 0

    private fun applyHeaderInsets(height: Int) {
        // 1. Adjust header padding so contents sit below status bar.
        // We no longer manipulate height manually since headerLayout is wrap_content with a fixed 48dp inner container.
        headerView?.let { header ->
            header.setPadding(
                header.paddingLeft,
                height,
                header.paddingRight,
                header.paddingBottom
            )
        }
        
        // 2. Expand gradient behind status bar
        val gradient = view?.findViewById<View>(R.id.topbarGradient)
        gradient?.let {
            val params = it.layoutParams
            val baseHeightPx = (48 * resources.displayMetrics.density).toInt()
            params.height = baseHeightPx + height
            it.layoutParams = params
        }
        
        // 3. Add top padding to RecyclerView so images can scroll under header and status bar
        val basePadding = (2 * resources.displayMetrics.density).toInt()
        val headerHeightPx = (48 * resources.displayMetrics.density).toInt()
        
        currentTopPadding = basePadding + headerHeightPx + height
        
        imageRecyclerView?.let { recyclerView ->
            recyclerView.setPadding(
                basePadding,
                currentTopPadding,
                basePadding,
                basePadding
            )
        }
    }
    
    // Track current image count for background adjustment
    private var currentImageCount: Int = 0
    private var allImagesCount: Int = 0 // Store total images count when loaded
    
    // Store all currently loaded image URIs for the editor (iOS: shows all album photos in editor)
    private var allLoadedImages: List<Uri> = emptyList()
    
    // Quick Scroller: Store images with dates
    private var imagesWithDates: List<ImageWithDate> = emptyList()
    
    // Quick Scroller UI components
    private var scrollBarTrack: View? = null
    private var scrollBarThumb: View? = null
    private var scrollBarThumbVisual: View? = null
    private var scrollBarTrackVisual: View? = null
    private var dateScrollIndicator: FrameLayout? = null
    private var dateLabel: TextView? = null
    
    // Quick Scroller state
    private var isDraggingScrollBar = false
    private var scrollBarThumbTopMargin = 0
    private var dateHideTimer: android.os.Handler? = null
    private var dateHideRunnable: Runnable? = null
    private var lastHapticDate: String = ""
    
    // Performance optimization
    private var isQuickScrolling = false
    private var isFastScrolling = false // Very fast scroll (drag) mode

    private var lastDateUpdateTime = 0L
    private val DATE_UPDATE_THROTTLE_MS = 100L // Update date at most every 100ms (optimized from 50ms)
    
    // Scroll velocity tracking
    private var lastScrollTime = 0L
    private var lastScrollY = 0
    
    // Quick scroller pause detection
    private var lastMoveTime = 0L
    private var pauseCheckRunnable: Runnable? = null
    private val PAUSE_DETECTION_DELAY = 120L
    
    // Periodic image loading during quick scroll
    private var lastImageLoadTime = 0L
    private val IMAGE_LOAD_INTERVAL = 100L
    private var lastDragDistance = 0f
    private var dragVelocity = 0f
    private val FAST_DRAG_THRESHOLD = 50f
    
    // Date formatting cache to avoid repeated SimpleDateFormat creation
    private var cachedDateFormat: SimpleDateFormat? = null
    
    // Flag to prevent reentrant dismiss calls
    private var isDismissing = false
    
    // Flag to track if callback has been invoked (prevent double invocation)
    private var hasInvokedCallback = false
    private var isCameraCurrentlyBound = false
    private var currentCameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
    private var currentCamera: Camera? = null
    
    // Track running animations
    private var runningFadeOutAnimator: ValueAnimator? = null
    private var runningFadeInAnimator: ValueAnimator? = null
    
    private var cameraOverlay: CameraExpandOverlay? = null
    private val backPressedCallback = object : androidx.activity.OnBackPressedCallback(false) {
        override fun handleOnBackPressed() {
            cameraOverlay?.startShrinkAnimation()
        }
    }
    
    // Camera
    private var cameraImageUri: Uri? = null
    private var cameraImageFile: File? = null
    private var imageCapture: ImageCapture? = null
    private var currentPreview: Preview? = null

    private var flashMode: Int = androidx.camera.core.ImageCapture.FLASH_MODE_OFF
    private val cameraLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            cameraImageFile?.let { file ->
                // Save image to MediaStore and get URI
                scope.launch {
                    try {
                        val savedUri = withContext(Dispatchers.IO) {
                            saveImageToMediaStore(file)
                        }
                        
                        savedUri?.let { uri ->
                            Log.d(TAG, "Camera photo saved to MediaStore: $uri")
                            if (!hasInvokedCallback) {
                                if (profileMode) {
                                    launchProfileCrop(uri)
                                } else if (enableEditor) {
                                    launchEditor(uri, 0)
                                } else {
                                    hasInvokedCallback = true
                                    val capturedImages = listOf(uri)
                                    onImagesSelected?.invoke(capturedImages)
                                    dismissWithAnimation()
                                }
                            }
                        } ?: run {
                            // Fallback to original file URI if MediaStore save fails
                            cameraImageUri?.let { uri ->
                                if (!hasInvokedCallback) {
                                    Log.d(TAG, "Camera photo captured (fallback): $uri")
                                    if (profileMode) {
                                        launchProfileCrop(uri)
                                    } else if (enableEditor) {
                                        launchEditor(uri, 0)
                                    } else {
                                        hasInvokedCallback = true
                                        val capturedImages = listOf(uri)
                                        onImagesSelected?.invoke(capturedImages)
                                        dismissWithAnimation()
                                    }
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error saving camera image to MediaStore", e)
                        // Fallback to original file URI
                        cameraImageUri?.let { uri ->
                            if (!hasInvokedCallback) {
                                if (profileMode) {
                                    launchProfileCrop(uri)
                                } else if (enableEditor) {
                                    launchEditor(uri, 0)
                                } else {
                                    hasInvokedCallback = true
                                    val capturedImages = listOf(uri)
                                    onImagesSelected?.invoke(capturedImages)
                                    dismissWithAnimation()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private val cameraPermissionLauncher = registerForActivityResult(ActivityResultContracts.RequestPermission()) { isGranted ->
        if (isGranted) {
            // Notify adapter to rebind the camera cell with live preview
            adapter?.notifyItemChanged(0)
            
            // Also if they just tapped the cell and triggered the permission prompt,
            // we should probably capture the image. But it might be safer to let them tap again 
            // once they see the live preview.
        } else {
            Log.w(TAG, "Camera permission denied")
        }
    }

    private fun handleDeselectEditedImage(uri: Uri, onConfirm: () -> Unit) {
        android.app.AlertDialog.Builder(requireContext())
            .setMessage(R.string.delete_edits_message)
            .setPositiveButton(R.string.yes) { _, _ ->
                editedImages.remove(uri.toString())
                onConfirm()
            }
            .setNegativeButton(R.string.no, null)
            .show()
    }

    // Editor Activity launcher
    private val editorLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val shouldDismiss = result.resultCode == android.app.Activity.RESULT_OK &&
                            result.data?.getStringExtra(ImageEditorActivity.EXTRA_RESULT_URI) != null &&
                            maxSelection <= 1

        if (!shouldDismiss) {
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                behavior?.isHideable = true
                if (behavior?.state == BottomSheetBehavior.STATE_HIDDEN) {
                    behavior?.state = BottomSheetBehavior.STATE_EXPANDED
                }
            }, 500)
        }

        if (result.resultCode == android.app.Activity.RESULT_OK) {
            val resultUriStr = result.data?.getStringExtra(ImageEditorActivity.EXTRA_RESULT_URI)
            val resultUrisStrings = result.data?.getStringArrayListExtra(ImageEditorActivity.EXTRA_RESULT_URIS)
            val originalUrisStrings = result.data?.getStringArrayListExtra(ImageEditorActivity.EXTRA_ORIGINAL_URIS)
            val resultSelectedUrisStrings = result.data?.getStringArrayListExtra(ImageEditorActivity.EXTRA_RESULT_SELECTED_URIS)
            
            if (resultUriStr != null) {
                if (maxSelection > 1) {
                    // Multi-select mode: Keep gallery open, update edited images
                    if (resultUrisStrings != null && originalUrisStrings != null) {
                        for (i in resultUrisStrings.indices) {
                            val originalUriStr = originalUrisStrings.getOrNull(i)
                            val editedUriStr = resultUrisStrings.getOrNull(i)
                            if (originalUriStr != null && editedUriStr != null && originalUriStr != editedUriStr) {
                                editedImages[originalUriStr] = android.net.Uri.parse(editedUriStr)
                            }
                        }
                    }
                    
                    val newSelection = mutableListOf<android.net.Uri>()
                    if (resultSelectedUrisStrings != null) {
                        resultSelectedUrisStrings.forEach {
                            newSelection.add(android.net.Uri.parse(it))
                        }
                    } else {
                        // Fallback: Add the original URIs to selection if not already selected
                        newSelection.addAll(selectedImages)
                        originalUrisStrings?.forEach { origStr ->
                            val origUri = android.net.Uri.parse(origStr)
                            if (!newSelection.contains(origUri)) {
                                newSelection.add(origUri)
                            }
                        }
                    }
                    
                    selectedImages = newSelection
                    adapter?.updateEditedImages(editedImages, notify = false)
                    adapter?.setSelectedImages(newSelection, notify = false)
                    
                    // Determine the item currently returning from the editor
                    val currentReturningUriStr = result.data?.getStringExtra(ImageEditorActivity.EXTRA_RESULT_URI)
                    var origOfCurrent: String? = null
                    if (currentReturningUriStr != null && resultUrisStrings != null && originalUrisStrings != null) {
                        val idx = resultUrisStrings.indexOf(currentReturningUriStr)
                        if (idx != -1 && idx < originalUrisStrings.size) {
                            origOfCurrent = originalUrisStrings[idx]
                        } else {
                            origOfCurrent = currentReturningUriStr
                        }
                    } else if (currentReturningUriStr != null) {
                        origOfCurrent = currentReturningUriStr
                    }
                    
                    val returningPos = if (origOfCurrent != null) adapter?.getPositionForUri(origOfCurrent) ?: -1 else -1

                    // Find holder and apply bitmap BEFORE notifying the adapter, otherwise the view gets invalidated and returns null
                    var didApplyBitmap = false
                    if (returningPos >= 0) {
                        val holder = imageRecyclerView?.findViewHolderForAdapterPosition(returningPos) as? com.rnturboimagepicker.ImageGridAdapter.ImageViewHolder
                        if (holder != null && TransitionHelper.editedBitmap != null) {
                            holder.imageView.setImageBitmap(TransitionHelper.editedBitmap)
                            holder.placeholderIcon.visibility = android.view.View.GONE
                            didApplyBitmap = true
                        }
                    }

                    val itemCount = adapter?.itemCount ?: 0
                    if (itemCount > 0) {
                        // Notify EDIT_CHANGED for everything EXCEPT the returning item
                        for (i in 0 until itemCount) {
                            if (i != returningPos) {
                                adapter?.notifyItemChanged(i, "EDIT_CHANGED")
                            }
                        }
                        
                        if (!didApplyBitmap && returningPos >= 0) {
                            // If holder was not visible or bitmap was null, fall back to Glide
                            adapter?.notifyItemChanged(returningPos, "EDIT_CHANGED")
                        }

                        // Update selection badges for all items
                        adapter?.notifyItemRangeChanged(0, itemCount, "SELECTION_CHANGED")
                    }
                    
                    TransitionHelper.editedBitmap = null
                    updateSelectionUI(newSelection.size)
                } else {
                    // Single-select mode: Send directly
                    hasInvokedCallback = true
                    
                    // Update the adapter so the return animation uses the edited image
                    if (resultUrisStrings != null && originalUrisStrings != null) {
                        for (i in resultUrisStrings.indices) {
                            val orig = originalUrisStrings.getOrNull(i)
                            val res = resultUrisStrings.getOrNull(i)
                            if (orig != null && res != null && orig != res) {
                                editedImages[orig] = android.net.Uri.parse(res)
                            }
                        }
                        adapter?.updateEditedImages(editedImages, notify = false)
                        
                        // Try to apply instantly to prevent flicker
                        val orig = originalUrisStrings.firstOrNull()
                        if (orig != null) {
                            val pos = adapter?.getPositionForUri(orig) ?: -1
                            if (pos >= 0) {
                                val holder = imageRecyclerView?.findViewHolderForAdapterPosition(pos) as? com.rnturboimagepicker.ImageGridAdapter.ImageViewHolder
                                if (holder != null && TransitionHelper.editedBitmap != null) {
                                    holder.imageView.setImageBitmap(TransitionHelper.editedBitmap)
                                    holder.placeholderIcon.visibility = android.view.View.GONE
                                } else {
                                    adapter?.notifyItemChanged(pos, "EDIT_CHANGED")
                                }
                            }
                        }
                    } else if (resultUriStr != null && originalUrisStrings != null && originalUrisStrings.isNotEmpty()) {
                        val orig = originalUrisStrings.first()
                        if (orig != resultUriStr) {
                            editedImages[orig] = android.net.Uri.parse(resultUriStr)
                            adapter?.updateEditedImages(editedImages, notify = false)
                            
                            val pos = adapter?.getPositionForUri(orig) ?: -1
                            if (pos >= 0) {
                                val holder = imageRecyclerView?.findViewHolderForAdapterPosition(pos) as? com.rnturboimagepicker.ImageGridAdapter.ImageViewHolder
                                if (holder != null && TransitionHelper.editedBitmap != null) {
                                    holder.imageView.setImageBitmap(TransitionHelper.editedBitmap)
                                    holder.placeholderIcon.visibility = android.view.View.GONE
                                } else {
                                    adapter?.notifyItemChanged(pos, "EDIT_CHANGED")
                                }
                            }
                        }
                    }
                    if (resultUrisStrings != null && resultUrisStrings.isNotEmpty()) {
                        val finalList = resultUrisStrings.map { android.net.Uri.parse(it) }
                        onImagesSelected?.invoke(finalList.toList())
                    } else {
                        val singleUri = android.net.Uri.parse(resultUriStr)
                        onImagesSelected?.invoke(listOf(singleUri))
                    }
                    
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        dismissWithAnimation()
                    }, 400)
                }
            }
        } else {
            // User pressed back in editor → reset flag so they can select again
            hasInvokedCallback = false
            
            val resultSelectedUrisStrings = result.data?.getStringArrayListExtra(ImageEditorActivity.EXTRA_RESULT_SELECTED_URIS)
            
            // If single selection mode, clear the selection when returning from editor
            if (maxSelection == 0 || maxSelection == 1) {
                selectedImages = emptyList()
                adapter?.clearSelection()
                updateSelectionUI(0)
            } else if (resultSelectedUrisStrings != null) {
                val newSelection = mutableListOf<android.net.Uri>()
                resultSelectedUrisStrings.forEach {
                    newSelection.add(android.net.Uri.parse(it))
                }
                selectedImages = newSelection
                adapter?.setSelectedImages(newSelection, notify = false)
                val itemCount = adapter?.itemCount ?: 0
                if (itemCount > 0) {
                    adapter?.notifyItemRangeChanged(0, itemCount, "SELECTION_CHANGED")
                }
                updateSelectionUI(newSelection.size)
            }
        }
        TransitionHelper.editedBitmap = null
    }
    private val profileCropLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val croppedUriStr = result.data?.getStringExtra(ProfileCropActivity.EXTRA_CROPPED_URI)
        val editorUris = result.data?.getStringArrayListExtra(ImageEditorActivity.EXTRA_RESULT_URIS)
        val editorSingleUri = result.data?.getStringExtra(ImageEditorActivity.EXTRA_RESULT_URI)

        val shouldDismiss = result.resultCode == android.app.Activity.RESULT_OK &&
                            (croppedUriStr != null || !editorUris.isNullOrEmpty() || editorSingleUri != null)

        if (!shouldDismiss) {
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                behavior?.isHideable = true
                if (behavior?.state == BottomSheetBehavior.STATE_HIDDEN) {
                    behavior?.state = BottomSheetBehavior.STATE_EXPANDED
                }
            }, 500)
        }

        if (result.resultCode == android.app.Activity.RESULT_OK) {
            if (!editorUris.isNullOrEmpty()) {
                hasInvokedCallback = true
                onImagesSelected?.invoke(editorUris.map { android.net.Uri.parse(it) })
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    dismissWithAnimation()
                }, 400)
            } else if (editorSingleUri != null) {
                hasInvokedCallback = true
                onImagesSelected?.invoke(listOf(android.net.Uri.parse(editorSingleUri)))
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    dismissWithAnimation()
                }, 400)
            } else if (croppedUriStr != null) {
                val uri = android.net.Uri.parse(croppedUriStr)
                hasInvokedCallback = true
                onImagesSelected?.invoke(listOf(uri))
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    dismissWithAnimation()
                }, 400)
            }
        } else {
            hasInvokedCallback = false
            if (maxSelection == 0 || maxSelection == 1) {
                selectedImages = emptyList()
                adapter?.clearSelection()
                updateSelectionUI(0)
            }
        }
    }

    private fun launchProfileCrop(uri: Uri) {
        val currentTime = android.os.SystemClock.elapsedRealtime()
        if (currentTime - lastEditorLaunchTime < 1000) {
            return
        }
        lastEditorLaunchTime = currentTime
        
        behavior?.isHideable = false
        val intent = Intent(requireContext(), ProfileCropActivity::class.java).apply {
            putExtra(ProfileCropActivity.EXTRA_SOURCE_URI, uri.toString())
            putExtra(ProfileCropActivity.EXTRA_MAX_WIDTH, maxWidth)
            putExtra(ProfileCropActivity.EXTRA_MAX_HEIGHT, maxHeight)
            putExtra("enable_editor", enableEditor)
            themeColor?.let { putExtra(ProfileCropActivity.EXTRA_THEME_COLOR, String.format("#%06X", 0xFFFFFF and it)) }
        }
        profileCropLauncher.launch(intent)
        requireActivity().overridePendingTransition(R.anim.slide_in_bottom, R.anim.no_animation)
    }
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onCreateDialog(savedInstanceState: Bundle?): android.app.Dialog {
        return object : com.google.android.material.bottomsheet.BottomSheetDialog(requireContext(), theme) {
            private var velocityTracker: android.view.VelocityTracker? = null
            private var flingRunnable: Runnable? = null
            private var reenableScrollRunnable: Runnable? = null
            private var isTouchInRecyclerView = false

            override fun dispatchTouchEvent(event: android.view.MotionEvent): Boolean {
                if (velocityTracker == null) {
                    velocityTracker = android.view.VelocityTracker.obtain()
                }
                
                when (event.actionMasked) {
                    android.view.MotionEvent.ACTION_DOWN -> {
                        velocityTracker?.clear()
                        velocityTracker?.addMovement(event)
                        
                        // Cancel any pending fling or scroll disable tasks
                        flingRunnable?.let { imageRecyclerView?.removeCallbacks(it) }
                        reenableScrollRunnable?.let { imageRecyclerView?.removeCallbacks(it) }
                        flingRunnable = null
                        reenableScrollRunnable = null
                        
                        // Check if the touch is inside the RecyclerView
                        val rect = android.graphics.Rect()
                        imageRecyclerView?.getGlobalVisibleRect(rect)
                        isTouchInRecyclerView = rect.contains(event.rawX.toInt(), event.rawY.toInt())
                        
                        // User touched the screen, re-enable nested scrolling immediately
                        // so that if they drag down, BottomSheetBehavior can collapse
                        imageRecyclerView?.isNestedScrollingEnabled = true
                    }
                    android.view.MotionEvent.ACTION_MOVE -> {
                        velocityTracker?.addMovement(event)
                    }
                    android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> {
                        velocityTracker?.addMovement(event)
                        velocityTracker?.computeCurrentVelocity(1000)
                        val yVel = velocityTracker?.yVelocity ?: 0f
                        
                        if (yVel < -500 && (behavior?.state == com.google.android.material.bottomsheet.BottomSheetBehavior.STATE_COLLAPSED || behavior?.state == com.google.android.material.bottomsheet.BottomSheetBehavior.STATE_DRAGGING)) {
                            behavior?.state = com.google.android.material.bottomsheet.BottomSheetBehavior.STATE_EXPANDED
                            
                            if (isTouchInRecyclerView) {
                                imageRecyclerView?.isNestedScrollingEnabled = false
                                
                                flingRunnable = Runnable {
                                    imageRecyclerView?.fling(0, (-yVel * 0.5f).toInt())
                                    reenableScrollRunnable = Runnable {
                                        imageRecyclerView?.isNestedScrollingEnabled = true
                                    }
                                    imageRecyclerView?.postDelayed(reenableScrollRunnable, 400)
                                }
                                imageRecyclerView?.postDelayed(flingRunnable, 10)
                            }
                        }
                        
                        velocityTracker?.clear()
                    }
                }
                
                return super.dispatchTouchEvent(event)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Reset all state when Fragment is created/recreated
        maxSelection = arguments?.getInt(ARG_MAX_SELECTION, 1) ?: 1
        languageCode = arguments?.getString(ARG_LANGUAGE_CODE, "en") ?: "en"
        enableEditor = arguments?.getBoolean(ARG_ENABLE_EDITOR, true) ?: true
        profileMode = arguments?.getBoolean(ARG_PROFILE_MODE, false) ?: false
        maxWidth = arguments?.getInt(ARG_MAX_WIDTH, 1024) ?: 1024
        maxHeight = arguments?.getInt(ARG_MAX_HEIGHT, 1024) ?: 1024
        
        val themeColorStr = arguments?.getString(ARG_THEME_COLOR)
        themeColor = try {
            if (!themeColorStr.isNullOrEmpty()) {
                try {
                    android.graphics.Color.parseColor(themeColorStr)
                } catch (e: IllegalArgumentException) {
                    android.graphics.Color.parseColor(if (!themeColorStr.startsWith("#")) "#$themeColorStr" else themeColorStr)
                }
            } else null
        } catch (e: Exception) {
            null
        }
        
        selectedImages = emptyList()
        imagesLoaded = false
        originalPadding = 0
        selectedCountHeight = 0
        isExplicitlyCancelled = false
        
        // Set locale based on language code
        setLocale(languageCode)
        
        // Set bottom sheet style
        setStyle(STYLE_NORMAL, R.style.BottomSheetDialogTheme)
        
        Log.d(TAG, "onCreate: maxSelection=$maxSelection, languageCode=$languageCode")
    }
    
    private fun setLocale(languageCode: String) {
        try {
            val locale = Locale(languageCode)
            Locale.setDefault(locale)
            val config = Configuration()
            config.setLocale(locale)
            val context = requireContext().createConfigurationContext(config)
            resources.updateConfiguration(config, resources.displayMetrics)
        } catch (e: Exception) {
            Log.e(TAG, "Error setting locale: ${e.message}", e)
        }
    }
    
    override fun getTheme(): Int {
        return R.style.BottomSheetDialogTheme
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        Log.d(TAG, "onCreateView")
        // Create configuration context with locale before inflating
        val config = Configuration(resources.configuration)
        config.setLocale(Locale(languageCode))
        val context = requireContext().createConfigurationContext(config)
        val localizedInflater = inflater.cloneInContext(context)
        val view = localizedInflater.inflate(R.layout.bottom_sheet_image_picker, container, false)
        rootContentView = view
        return view
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        Log.d(TAG, "onViewCreated")
        
        imageRecyclerView = view.findViewById(R.id.imageRecyclerView)
        closeButton = view.findViewById(R.id.closeButton)
        albumTitleLayout = view.findViewById(R.id.albumTitleLayout)
        albumTitleText = view.findViewById(R.id.albumTitleText)
        tabContainer = view.findViewById(R.id.tabContainer)
        tabActiveIndicator = view.findViewById(R.id.tabActiveIndicator)
        allTabButton = view.findViewById(R.id.allTabButton)
        selectedCountTab = view.findViewById(R.id.selectedCountTab)
        headerView = view.findViewById(R.id.headerLayout)
        doneButton = view.findViewById(R.id.doneButton)
        selectedCountLayout = view.findViewById(R.id.selectedCountLayout)
        selectedCountText = view.findViewById(R.id.selectedCountText)
        loadingIndicator = view.findViewById(R.id.loadingIndicator)
        
        // Quick Scroller UI
        scrollBarTrack = view.findViewById(R.id.scrollBarTrack)
        scrollBarThumb = view.findViewById(R.id.scrollBarThumb)
        scrollBarThumbVisual = view.findViewById(R.id.scrollBarThumbVisual)
        scrollBarTrackVisual = view.findViewById(R.id.scrollBarTrackVisual)
        dateScrollIndicator = view.findViewById(R.id.dateScrollIndicator)
        dateLabel = view.findViewById(R.id.dateLabel)
        
        // Get RecyclerView's parent FrameLayout container
        recyclerViewContainer = view.findViewById<ViewGroup>(R.id.recyclerViewContainer)
        
        // Log scrollbar view info
        scrollBarTrack?.post {
            Log.d(TAG, "ScrollBar Track: size=${scrollBarTrack?.width}x${scrollBarTrack?.height}, " +
                      "visible=${scrollBarTrack?.visibility}, clickable=${scrollBarTrack?.isClickable}, " +
                      "alpha=${scrollBarTrack?.alpha}")
        }
        scrollBarThumb?.post {
            Log.d(TAG, "ScrollBar Thumb: size=${scrollBarThumb?.width}x${scrollBarThumb?.height}, " +
                      "visible=${scrollBarThumb?.visibility}, clickable=${scrollBarThumb?.isClickable}, " +
                      "alpha=${scrollBarThumb?.alpha}")
        }
        
        // Initialize quick scroller (after views are laid out)
        view.post {
            setupQuickScroller()
        }
        
        // Initialize tab active indicator to all tab position
        initTabIndicator()

        // Setup album title click to show album list (original UI)
        albumTitleLayout?.setOnClickListener {
            showAlbumPickerDialog()
        }
        
        // Setup all tab click (new UI - toggle filter back to all)
        allTabButton?.setOnClickListener {
            if (isShowingOnlySelected) {
                // Switch back to all images view
                switchToAllImagesView()
            }
        }

        // Setup selected count tab click to toggle filter
        selectedCountTab?.setOnClickListener {
            if (isShowingOnlySelected) {
                // Switch back to all images view
                switchToAllImagesView()
            } else {
                // Switch to selected images only view
                switchToSelectedImagesView()
            }
        }

        // Setup close button
        closeButton?.setOnClickListener {
            isExplicitlyCancelled = true
            dismissWithAnimation()
        }


        doneButton?.setOnClickListener {
            if (selectedImages.isNotEmpty() && !hasInvokedCallback) {
                // Only launch editor if it's single selection mode AND editor is enabled
                if (enableEditor && maxSelection <= 1) {
                    val themeColorStr = arguments?.getString(ARG_THEME_COLOR)
                    val imageListToPass = selectedImages.toList()
                    val startIndex = 0
                    
                    val intent = ImageEditorActivity.createIntent(
                        requireActivity(),
                        imageListToPass,
                        startIndex = startIndex,
                        themeColor = themeColorStr,
                        selectedUris = LinkedHashSet(selectedImages),
                        editedUris = editedImages,
                        singlePhotoMode = true,
                        maxWidth = maxWidth,
                        maxHeight = maxHeight
                    )
                    editorLauncher.launch(intent)
                    requireActivity().overridePendingTransition(R.anim.slide_in_bottom, R.anim.no_animation)
                } else {

                    hasInvokedCallback = true
                    
                    // Map selected images to their edited versions if they exist
                    val mappedImages = selectedImages.map { uri ->
                        editedImages[uri.toString()] ?: uri
                    }
                    
                    onImagesSelected?.invoke(mappedImages)
                    dismissWithAnimation()
                }
            }
        }
        
        // Apply theme color to done button if provided
        themeColor?.let { color ->
            doneButton?.backgroundTintList = android.content.res.ColorStateList.valueOf(color)
        }

        val spanCount = 3
        // Always recalculate original padding values to ensure consistency
        // This is critical when Fragment is reused - padding must be reset from XML default
        val xmlPadding = (2 * resources.displayMetrics.density).toInt() // Original padding from XML (2dp)
        originalPadding = xmlPadding
        selectedCountHeight = (48 * resources.displayMetrics.density).toInt() // Selected count layout height (48dp)
        
        imageRecyclerView?.apply {
            // Set up scroll listener for quick scroller (moved to setupQuickScroller)
            // CRITICAL: Always reset padding to XML default when view is created/recreated
            // This ensures padding is correct when BottomSheet is reopened after being closed
            // The view might have had its padding modified in a previous session
            setPadding(xmlPadding, xmlPadding + (48 * resources.displayMetrics.density).toInt(), xmlPadding, xmlPadding)
            
            // Ensure clipToPadding is false so padding area is scrollable
            clipToPadding = false
            
            // Force initial layout calculation to ensure padding is applied
            post {
                requestLayout()
            }
            
            layoutManager = StaggeredGridLayoutManager(spanCount, StaggeredGridLayoutManager.VERTICAL).apply {
                // Enable item prefetching for smoother scrolling
                isItemPrefetchEnabled = true
            }
            
            // Performance optimizations for large datasets (10,000+ items)
            setHasFixedSize(false) // Allow size changes for dynamic padding
            
            // Aggressively recycle views to trigger Glide.clear() immediately!
            // Optimize view cache: keep it small so off-screen views are recycled quickly,
            // which allows Glide to cancel their image loading tasks. A large cache (e.g. 20)
            // keeps off-screen images loading, wasting CPU and causing thermal throttling.
            setItemViewCacheSize(4) 
            recycledViewPool.setMaxRecycledViews(0, 40) // Increased pool size
            
            // Enable nested scrolling for proper CoordinatorLayout behavior
            isNestedScrollingEnabled = true
            
            // Disable overscroll to prevent it from eating nested scroll events at the top
            overScrollMode = View.OVER_SCROLL_NEVER
            
            // Reduce overdraw
            setWillNotDraw(false)
            
            // Enable hardware acceleration for smoother scrolling
            setLayerType(View.LAYER_TYPE_HARDWARE, null)
            
            // Optimize touch handling during scroll
            descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
            
            // Disable item animator to prevent flickering when items change
            // This eliminates the flash/blink when initial images load and when updating images
            itemAnimator = null
        }
        
        // Reset state when view is created/recreated
        // Do NOT clear selectedImages here as it will be lost on fragment recreation!
        imagesLoaded = false
        currentImageCount = 0
        allImagesCount = 0
        
        // Show RecyclerView immediately (will show placeholders until images load)
        imageRecyclerView?.visibility = View.VISIBLE
        loadingIndicator?.visibility = View.GONE
        
        // Initialize UI state with original padding
        updateSelectionUI(0)
        
        // Handle Edge-to-Edge Window Insets
        // In a BottomSheet, window insets might be consumed by the CoordinatorLayout
        val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
        if (resourceId > 0) {
            deviceStatusBarHeight = resources.getDimensionPixelSize(resourceId)
        }
        
        // Start with 0 padding for collapsed state
        applyHeaderInsets(0)

        androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(view) { _, insets ->
            val insetsTop = insets.getInsets(androidx.core.view.WindowInsetsCompat.Type.statusBars()).top
            if (insetsTop > 0 && insetsTop != deviceStatusBarHeight) {
                deviceStatusBarHeight = insetsTop
            }
            insets
        }

        // Load ALL images at once to completely eliminate flickering
        // This is the only way to guarantee no visual glitches
        loadAllImages()
    }
    
    override fun onStart() {
        super.onStart()
        
        Log.d(TAG, "onStart")
        
        // Ensure padding is reset every time BottomSheet is shown
        // This handles the case when Fragment is reused
        // Initialize padding values if not already set
        if (originalPadding == 0) {
            originalPadding = (2 * resources.displayMetrics.density).toInt()
            selectedCountHeight = (48 * resources.displayMetrics.density).toInt()
        }
        
        // Force layout recalculation to ensure padding is properly applied
        imageRecyclerView?.let { recyclerView ->
            recyclerView.post {
                recyclerView.requestLayout()
            }
            // Reset UI state to ensure correct padding
            updateSelectionUI(selectedImages.size)
        }
        
        // Configure BottomSheetDialog
        val dialog = dialog as? BottomSheetDialog ?: return
        
        // Enable cancel on back press
        dialog.setCancelable(true)
        dialog.setCanceledOnTouchOutside(false) // Only cancel on back press, not on outside touch
        
        // Intercept back button to use animation dismiss
        dialog.setOnKeyListener { _, keyCode, event ->
            if (keyCode == android.view.KeyEvent.KEYCODE_BACK && event.action == android.view.KeyEvent.ACTION_UP) {
                // Mark as explicitly cancelled (back button press)
                isExplicitlyCancelled = true
                // Use animated dismiss instead of instant dismiss
                dismissWithAnimation()
                true // Consume the event
            } else {
                false
            }
        }
        
        // Find the bottom sheet view
        val bottomSheet = dialog.findViewById<FrameLayout>(
            com.google.android.material.R.id.design_bottom_sheet
        ) ?: return
        
        // Fix: Force bottom sheet to match_parent so it doesn't leave a transparent gap at the bottom
        // when the gallery has only a few images.
        bottomSheet.layoutParams?.let { params ->
            params.height = android.view.ViewGroup.LayoutParams.MATCH_PARENT
            bottomSheet.layoutParams = params
        }
        
        // Disable fitsSystemWindows so the bottom sheet can draw behind the status bar
        val coordinator = bottomSheet.parent as? ViewGroup
        coordinator?.fitsSystemWindows = false
        bottomSheet.fitsSystemWindows = false
        
        // Also disable fitsSystemWindows on the root container
        val container = dialog.findViewById<View>(com.google.android.material.R.id.container)
        container?.fitsSystemWindows = false
        
        bottomSheetView = bottomSheet
        
        // Get the behavior
        behavior = BottomSheetBehavior.from(bottomSheet)
        
        // Disable dim to prevent flickering when dismissing
        // We'll handle dim animation ourselves if needed
        dialog.window?.let { window ->
            // Use FLAG_LAYOUT_NO_LIMITS to forcefully draw behind status bar
            window.setFlags(
                android.view.WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                android.view.WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            )
            androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
            window.setDimAmount(0f)
            window.statusBarColor = android.graphics.Color.TRANSPARENT
            window.navigationBarColor = android.graphics.Color.TRANSPARENT
            // Configure navigation bar for light mode
            configureNavigationBar(window)
            
            // Also ensure the decor view does not fit system windows
            window.decorView.fitsSystemWindows = false
            
            // Recursively disable fitsSystemWindows on all parents
            var parent = bottomSheet.parent as? View
            while (parent != null) {
                parent.fitsSystemWindows = false
                parent = parent.parent as? View
            }
        }
        
        // Get max corner radius
        maxCornerRadius = resources.getDimension(R.dimen.bottom_sheet_corner_radius)
        
        // Set initial background with corner radius
        updateCornerRadius(maxCornerRadius)
        
        // Calculate peek height (60% of screen height for initial view)
        val screenHeight = Resources.getSystem().displayMetrics.heightPixels
        val peekHeight = (screenHeight * 0.6).toInt()
        
        Log.d(TAG, "Screen height: $screenHeight, Peek height: $peekHeight")
        
        if (isBehaviorInitialized) {
            return
        }
        isBehaviorInitialized = true
        
        // Configure behavior for smooth bottom sheet animation
        behavior?.apply {
            // Set peek height first
            this.peekHeight = peekHeight
            
            // Disable fitToContents to use peekHeight, and skip half-expanded state
            isFitToContents = false
            expandedOffset = 0
            skipCollapsed = false
            
            // Disable half-expanded state (50%) - only use collapsed (60%) and expanded (100%)
            halfExpandedRatio = 0.6f
            
            // Enable smooth slide up animation
            isHideable = true
            isDraggable = true
            
            // Start with hidden state below the screen
            state = BottomSheetBehavior.STATE_HIDDEN
            
            // Wait for layout to complete before animating up
            bottomSheet.viewTreeObserver.addOnGlobalLayoutListener(object : ViewTreeObserver.OnGlobalLayoutListener {
                override fun onGlobalLayout() {
                    bottomSheet.viewTreeObserver.removeOnGlobalLayoutListener(this)
                    // Post to next frame to guarantee the initial HIDDEN state is measured first,
                    // which is absolutely necessary for the slide-up animation to trigger.
                    bottomSheet.post {
                        state = BottomSheetBehavior.STATE_COLLAPSED
                    }
                }
            })
            
            // Add callback to handle state changes
            addBottomSheetCallback(object : BottomSheetBehavior.BottomSheetCallback() {
                override fun onStateChanged(bottomSheet: View, newState: Int) {
                    when (newState) {
                        BottomSheetBehavior.STATE_HIDDEN -> {
                            Log.d(TAG, "Bottom sheet STATE_HIDDEN - dismissing dialog")
                            // Bottom sheet is hidden, now dismiss the dialog
                            behavior?.removeBottomSheetCallback(this)
                            
                            // If dismissed by swipe (not by done button), mark as explicitly cancelled
                            // This prevents returning selected images when user swipes to close
                            if (!hasInvokedCallback && !isExplicitlyCancelled) {
                                // User swiped down to dismiss - treat as cancellation
                                isExplicitlyCancelled = true
                            }
                            
                            if (!isDismissing) {
                                isDismissing = true
                                // Wait a bit for slide-down animation to complete visually
                                // before dismissing dialog. This ensures smooth transition to RN.
                                bottomSheet.postDelayed({
                                    try {
                                        dismissAllowingStateLoss()
                                    } catch (e: Exception) {
                                        Log.e(TAG, "Error dismissing dialog", e)
                                    }
                                }, 150) // Wait for slide animation to complete
                            }
                        }
                        BottomSheetBehavior.STATE_COLLAPSED -> {
                            Log.d(TAG, "Bottom sheet STATE_COLLAPSED at peek height")
                            // Update container background coverage
                            updateContainerBackgroundCoverage()
                            imageRecyclerView?.post { updateScrollBarPosition() }
                        }
                        BottomSheetBehavior.STATE_EXPANDED -> {
                            Log.d(TAG, "Bottom sheet STATE_EXPANDED")
                            // Update container background coverage
                            updateContainerBackgroundCoverage()
                            imageRecyclerView?.post { updateScrollBarPosition() }
                        }
                    }
                }
                
                override fun onSlide(bottomSheet: View, slideOffset: Float) {
                    // Adjust dim amount based on slide for smooth transition
                    
                    // Update scroll bar position during slide
                    updateScrollBarPosition()
                    
                    // Only animate dim when transitioning between collapsed and expanded (not when hiding)
                    if (slideOffset >= 0) {
                        // Keep dim constant at MAX_DIM_AMOUNT when sliding between states
                        dialog.window?.let { window ->
                            val params = window.attributes
                            params.dimAmount = MAX_DIM_AMOUNT
                            window.attributes = params
                        }
                        
                        // Animate corner radius based on slide offset
                        // When slideOffset = 0 (collapsed at 60%), radius = maxCornerRadius (20dp)
                        // When slideOffset = 1 (expanded at 100%), radius = 0dp
                        val cornerRadius = maxCornerRadius * (1f - slideOffset)
                        updateCornerRadius(cornerRadius, slideOffset)
                        
                        // Animate topbar height based on slide offset
                        if (deviceStatusBarHeight > 0) {
                            val animHeight = (deviceStatusBarHeight * slideOffset).toInt()
                            applyHeaderInsets(animHeight)
                        }
                        
                        Log.d(TAG, "onSlide: slideOffset=$slideOffset, cornerRadius=$cornerRadius")
                    } else {
                        // When slideOffset < 0 (hiding), gradually fade out dim
                        val fadeOutAmount = (1f + slideOffset) * MAX_DIM_AMOUNT  // 0 to MAX_DIM_AMOUNT as it slides down
                        val dimAmount = fadeOutAmount.coerceIn(0f, MAX_DIM_AMOUNT)
                        dialog.window?.let { window ->
                            val params = window.attributes
                            params.dimAmount = dimAmount
                            window.attributes = params
                        }
                    }
                }
            })
        }
        
        // Set initial dim amount to 0f so it can smoothly animate in during slide-up
        dialog.window?.let { window ->
            val params = window.attributes
            params.dimAmount = 0f
            window.attributes = params
            // Ensure navigation bar stays white
            configureNavigationBar(window)
        }

        requireActivity().onBackPressedDispatcher.addCallback(viewLifecycleOwner, backPressedCallback)
    }
    
    
    private fun updateCornerRadius(cornerRadius: Float, slideOffset: Float = 0f) {
        val backgroundColor = ContextCompat.getColor(
            requireContext(),
            R.color.bottom_sheet_background
        )
        
        // Update bottom sheet background
        val shapeAppearanceModel = ShapeAppearanceModel.builder()
            .setTopLeftCornerSize(cornerRadius)
            .setTopRightCornerSize(cornerRadius)
            .build()
        
        val shapeDrawable = MaterialShapeDrawable(shapeAppearanceModel)
        shapeDrawable.setTint(backgroundColor)
        bottomSheetView?.background = shapeDrawable
        bottomSheetView?.clipToOutline = true
        
        // Update header background with same corner radius but dynamic alpha
        val alpha = (255 * (1f - slideOffset)).toInt().coerceIn(0, 255)
        val headerColor = androidx.core.graphics.ColorUtils.setAlphaComponent(backgroundColor, alpha)
        
        val headerDrawable = MaterialShapeDrawable(shapeAppearanceModel)
        headerDrawable.setTint(headerColor)
        headerView?.background = headerDrawable
    }
    
    private fun configureNavigationBar(window: Window) {
        // Detect system dark mode
        val isDarkMode = (resources.configuration.uiMode and 
            android.content.res.Configuration.UI_MODE_NIGHT_MASK) == 
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        
        // Set navigation bar color based on dark/light mode
        val navigationBarColor = if (isDarkMode) {
            // Dark mode: use dark color (usually black or dark gray)
            Color.BLACK
        } else {
            // Light mode: use white
            Color.WHITE
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+ (API 30+)
            window.navigationBarColor = navigationBarColor
            window.insetsController?.let { controller ->
                if (isDarkMode) {
                    // Dark mode: light icons on dark background (no flags)
                    controller.setSystemBarsAppearance(
                        0,
                        android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
                    )
                } else {
                    // Light mode: dark icons on light background
                    controller.setSystemBarsAppearance(
                        android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
                        android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
                    )
                }
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Android 8.0+ (API 26+) but below API 30
            window.navigationBarColor = navigationBarColor
            var flags = window.decorView.systemUiVisibility
            // Clear previous flag first
            flags = flags and android.view.View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR.inv()
            if (!isDarkMode) {
                // Light mode: dark icons on light background
                flags = flags or android.view.View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
            }
            // If dark mode, don't set flag (default is light icons on dark background)
            window.decorView.systemUiVisibility = flags
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            // Android 5.0+ (API 21+) but below API 26
            window.navigationBarColor = navigationBarColor
        }
    }
    
    /**
     * Update container background coverage based on image count
     * When image count is 20 or fewer, ensure the container fills the screen height
     * so background color covers the entire scrollable area
     */
    private fun updateContainerBackgroundCoverage() {
        // No longer needed because we force the bottom sheet to MATCH_PARENT in setupDialog
    }
    
    /**
     * Dismiss bottom sheet with smooth slide-down animation
     */
    private fun dismissWithAnimation() {
        Log.e(TAG, "dismissWithAnimation called", Exception())
        if (isDismissing) {
            return // Already dismissing, prevent reentrant calls
        }
        
        behavior?.let { b ->
            b.isHideable = true
            if (b.state != BottomSheetBehavior.STATE_HIDDEN) {
                b.state = BottomSheetBehavior.STATE_HIDDEN
                // onStateChanged will call dismissAllowingStateLoss()
            } else {
                // Already hidden, dismiss immediately
                isDismissing = true
                super.dismiss()
            }
        } ?: run {
            // No behavior, dismiss immediately
            isDismissing = true
            super.dismiss()
        }
    }
    
    override fun dismiss() {
        // Override dismiss to use animation
        dismissWithAnimation()
    }
    
    override fun onCancel(dialog: android.content.DialogInterface) {
        // Called when dialog is cancelled (e.g., back button)
        // Mark as explicitly cancelled
        isExplicitlyCancelled = true
        
        // Don't call super.onCancel as it will dismiss immediately
        // Instead, use our animated dismiss
        dismissWithAnimation()
    }

    private fun loadAllImages() {
        if (!hasPermission()) {
            Log.w(TAG, "No permission to read images")
            return
        }

        Log.d(TAG, "Loading images progressively to optimize startup...")

        if (cachedInitialImages != null) {
            Log.d(TAG, "Using cached initial images for INSTANT synchronous load")
            val initialImages = cachedInitialImages!!
            currentImageCount = initialImages.size
            allImagesCount = initialImages.size
            updateContainerBackgroundCoverage()
            allLoadedImages = initialImages

            adapter = ImageGridAdapter(
                initialImages.toMutableList(),
                maxSelection,
                themeColor,
                enableEditor,
                { selected ->
                    selectedImages = selected
                    updateSelectionUI(selected.size)
                    if ((maxSelection == 0 || maxSelection == 1) && selected.isNotEmpty() && !hasInvokedCallback) {
                        val tappedUri = selected.first()
                        if (profileMode) {
                            launchProfileCrop(tappedUri)
                        } else if (enableEditor) {
                            val startIndex = allLoadedImages.indexOfFirst { it == tappedUri }.coerceAtLeast(0)
                            val posInAdapter = if (adapter?.showCamera == true && !isShowingOnlySelected) startIndex + 1 else startIndex
                            val view = (imageRecyclerView?.layoutManager as? androidx.recyclerview.widget.GridLayoutManager)?.findViewByPosition(posInAdapter)
                            launchEditor(tappedUri, startIndex, sourceView = view)
                        } else {
                            hasInvokedCallback = true
                            onImagesSelected?.invoke(selected)
                            dismissWithAnimation()
                        }
                    }
                },
                { uri, position, view ->
                    if (profileMode) {
                        launchProfileCrop(uri)
                    } else if (enableEditor) {
                        val startIndex = allLoadedImages.indexOfFirst { it == uri }.coerceAtLeast(0)
                        launchEditor(uri, startIndex, sourceView = view)
                    }
                },
                { sourceView ->
                    if (androidx.core.content.ContextCompat.checkSelfPermission(requireContext(), android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        showCameraFullscreen(sourceView)
                    } else {
                        requestCameraPermission()
                    }
                },
                { previewView -> bindCameraPreview(previewView) },
                { hasCameraPermission() },
                { uri, onConfirm -> handleDeselectEditedImage(uri, onConfirm) }
            )
            adapter?.setQuickScrollMode(false)
            adapter?.setFastScrollMode(false)
            imageRecyclerView?.adapter = adapter
            
            // Allow setupDialog's onGlobalLayout to naturally trigger the animation 
            // from HIDDEN to COLLAPSED, ensuring a smooth slide-up effect.
            imagesLoaded = true

            scope.launch {
                // Wait for the slide-up animation (~300ms) to complete before doing heavy IO
                delay(300)
                val allImages = withContext(Dispatchers.IO) { loadImagesFromDevice(limit = null) }
                withContext(Dispatchers.Main) {
                    allLoadedImages = allImages
                    currentImageCount = allImages.size
                    allImagesCount = allImages.size
                    updateContainerBackgroundCoverage()
                    adapter?.updateImages(allImages, isAppend = true)
                }
            }
            return
        }

        scope.launch {
            try {
                // Initial fast load
                val initialImages = withContext(Dispatchers.IO) {
                    val loaded = loadImagesFromDevice(limit = 40)
                    cachedInitialImages = loaded
                    loaded
                }
                
                Log.d(TAG, "Loaded initial ${initialImages.size} images")
                
                currentImageCount = initialImages.size
                allImagesCount = initialImages.size
                withContext(Dispatchers.Main) {
                    updateContainerBackgroundCoverage()
                }
                
                allLoadedImages = initialImages

                adapter = ImageGridAdapter(
                    initialImages.toMutableList(),
                    maxSelection,
                    themeColor,
                    enableEditor,
                    { selected ->
                        selectedImages = selected
                        updateSelectionUI(selected.size)
                        if ((maxSelection == 0 || maxSelection == 1) && selected.isNotEmpty() && !hasInvokedCallback) {
                            val tappedUri = selected.first()
                            if (profileMode) {
                                launchProfileCrop(tappedUri)
                            } else if (enableEditor) {
                                val startIndex = allLoadedImages.indexOfFirst { it == tappedUri }.coerceAtLeast(0)
                                val posInAdapter = if (adapter?.showCamera == true && !isShowingOnlySelected) startIndex + 1 else startIndex
                                val view = (imageRecyclerView?.layoutManager as? androidx.recyclerview.widget.GridLayoutManager)?.findViewByPosition(posInAdapter)
                                launchEditor(tappedUri, startIndex, sourceView = view)
                            } else {
                                hasInvokedCallback = true
                                onImagesSelected?.invoke(selected)
                                dismissWithAnimation()
                            }
                        }
                    },
                    { uri, position, view ->
                        if (profileMode) {
                            launchProfileCrop(uri)
                        } else if (enableEditor) {
                            val startIndex = allLoadedImages.indexOfFirst { it == uri }.coerceAtLeast(0)
                            launchEditor(uri, startIndex, sourceView = view)
                        }
                    },
                    { sourceView ->
                        if (androidx.core.content.ContextCompat.checkSelfPermission(requireContext(), android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                            showCameraFullscreen(sourceView)
                        } else {
                            requestCameraPermission()
                        }
                    },
                    { previewView -> bindCameraPreview(previewView) },
                    { hasCameraPermission() },
                    { uri, onConfirm -> handleDeselectEditedImage(uri, onConfirm) }
                )
                
                adapter?.setQuickScrollMode(false)
                adapter?.setFastScrollMode(false)
                
                withContext(Dispatchers.Main) {
                    imageRecyclerView?.adapter = adapter
                    imageRecyclerView?.post {
                        Log.d(TAG, "RecyclerView laid out, starting animation")
                        behavior?.state = BottomSheetBehavior.STATE_COLLAPSED
                    }
                }
                
                Log.d(TAG, "All images loaded and adapter set - SINGLE LOAD, NO UPDATES")
                
                imageRecyclerView?.scrollToPosition(0)
                imageRecyclerView?.post {
                    imageRecyclerView?.scrollTo(0, 0)
                    imageRecyclerView?.post { initializeScrollBarPosition() }
                }
                
                imagesLoaded = true
                
                // Wait for the slide-up animation (~300ms) to complete before doing heavy IO
                delay(300)
                val allImages = withContext(Dispatchers.IO) { loadImagesFromDevice(limit = null) }
                withContext(Dispatchers.Main) {
                    allLoadedImages = allImages
                    currentImageCount = allImages.size
                    allImagesCount = allImages.size
                    updateContainerBackgroundCoverage()
                    adapter?.updateImages(allImages, isAppend = true)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error loading all images", e)
            }
        }
    }
    

    private fun loadImagesFromDevice(limit: Int? = null): List<Uri> {
        val imagesWithDatesList = loadImagesWithDatesFromDevice(limit)
        imagesWithDates = imagesWithDatesList
        return imagesWithDatesList.map { it.uri }
    }
    
    private fun loadImagesWithDatesFromDevice(limit: Int? = null): List<ImageWithDate> {
        val images = mutableListOf<ImageWithDate>()
        
        // Load date information along with ID
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.DATE_TAKEN
        )
        
        val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"
        
        val cursor = context?.contentResolver?.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            null,
            null,
            sortOrder
        )

        cursor?.use {
            val idColumn = it.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val dateAddedColumn = it.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
            val dateTakenColumn = it.getColumnIndex(MediaStore.Images.Media.DATE_TAKEN)
            var count = 0
            
            while (it.moveToNext()) {
                // If limit is set and reached, stop loading
                if (limit != null && count >= limit) {
                    break
                }
                
                val id = it.getLong(idColumn)
                val contentUri = ContentUris.withAppendedId(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    id
                )
                
                // Prefer DATE_TAKEN if available, otherwise use DATE_ADDED
                val dateAdded = if (dateTakenColumn >= 0 && !it.isNull(dateTakenColumn)) {
                    // DATE_TAKEN is in milliseconds, DATE_ADDED is in seconds
                    it.getLong(dateTakenColumn) / 1000 // Convert to seconds
                } else {
                    it.getLong(dateAddedColumn)
                }
                
                images.add(ImageWithDate(contentUri, dateAdded))
                count++
            }
        }
        
        return images
    }
    
    private fun initTabIndicator() {
        // Set initial position and size of active indicator to match all tab
        allTabButton?.post {
            allTabButton?.let { tab ->
                tabActiveIndicator?.let { indicator ->
                    val layoutParams = indicator.layoutParams as? FrameLayout.LayoutParams
                    layoutParams?.apply {
                        width = tab.width
                        leftMargin = (tab.left - (tabContainer?.paddingLeft ?: 0)).coerceAtLeast(0)
                    }
                    indicator.layoutParams = layoutParams
                    indicator.alpha = 1f
                }
            }
        }
    }
    
    private fun animateIndicatorToTab(targetTab: View) {
        tabActiveIndicator?.let { indicator ->
            val targetLayoutParams = indicator.layoutParams as? FrameLayout.LayoutParams
            targetLayoutParams?.apply {
                width = targetTab.width
                leftMargin = (targetTab.left - (tabContainer?.paddingLeft ?: 0)).coerceAtLeast(0)
            }
            
            val animator = android.animation.ValueAnimator.ofInt(
                indicator.left,
                targetLayoutParams?.leftMargin ?: 0
            )
            
            val startWidth = indicator.width
            val endWidth = targetTab.width
            
            animator.duration = 200
            animator.interpolator = DecelerateInterpolator()
            animator.addUpdateListener { valueAnimator ->
                val animatedValue = valueAnimator.animatedValue as Int
                val layoutParams = indicator.layoutParams as? FrameLayout.LayoutParams
                layoutParams?.apply {
                    leftMargin = animatedValue
                    width = ((startWidth + (endWidth - startWidth) * valueAnimator.animatedFraction)).toInt()
                }
                indicator.layoutParams = layoutParams
            }
            animator.start()
        }
    }
    
    private fun switchToSelectedImagesView() {
        Log.d(TAG, "Switching to selected images view")
        isShowingOnlySelected = true
        
        // Change text colors (use theme-aware colors)
        allTabButton?.setTextColor(ContextCompat.getColor(requireContext(), R.color.tab_inactive_text))
        selectedCountTab?.setTextColor(ContextCompat.getColor(requireContext(), R.color.tab_active_text))
        
        // Animate indicator to selected tab
        selectedCountTab?.let { tab ->
            animateIndicatorToTab(tab)
        }
        
        // Filter adapter to show only selected images
        adapter?.showOnlySelected(true)
        
        // Update currentImageCount to selected images count for background coverage calculation
        val selectedCount = adapter?.getSelectedImages()?.size ?: selectedImages.size
        currentImageCount = selectedCount
        updateContainerBackgroundCoverage()
        
        // Scroll to top
        imageRecyclerView?.scrollToPosition(0)
    }

    private fun launchEditor(uri: Uri, startIndex: Int, disableCrop: Boolean = false, sourceView: android.view.View? = null) {
        val currentTime = android.os.SystemClock.elapsedRealtime()
        if (currentTime - lastEditorLaunchTime < 1000) {
            return
        }
        lastEditorLaunchTime = currentTime
        
        Log.d(TAG, "launchEditor with URI: $uri, startIndex: $startIndex, singlePhotoMode: ${maxSelection <= 1}")
        behavior?.isHideable = false
        val themeColorStr = arguments?.getString(ARG_THEME_COLOR)
        
        val imageListToPass = if (isShowingOnlySelected) {
            selectedImages.toList()
        } else {
            allLoadedImages
        }
        
        val adjustedStartIndex = if (isShowingOnlySelected) {
            imageListToPass.indexOfFirst { it == uri }.coerceAtLeast(0)
        } else {
            startIndex
        }
        
        val intent = ImageEditorActivity.createIntent(
            requireActivity(),
            imageListToPass,
            startIndex = adjustedStartIndex,
            themeColor = themeColorStr,
            selectedUris = LinkedHashSet(selectedImages),
            editedUris = editedImages.mapKeys { it.key },
            singlePhotoMode = (maxSelection <= 1),
            disableCrop = disableCrop,
            maxWidth = maxWidth,
            maxHeight = maxHeight
        )
        
        TransitionHelper.onPageChanged = { uriStr ->
            imageRecyclerView?.let { rv ->
                adapter?.getPositionForUri(uriStr)?.let { index ->
                    if (index != -1) {
                        rv.scrollToPosition(index)
                    }
                }
            }
        }

        TransitionHelper.requestThumbnailRect = { uriStr ->
            var resultRect: android.graphics.Rect? = null
            imageRecyclerView?.let { rv ->
                adapter?.getPositionForUri(uriStr)?.let { index ->
                    if (index != -1) {
                        val view = rv.layoutManager?.findViewByPosition(index)
                        if (view != null) {
                            val imageView = view.findViewById<android.widget.ImageView>(R.id.imageView) ?: view
                            if (imageView.width > 0 && imageView.height > 0) {
                                val rect = android.graphics.Rect()
                                imageView.getGlobalVisibleRect(rect)
                                resultRect = rect
                            }
                        }
                    }
                }
            }
            resultRect
        }
        
        TransitionHelper.onEditingFinished = { uriStr, bitmap, isSaved ->
            if (bitmap != null && isSaved) {
                val pos = adapter?.getPositionForUri(uriStr) ?: -1
                if (pos >= 0) {
                    val holder = imageRecyclerView?.findViewHolderForAdapterPosition(pos) as? com.rnturboimagepicker.ImageGridAdapter.ImageViewHolder
                    if (holder != null) {
                        holder.imageView.setImageBitmap(bitmap)
                        holder.placeholderIcon.visibility = android.view.View.GONE
                    }
                }
            }
        }
        
        if (sourceView != null) {
            val imageView = sourceView.findViewById<android.widget.ImageView>(R.id.imageView) ?: sourceView
            if (imageView.width > 0 && imageView.height > 0) {
                val rect = android.graphics.Rect()
                imageView.getGlobalVisibleRect(rect)
                
                // Load the true aspect ratio thumbnail (max 800px)
                val displayUri = editedImages[uri.toString()] ?: uri
                val loadObject: Any = if (displayUri.scheme == "file") {
                    java.io.File(displayUri.path ?: "")
                } else {
                    displayUri
                }
                com.bumptech.glide.Glide.with(this)
                    .asBitmap()
                    .load(loadObject)
                    .override(800)
                    .into(object : com.bumptech.glide.request.target.CustomTarget<android.graphics.Bitmap>() {
                        override fun onResourceReady(
                            resource: android.graphics.Bitmap,
                            transition: com.bumptech.glide.request.transition.Transition<in android.graphics.Bitmap>?
                        ) {
                            TransitionHelper.thumbnailBitmap = resource
                            TransitionHelper.sourceRect = rect
                            
                            editorLauncher.launch(intent)
                            if (android.os.Build.VERSION.SDK_INT >= 34) {
                                requireActivity().overrideActivityTransition(android.app.Activity.OVERRIDE_TRANSITION_OPEN, 0, 0)
                            }
                            @Suppress("DEPRECATION")
                            requireActivity().overridePendingTransition(0, 0)
                        }
                        
                        override fun onLoadCleared(placeholder: android.graphics.drawable.Drawable?) {}
                        
                        override fun onLoadFailed(errorDrawable: android.graphics.drawable.Drawable?) {
                            // Fallback to square if glide fails
                            val fallbackBitmap = android.graphics.Bitmap.createBitmap(imageView.width, imageView.height, android.graphics.Bitmap.Config.ARGB_8888)
                            val canvas = android.graphics.Canvas(fallbackBitmap)
                            imageView.draw(canvas)
                            TransitionHelper.thumbnailBitmap = fallbackBitmap
                            TransitionHelper.sourceRect = rect
                            
                            editorLauncher.launch(intent)
                            if (android.os.Build.VERSION.SDK_INT >= 34) {
                                requireActivity().overrideActivityTransition(android.app.Activity.OVERRIDE_TRANSITION_OPEN, 0, 0)
                            }
                            @Suppress("DEPRECATION")
                            requireActivity().overridePendingTransition(0, 0)
                        }
                    })
            } else {
                editorLauncher.launch(intent)
                requireActivity().overridePendingTransition(R.anim.slide_in_bottom, R.anim.no_animation)
            }
        } else {
            editorLauncher.launch(intent)
            requireActivity().overridePendingTransition(R.anim.slide_in_bottom, R.anim.no_animation)
        }
    }
    
    private fun switchToAllImagesView() {
        Log.d(TAG, "Switching to all images view")
        isShowingOnlySelected = false
        
        // Change text colors (use theme-aware colors)
        allTabButton?.setTextColor(ContextCompat.getColor(requireContext(), R.color.tab_active_text))
        selectedCountTab?.setTextColor(ContextCompat.getColor(requireContext(), R.color.tab_inactive_text))
        
        // Animate indicator back to all tab
        allTabButton?.let { tab ->
            animateIndicatorToTab(tab)
        }
        
        // Show all images in adapter
        adapter?.showOnlySelected(false)
        
        // Restore currentImageCount to all images count for background coverage calculation
        currentImageCount = allImagesCount
        updateContainerBackgroundCoverage()
        
        // Scroll to top
        imageRecyclerView?.scrollToPosition(0)
    }
    
    private fun showAlbumPickerDialog() {
        // Don't show album picker if in selected filter mode
        if (isShowingOnlySelected) {
            switchToAllImagesView()
            return
        }
        
        // Calculate header position for dropdown placement
        var headerTop = 0
        
        headerView?.let { header ->
            val location = IntArray(2)
            header.getLocationInWindow(location)
            headerTop = location[1]
        }
        
        val headerBottom = headerTop + 48 // 48dp header height
        
        val albumDialog = AlbumPickerDialog.newInstance(languageCode)
        albumDialog.setOnAlbumSelectedListener { album ->
            onAlbumSelected(album)
        }
        // Pass offset to position dialog below header
        albumDialog.setOffsetY(headerBottom)
        // Use parent fragment manager to show on activity level, not bottom sheet level
        albumDialog.show(parentFragmentManager, "AlbumPickerDialog")
    }
    
    private fun onAlbumSelected(album: Album) {
        Log.d(TAG, "Album selected: ${album.bucketName}")
        
        // Update album title text
        albumTitleText?.text = album.bucketName
        // Update tab button text (for new UI)
        allTabButton?.text = album.bucketName
        
        // Load images from selected album
        loadImagesFromAlbum(album)
    }
    
    private fun loadImagesFromAlbum(album: Album) {
        Log.d(TAG, "Loading images from album: ${album.bucketName}")
        
        scope.launch {
            try {
                val images = withContext(Dispatchers.IO) {
                    loadImagesFromDeviceByBucket(album.bucketId)
                }
                
                Log.d(TAG, "Loaded ${images.size} images from album")
                
                // Update image count
                currentImageCount = images.size
                allImagesCount = images.size
                updateContainerBackgroundCoverage()
                
                // Update adapter with images from selected album
                // Save all loaded images for editor (swipe through all album photos)
                allLoadedImages = images

                if (adapter == null) {
                    adapter = ImageGridAdapter(
                        images.toMutableList(),
                        maxSelection,
                        themeColor,
                        enableEditor,
                        { selected ->
                            selectedImages = selected
                            updateSelectionUI(selected.size)

                            // Auto-launch editor for single selection (maxSelection == 0 or 1)
                            if ((maxSelection == 0 || maxSelection == 1) && selected.isNotEmpty() && !hasInvokedCallback) {
                                val tappedUri = selected.first()
                                if (profileMode) {
                                    launchProfileCrop(tappedUri)
                                } else if (enableEditor) {
                                    val startIndex = allLoadedImages.indexOfFirst { it == tappedUri }.coerceAtLeast(0)
                                    val posInAdapter = if (adapter?.showCamera == true && !isShowingOnlySelected) startIndex + 1 else startIndex
                                    val view = (imageRecyclerView?.layoutManager as? androidx.recyclerview.widget.GridLayoutManager)?.findViewByPosition(posInAdapter)
                                    launchEditor(tappedUri, startIndex, sourceView = view)
                                } else {
                                    hasInvokedCallback = true
                                    onImagesSelected?.invoke(selected)
                                    dismissWithAnimation()
                                }
                            }
                        },
                        { uri, position, view ->
                            if (profileMode) {
                                launchProfileCrop(uri)
                            } else if (enableEditor) {
                                val startIndex = allLoadedImages.indexOfFirst { it == uri }.coerceAtLeast(0)
                                launchEditor(uri, startIndex, sourceView = view)
                            }
                        },
                        { sourceView ->
                            if (androidx.core.content.ContextCompat.checkSelfPermission(requireContext(), android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                showCameraFullscreen(sourceView)
                            } else {
                                requestCameraPermission()
                            }
                        },
                        { previewView -> bindCameraPreview(previewView) },
                        { hasCameraPermission() },
                        { uri, onConfirm -> handleDeselectEditedImage(uri, onConfirm) }
                    )
                    imageRecyclerView?.adapter = adapter
                    
                    // Scroll to top immediately
                    imageRecyclerView?.scrollToPosition(0)
                    
                    // Initialize scroll bar position after layout
                    imageRecyclerView?.viewTreeObserver?.addOnGlobalLayoutListener(object : ViewTreeObserver.OnGlobalLayoutListener {
                        override fun onGlobalLayout() {
                            imageRecyclerView?.viewTreeObserver?.removeOnGlobalLayoutListener(this)
                            
                            // Ensure RecyclerView is at the very top
                            imageRecyclerView?.scrollToPosition(0)
                            imageRecyclerView?.post {
                                imageRecyclerView?.scrollTo(0, 0)
                                
                                // Now initialize scroll bar to top position
                                imageRecyclerView?.post {
                                    initializeScrollBarPosition()
                                }
                            }
                        }
                    })
                } else {
                    adapter?.updateImages(images)
                    
                    // Scroll to top and reinitialize scroll bar position
                    // This is for album switching, so we need to reset scroll position
                    imageRecyclerView?.scrollToPosition(0)
                    imageRecyclerView?.post {
                        imageRecyclerView?.scrollTo(0, 0)
                        
                        imageRecyclerView?.post {
                            initializeScrollBarPosition()
                        }
                    }
                }
                
                Log.d(TAG, "Images from album loaded successfully")
                
            } catch (e: Exception) {
                Log.e(TAG, "Error loading images from album", e)
            }
        }
    }
    
    private fun loadImagesFromDeviceByBucket(bucketId: String): List<Uri> {
        val imagesWithDatesList = loadImagesWithDatesFromDeviceByBucket(bucketId)
        imagesWithDates = imagesWithDatesList
        return imagesWithDatesList.map { it.uri }
    }
    
    private fun loadImagesWithDatesFromDeviceByBucket(bucketId: String): List<ImageWithDate> {
        val images = mutableListOf<ImageWithDate>()
        
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.DATE_TAKEN
        )
        
        val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"
        
        // Handle "ALL_IMAGES" special case - load all images without bucket filter
        val selection = if (bucketId == "ALL_IMAGES") {
            null
        } else {
            "${MediaStore.Images.Media.BUCKET_ID} = ?"
        }
        val selectionArgs = if (bucketId == "ALL_IMAGES") {
            null
        } else {
            arrayOf(bucketId)
        }
        
        val cursor = context?.contentResolver?.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            sortOrder
        )
        
        cursor?.use {
            val idColumn = it.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val dateAddedColumn = it.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
            val dateTakenColumn = it.getColumnIndex(MediaStore.Images.Media.DATE_TAKEN)
            
            while (it.moveToNext()) {
                val id = it.getLong(idColumn)
                val contentUri = ContentUris.withAppendedId(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    id
                )
                
                // Prefer DATE_TAKEN if available, otherwise use DATE_ADDED
                val dateAdded = if (dateTakenColumn >= 0 && !it.isNull(dateTakenColumn)) {
                    // DATE_TAKEN is in milliseconds, DATE_ADDED is in seconds
                    it.getLong(dateTakenColumn) / 1000 // Convert to seconds
                } else {
                    it.getLong(dateAddedColumn)
                }
                
                images.add(ImageWithDate(contentUri, dateAdded))
            }
        }
        
        return images
    }

    private fun hasPermission(): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        
        return ContextCompat.checkSelfPermission(
            requireContext(),
            permission
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    private fun hasCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            requireContext(),
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    private fun openCamera() {
        if (!hasCameraPermission()) {
            Log.w(TAG, "No camera permission")
            // Request camera permission
            requestCameraPermission()
            return
        }
        
        val takePictureIntent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
        
        // Create file for image
        val photoFile = createImageFile()
        if (photoFile != null) {
            val photoUri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // Use FileProvider for Android 7.0+
                FileProvider.getUriForFile(
                    requireContext(),
                    "${requireContext().packageName}.fileprovider",
                    photoFile
                )
            } else {
                // Use file:// URI for older versions
                Uri.fromFile(photoFile)
            }
            
            cameraImageUri = photoUri
            cameraImageFile = photoFile
            takePictureIntent.putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
            
            // Grant read/write permissions to camera app
            if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.LOLLIPOP) {
                takePictureIntent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            } else {
                takePictureIntent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            
            cameraLauncher.launch(takePictureIntent)
        } else {
            Log.e(TAG, "Failed to create image file")
        }
    }
    
    private fun requestCameraPermission() {
        cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
    }

    private fun bindCameraPreview(previewView: PreviewView) {
        if (!hasCameraPermission()) return
        
        val cameraProviderFuture = ProcessCameraProvider.getInstance(requireContext())
        cameraProviderFuture.addListener({
            try {
                val cameraProvider = cameraProviderFuture.get()

                val preview = Preview.Builder()
                    .setTargetAspectRatio(androidx.camera.core.AspectRatio.RATIO_16_9)
                    .build()
                    .also {
                        val activeSurfaceProvider = previewView.surfaceProvider
                        it.setSurfaceProvider(activeSurfaceProvider)
                        previewView.scaleType = PreviewView.ScaleType.FILL_CENTER
                    }
                currentPreview = preview

                imageCapture = ImageCapture.Builder()
                    .setTargetAspectRatio(androidx.camera.core.AspectRatio.RATIO_16_9)
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                    .setFlashMode(flashMode)
                    .build()

                cameraProvider.unbindAll()
                currentCamera = cameraProvider.bindToLifecycle(
                    this@ImagePickerBottomSheet, currentCameraSelector, preview, imageCapture
                )
                isCameraCurrentlyBound = true
                
                previewView.previewStreamState.removeObservers(viewLifecycleOwner)
                previewView.previewStreamState.observe(viewLifecycleOwner, androidx.lifecycle.Observer { state ->
                    if (state == androidx.camera.view.PreviewView.StreamState.STREAMING) {
                        val currentSnapshotView = previewView.tag as? ImageView
                        currentSnapshotView?.let { view ->
                            if (view.visibility == android.view.View.VISIBLE && view.alpha > 0f) {
                                view.animate()
                                    .alpha(0f)
                                    .setDuration(300)
                                    .withEndAction {
                                        view.visibility = android.view.View.GONE
                                        if (view.id != R.id.cameraLastFrameView) {
                                            (view.parent as? android.view.ViewGroup)?.removeView(view)
                                        }
                                        if (previewView.tag === view) {
                                            previewView.tag = null
                                        }
                                    }
                                    .start()
                            }
                        }
                    }
                })
            } catch (exc: Exception) {
                Log.e(TAG, "CameraX binding failed", exc)
            }
        }, ContextCompat.getMainExecutor(requireContext()))
    }
    
    fun showCameraFullscreen(sourceView: View) {
        val previewView = sourceView.findViewById<PreviewView>(R.id.cameraPreview) ?: return
        val cellParent = previewView.parent as? ViewGroup
        val cellIndex = cellParent?.indexOfChild(previewView) ?: 0
        
        val rect = Rect()
        val cardView = sourceView.findViewById<android.view.View>(R.id.cardView)
        if (cardView != null) {
            cardView.getGlobalVisibleRect(rect)
        } else {
            sourceView.getGlobalVisibleRect(rect)
        }
        
        val overlay = CameraExpandOverlay(
            context = requireContext(),
            sourceRect = rect,
            previewView = previewView,
            initialBitmap = previewView.bitmap,
            onDismiss = { bitmap ->
                cameraOverlay = null
                backPressedCallback.isEnabled = false
                
                // Return previewView back to the cell physically
                (previewView.parent as? ViewGroup)?.removeView(previewView)
                if (cellIndex >= 0) {
                    cellParent?.addView(previewView, cellIndex)
                } else {
                    cellParent?.addView(previewView)
                }
                
                // Use the recent snapshot to cover any frame skips when recreating surface
                if (bitmap != null) {
                    val cameraLastFrameView = sourceView.findViewById<android.widget.ImageView>(R.id.cameraLastFrameView)
                    if (cameraLastFrameView != null) {
                        cameraLastFrameView.setImageBitmap(bitmap)
                        cameraLastFrameView.visibility = android.view.View.VISIBLE
                        cameraLastFrameView.alpha = 1f
                        
                        // Fade out the snapshot after a short delay (gives surface time to recreate)
                        cameraLastFrameView.animate()
                            .alpha(0f)
                            .setDuration(300)
                            .setStartDelay(300)
                            .withEndAction {
                                cameraLastFrameView.visibility = android.view.View.GONE
                            }
                            .start()
                    }
                }
            },
            onCapture = { takePictureWithCameraX() },
            onSwitchCamera = {
                val overlayView = previewView // Use the same previewView
                val container = cameraOverlay?.cameraContainer
                if (container != null) {
                    val bitmap = overlayView.bitmap
                    if (bitmap != null) {
                        val snapshotView = android.widget.ImageView(requireContext()).apply {
                            setImageBitmap(bitmap)
                            layoutParams = android.view.ViewGroup.LayoutParams(
                                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                                android.view.ViewGroup.LayoutParams.MATCH_PARENT
                            )
                            scaleType = android.widget.ImageView.ScaleType.CENTER_CROP
                        }
                        container.addView(snapshotView)
                        overlayView.tag = snapshotView
                    }
                }

                currentCameraSelector = if (currentCameraSelector == CameraSelector.DEFAULT_BACK_CAMERA) {
                    CameraSelector.DEFAULT_FRONT_CAMERA
                } else {
                    CameraSelector.DEFAULT_BACK_CAMERA
                }
                
                // Rebind camera for the new selector, and bindCameraPreview will handle routing surface
                bindCameraPreview(previewView)
            },
            onFlashToggle = {
                flashMode = when (flashMode) {
                    androidx.camera.core.ImageCapture.FLASH_MODE_OFF -> androidx.camera.core.ImageCapture.FLASH_MODE_AUTO
                    androidx.camera.core.ImageCapture.FLASH_MODE_AUTO -> androidx.camera.core.ImageCapture.FLASH_MODE_ON
                    else -> androidx.camera.core.ImageCapture.FLASH_MODE_OFF
                }
                bindCameraPreview(previewView)
                flashMode
            },
            lifecycleOwner = viewLifecycleOwner,
            getCamera = { currentCamera }
        )
        cameraOverlay = overlay
        backPressedCallback.isEnabled = true

        // Just add the overlay to the window.
        dialog?.window?.decorView?.let { decorView ->
            if (decorView is ViewGroup) {
                decorView.addView(overlay, ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                ))
            }
        }
    }

    private fun takePictureWithCameraX() {
        val imageCapture = imageCapture ?: run {
            Toast.makeText(context, "카메라를 준비하는 중입니다.", Toast.LENGTH_SHORT).show()
            return
        }

        if (!hasCameraPermission()) {
            requestCameraPermission()
            return
        }

        val photoFile = createImageFile() ?: run {
            Log.e(TAG, "Failed to create image file for CameraX")
            Toast.makeText(context, "파일 생성에 실패했습니다.", Toast.LENGTH_SHORT).show()
            return
        }
        val outputOptions = ImageCapture.OutputFileOptions.Builder(photoFile).build()

        imageCapture.takePicture(
            outputOptions, ContextCompat.getMainExecutor(requireContext()), object : ImageCapture.OnImageSavedCallback {
                override fun onError(exc: ImageCaptureException) {
                    Log.e(TAG, "Photo capture failed: ${exc.message}", exc)
                    Toast.makeText(context, "사진 촬영에 실패했습니다.", Toast.LENGTH_SHORT).show()
                }

                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    val savedUri = Uri.fromFile(photoFile)
                    scope.launch {
                        try {
                            val mediaStoreUri = withContext(Dispatchers.IO) {
                                saveImageToMediaStore(photoFile)
                            } ?: savedUri

                            Log.d(TAG, "CameraX photo saved: $mediaStoreUri")
                            
                            withContext(Dispatchers.Main) {
                                // Add to gallery and select it
                                adapter?.insertAndSelectImage(mediaStoreUri)
                                
                                // Shrink camera overlay to return to gallery
                                cameraOverlay?.startShrinkAnimation()
                                
                                // Make sure gallery grid scrolls to the top to see the new image
                                imageRecyclerView?.scrollToPosition(0)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error processing CameraX image", e)
                        }
                    }
                }
            })
    }
    
    private fun createImageFile(): File? {
        try {
            val timeStamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
            val imageFileName = "JPEG_${timeStamp}_"
            
            val storageDir = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+ uses MediaStore, no need for external storage directory
                requireContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES)
            } else {
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            }
            
            val imageFile = File.createTempFile(
                imageFileName,
                ".jpg",
                storageDir
            )
            
            return imageFile
        } catch (e: Exception) {
            Log.e(TAG, "Error creating image file", e)
            return null
        }
    }
    
    private fun saveImageToMediaStore(imageFile: File): Uri? {
        return try {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, imageFile.name)
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    // Android 10+ uses RELATIVE_PATH
                    put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES)
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                } else {
                    // For older versions, use DATA path
                    put(MediaStore.Images.Media.DATA, imageFile.absolutePath)
                }
            }
            
            val uri = requireContext().contentResolver.insert(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                values
            )
            
            uri?.let { u ->
                // Copy file content to MediaStore
                requireContext().contentResolver.openOutputStream(u)?.use { outputStream ->
                    imageFile.inputStream().use { inputStream ->
                        inputStream.copyTo(outputStream)
                    }
                }
                
                // For Android 10+, update IS_PENDING to 0 after copying
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    values.clear()
                    values.put(MediaStore.Images.Media.IS_PENDING, 0)
                    requireContext().contentResolver.update(u, values, null, null)
                }
                
                // Delete temporary file after saving to MediaStore
                imageFile.delete()
                
                u
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error saving image to MediaStore", e)
            null
        }
    }

    private fun updateSelectionUI(count: Int) {
        val topPadding = if (currentTopPadding > 0) currentTopPadding else {
            val basePadding = (2 * resources.displayMetrics.density).toInt()
            val headerHeightPx = (48 * resources.displayMetrics.density).toInt()
            basePadding + headerHeightPx
        }
        
        imageRecyclerView?.let { recyclerView ->
            // Handle maxSelection == 0 (single selection mode)
            if (maxSelection == 0) {
                // Single selection mode - done button is hidden (auto-dismiss on selection)
                doneButton?.visibility = View.GONE
                selectedCountLayout?.visibility = View.GONE
                albumTitleLayout?.visibility = View.VISIBLE
                tabContainer?.visibility = View.GONE
                
                // Update padding
                recyclerView.setPadding(
                    originalPadding,
                    topPadding,
                    originalPadding,
                    originalPadding
                )
                return@let
            }
            
            // Multi-selection mode (maxSelection > 0)
            if (maxSelection > 0) {
                if (count > 0) {
                    // Show selected count tab
                    val tabSelectedString = "$count ${getString(R.string.tab_selected)}"
                    selectedCountTab?.text = tabSelectedString
                    val wasTabHidden = selectedCountTab?.visibility != View.VISIBLE
                    selectedCountTab?.visibility = View.VISIBLE
                    
                    // Switch to new tab UI when selection exists with animation
                    val wasShowingAlbumTitle = albumTitleLayout?.visibility == View.VISIBLE
                    if (wasShowingAlbumTitle) {
                        animateUIChange(albumTitleLayout, tabContainer) {
                            // Initialize indicator after animation completes
                            if (wasTabHidden) {
                                initTabIndicator()
                            }
                        }
                    } else {
                        albumTitleLayout?.visibility = View.GONE
                        tabContainer?.visibility = View.VISIBLE
                        
                        // Reinitialize indicator position when selected tab appears
                        if (wasTabHidden) {
                            initTabIndicator()
                        }
                    }
                    
                    // Animate done button in if it was hidden
                    doneButton?.let { button ->
                        if (button.visibility != View.VISIBLE) {
                            button.visibility = View.VISIBLE
                            animateDoneButtonIn(button)
                        }
                    }
                } else {
                    // Animate done button out if it was visible
                    doneButton?.let { button ->
                        if (button.visibility == View.VISIBLE) {
                            animateDoneButtonOut(button)
                        }
                    }
                    
                    // If in selected filter mode, switch back to all images
                    if (isShowingOnlySelected) {
                        switchToAllImagesView()
                    }
                    
                    // Switch back to album title UI when no selection with animation
                    val wasShowingTabs = tabContainer?.visibility == View.VISIBLE
                    if (wasShowingTabs) {
                        animateUIChange(tabContainer, albumTitleLayout)
                    }
                }
            }
        }
    }

    private fun animateDoneButtonIn(view: View) {
        // Combined scale and fade in animation
        val scaleAnimation = ScaleAnimation(
            0.5f, 1.0f, // fromX, toX
            0.5f, 1.0f, // fromY, toY
            Animation.RELATIVE_TO_SELF, 0.5f, // pivotXType, pivotXValue
            Animation.RELATIVE_TO_SELF, 0.5f  // pivotYType, pivotYValue
        )
        val alphaAnimation = AlphaAnimation(0f, 1f)
        
        // Combine animations
        val animationSet = android.view.animation.AnimationSet(true)
        animationSet.addAnimation(scaleAnimation)
        animationSet.addAnimation(alphaAnimation)
        animationSet.duration = 200
        animationSet.interpolator = DecelerateInterpolator()
        
        view.startAnimation(animationSet)
    }
    
    private fun animateDoneButtonOut(view: View) {
        // Combined scale and fade out animation
        val scaleAnimation = ScaleAnimation(
            1.0f, 0.5f, // fromX, toX
            1.0f, 0.5f, // fromY, toY
            Animation.RELATIVE_TO_SELF, 0.5f, // pivotXType, pivotXValue
            Animation.RELATIVE_TO_SELF, 0.5f  // pivotYType, pivotYValue
        )
        val alphaAnimation = AlphaAnimation(1f, 0f)
        
        // Combine animations
        val animationSet = android.view.animation.AnimationSet(true)
        animationSet.addAnimation(scaleAnimation)
        animationSet.addAnimation(alphaAnimation)
        animationSet.duration = 150
        animationSet.interpolator = DecelerateInterpolator()
        
        animationSet.setAnimationListener(object : Animation.AnimationListener {
            override fun onAnimationStart(animation: Animation?) {}
            override fun onAnimationRepeat(animation: Animation?) {}
            override fun onAnimationEnd(animation: Animation?) {
                view.visibility = View.GONE
            }
        })
        
        view.startAnimation(animationSet)
    }
    
    private fun animateUIChange(hideView: View?, showView: View?, onComplete: (() -> Unit)? = null) {
        hideView?.let { hide ->
            showView?.let { show ->
                // Cancel any running animations
                runningFadeOutAnimator?.cancel()
                runningFadeInAnimator?.cancel()
                hide.removeCallbacks(null)
                show.removeCallbacks(null)
                
                // Fade out hide view
                runningFadeOutAnimator = ValueAnimator.ofFloat(1f, 0f).apply {
                    duration = 200
                    addUpdateListener { animator ->
                        hide.alpha = animator.animatedValue as Float
                    }
                }
                runningFadeOutAnimator?.start()
                
                // Fade in show view after delay
                show.postDelayed({
                    show.alpha = 0f
                    show.visibility = View.VISIBLE
                    runningFadeInAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
                        duration = 200
                        addUpdateListener { animator ->
                            show.alpha = animator.animatedValue as Float
                        }
                        addListener(object : AnimatorListenerAdapter() {
                            override fun onAnimationEnd(animation: Animator) {
                                hide.visibility = View.GONE
                                hide.alpha = 1f // Reset alpha for next use
                                runningFadeOutAnimator = null
                                runningFadeInAnimator = null
                                onComplete?.invoke()
                            }
                        })
                    }
                    runningFadeInAnimator?.start()
                }, 100)
            }
        }
    }

    // MARK: - Quick Scroller Setup
    
    /**
     * Enable/disable quick scroll mode for performance optimization
     * When enabled, adapter loads smaller thumbnails and uses cache only
     */
    private fun setQuickScrollMode(enabled: Boolean) {
        if (isQuickScrolling != enabled) {
            isQuickScrolling = enabled
            adapter?.setQuickScrollMode(enabled)
        }
    }
    
    /**
     * Enable/disable fast scroll mode for maximum performance during very fast scrolling
     * When enabled, adapter skips image loading completely and shows only placeholders
     */
    private fun setFastScrollMode(enabled: Boolean) {
        if (isFastScrolling != enabled) {
            isFastScrolling = enabled
            adapter?.setFastScrollMode(enabled)
        }
    }

    
    private fun initializeScrollBarPosition() {
        scrollBarThumb?.let { thumb ->
            scrollBarTrack?.let { track ->
                val recyclerView = imageRecyclerView ?: return
                
                // Scroll RecyclerView to top first
                recyclerView.scrollToPosition(0)
                recyclerView.post {
                    recyclerView.scrollTo(0, 0)
                }
                
                // Reset thumb to top position (0%)
                thumb.translationY = 0f
                
                // Update visual thumb position to match
                scrollBarThumbVisual?.let { visual ->
                    visual.translationY = 0f
                }
                
                scrollBarThumbTopMargin = 0
                
                // Update date indicator position to match thumb at top
                dateScrollIndicator?.post {
                    updateDateIndicatorVerticalPosition()
                    
                    // Force update date after position is set
                    recyclerView.post {
                        updateDateForCurrentScroll()
                    }
                }
            }
        }
    }
    
    private fun setupQuickScroller() {
        // Bring scrollbar views to front to ensure they receive touch events
        scrollBarTrack?.parent?.let { parent ->
            if (parent is ViewGroup) {
                scrollBarTrack?.bringToFront()
                scrollBarThumb?.bringToFront()
                scrollBarTrackVisual?.bringToFront()
                scrollBarThumbVisual?.bringToFront()
                dateScrollIndicator?.bringToFront()
            }
        }
        
        // Disable touch listeners for track and thumb - only date indicator should be draggable
        scrollBarTrack?.apply {
            setOnTouchListener(null)
            isClickable = false
            isFocusable = false
            isEnabled = false
        }
        
        scrollBarThumb?.apply {
            setOnTouchListener(null)
            isClickable = false
            isFocusable = false
            isEnabled = false
        }
        
        // Date indicator should be draggable (like iOS)
        // Only intercept touch when visible
        dateScrollIndicator?.apply {
            setOnTouchListener { view, event ->
                // Only handle touch when visible
                if (visibility == View.VISIBLE) {
                    Log.d(TAG, "========================================")
                    Log.d(TAG, "DATE INDICATOR TOUCHED! action=${event.action}, x=${event.x}, y=${event.y}")
                    Log.d(TAG, "========================================")
                    handleScrollBarTouch(view, event)
                } else {
                    // Not visible, let touch pass through
                    false
                }
            }
        }
        
        // Prevent RecyclerView from intercepting touches in scrollbar area
        imageRecyclerView?.setOnTouchListener { view, event ->
            val track = scrollBarTrack ?: return@setOnTouchListener false
            val location = IntArray(2)
            view.getLocationOnScreen(location)
            val x = event.rawX
            val y = event.rawY
            
            // Get scrollbar location
            val trackLocation = IntArray(2)
            track.getLocationOnScreen(trackLocation)
            val trackWidth = track.width
            val trackStartX = trackLocation[0]
            val trackEndX = trackStartX + trackWidth
            
            // If touch is in scrollbar area, don't let RecyclerView handle it
            if (x >= trackStartX && x <= trackEndX) {
                // Let scrollbar handle this touch
                false
            } else {
                // Let RecyclerView handle normal scrolls
                false
            }
        }
        
        // Add scroll listener to RecyclerView
        imageRecyclerView?.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                super.onScrolled(recyclerView, dx, dy)
                
                val speed = Math.abs(dy)
                val targetSize = when {
                    speed > 130 -> 100
                    speed > 90 -> 200
                    speed > 50 -> 300
                    else -> 400
                }
                adapter?.updateTargetSize(targetSize, recyclerView)
                

                
                if (!isDraggingScrollBar && dy != 0) {
                    updateScrollBarPosition()
                    updateDateForCurrentScrollThrottled()
                    showScrollBarAndDate()
                    scheduleDateIndicatorHide()
                }
            }
            
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                super.onScrollStateChanged(recyclerView, newState)

                if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                    adapter?.updateTargetSize(400, recyclerView)
                    adapter?.reloadVisibleItems(recyclerView)
                }
                
                // Check if scrollable
                val canScroll = recyclerView.canScrollVertically(1) || 
                               recyclerView.canScrollVertically(-1) ||
                               recyclerView.computeVerticalScrollRange() > recyclerView.height
                
                if (!canScroll) {
                    hideScrollBarAndDate()
                    return
                }

                if (newState != RecyclerView.SCROLL_STATE_IDLE && !isDraggingScrollBar) {
                    showScrollBarAndDate()
                } else if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                    scheduleDateIndicatorHide()
                }
                
                // Removed aggressive pause/resume to allow Glide to load images during scroll
            }
        })

        
        // Update scroll position when RecyclerView resizes (e.g. half-screen to full-screen)
        imageRecyclerView?.addOnLayoutChangeListener { _, _, top, _, bottom, _, oldTop, _, oldBottom ->
            if (bottom - top != oldBottom - oldTop) {
                imageRecyclerView?.post {
                    updateScrollBarPosition()
                }
            }
        }
        
        // Initialize date hide handler
        dateHideTimer = android.os.Handler(android.os.Looper.getMainLooper())
    }
    
    private var lastTouchY = 0f
    
    private fun handleScrollBarTouch(view: View, event: MotionEvent): Boolean {
        try {
            val track = scrollBarTrack ?: return false
            val recyclerView = imageRecyclerView ?: return false
            
            // Get touch position relative to track
            val rawY = event.rawY
            val trackLocation = IntArray(2)
            track.getLocationOnScreen(trackLocation)
            val trackY = rawY - trackLocation[1]
            
            when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                // Reset velocity tracking
                lastMoveTime = System.currentTimeMillis()
                lastImageLoadTime = 0L
                dragVelocity = 0f
                
                // Start with Quick Scroll Mode (will adapt based on velocity)
                setQuickScrollMode(true)
                
                // Bring scrollbar to front to ensure it receives touches
                track.parent?.let { parent ->
                    if (parent is ViewGroup) {
                        track.bringToFront()
                        scrollBarThumb?.bringToFront()
                        scrollBarTrackVisual?.bringToFront()
                        scrollBarThumbVisual?.bringToFront()
                        dateScrollIndicator?.bringToFront()
                        parent.invalidate()
                    }
                }
                
                // Prevent parent views from intercepting touch events
                view.parent?.requestDisallowInterceptTouchEvent(true)
                recyclerView.parent?.requestDisallowInterceptTouchEvent(true)
                recyclerView.stopScroll()
                
                isDraggingScrollBar = true
                lastTouchY = trackY
                
                // If touching track directly (not date indicator), move thumb to touch position immediately
                if (view == track) {
                    scrollBarThumb?.let { thumb ->
                        val thumbHeight = thumb.height
                        val actualVisibleHeight = recyclerView.height
                        val trackHeight = actualVisibleHeight
                        val maxOffset = trackHeight - thumbHeight
                        if (maxOffset > 0) {
                            val newY = (trackY - thumbHeight / 2).coerceIn(0f, maxOffset.toFloat())
                            
                            thumb.translationY = newY
                            
                            // Update visual thumb position to match
                            scrollBarThumbVisual?.let { visual ->
                                visual.translationY = newY
                            }
                            
                            scrollBarThumbTopMargin = newY.toInt()
                            
                            // Scroll RecyclerView to match thumb position immediately
                            scrollToThumbPosition(false)
                            
                            // Update date after scroll
                            recyclerView.postDelayed({
                                updateDateForThumbPosition()
                            }, 50)
                        }
                    }
                }
                
                showScrollBarAndDate()
                // Always move date indicator to center when grabbing scrollbar or indicator
                moveDateIndicatorToCenter(true)
                
                dateHideTimer?.removeCallbacks(dateHideRunnable ?: return false)
                lastHapticDate = ""
                    return true
                }
            MotionEvent.ACTION_MOVE -> {
                if (!isDraggingScrollBar) {
                    // Restart dragging if it was cancelled
                    isDraggingScrollBar = true
                    view.parent?.requestDisallowInterceptTouchEvent(true)
                    recyclerView.parent?.requestDisallowInterceptTouchEvent(true)
                    lastTouchY = trackY
                    return true
                }
                
                val deltaY = trackY - lastTouchY
                val currentTime = System.currentTimeMillis()
                
                // Calculate drag velocity (distance per 100ms)
                val timeSinceLastMove = currentTime - lastMoveTime
                if (timeSinceLastMove > 0) {
                    dragVelocity = Math.abs(deltaY) / (timeSinceLastMove / 100f)
                }
                
                // Remember thumb position before update
                val prevThumbMargin = scrollBarThumbTopMargin
                
                // Update thumb position
                updateScrollBarThumbPosition(deltaY)
                
                // If thumb didn't actually move (clamped at top or bottom boundary),
                // disable all scroll modes and show images normally
                if (scrollBarThumbTopMargin == prevThumbMargin && Math.abs(deltaY) > 0.5f) {
                    lastTouchY = trackY
                    lastMoveTime = currentTime
                    
                    // Cancel any pending pause detection
                    pauseCheckRunnable?.let { dateHideTimer?.removeCallbacks(it) }
                    
                    // Disable all optimization modes so images load normally
                    if (isFastScrolling || isQuickScrolling) {
                        setFastScrollMode(false)
                        setQuickScrollMode(false)
                        
                        // Reload visible items at full quality
                        recyclerView.post {
                            adapter?.notifyDataSetChanged()
                        }
                    }
                    
                    return true
                }
                
                // Update date while dragging
                updateDateForThumbPosition()
                
                // Ensure date indicator vertical position tracks the thumb!
                updateDateIndicatorVerticalPosition()
                
                // Scroll RecyclerView immediately (no animation during drag for responsiveness)
                scrollToThumbPosition(false)
                
                lastTouchY = trackY
                lastMoveTime = currentTime
                
                // Adaptive scroll mode based on velocity
                if (dragVelocity > FAST_DRAG_THRESHOLD) {
                    // Very fast drag: Use Fast Scroll Mode (placeholder only)
                    if (!isFastScrolling) {
                        setFastScrollMode(true)
                    }
                } else {
                    // Slow drag: Use Quick Scroll Mode and load images periodically
                    if (isFastScrolling) {
                        setFastScrollMode(false)
                        setQuickScrollMode(true)
                    }
                    
                    // Load images every 100ms during slow drag
                    val timeSinceLastLoad = currentTime - lastImageLoadTime
                    if (timeSinceLastLoad >= IMAGE_LOAD_INTERVAL) {
                        lastImageLoadTime = currentTime
                        
                        // Reload visible items with small thumbnails (Quick Scroll Mode)
                        recyclerView.layoutManager?.let { lm ->
                            val firstVisible = lm.findFirstVisibleItemPosition()
                            val lastVisible = lm.findLastVisibleItemPosition()
                            
                            if (firstVisible in 0..lastVisible) {
                                adapter?.notifyItemRangeChanged(firstVisible, lastVisible - firstVisible + 1)
                            }
                        }
                    }
                }
                
                // Cancel previous pause detection
                pauseCheckRunnable?.let { dateHideTimer?.removeCallbacks(it) }
                
                // Schedule pause detection - if no movement for 120ms, show full quality images
                pauseCheckRunnable = Runnable {
                    val timeSinceLastMoveCheck = System.currentTimeMillis() - lastMoveTime
                    if (timeSinceLastMoveCheck >= PAUSE_DETECTION_DELAY && isDraggingScrollBar) {
                        // User paused dragging - disable all optimization modes
                        setFastScrollMode(false)
                        setQuickScrollMode(false)
                        
                        // Reload ALL items to ensure consistent state
                        adapter?.notifyDataSetChanged()
                    }
                }
                dateHideTimer?.postDelayed(pauseCheckRunnable!!, PAUSE_DETECTION_DELAY)
                
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                isDraggingScrollBar = false
                
                // Cancel pause detection
                pauseCheckRunnable?.let { dateHideTimer?.removeCallbacks(it) }
                pauseCheckRunnable = null
                
                // Disable all optimization modes
                setFastScrollMode(false)
                setQuickScrollMode(false)
                
                // Allow parent to intercept touch events again
                view.parent?.requestDisallowInterceptTouchEvent(false)
                recyclerView.parent?.requestDisallowInterceptTouchEvent(false)
                
                scrollToThumbPosition(true)
                
                // Always move date indicator to edge when finishing drag
                moveDateIndicatorToEdge(true)
                
                // Reload ALL items to ensure no placeholder remains after quick scroll
                recyclerView.postDelayed({
                    adapter?.notifyDataSetChanged()
                }, 50)
                
                scheduleDateIndicatorHide()
                return true
            }
        }
        } catch (e: Exception) {
            Log.e(TAG, "Error in handleScrollBarTouch", e)
        }
        return false
    }
    
    private fun updateScrollBarThumbPosition(deltaY: Float) {
        val thumb = scrollBarThumb ?: return
        val recyclerView = imageRecyclerView ?: return
        
        val topbarHeight = (48 * thumb.resources.displayMetrics.density).toInt()
        val thumbHeight = thumb.height
        val actualVisibleHeight = recyclerView.height
        val trackHeight = actualVisibleHeight - topbarHeight
        val maxOffset = trackHeight - thumbHeight
        
        if (maxOffset <= 0) return
        
        val currentMargin = scrollBarThumbTopMargin
        val newY = (currentMargin + deltaY).coerceIn(topbarHeight.toFloat(), (topbarHeight + maxOffset).toFloat()).toInt()
        
        // Update touch area thumb position
        thumb.translationY = newY.toFloat()
        
        // Update visual thumb position to match
        scrollBarThumbVisual?.let { visual ->
            visual.translationY = newY.toFloat()
        }
        
        scrollBarThumbTopMargin = newY
    }
    
    private fun scrollToThumbPosition(animated: Boolean) {
        val thumb = scrollBarThumb ?: return
        val recyclerView = imageRecyclerView ?: return
        
        val topbarHeight = (48 * thumb.resources.displayMetrics.density).toInt()
        val thumbHeight = thumb.height
        val actualVisibleHeight = recyclerView.height
        val trackHeight = actualVisibleHeight - topbarHeight
        val maxOffset = trackHeight - thumbHeight
        
        if (maxOffset <= 0) return
        
        // Calculate scroll ratio from thumb position: 0.0 (top) to 1.0 (bottom)
        val relativeY = scrollBarThumbTopMargin - topbarHeight
        val ratio = (relativeY.toFloat() / maxOffset).coerceIn(0f, 1f)
        
        val layoutManager = recyclerView.layoutManager ?: return
        val itemCount = recyclerView.adapter?.itemCount ?: 0
        if (itemCount == 0) return

        val spanCount = (layoutManager as? StaggeredGridLayoutManager)?.spanCount ?: (layoutManager as? GridLayoutManager)?.spanCount ?: 1
        val totalRows = Math.ceil(itemCount.toDouble() / spanCount).toInt()
        if (totalRows == 0) return

        val visibleHeight = actualVisibleHeight
        
        if (animated) {
            val contentHeight = recyclerView.computeVerticalScrollRange()
            if (contentHeight <= visibleHeight) return
            
            val scrollableHeight = contentHeight - visibleHeight
            val targetScrollOffset = (scrollableHeight * ratio).toInt().coerceIn(0, scrollableHeight)
            val currentScroll = recyclerView.computeVerticalScrollOffset()
            val scrollDelta = targetScrollOffset - currentScroll
            
            if (Math.abs(scrollDelta) > 1) {
                recyclerView.smoothScrollBy(0, scrollDelta)
            } else {
                updateDateForThumbPosition()
            }
        } else {
            // High-performance direct row scrolling (O(1) complexity)
            recyclerView.stopScroll()
            
            val exactRow = ratio * (totalRows - 1).coerceAtLeast(0)
            val targetRowIndex = exactRow.toInt()
            
            var rowHeight = 0
            if (layoutManager.childCount > 0) {
                val child = layoutManager.getChildAt(0)
                if (child != null) {
                    rowHeight = child.height
                }
            }
            if (rowHeight == 0) {
                rowHeight = visibleHeight / 4
            }
            
            val rowOffsetRatio = exactRow - targetRowIndex
            val offsetInPixels = -(rowHeight * rowOffsetRatio).toInt()
            
            val targetItemPosition = (targetRowIndex * spanCount).coerceIn(0, itemCount - 1)
            (layoutManager as? StaggeredGridLayoutManager)?.scrollToPositionWithOffset(targetItemPosition, offsetInPixels)
            (layoutManager as? GridLayoutManager)?.scrollToPositionWithOffset(targetItemPosition, offsetInPixels)
            
            updateDateForThumbPosition()
        }
    }
    
    private fun updateScrollBarPosition() {
        scrollBarThumb?.let { thumb ->
            scrollBarTrack?.let { track ->
                val recyclerView = imageRecyclerView ?: return
                
                // Wait for RecyclerView to be measured and laid out
                if (recyclerView.height == 0 || recyclerView.width == 0) {
                    return
                }
                
                // Calculate actual visible height
                val actualVisibleHeight = recyclerView.height
                
                // Use actual scroll offsets for accurate position calculation
                val contentHeight = recyclerView.computeVerticalScrollRange()
                val visibleHeight = actualVisibleHeight
                val scrollOffset = recyclerView.computeVerticalScrollOffset()
                
                // If content fits in view or no content, hide scroll bar
                if (contentHeight <= visibleHeight || contentHeight == 0) {
                    hideScrollBarAndDate()
                    return
                }
                
                val scrollableHeight = contentHeight - visibleHeight
                if (scrollableHeight <= 0) {
                    hideScrollBarAndDate()
                    return
                }
                
                // Calculate scroll ratio: 0.0 (top) to 1.0 (bottom)
                val scrollRatio = (scrollOffset.toFloat() / scrollableHeight).coerceIn(0f, 1f)
                
                val thumbHeight = thumb.height
                val topbarHeight = (48 * thumb.resources.displayMetrics.density).toInt()
                val trackHeight = actualVisibleHeight - topbarHeight // Restrict to below topbar
                val maxOffset = trackHeight - thumbHeight
                
                if (maxOffset <= 0) {
                    return
                }
                
                // Calculate thumb position: topbarHeight (top) to topbarHeight + maxOffset (bottom)
                val newTopMargin = topbarHeight + (maxOffset * scrollRatio).toInt().coerceIn(0, maxOffset)
                
                // Update touch area thumb position
                thumb.translationY = newTopMargin.toFloat()
                
                // Update visual thumb position to match
                scrollBarThumbVisual?.let { visual ->
                    visual.translationY = newTopMargin.toFloat()
                }
                
                scrollBarThumbTopMargin = newTopMargin
                
                // Update date indicator position to follow thumb
                updateDateIndicatorPosition()
            }
        }
    }
    
    /**
     * Throttled version of updateDateForCurrentScroll for better performance
     * Only updates date if enough time has passed since last update
     */
    private fun updateDateForCurrentScrollThrottled() {
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastDateUpdateTime >= DATE_UPDATE_THROTTLE_MS) {
            lastDateUpdateTime = currentTime
            updateDateForCurrentScroll()
        }
    }
    
    private fun updateDateForCurrentScroll() {
        val recyclerView = imageRecyclerView ?: return
        val layoutManager = recyclerView.layoutManager ?: return
        
        var firstVisiblePosition = layoutManager.findFirstVisibleItemPosition()
        
        // Account for camera cell if shown (adapter shows camera at position 0)
        // But imagesWithDates doesn't include camera, so we need to adjust
        if (firstVisiblePosition < 0) return
        
        // Camera cell is at position 0 if shown, so actual image index is position - 1
        // For now, we'll assume camera is shown if position 0 exists and has a special identifier
        // We can check if first visible is camera by checking adapter item count vs images count
        val adapter = adapter ?: return
        val totalItems = adapter.itemCount
        val totalImages = imagesWithDates.size
        val hasCamera = totalItems > totalImages
        
        val imageIndex = if (hasCamera && firstVisiblePosition == 0) {
            // First visible is camera, use next position
            val nextPosition = layoutManager.findFirstCompletelyVisibleItemPosition()
            if (nextPosition > 0) nextPosition - 1 else 0
        } else {
            firstVisiblePosition - if (hasCamera) 1 else 0
        }
        
        if (imageIndex < 0 || imageIndex >= imagesWithDates.size) return
        
        val imageWithDate = imagesWithDates[imageIndex]
        val dateString = formatDate(Date(imageWithDate.dateAdded * 1000))
        
        if (dateLabel?.text != dateString) {
            dateLabel?.text = dateString
            
            // Haptic feedback when date changes (only during drag for better UX)
            if (dateString != lastHapticDate && isDraggingScrollBar) {
                lastHapticDate = dateString
                performHapticFeedback()
            }
        }
    }
    
    /**
     * Perform haptic feedback with proper API level handling
     * Optimized to minimize overhead during fast scrolling
     */
    private fun performHapticFeedback() {
        try {
            val vibrator = context?.getSystemService(android.content.Context.VIBRATOR_SERVICE) as? android.os.Vibrator ?: return
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Use lighter haptic effect for better performance
                vibrator.vibrate(android.os.VibrationEffect.createOneShot(5, android.os.VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(5) // Reduced from 10ms to 5ms
            }
        } catch (e: Exception) {
            // Silently fail to avoid performance impact
        }
    }
    
    private fun updateDateForThumbPosition() {
        // Throttle date updates during thumb dragging for better performance
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastDateUpdateTime < DATE_UPDATE_THROTTLE_MS) {
            return // Skip this update, too soon
        }
        lastDateUpdateTime = currentTime
        
        scrollBarThumb?.let { thumb ->
            scrollBarTrack?.let { track ->
                val topbarHeight = (48 * thumb.resources.displayMetrics.density).toInt()
                val thumbHeight = thumb.height
                val trackHeight = track.height - topbarHeight
                val maxOffset = trackHeight - thumbHeight
                
                if (maxOffset <= 0 || imagesWithDates.isEmpty()) return
                
                val relativeY = scrollBarThumbTopMargin - topbarHeight
                val ratio = (relativeY.toFloat() / maxOffset).coerceIn(0f, 1f)
                val estimatedIndex = (imagesWithDates.size * ratio).toInt().coerceIn(0, imagesWithDates.size - 1)
                val imageWithDate = imagesWithDates[estimatedIndex]
                val dateString = formatDate(Date(imageWithDate.dateAdded * 1000))
                
                if (dateLabel?.text != dateString) {
                    dateLabel?.text = dateString
                    
                    // Haptic feedback when date changes
                    if (dateString != lastHapticDate) {
                        lastHapticDate = dateString
                        performHapticFeedback()
                    }
                }
            }
        }
    }
    
    private fun formatDate(date: Date): String {
        // Use cached date format to avoid repeated SimpleDateFormat creation
        if (cachedDateFormat == null) {
            cachedDateFormat = SimpleDateFormat(getDateFormatPattern(), Locale(languageCode))
        }
        return cachedDateFormat?.format(date) ?: ""
    }
    
    private fun getDateFormatPattern(): String {
        return when (languageCode) {
            "ko" -> "yyyy년 M월"
            "ja" -> "yyyy年M月"
            "zh" -> "yyyy年M月"
            else -> "MMM yyyy"
        }
    }
    
    private fun moveDateIndicatorToCenter(animated: Boolean) {
        dateScrollIndicator?.let { indicator ->
            val parent = indicator.parent as? ViewGroup ?: return@let
            
            if (animated) {
                val transition = android.transition.ChangeBounds()
                transition.duration = 200
                transition.interpolator = android.view.animation.DecelerateInterpolator()
                android.transition.TransitionManager.beginDelayedTransition(parent, transition)
            }
            
            val layoutParams = indicator.layoutParams as? FrameLayout.LayoutParams ?: return@let
            layoutParams.gravity = Gravity.CENTER_HORIZONTAL or Gravity.TOP
            indicator.layoutParams = layoutParams
            
            updateDateIndicatorVerticalPosition()
            
            // Ensure indicator is visible and above other views
            indicator.bringToFront()
            
            if (animated) {
                indicator.animate()
                    .alpha(1f)
                    .scaleX(1.1f)
                    .scaleY(1.1f)
                    .setDuration(200)
                    .withEndAction(null)
                    .start()
            } else {
                indicator.alpha = 1f
                indicator.scaleX = 1.1f
                indicator.scaleY = 1.1f
            }
        }
    }
    
    private fun moveDateIndicatorToEdge(animated: Boolean) {
        dateScrollIndicator?.let { indicator ->
            if (animated) {
                val parent = indicator.parent as? ViewGroup
                if (parent != null) {
                    val transition = android.transition.ChangeBounds()
                    transition.duration = 200
                    transition.interpolator = android.view.animation.DecelerateInterpolator()
                    android.transition.TransitionManager.beginDelayedTransition(parent, transition)
                }
            }
            
            val layoutParams = indicator.layoutParams as? FrameLayout.LayoutParams
            if (layoutParams != null) {
                layoutParams.gravity = Gravity.END or Gravity.TOP
                indicator.layoutParams = layoutParams
            }
            
            // Update position to match thumb
            updateDateIndicatorVerticalPosition()
            
            if (animated) {
                indicator.animate()
                    .alpha(1f)
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(200)
                    .withEndAction(null)
                    .start()
            }
        }
    }
    
    private fun updateDateIndicatorPosition() {
        if (isDraggingScrollBar) return
        updateDateIndicatorVerticalPosition()
    }
    
    private fun updateDateIndicatorVerticalPosition() {
        dateScrollIndicator?.let { indicator ->
            scrollBarThumb?.let { thumb ->
                // Get thumb's top margin (which is relative to its parent)
                val thumbTopMargin = scrollBarThumbTopMargin
                val thumbHeight = thumb.height
                val thumbCenterY = thumbTopMargin + thumbHeight / 2
                
                // Calculate indicator position to align with thumb center
                var indicatorHeight = indicator.height
                if (indicatorHeight == 0) {
                    indicator.measure(android.view.View.MeasureSpec.UNSPECIFIED, android.view.View.MeasureSpec.UNSPECIFIED)
                    indicatorHeight = indicator.measuredHeight
                }
                
                val indicatorCenterY = indicatorHeight / 2
                
                // Set indicator translationY to align centers
                val indicatorTopMargin = (thumbCenterY - indicatorCenterY).coerceAtLeast(0)
                
                indicator.translationY = indicatorTopMargin.toFloat()
            }
        }
    }
    
    private fun showScrollBarAndDate() {
        // Cancel hide timer if active
        dateHideRunnable?.let { dateHideTimer?.removeCallbacks(it) }
        
        // Only show date indicator if RecyclerView is actually scrollable
        val recyclerView = imageRecyclerView ?: return
        
        // Check if RecyclerView can scroll
        val canScroll = recyclerView.canScrollVertically(1) || 
                       recyclerView.canScrollVertically(-1) ||
                       recyclerView.computeVerticalScrollRange() > recyclerView.height
        
        if (!canScroll) {
            // Not scrollable, don't show date indicator
            return
        }
        
        // Only show date indicator, scrollbar visuals are hidden
        dateScrollIndicator?.let {
            if (it.visibility != View.VISIBLE) {
                it.visibility = View.VISIBLE
                it.isClickable = true
                it.isFocusable = true
                it.alpha = 0f
                it.animate().alpha(1f).setDuration(200).withEndAction(null).start()
            } else if (it.alpha < 1f && it.animate().duration == 300L) {
                // If it's currently fading out, reverse it
                it.animate().alpha(1f).setDuration(200).withEndAction(null).start()
            }
        }
    }
    
    private fun hideScrollBarAndDate() {
        if (isDraggingScrollBar) return
        
        // Only hide date indicator, scrollbar visuals are always hidden
        dateScrollIndicator?.let {
            if (it.visibility == View.VISIBLE && it.alpha > 0f) {
                it.animate().alpha(0f).setDuration(300)
                    .withEndAction {
                        if (!isDraggingScrollBar) {
                            it.visibility = View.GONE
                            it.isClickable = false
                            it.isFocusable = false
                        }
                    }
                    .start()
            }
        }
    }
    
    private fun scheduleDateIndicatorHide() {
        if (dateHideRunnable == null) {
            dateHideRunnable = Runnable {
                hideScrollBarAndDate()
            }
        }
        dateHideRunnable?.let { dateHideTimer?.removeCallbacks(it) }
        dateHideTimer?.postDelayed(dateHideRunnable!!, 800)
    }

    fun setOnImagesSelectedListener(listener: (List<Uri>) -> Unit) {
        onImagesSelected = listener
    }

    fun setOnCancelledListener(listener: () -> Unit) {
        onCancelled = listener
    }
    
    fun setOnDismissedListener(listener: () -> Unit) {
        onDismissed = listener
    }

    override fun onDismiss(dialog: android.content.DialogInterface) {
        super.onDismiss(dialog)
        
        Log.d(TAG, "onDismiss: Cleaning up resources before dismissing")
        
        // Clean up before dismissing
        // Cancel all animations and timers
        runningFadeOutAnimator?.cancel()
        runningFadeOutAnimator = null
        runningFadeInAnimator?.cancel()
        runningFadeInAnimator = null
        dateHideTimer?.removeCallbacksAndMessages(null)
        dateHideTimer = null
        pauseCheckRunnable = null
        
        // Clear any pending Glide requests
        try {
            context?.let { ctx ->
                com.bumptech.glide.Glide.with(ctx).pauseRequests()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error pausing Glide requests", e)
        }
        
        // Handle callbacks before cleanup
        // Only invoke callbacks if they haven't been invoked already
        // If explicitly cancelled (close button or swipe), return empty array instead of null
        if (!hasInvokedCallback) {
            val selectedImagesCopy = selectedImages.toList()
            val imagesSelectedCallback = onImagesSelected
            val cancelledCallback = onCancelled
            
            // Clear callbacks first to prevent issues
            // onImagesSelected = null
            // onCancelled = null
            
            // If explicitly cancelled (close button or swipe), return empty array
            if (isExplicitlyCancelled) {
                hasInvokedCallback = true
                imagesSelectedCallback?.invoke(emptyList())
            } else if (selectedImagesCopy.isNotEmpty()) {
                // Images were selected and not explicitly cancelled - return them
                hasInvokedCallback = true
                imagesSelectedCallback?.invoke(selectedImagesCopy)
            } else {
                // No images selected - return empty array
                imagesSelectedCallback?.invoke(emptyList())
            }
        } else {
            // Callback already invoked, just clear references
            // onImagesSelected = null
            // onCancelled = null
        }
        
        // Reset state
        isDismissing = false
        
        // Notify that bottom sheet is fully dismissed (after animation completes)
        // This allows activity to finish after bottom sheet animation completes
        onDismissed?.invoke()
        // onDismissed = null
    }

    override fun onDestroyView() {
        super.onDestroyView()
        
        Log.d(TAG, "onDestroyView: Starting memory cleanup")
        
        // Cancel all running animations
        runningFadeOutAnimator?.cancel()
        runningFadeOutAnimator = null
        runningFadeInAnimator?.cancel()
        runningFadeInAnimator = null
        
        // Clean up RecyclerView and free memory
        imageRecyclerView?.let { recyclerView ->
            // Remove all scroll listeners
            recyclerView.clearOnScrollListeners()
            
            // Remove touch listener
            recyclerView.setOnTouchListener(null)
            
            // Clear adapter and layout manager
            recyclerView.adapter = null
            recyclerView.layoutManager = null
            
            // Clear recycled view pool to free memory
            recyclerView.recycledViewPool.clear()
            
            // Reset padding
            if (originalPadding > 0) {
                val topPadding = if (currentTopPadding > 0) currentTopPadding else {
                    originalPadding + (48 * resources.displayMetrics.density).toInt()
                }
                recyclerView.setPadding(
                    originalPadding,
                    topPadding,
                    originalPadding,
                    originalPadding
                )
            }
        }
        
        // Clean up adapter and clear Glide cache
        adapter?.let {
            // Clear selection to free references
            it.clearSelection()
            // Clean up adapter resources
            it.cleanup()
        }
        adapter = null
        
        // AGGRESSIVE MEMORY CLEANUP: Clear Glide's entire memory cache when gallery closes!
        // This is crucial for preventing the app from slowing down after scrolling 10,000+ images.
        try {
            context?.let { ctx ->
                com.bumptech.glide.Glide.get(ctx).clearMemory()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing Glide memory cache", e)
        }
        
        // Clear Glide memory cache for this context
        try {
            context?.let { ctx ->
                // Clear Glide memory on background thread
                scope.launch(Dispatchers.IO) {
                    try {
                        com.bumptech.glide.Glide.get(ctx).clearDiskCache()
                    } catch (e: Exception) {
                        Log.e(TAG, "Error clearing Glide disk cache", e)
                    }
                }
                // Clear memory cache on main thread
                com.bumptech.glide.Glide.get(ctx).clearMemory()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing Glide cache", e)
        }
        
        // Remove all touch listeners
        scrollBarTrack?.setOnTouchListener(null)
        scrollBarThumb?.setOnTouchListener(null)
        dateScrollIndicator?.setOnTouchListener(null)
        
        // Remove BottomSheetBehavior callbacks
        behavior?.removeBottomSheetCallback(object : BottomSheetBehavior.BottomSheetCallback() {
            override fun onStateChanged(bottomSheet: View, newState: Int) {}
            override fun onSlide(bottomSheet: View, slideOffset: Float) {}
        })
        
        // Cancel coroutine scope - this will cancel all running coroutines
        scope.cancel()
        
        // Clean up quick scroller - remove all callbacks first
        dateHideTimer?.removeCallbacksAndMessages(null)
        dateHideTimer = null
        dateHideRunnable = null
        pauseCheckRunnable = null
        
        // Nullify all view references to prevent memory leaks
        behavior = null
        bottomSheetView = null
        headerView = null
        albumTitleLayout = null
        albumTitleText = null
        tabContainer = null
        tabActiveIndicator = null
        allTabButton = null
        selectedCountTab = null
        imageRecyclerView = null
        closeButton = null
        doneButton = null
        selectedCountLayout = null
        selectedCountText = null
        loadingIndicator = null
        rootContentView = null
        recyclerViewContainer = null
        
        // Quick scroller views
        scrollBarTrack = null
        scrollBarThumb = null
        scrollBarThumbVisual = null
        scrollBarTrackVisual = null
        dateScrollIndicator = null
        dateLabel = null
        
        // Clear collections to free memory
        imagesWithDates = emptyList()
        // selectedImages = emptyList() // DO NOT clear selection
        
        // Clear callbacks to prevent memory leaks
        // onImagesSelected = null
        // onCancelled = null
        // onDismissed = null
        
        // Reset state
        originalPadding = 0
        selectedCountHeight = 0
        currentImageCount = 0
        allImagesCount = 0
        isDraggingScrollBar = false
        scrollBarThumbTopMargin = 0
        lastHapticDate = ""
        isExplicitlyCancelled = false
        isShowingOnlySelected = false
        imagesLoaded = false
        isDismissing = false
        hasInvokedCallback = false
        isQuickScrolling = false
        isFastScrolling = false
        lastDateUpdateTime = 0L
        lastScrollTime = 0L
        lastScrollY = 0
        lastMoveTime = 0L
        lastImageLoadTime = 0L
        dragVelocity = 0f
        lastDragDistance = 0f
        cachedDateFormat = null
        
        // Clear camera references
        cameraImageUri = null
        cameraImageFile = null
    }
    private fun RecyclerView.LayoutManager.findFirstVisibleItemPosition(): Int {
        return when (this) {
            is GridLayoutManager -> this.findFirstVisibleItemPosition()
            is StaggeredGridLayoutManager -> {
                val positions = IntArray(spanCount)
                findFirstVisibleItemPositions(positions)
                positions.minOrNull() ?: 0
            }
            else -> 0
        }
    }

    private fun RecyclerView.LayoutManager.findLastVisibleItemPosition(): Int {
        return when (this) {
            is GridLayoutManager -> this.findLastVisibleItemPosition()
            is StaggeredGridLayoutManager -> {
                val positions = IntArray(spanCount)
                findLastVisibleItemPositions(positions)
                positions.maxOrNull() ?: 0
            }
            else -> 0
        }
    }
    private fun RecyclerView.LayoutManager.findFirstCompletelyVisibleItemPosition(): Int {
        return when (this) {
            is GridLayoutManager -> this.findFirstCompletelyVisibleItemPosition()
            is StaggeredGridLayoutManager -> {
                val positions = IntArray(spanCount)
                findFirstCompletelyVisibleItemPositions(positions)
                positions.minOrNull() ?: 0
            }
            else -> 0
        }
    }
}

