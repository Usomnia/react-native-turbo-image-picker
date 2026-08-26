package com.rnturboimagepicker

import android.net.Uri
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.cardview.widget.CardView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.bumptech.glide.Priority
import com.bumptech.glide.request.RequestListener
import com.bumptech.glide.request.target.Target
import com.bumptech.glide.load.DataSource
import com.bumptech.glide.load.engine.GlideException

class ImageGridAdapter(
    private var images: MutableList<Uri>,
    private val maxSelection: Int = 1,
    private val themeColor: Int? = null,
    private val enableEditor: Boolean = true,
    private val onImageSelected: (List<Uri>) -> Unit,
    private val onImageClick: ((Uri, Int, android.view.View) -> Unit)? = null,
    private val onCameraClick: ((View) -> Unit)? = null,
    private val onBindCameraPreview: ((androidx.camera.view.PreviewView) -> Unit)? = null,
    private val hasCameraPermission: (() -> Boolean)? = null,
    private val onDeselectEditedImage: ((Uri, () -> Unit) -> Unit)? = null
) : RecyclerView.Adapter<ImageGridAdapter.ImageViewHolder>() {

    // Use LinkedHashSet to maintain insertion order with O(1) lookup
    private val selectedImages = LinkedHashSet<Uri>()

    private var selectedImagesList: List<Uri> = emptyList()
    private var currentTargetSize = 400
    private var editedImages: Map<String, Uri> = emptyMap()

    fun updateEditedImages(map: Map<String, Uri>, notify: Boolean = true) {
        editedImages = map
        if (notify) {
            notifyDataSetChanged()
        }
    }
    
    fun setSelectedImages(uris: List<Uri>, notify: Boolean = true) {
        selectedImages.clear()
        selectedImages.addAll(uris)
        updateSelectedImagesCache()
        if (notify) {
            notifyDataSetChanged()
        }
    }

    fun updateTargetSize(newSize: Int, recyclerView: RecyclerView) {
        if (currentTargetSize != newSize) {
            currentTargetSize = newSize
        }
    }
    
    fun reloadVisibleItems(recyclerView: RecyclerView) {
        val reloadAction = Runnable {
            val lm = recyclerView.layoutManager ?: return@Runnable
            val first = (lm as? androidx.recyclerview.widget.GridLayoutManager)?.findFirstVisibleItemPosition()
                ?: (lm as? androidx.recyclerview.widget.StaggeredGridLayoutManager)?.let {
                    val positions = IntArray(it.spanCount)
                    it.findFirstVisibleItemPositions(positions)
                    positions.minOrNull() ?: 0
                } ?: return@Runnable
            val last = (lm as? androidx.recyclerview.widget.GridLayoutManager)?.findLastVisibleItemPosition()
                ?: (lm as? androidx.recyclerview.widget.StaggeredGridLayoutManager)?.let {
                    val positions = IntArray(it.spanCount)
                    it.findLastVisibleItemPositions(positions)
                    positions.maxOrNull() ?: 0
                } ?: return@Runnable
                
            if (first >= 0 && last >= first) {
                notifyItemRangeChanged(first, last - first + 1, "HIGH_RES")
            }
        }
        
        if (recyclerView.isComputingLayout) {
            recyclerView.post(reloadAction)
        } else {
            reloadAction.run()
        }
    }

    
    private fun updateSelectedImagesCache() {
        selectedImagesList = selectedImages.toList()
    }
    
    private var showOnlySelected = false
    internal var showCamera = true // Show camera cell as first item
    
    // Quick scroll mode: when true, minimize image loading for performance
    private var isQuickScrolling = false
    
    // Very fast scroll mode: when true, skip image loading completely (placeholder only)
    private var isFastScrolling = false
    var lastCameraFrame: android.graphics.Bitmap? = null
    
    init {
        // Enable stable IDs for better performance with large datasets
        setHasStableIds(true)
    }
    
    /**
     * Set quick scroll mode to optimize image loading during fast scrolling
     */
    fun setQuickScrollMode(scrolling: Boolean) {
        isQuickScrolling = scrolling
    }
    
    /**
     * Set fast scroll mode for extremely fast scrolling (drag)
     * When enabled, only shows placeholders without loading any images
     */
    fun setFastScrollMode(scrolling: Boolean) {
        isFastScrolling = scrolling
    }

    inner class ImageViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val imageView: ImageView = itemView.findViewById(R.id.imageView)
        val placeholderIcon: ImageView = itemView.findViewById(R.id.placeholderIcon)
        val selectionOverlay: View = itemView.findViewById(R.id.selectionOverlay)
        val checkmark: ImageView = itemView.findViewById(R.id.checkmark)
        val selectionCircleBorder: View = itemView.findViewById(R.id.selectionCircleBorder)
        val selectionNumber: TextView = itemView.findViewById(R.id.selectionNumber)
        val selectionBadgeContainer: View = itemView.findViewById(R.id.selectionBadgeContainer)
        val selectionTouchArea: View = itemView.findViewById(R.id.selectionTouchArea)
        val cardView: CardView = itemView.findViewById(R.id.cardView)
        val cameraPreview: androidx.camera.view.PreviewView? = itemView.findViewById(R.id.cameraPreview)
        val cameraLastFrameView: ImageView? = itemView.findViewById(R.id.cameraLastFrameView)
        val cameraOverlayIcon: ImageView? = itemView.findViewById(R.id.cameraOverlayIcon)
        val permissionPromptText: TextView? = itemView.findViewById(R.id.permissionPromptText)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ImageViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_image_grid, parent, false)
        val holder = ImageViewHolder(view)
        // Explicitly remove all backgrounds and foregrounds to prevent any ripple effect
        view.background = null
        holder.cardView.background = null
        holder.imageView.background = null
        val imageContainer: View = view.findViewById(R.id.imageContainer)
        imageContainer.background = null
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            view.foreground = null
            holder.cardView.foreground = null
            holder.imageView.foreground = null
        }
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
            view.stateListAnimator = null
            holder.cardView.stateListAnimator = null
        }
        
        return holder
    }
    
    override fun onViewDetachedFromWindow(holder: ImageViewHolder) {
        super.onViewDetachedFromWindow(holder)
        val isCameraCell = !showOnlySelected && showCamera && holder.layoutPosition == 0
        if (isCameraCell) {
            holder.cameraPreview?.bitmap?.let { bitmap ->
                lastCameraFrame = bitmap
            }
        }
    }
    
    override fun getItemCount(): Int {
        return if (showOnlySelected) {
            selectedImages.size
        } else {
            // Add 1 for camera cell if showing camera
            images.size + if (showCamera) 1 else 0
        }
    }
    
    fun getPositionForUri(uriStr: String): Int {
        if (showOnlySelected) {
            return selectedImagesList.indexOfFirst { it.toString() == uriStr }
        } else {
            val idx = images.indexOfFirst { it.toString() == uriStr }
            if (idx == -1) return -1
            return if (showCamera) idx + 1 else idx
        }
    }
    
    override fun getItemId(position: Int): Long {
        if (!showOnlySelected && showCamera && position == 0) {
            return -1 // Fixed ID for camera cell
        }
        
        val uri = if (showOnlySelected) {
            selectedImagesList[position]
        } else {
            images[if (showCamera) position - 1 else position]
        }
        return uri.hashCode().toLong()
    }


    override fun onBindViewHolder(holder: ImageViewHolder, position: Int, payloads: MutableList<Any>) {
        var handled = false
        
        if (payloads.isNotEmpty() && payloads.contains("SELECTION_CHANGED")) {
            // Update selection UI
            if (!(!showOnlySelected && showCamera && position == 0)) {
                val imageUri = if (showOnlySelected) {
                    selectedImagesList[position]
                } else {
                    images[if (showCamera) position - 1 else position]
                }
                val isSelected = selectedImages.contains(imageUri)
                
                updateSelectionUI(holder, isSelected, imageUri)
                handled = true
            }
        }
        
        if (payloads.isNotEmpty() && (payloads.contains("EDIT_CHANGED") || payloads.contains("HIGH_RES"))) {
            // Update image UI
            if (!(!showOnlySelected && showCamera && position == 0)) {
                val imageUri = if (showOnlySelected) {
                    selectedImagesList[position]
                } else {
                    images[if (showCamera) position - 1 else position]
                }
                val displayUri = editedImages[imageUri.toString()] ?: imageUri
                
                // Use loadImage to leverage FastThumbnail and hardware acceleration
                loadImage(holder, displayUri, isHighResReload = true)
                handled = true
            }
        }
        
        if (handled) return
        
        super.onBindViewHolder(holder, position, payloads)
    }

    override fun onBindViewHolder(holder: ImageViewHolder, position: Int) {
        // Check if this is camera cell (first position when not showing only selected)
        val isCameraCell = !showOnlySelected && showCamera && position == 0
        
        val frameLayout = holder.itemView as? SquareFrameLayout
        
        if (isCameraCell) {
            frameLayout?.verticalSpan = 2
            holder.cardView.radius = 0f // No corner radius for camera cell
            
            // Setup live camera preview instead of static icon
            holder.imageView.visibility = View.GONE
            holder.placeholderIcon.visibility = View.GONE
            
            holder.cameraPreview?.visibility = View.VISIBLE
            holder.cameraOverlayIcon?.visibility = View.VISIBLE
            
            if (lastCameraFrame != null) {
                holder.cameraLastFrameView?.setImageBitmap(lastCameraFrame)
                holder.cameraLastFrameView?.visibility = View.VISIBLE
                holder.cameraLastFrameView?.alpha = 1f
            } else {
                holder.cameraLastFrameView?.visibility = View.GONE
            }
            
            val hasPermission = hasCameraPermission?.invoke() ?: false
            if (hasPermission) {
                holder.permissionPromptText?.visibility = View.GONE
                // Pass the preview view to the fragment to bind CameraX
                holder.cameraPreview?.let { previewView ->
                    previewView.tag = holder.cameraLastFrameView
                    onBindCameraPreview?.invoke(previewView)
                }
            } else {
                holder.permissionPromptText?.visibility = View.VISIBLE
            }
            
            // Hide all selection UI for camera cell
            holder.selectionOverlay.visibility = View.GONE
            holder.checkmark.visibility = View.GONE
            holder.selectionCircleBorder.visibility = View.GONE
            holder.selectionNumber.visibility = View.GONE
            holder.selectionTouchArea.visibility = View.GONE
            
            // Handle camera click
            holder.itemView.setOnClickListener {
                onCameraClick?.invoke(holder.itemView)
            }
            return
        } else {
            frameLayout?.verticalSpan = 1
            holder.imageView.visibility = View.VISIBLE
            holder.cameraPreview?.visibility = View.GONE
            holder.cameraLastFrameView?.visibility = View.GONE
            holder.cameraOverlayIcon?.visibility = View.GONE
            holder.permissionPromptText?.visibility = View.GONE
            holder.selectionTouchArea.visibility = View.VISIBLE
        }
        
        val imageUri = if (showOnlySelected) {
            selectedImagesList[position]
        } else {
            images[if (showCamera) position - 1 else position]
        }
        val isSelected = selectedImages.contains(imageUri)

        // Reset image view scale type for normal cells
        holder.imageView.scaleType = android.widget.ImageView.ScaleType.CENTER_CROP
        
        // Show placeholder icon while loading
        holder.placeholderIcon.visibility = View.VISIBLE
        
        // Clear previous image
        holder.imageView.setImageDrawable(null)
        holder.imageView.setBackgroundColor(android.graphics.Color.TRANSPARENT)
        
        // Build Glide request with custom FastThumbnail model to force OS-level hardware thumbnails
        val displayUri = editedImages[imageUri.toString()] ?: imageUri
        loadImage(holder, displayUri, isHighResReload = false)

        // Update selection UI
        updateSelectionUI(holder, isSelected, imageUri)

        // Handle click logic based on maxSelection and enableEditor
        val performClick = { isBadgeClick: Boolean ->
            val currentPos = holder.bindingAdapterPosition
            if (currentPos != androidx.recyclerview.widget.RecyclerView.NO_POSITION) {
                val currentUri = if (showOnlySelected) {
                    selectedImagesList[currentPos]
                } else {
                    images[if (showCamera) currentPos - 1 else currentPos]
                }

                if (enableEditor) {
                    // Editor is enabled: Split click logic for multi-selection, direct launch for single selection
                    if (maxSelection > 1 && isBadgeClick) {
                        val handledAsync = toggleSelection(currentUri)
                        if (!handledAsync) {
                            notifyItemChanged(currentPos, "SELECTION_CHANGED")
                            onImageSelected(selectedImagesList)
                        }
                    } else {
                        onImageClick?.invoke(currentUri, currentPos, holder.itemView)
                    }
                } else {
                    // Standard click logic (Single selection or Multi-selection without Editor)
                    val wasSelected = selectedImages.contains(currentUri)
                    val handledAsync = toggleSelection(currentUri)
                    
                    if (!handledAsync) {
                        // For single selection mode (maxSelection <= 1), callback immediately without notifying
                        // This prevents crash when bottom sheet dismisses during notification
                        if (maxSelection <= 1 && selectedImages.contains(currentUri)) {
                            onImageSelected(selectedImagesList)
                        } else {
                            // For multi-selection mode, update UI and callback
                            if (showOnlySelected && wasSelected && !selectedImages.contains(currentUri)) {
                                // Item was deselected and removed from filtered list
                                notifyDataSetChanged()
                            } else {
                                // Notify this item changed
                                notifyItemChanged(currentPos, "SELECTION_CHANGED")
                            }
                            onImageSelected(selectedImagesList)
                        }
                    }
                }
            }
        }

        if (maxSelection > 1 && enableEditor) {
            holder.selectionTouchArea.setOnClickListener { performClick(true) }
            holder.itemView.setOnClickListener { performClick(false) }
        } else {
            val clickListener = View.OnClickListener { performClick(false) }
            holder.selectionTouchArea.setOnClickListener(clickListener)
            holder.itemView.setOnClickListener(clickListener)
        }
    }

    fun insertAndSelectImage(imageUri: Uri) {
        // Insert at the beginning (index 0) of the images list
        images.add(0, imageUri)
        
        // Ensure it is selected (respecting maxSelection limits)
        if (maxSelection > 0) {
            if (maxSelection == 1) {
                selectedImages.clear()
            }
            if (selectedImages.size < maxSelection || maxSelection == 1) {
                selectedImages.add(imageUri)
                updateSelectedImagesCache()
            }
        } else if (maxSelection == 0) {
            // Single selection mode (0)
            selectedImages.clear()
            selectedImages.add(imageUri)
            updateSelectedImagesCache()
        }
        
        // Notify insertion. Position 0 is camera if showCamera is true, so image is at position 1.
        val insertPos = if (showCamera) 1 else 0
        notifyItemInserted(insertPos)
        
        // Also notify the rest if needed, but for insertion at top, it shifts automatically.
        // However, we should notify the previous selection to clear their badges if it's single selection mode
        if (maxSelection <= 1) {
            notifyDataSetChanged()
        }
        
        // Trigger callback
        onImageSelected(selectedImagesList)
    }

    private fun toggleSelection(imageUri: Uri): Boolean {
        // If maxSelection is less than 0, disable selection
        if (maxSelection < 0) {
            return false
        }
        
        val wasSelected = selectedImages.contains(imageUri)
        
        if (wasSelected) {
            if (editedImages.containsKey(imageUri.toString()) && onDeselectEditedImage != null) {
                onDeselectEditedImage.invoke(imageUri) {
                    selectedImages.remove(imageUri)
                    updateSelectedImagesCache()
                    val pos = getPositionForUri(imageUri.toString())
                    if (pos != -1) notifyItemChanged(pos) // Full rebind to update both image and selection UI
                    onImageSelected(selectedImagesList)
                }
                return true
            } else {
                selectedImages.remove(imageUri)
                updateSelectedImagesCache()
            }
        } else {
            if (maxSelection <= 1) {
                // Single selection mode
                val previousSelected = selectedImagesList
                selectedImages.clear()
                selectedImages.add(imageUri)
                updateSelectedImagesCache()
                
                // Notify previous selection removed
                previousSelected.forEach { uri ->
                    val index = getPositionForUri(uri.toString())
                    if (index >= 0) {
                        notifyItemChanged(index, "SELECTION_CHANGED")
                    }
                }
            } else {
                // Multi-selection mode (maxSelection > 0)
                if (selectedImages.size < maxSelection) {
                    selectedImages.add(imageUri)
                    updateSelectedImagesCache()
                }
            }
        }
        return false
    }

    private fun updateSelectionUI(holder: ImageViewHolder, isSelected: Boolean, imageUri: Uri) {
        Log.d("ImageGridAdapter", "updateSelectionUI: maxSelection=$maxSelection, isSelected=$isSelected")
        
        if (themeColor != null) {
            holder.selectionNumber.backgroundTintList = android.content.res.ColorStateList.valueOf(themeColor)
            holder.checkmark.imageTintList = android.content.res.ColorStateList.valueOf(themeColor)
        }
        
        // Reset to original background color for unselected items (removed border foreground)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            holder.cardView.foreground = null
        }
        
        if (maxSelection > 1) {
            // Multi-selection mode: always show circle (border or filled)
            holder.selectionBadgeContainer.visibility = View.VISIBLE
            if (isSelected) {
                Log.d("ImageGridAdapter", "Showing selection number")
                holder.selectionOverlay.visibility = View.GONE
                holder.checkmark.visibility = View.GONE
                holder.selectionCircleBorder.visibility = View.GONE
                holder.selectionNumber.visibility = View.VISIBLE
                val index = selectedImagesList.indexOf(imageUri) + 1
                holder.selectionNumber.text = index.toString()
            } else {
                Log.d("ImageGridAdapter", "Showing circle border")
                holder.selectionOverlay.visibility = View.GONE
                holder.checkmark.visibility = View.GONE
                holder.selectionCircleBorder.visibility = View.VISIBLE
                holder.selectionNumber.visibility = View.GONE
            }
        } else {
            // Single selection mode (maxSelection == 1 or 0)
            holder.selectionBadgeContainer.visibility = View.GONE
            if (isSelected) {
                if (!enableEditor) {
                    // Hide selection UI if single selection and editor is disabled
                    holder.selectionOverlay.visibility = View.GONE
                    holder.checkmark.visibility = View.GONE
                } else {
                    holder.selectionOverlay.visibility = View.GONE
                    holder.checkmark.visibility = View.VISIBLE
                }
                holder.selectionCircleBorder.visibility = View.GONE
                holder.selectionNumber.visibility = View.GONE
            } else {
                holder.selectionOverlay.visibility = View.GONE
                holder.checkmark.visibility = View.GONE
                holder.selectionCircleBorder.visibility = View.GONE
                holder.selectionNumber.visibility = View.GONE
            }
        }
    }
    
    override fun onViewRecycled(holder: ImageViewHolder) {
        super.onViewRecycled(holder)
        // Clear Glide load when view is recycled to prevent memory leaks
        try {
            com.bumptech.glide.Glide.with(holder.itemView.context).clear(holder.imageView)
        } catch (e: Exception) {
            // Ignore if context is no longer valid
        }
    }
    
    private fun loadImage(holder: ImageViewHolder, imageUri: Uri, isHighResReload: Boolean = false) {
        val targetSize = currentTargetSize
        
        val requestBuilder = if (imageUri.scheme == "file") {
            val path = imageUri.path ?: ""
            Glide.with(holder.itemView.context).load(java.io.File(path))
        } else {
            Glide.with(holder.itemView.context).load(com.rnturboimagepicker.glide.FastThumbnail(imageUri, targetSize))
        }
        
        requestBuilder
            .centerCrop()
            .format(com.bumptech.glide.load.DecodeFormat.PREFER_RGB_565)
            .diskCacheStrategy(DiskCacheStrategy.NONE)
            .skipMemoryCache(false)
            .override(targetSize, targetSize)
            .priority(Priority.HIGH)
            
        if (isHighResReload && holder.imageView.drawable != null) {
            // Keep the current low-res image as placeholder to prevent flickering!
            requestBuilder.placeholder(holder.imageView.drawable)
            requestBuilder.error(holder.imageView.drawable)
        } else {
            requestBuilder.placeholder(R.drawable.image_placeholder)
            requestBuilder.error(R.drawable.image_placeholder)
        }
            .dontAnimate()
        
        requestBuilder
            .listener(object : RequestListener<android.graphics.drawable.Drawable> {
                override fun onLoadFailed(
                    e: GlideException?,
                    model: Any?,
                    target: Target<android.graphics.drawable.Drawable>,
                    isFirstResource: Boolean
                ): Boolean {
                    holder.placeholderIcon.visibility = View.GONE
                    return false
                }

                override fun onResourceReady(
                    resource: android.graphics.drawable.Drawable,
                    model: Any,
                    target: Target<android.graphics.drawable.Drawable>,
                    dataSource: DataSource,
                    isFirstResource: Boolean
                ): Boolean {
                    holder.placeholderIcon.visibility = View.GONE
                    return false
                }
            })
            .into(holder.imageView)
    }

    /**
     * Clean up all resources when adapter is being destroyed
     */
    fun cleanup() {
        try {
            // Clear all selections
            selectedImages.clear()
            updateSelectedImagesCache()
            images.clear()
            
            // Notify to unbind all views
            notifyDataSetChanged()
        } catch (e: Exception) {
            // Ignore any errors during cleanup
        }
    }

    fun getSelectedImages(): List<Uri> = selectedImagesList

    fun clearSelection() {
        val oldSelected = selectedImages.toList()
        selectedImages.clear()
        updateSelectedImagesCache()
        for (uri in oldSelected) {
            val pos = images.indexOf(uri)
            if (pos >= 0) {
                notifyItemChanged(if (showCamera) pos + 1 else pos, "SELECTION_CHANGED")
            }
        }
    }
    
    fun updateImages(newImages: List<Uri>, isAppend: Boolean = false) {
        val oldSize = images.size
        val newSize = newImages.size
        
        if (isAppend && newSize > oldSize) {
            // Only add new images to prevent flickering (for progressive load)
            val newImagesToAdd = newImages.subList(oldSize, newSize)
            images.addAll(newImagesToAdd)
            
            // Only notify about the newly inserted items (no flicker)
            notifyItemRangeInserted(oldSize, newImagesToAdd.size)
            
            Log.d("ImageGridAdapter", "Appended ${newImagesToAdd.size} new images, total now: ${images.size}")
        } else {
            // If album changed, replace all images
            images.clear()
            images.addAll(newImages)
            
            if (!isAppend) {
                selectedImages.clear() // Clear selection when album changes completely
                updateSelectedImagesCache()
            }
            
            notifyDataSetChanged()
            Log.d("ImageGridAdapter", "Replaced all images: ${images.size}")
        }
    }
    
    fun showOnlySelected(showOnly: Boolean) {
        showOnlySelected = showOnly
        notifyDataSetChanged()
    }
}
