package com.rnturboimagepicker

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import com.facebook.react.bridge.*
import com.facebook.react.module.annotations.ReactModule
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.*

@ReactModule(name = RNTurboImagePickerModule.NAME)
class RNTurboImagePickerModule(reactContext: ReactApplicationContext) :
    NativeTurboImagePickerSpec(reactContext), ActivityEventListener {

    companion object {
        const val NAME = "RNTurboImagePicker"
        private const val E_PICKER_CANCELLED = "E_PICKER_CANCELLED"
        private const val E_NO_ACTIVITY = "E_NO_ACTIVITY"
        private const val E_FAILED_TO_PICK = "E_FAILED_TO_PICK"
        private const val REQUEST_CODE_IMAGE_PICKER = 3001
        private const val REQUEST_CODE_IMAGE_EDITOR = 3002
    }

    private var pickImagesPromise: Promise? = null
    private var editImagePromise: Promise? = null
    private val moduleScope = CoroutineScope(Dispatchers.Main)
    private var maxWidth: Int = 1024
    private var maxHeight: Int = 1024
    private var outputFormat: String = "webp" // Default to webp
    private var asyncProcessing: Boolean = false

    init {
        reactContext.addActivityEventListener(this)
    }

    override fun getName(): String = NAME

    override fun init(licenseKey: String, promise: Promise) {
        val result = LicenseManager.initialize(reactApplicationContext, licenseKey)
        promise.resolve(result)
    }

    override fun openEditor(options: ReadableMap, promise: Promise) {
        val activity = getCurrentActivity()
        if (activity == null) {
            promise.reject(E_NO_ACTIVITY, "Activity doesn't exist")
            return
        }

        val uriStr = if (options.hasKey("uri")) options.getString("uri") else null
        if (uriStr == null) {
            promise.reject(E_FAILED_TO_PICK, "uri is required")
            return
        }

        val themeColor = if (options.hasKey("themeColor")) options.getString("themeColor") else null
        
          
        val languageCode = if (options.hasKey("languageCode")) {
            options.getString("languageCode") ?: "en"
        } else {
            "en"
        }
        TurboImagePickerConfig.applyLocale(languageCode)
        
        if (options.hasKey("maxWidth")) maxWidth = options.getInt("maxWidth")
        if (options.hasKey("maxHeight")) maxHeight = options.getInt("maxHeight")
        
        editImagePromise = promise

        try {
            val intent = ImageEditorActivity.createIntent(
                activity = activity,
                uris = listOf(Uri.parse(uriStr)),
                startIndex = 0,
                themeColor = themeColor,
                singlePhotoMode = true
            )
            activity.startActivityForResult(intent, REQUEST_CODE_IMAGE_EDITOR)
        } catch (e: Exception) {
            promise.reject(E_FAILED_TO_PICK, "Failed to open image editor: ${e.message}", e)
            editImagePromise = null
        }
    }

    @ReactMethod
    override fun openGallery(options: ReadableMap, promise: Promise) {
        val activity = getCurrentActivity()
        
        if (activity == null) {
            promise.reject(E_NO_ACTIVITY, "Activity doesn't exist")
            return
        }

        // Parse options
        val autoCloseOnSelect = if (options.hasKey("autoCloseOnSelect")) {
            options.getBoolean("autoCloseOnSelect")
        } else false

        asyncProcessing = if (options.hasKey("asyncProcessing")) {
            options.getBoolean("asyncProcessing")
        } else false

        val maxSelection = if (autoCloseOnSelect) {
            0
        } else if (options.hasKey("maxSelection")) {
            options.getInt("maxSelection")
        } else {
            1
        }
        
          
        val languageCode = if (options.hasKey("languageCode")) {
            options.getString("languageCode") ?: "en"
        } else {
            "en"
        }
        TurboImagePickerConfig.applyLocale(languageCode)
        
        val themeColor = if (options.hasKey("themeColor")) {
            options.getString("themeColor")
        } else {
            null
        }
        
        maxWidth = if (options.hasKey("maxWidth")) {
            val value = options.getInt("maxWidth")
            if (value > 0) value else 1024
        } else {
            1024
        }
        
        maxHeight = if (options.hasKey("maxHeight")) {
            val value = options.getInt("maxHeight")
            if (value > 0) value else 1024
        } else {
            1024
        }

        outputFormat = if (options.hasKey("outputFormat")) {
            options.getString("outputFormat")?.lowercase() ?: "webp"
        } else if (options.hasKey("format")) {
            options.getString("format")?.lowercase() ?: "webp"
        } else {
            "webp"
        }

        val enableEditor = if (options.hasKey("enableEditor")) {
            options.getBoolean("enableEditor")
        } else {
            false
        }
        
        val profileMode = if (options.hasKey("profileMode")) {
            options.getBoolean("profileMode")
        } else {
            false
        }

        pickImagesPromise = promise

        // Launch ImagePickerActivity
        try {
            val intent = Intent(activity, ImagePickerActivity::class.java).apply {
                putExtra(ImagePickerActivity.EXTRA_MAX_SELECTION, maxSelection)
                putExtra(ImagePickerActivity.EXTRA_LANGUAGE_CODE, languageCode)
                putExtra(ImagePickerActivity.EXTRA_ENABLE_EDITOR, enableEditor)
                putExtra(ImagePickerActivity.EXTRA_PROFILE_MODE, profileMode)
                putExtra(ImagePickerActivity.EXTRA_MAX_WIDTH, maxWidth)
                putExtra(ImagePickerActivity.EXTRA_MAX_HEIGHT, maxHeight)
                if (themeColor != null) {
                    putExtra(ImagePickerActivity.EXTRA_THEME_COLOR, themeColor)
                }
            }
            activity.startActivityForResult(intent, REQUEST_CODE_IMAGE_PICKER)
        } catch (e: Exception) {
            promise.reject(E_FAILED_TO_PICK, "Failed to open image picker: ${e.message}", e)
            pickImagesPromise = null
        }
    }

    override fun openViewer(options: ReadableMap, promise: Promise) {
        val activity = getCurrentActivity()
        if (activity == null) {
            promise.reject(E_NO_ACTIVITY, "Activity doesn't exist")
            return
        }

        if (!options.hasKey("images")) {
            promise.reject(E_FAILED_TO_PICK, "images array is required")
            return
        }

        val imagesArray = options.getArray("images")
        if (imagesArray == null || imagesArray.size() == 0) {
            promise.reject(E_FAILED_TO_PICK, "images array cannot be empty")
            return
        }

        val images = ArrayList<String>()
        for (i in 0 until imagesArray.size()) {
            val str = imagesArray.getString(i)
            if (str != null) {
                images.add(str)
            }
        }

        val initialIndex = if (options.hasKey("initialIndex")) options.getInt("initialIndex") else 0
        val themeColor = if (options.hasKey("themeColor")) options.getString("themeColor") else "#FF6B35"
        val title = if (options.hasKey("title")) options.getString("title") else null

        val languageCode = if (options.hasKey("languageCode")) {
            options.getString("languageCode") ?: "en"
        } else {
            "en"
        }
        TurboImagePickerConfig.applyLocale(languageCode)

        val currentActivity = activity
        if (currentActivity != null) {
            val animationType = if (options.hasKey("animationType")) options.getString("animationType") else if (options.hasKey("sourceRect")) "zoom" else "slide"
            val intent = Intent(currentActivity, ImageViewerActivity::class.java).apply {
                putStringArrayListExtra(ImageViewerActivity.EXTRA_IMAGES, ArrayList(images))
                putExtra(ImageViewerActivity.EXTRA_INITIAL_INDEX, initialIndex)
                putExtra("EXTRA_THEME_COLOR", themeColor)
                putExtra("animationType", animationType)
                if (options.hasKey("closeAnimationType")) {
                    putExtra("closeAnimationType", options.getString("closeAnimationType"))
                }
                if (themeColor != null) {
                    putExtra("themeColor", themeColor)
                }
                if (title != null) {
                    putExtra(ImageViewerActivity.EXTRA_TITLE, title)
                }
                
                if (options.hasKey("sourceRect")) {
                    val rect = options.getMap("sourceRect")
                    if (rect != null) {
                        putExtra("startX", if (rect.hasKey("x")) rect.getDouble("x").toFloat() else 0f)
                        putExtra("startY", if (rect.hasKey("y")) rect.getDouble("y").toFloat() else 0f)
                        putExtra("startWidth", if (rect.hasKey("width")) rect.getDouble("width").toFloat() else 0f)
                        putExtra("startHeight", if (rect.hasKey("height")) rect.getDouble("height").toFloat() else 0f)
                    }
                }
            }
            TransitionHelper.onViewerPageChanged = { index ->
                val params = Arguments.createMap().apply { putInt("index", index) }
                reactApplicationContext
                    .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                    .emit("onPageSelected", params)
            }
            activity.startActivity(intent)
            if (animationType == "zoom" && options.hasKey("sourceRect")) {
                activity.overridePendingTransition(0, 0)
            } else if (animationType == "fade") {
                activity.overridePendingTransition(android.R.anim.fade_in, android.R.anim.fade_out)
            } else if (animationType == "slide") {
                activity.overridePendingTransition(R.anim.slide_in_bottom, R.anim.no_animation)
            }
            promise.resolve(null)
        } catch (e: Exception) {
            promise.reject(E_FAILED_TO_PICK, "Failed to open image viewer: ${e.message}", e)
        }
    }

    override fun updateViewerSourceRect(rect: ReadableMap, promise: Promise) {
        try {
            val x = if (rect.hasKey("x")) rect.getDouble("x").toFloat() else 0f
            val y = if (rect.hasKey("y")) rect.getDouble("y").toFloat() else 0f
            val width = if (rect.hasKey("width")) rect.getDouble("width").toFloat() else 0f
            val height = if (rect.hasKey("height")) rect.getDouble("height").toFloat() else 0f
            
            // active ImageViewerActivity에 전달
            ImageViewerActivity.currentInstance?.get()?.updateSourceRect(x, y, width, height)
            
            promise.resolve(null)
        } catch (e: Exception) {
            promise.reject("ERROR", e.message, e)
        }
    }

    override fun closeGallery(promise: Promise) {
        val activity = getCurrentActivity()
        if (activity == null) {
            promise.reject(E_NO_ACTIVITY, "Activity doesn't exist")
            return
        }
        activity.finishActivity(REQUEST_CODE_IMAGE_PICKER)
        promise.resolve(true)
    }

    override fun addListener(eventName: String) {
        // Keep: Required for RN built-in Event Emitter Calls.
    }

    override fun removeListeners(count: Double) {
        // Keep: Required for RN built-in Event Emitter Calls.
    }

    override fun onActivityResult(
        activity: Activity,
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        if (requestCode == REQUEST_CODE_IMAGE_EDITOR) {
            val promise = editImagePromise ?: return
            editImagePromise = null

            if (resultCode != Activity.RESULT_OK || data == null) {
                promise.reject(E_PICKER_CANCELLED, "User cancelled image editor")
                return
            }

            val uriStrings = data.getStringArrayListExtra(ImageEditorActivity.EXTRA_RESULT_URIS)
            if (uriStrings == null || uriStrings.isEmpty()) {
                promise.reject(E_PICKER_CANCELLED, "User cancelled image editor")
                return
            }

            val uris = uriStrings.mapNotNull { uriString ->
                try { Uri.parse(uriString) } catch (e: Exception) { null }
            }

            if (uris.isEmpty()) {
                promise.reject(E_FAILED_TO_PICK, "Failed to parse image URIs")
                return
            }

            moduleScope.launch {
                try {
                    val results = processImages(uris)
                    if (results.isNotEmpty()) {
                        promise.resolve(results[0])
                    } else {
                        promise.reject(E_FAILED_TO_PICK, "Failed to process image")
                    }
                } catch (e: Exception) {
                    promise.reject(E_FAILED_TO_PICK, "Failed to process image: ${e.message}", e)
                }
            }
            return
        }

        if (requestCode != REQUEST_CODE_IMAGE_PICKER) {
            return
        }

        val promise = pickImagesPromise ?: return
        pickImagesPromise = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            promise.reject(E_PICKER_CANCELLED, "User cancelled image picker")
            return
        }

        val pickerResultCode = data.getIntExtra(ImagePickerActivity.EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
        
        val uriStrings = data.getStringArrayListExtra(ImagePickerActivity.EXTRA_URIS)
        
        // If empty array (cancelled), reject promise so it can be caught in RN (like iOS)
        if (uriStrings == null || uriStrings.isEmpty()) {
            promise.reject(E_PICKER_CANCELLED, "User cancelled image picker")
            return
        }

        // Convert string URIs to Uri objects
        val uris = uriStrings.mapNotNull { uriString ->
            try {
                Uri.parse(uriString)
            } catch (e: Exception) {
                null
            }
        }

        if (uris.isEmpty()) {
            promise.reject(E_FAILED_TO_PICK, "Failed to parse image URIs")
            return
        }

        // Process images asynchronously
        val eventMap = com.facebook.react.bridge.WritableNativeMap()
        eventMap.putInt("selectedCount", uris.size)
        eventMap.putInt("maxSelection", 10)
        try {
            reactApplicationContext.getJSModule(com.facebook.react.modules.core.DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                .emit("onSelectionChange", eventMap)
        } catch (e: Exception) {
            // Ignore
        }

        moduleScope.launch {
            try {
                if (asyncProcessing) {
                    val array = com.facebook.react.bridge.Arguments.createArray()
                    promise.resolve(array)
                    processImages(uris)
                } else {
                    val results = processImages(uris)
                    val array = com.facebook.react.bridge.Arguments.createArray()
                    results.forEach { array.pushMap(it) }
                    promise.resolve(array)
                }
            } catch (e: Exception) {
                if (!asyncProcessing) {
                    promise.reject(E_FAILED_TO_PICK, "Failed to process images: ${e.message}", e)
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        // Not needed for this module
    }

    private suspend fun processImages(uris: List<Uri>): List<com.facebook.react.bridge.WritableMap> = withContext(Dispatchers.IO) {
        val results = mutableListOf<com.facebook.react.bridge.WritableMap>()
        val contentResolver = reactApplicationContext.contentResolver

        for (uri in uris) {
            try {
                // 1. Get EXIF Orientation
                var orientation = android.media.ExifInterface.ORIENTATION_NORMAL
                try {
                    contentResolver.openInputStream(uri)?.use { exifInputStream ->
                        val exif = android.media.ExifInterface(exifInputStream)
                        orientation = exif.getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, android.media.ExifInterface.ORIENTATION_NORMAL)
                    }
                } catch (e: Exception) {}

                contentResolver.openInputStream(uri)?.use { inputStream ->
                    // Get original image dimensions
                    val originalOptions = BitmapFactory.Options().apply {
                        inJustDecodeBounds = true
                    }
                    BitmapFactory.decodeStream(inputStream, null, originalOptions)
                    
                    var originalWidth = originalOptions.outWidth
                    var originalHeight = originalOptions.outHeight
                    
                    // Swap width and height if rotated by 90 or 270 degrees
                    if (orientation == android.media.ExifInterface.ORIENTATION_ROTATE_90 || orientation == android.media.ExifInterface.ORIENTATION_ROTATE_270) {
                        val temp = originalWidth
                        originalWidth = originalHeight
                        originalHeight = temp
                    }
                    
                    // Load and resize image
                    contentResolver.openInputStream(uri)?.use { resizedInputStream ->
                        // Initial decode for sizing
                        val decodeOptions = BitmapFactory.Options().apply {
                            inSampleSize = calculateInSampleSize(originalWidth, originalHeight, maxWidth, maxHeight)
                        }
                        var bitmap = BitmapFactory.decodeStream(resizedInputStream, null, decodeOptions)
                        
                        if (bitmap != null) {
                            // Apply EXIF Rotation
                            val matrix = android.graphics.Matrix()
                            when (orientation) {
                                android.media.ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                                android.media.ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                                android.media.ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                                android.media.ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
                                android.media.ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
                            }
                            
                            if (!matrix.isIdentity) {
                                val rotatedBitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                                if (rotatedBitmap != bitmap) {
                                    bitmap.recycle()
                                    bitmap = rotatedBitmap
                                }
                            }

                            // Precise resize if needed
                            var finalBitmap = if (bitmap.width > maxWidth || bitmap.height > maxHeight) {
                                resizeBitmap(bitmap, maxWidth, maxHeight)
                            } else {
                                bitmap
                            }
                            
                            if (!LicenseManager.isValidLicense(reactApplicationContext)) {
                                val watermarked = applyEvaluationWatermark(finalBitmap)
                                if (finalBitmap != bitmap && finalBitmap != watermarked) {
                                    finalBitmap.recycle()
                                }
                                finalBitmap = watermarked
                            }
                            
                            // Determine format and extension
                            val compressFormat: Bitmap.CompressFormat
                            val extension: String
                            val mimeType: String
                            
                            when (outputFormat) {
                                "png" -> {
                                    compressFormat = Bitmap.CompressFormat.PNG
                                    extension = "png"
                                    mimeType = "image/png"
                                }
                                "jpg", "jpeg" -> {
                                    compressFormat = Bitmap.CompressFormat.JPEG
                                    extension = "jpg"
                                    mimeType = "image/jpeg"
                                }
                                else -> { // webp
                                    compressFormat = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                        Bitmap.CompressFormat.WEBP_LOSSY
                                    } else {
                                        @Suppress("DEPRECATION")
                                        Bitmap.CompressFormat.WEBP
                                    }
                                    extension = "webp"
                                    mimeType = "image/webp"
                                }
                            }

                            // Save to temporary file
                            val tempFile = File.createTempFile("turbo_edited_${System.currentTimeMillis()}_", ".$extension", reactApplicationContext.cacheDir)
                            FileOutputStream(tempFile).use { out ->
                                finalBitmap.compress(compressFormat, 85, out)
                            }
                            
                            val finalWidth = finalBitmap.width
                            val finalHeight = finalBitmap.height

                            // Cleanup
                            if (bitmap != finalBitmap) {
                                bitmap.recycle()
                            }
                            finalBitmap.recycle()
                            
                            val imageInfo = WritableNativeMap().apply {
                                putString("uri", Uri.fromFile(tempFile).toString())
                                putInt("width", finalWidth)
                                putInt("height", finalHeight)
                                putString("type", mimeType)
                                putString("fileName", tempFile.name)
                                putString("fileExtension", extension)
                                putDouble("fileSize", tempFile.length().toDouble())
                                putString("originalUri", uri.toString())
                                putInt("originalWidth", originalWidth)
                                putInt("originalHeight", originalHeight)
                            }
                            results.add(imageInfo)
                            
                            if (asyncProcessing) {
                                try {
                                    val eventMap = WritableNativeMap().apply {
                                        putInt("index", results.size - 1)
                                        putInt("total", uris.size)
                                        // Need to create a copy for the event map since WritableMap cannot be reused easily if it's pushed to array, but here we can just create a new map or use copy
                                        putMap("image", WritableNativeMap().apply {
                                            putString("uri", Uri.fromFile(tempFile).toString())
                                            putInt("width", finalWidth)
                                            putInt("height", finalHeight)
                                            putString("type", mimeType)
                                            putString("fileName", tempFile.name)
                                            putString("fileExtension", extension)
                                            putDouble("fileSize", tempFile.length().toDouble())
                                            putString("originalUri", uri.toString())
                                            putInt("originalWidth", originalWidth)
                                            putInt("originalHeight", originalHeight)
                                        })
                                    }
                                    reactApplicationContext.getJSModule(com.facebook.react.modules.core.DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                                        .emit("onImageProcessed", eventMap)
                                } catch (e: Exception) {
                                    // Ignore
                                }
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                // Skip failed images
                continue
            }
        }

        results
    }
    
    private fun calculateInSampleSize(
        reqWidth: Int,
        reqHeight: Int,
        maxWidth: Int,
        maxHeight: Int
    ): Int {
        var inSampleSize = 1
        
        if (reqHeight > maxHeight || reqWidth > maxWidth) {
            val halfHeight = reqHeight / 2
            val halfWidth = reqWidth / 2
            
            while ((halfHeight / inSampleSize) >= maxHeight && (halfWidth / inSampleSize) >= maxWidth) {
                inSampleSize *= 2
            }
        }
        
        return inSampleSize
    }
    
    private fun resizeBitmap(bitmap: Bitmap, maxWidth: Int, maxHeight: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        
        val ratioBitmap = width.toFloat() / height.toFloat()
        val ratioMax = maxWidth.toFloat() / maxHeight.toFloat()
        
        var finalWidth = maxWidth
        var finalHeight = maxHeight
        
        if (ratioMax > ratioBitmap) {
            finalWidth = (maxHeight * ratioBitmap).toInt()
        } else {
            finalHeight = (maxWidth / ratioBitmap).toInt()
        }
        
        return Bitmap.createScaledBitmap(bitmap, finalWidth, finalHeight, true)
    }

    private fun applyEvaluationWatermark(bitmap: Bitmap): Bitmap {
        val mutableBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = android.graphics.Canvas(mutableBitmap)
        
        val text = "TURBO IMAGE PICKER"
        val textPaint = android.text.TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.WHITE
            alpha = 64
            textSize = Math.max(20f, Math.min(bitmap.width, bitmap.height) / 15f)
            isFakeBoldText = true
            setShadowLayer(3f, 1f, 1f, android.graphics.Color.argb(128, 0, 0, 0))
        }
        
        val textWidth = textPaint.measureText(text)
        val textHeight = textPaint.descent() - textPaint.ascent()
        
        val diagonal = Math.hypot(bitmap.width.toDouble(), bitmap.height.toDouble()).toFloat()
        
        canvas.save()
        canvas.translate(bitmap.width / 2f, bitmap.height / 2f)
        canvas.rotate(-35f)
        canvas.translate(-diagonal / 2f, -diagonal / 2f)
        
        val stepX = textWidth * 1.5f
        val stepY = textHeight * 3.5f
        
        var y = 0f
        var row = 0
        while (y < diagonal + stepY) {
            var x = 0f
            val offset = if (row % 2 == 0) 0f else stepX / 2f
            while (x < diagonal + stepX) {
                canvas.drawText(text, x + offset, y, textPaint)
                x += stepX
            }
            y += stepY
            row++
        }
        
        canvas.restore()
        return mutableBitmap
    }

    override fun invalidate() {
        super.invalidate()
        reactApplicationContext.removeActivityEventListener(this)
    }
}

