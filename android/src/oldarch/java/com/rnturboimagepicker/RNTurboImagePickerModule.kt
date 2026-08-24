package com.rnturboimagepicker

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import com.facebook.react.bridge.*
import com.facebook.react.module.annotations.ReactModule
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.facebook.react.modules.core.PermissionAwareActivity
import com.facebook.react.modules.core.PermissionListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.*

@ReactModule(name = RNTurboImagePickerModule.NAME)
class RNTurboImagePickerModule(reactContext: ReactApplicationContext) :
    NativeRNTurboImagePickerSpec(reactContext), ActivityEventListener {

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

    init {
        reactContext.addActivityEventListener(this)
    }

    override fun getName(): String = NAME

    @ReactMethod
    override fun init(licenseKey: String, promise: Promise) {
        val result = LicenseManager.initialize(reactApplicationContext, licenseKey)
        promise.resolve(result)
    }

    @ReactMethod
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
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                activity.startActivityForResult(intent, REQUEST_CODE_IMAGE_EDITOR)
            }, 50)
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

        val fragmentActivity = activity as? FragmentActivity
        if (fragmentActivity == null) {
            promise.reject(E_NO_ACTIVITY, "Activity is not a FragmentActivity")
            return
        }

        pickImagesPromise = promise

        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

        val showSheet = {
            fragmentActivity.runOnUiThread {
                try {
                    val bottomSheet = ImagePickerBottomSheet.newInstance(
                        maxSelection, languageCode, enableEditor, profileMode, maxWidth, maxHeight, themeColor
                    )
                    bottomSheet.setOnImagesSelectedListener { uris ->
                        val result = WritableNativeArray()
                        for (uri in uris) {
                            result.pushString(uri.toString())
                        }
                        handleSelectedImages(result, pickImagesPromise)
                        pickImagesPromise = null
                    }
                    bottomSheet.setOnCancelledListener {
                        pickImagesPromise?.reject(E_PICKER_CANCELLED, "User cancelled image picker")
                        pickImagesPromise = null
                    }
                    
                    val existingFragment = fragmentActivity.supportFragmentManager.findFragmentByTag("ImagePickerBottomSheet")
                    existingFragment?.let {
                        fragmentActivity.supportFragmentManager.beginTransaction().remove(it).commitAllowingStateLoss()
                    }
                    
                    fragmentActivity.supportFragmentManager.beginTransaction()
                        .add(bottomSheet, "ImagePickerBottomSheet")
                        .commitAllowingStateLoss()
                        
                } catch (e: Exception) {
                    pickImagesPromise?.reject(E_FAILED_TO_PICK, "Failed to open image picker: ${e.message}", e)
                    pickImagesPromise = null
                }
            }
        }

        if (ContextCompat.checkSelfPermission(fragmentActivity, permission) == PackageManager.PERMISSION_GRANTED) {
            showSheet()
        } else {
            val permissionAwareActivity = fragmentActivity as? PermissionAwareActivity
            if (permissionAwareActivity == null) {
                promise.reject(E_NO_ACTIVITY, "Activity is not PermissionAwareActivity")
                pickImagesPromise = null
                return
            }

            val permissionsToRequest = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE && permission == Manifest.permission.READ_MEDIA_IMAGES) {
                if (ContextCompat.checkSelfPermission(fragmentActivity, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) == PackageManager.PERMISSION_GRANTED) {
                    showSheet()
                    return
                }
                arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
            } else {
                arrayOf(permission)
            }

            permissionAwareActivity.requestPermissions(permissionsToRequest, 100, object : PermissionListener {
                override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray): Boolean {
                    if (requestCode == 100 && grantResults != null) {
                        val isGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            grantResults.isNotEmpty() && (
                                grantResults[0] == PackageManager.PERMISSION_GRANTED || 
                                (grantResults.size > 1 && grantResults[1] == PackageManager.PERMISSION_GRANTED)
                            )
                        } else {
                            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
                        }

                        if (isGranted) {
                            showSheet()
                        } else {
                            pickImagesPromise?.reject("E_PERMISSION_DENIED", "Permission denied")
                            pickImagesPromise = null
                        }
                    }
                    return true
                }
            })
        }
    }

    @ReactMethod
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

        try {
            val intent = Intent(activity, ImageViewerActivity::class.java).apply {
                putStringArrayListExtra(ImageViewerActivity.EXTRA_IMAGES, images)
                putExtra(ImageViewerActivity.EXTRA_INITIAL_INDEX, initialIndex)
                putExtra("EXTRA_THEME_COLOR", themeColor)
                if (title != null) {
                    putExtra(ImageViewerActivity.EXTRA_TITLE, title)
                }
            }
            activity.startActivity(intent)
            promise.resolve(null)
        } catch (e: Exception) {
            promise.reject(E_FAILED_TO_PICK, "Failed to open image viewer: ${e.message}", e)
        }
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


    }

    override fun onNewIntent(intent: Intent) {
        // Not needed for this module
    }

    private fun handleSelectedImages(uriStrings: ReadableArray, promise: Promise?) {
        val actualPromise = promise ?: return

        // Convert string URIs to Uri objects
        val uris = mutableListOf<Uri>()
        for (i in 0 until uriStrings.size()) {
            val uriString = uriStrings.getString(i)
            if (uriString != null) {
                try {
                    uris.add(Uri.parse(uriString))
                } catch (e: Exception) {
                    // Ignore
                }
            }
        }

        if (uris.isEmpty()) {
            actualPromise.reject(E_FAILED_TO_PICK, "Failed to parse image URIs")
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
                val results = processImages(uris)
                val array = com.facebook.react.bridge.Arguments.createArray()
                results.forEach { array.pushMap(it) }
                actualPromise.resolve(array)
            } catch (e: Exception) {
                actualPromise.reject(E_FAILED_TO_PICK, "Failed to process images: ${e.message}", e)
            }
        }
    }

    private suspend fun processImages(uris: List<Uri>): List<com.facebook.react.bridge.WritableMap> = withContext(Dispatchers.IO) {
        val results = mutableListOf<com.facebook.react.bridge.WritableMap>()
        val contentResolver = reactApplicationContext.contentResolver
        val totalCount = uris.size
        var currentIndex = 0

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
                            val finalBitmap = if (bitmap.width > maxWidth || bitmap.height > maxHeight) {
                                resizeBitmap(bitmap, maxWidth, maxHeight)
                            } else {
                                bitmap
                            }
                            
                            val processedBitmap = ImageProcessor.applyWatermarkIfNeeded(reactApplicationContext, finalBitmap)
                            
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
                                processedBitmap.compress(compressFormat, 85, out)
                            }
                            
                            val finalWidth = processedBitmap.width
                            val finalHeight = processedBitmap.height

                            // Cleanup
                            if (bitmap != processedBitmap) {
                                bitmap.recycle()
                            }
                            if (finalBitmap != processedBitmap && finalBitmap != bitmap) {
                                finalBitmap.recycle()
                            }
                            processedBitmap.recycle()
                            
                            val createImageInfo = {
                                WritableNativeMap().apply {
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
                            }
                            val imageInfo = createImageInfo()
                            results.add(imageInfo)

                            try {
                                val eventMap = WritableNativeMap().apply {
                                    putInt("total", totalCount)
                                    putInt("index", currentIndex)
                                    putMap("image", createImageInfo())
                                }
                                reactApplicationContext.getJSModule(com.facebook.react.modules.core.DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                                    .emit("onImageProcessed", eventMap)
                            } catch (e: Exception) { }
                        }
                    }
                }
                currentIndex++
            } catch (e: Exception) {
                currentIndex++
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


    override fun invalidate() {
        super.invalidate()
        reactApplicationContext.removeActivityEventListener(this)
    }

}
