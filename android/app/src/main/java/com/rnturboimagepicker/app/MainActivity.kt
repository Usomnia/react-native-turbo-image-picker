package com.rnturboimagepicker.app

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.Button
import android.widget.EditText
import android.widget.RadioGroup
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.rnturboimagepicker.ImagePickerBottomSheet
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream

class MainActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "MainActivity"
    }

    // ─── Views ───
    private lateinit var btnSingleSelect: Button
    private lateinit var btnSingleEdit: Button
    private lateinit var btnMultiSelect: Button
    private lateinit var btnMultiEdit: Button
    private lateinit var btnProfileCropOnly: Button
    private lateinit var btnProfileCrop: Button
    private lateinit var btnCacheTest: Button
    private lateinit var resultText: TextView
    private lateinit var logText: TextView
    private lateinit var formatRadioGroup: RadioGroup
    private lateinit var inputMaxWidth: EditText
    private lateinit var inputMaxHeight: EditText
    private lateinit var resultImagesLabelZoom: TextView
    private lateinit var resultImagesLabelFade: TextView
    private lateinit var resultImagesLabelSlide: TextView
    private lateinit var resultImagesRecyclerViewZoom: RecyclerView
    private lateinit var resultImagesRecyclerViewFade: RecyclerView
    private lateinit var resultImagesRecyclerViewSlide: RecyclerView

    private var bottomSheet: ImagePickerBottomSheet? = null
    private val resultAdapterZoom = ResultImageAdapter().apply {
        onItemClick = { index, view -> openImageViewer(index, view, "zoom") }
    }
    private val resultAdapterFade = ResultImageAdapter().apply {
        onItemClick = { index, view -> openImageViewer(index, view, "fade") }
    }
    private val resultAdapterSlide = ResultImageAdapter().apply {
        onItemClick = { index, view -> openImageViewer(index, view, "slide") }
    }
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    
    private val pageChangeReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
            if (intent?.action == "com.rnturboimagepicker.PAGE_CHANGED") {
                val index = intent.getIntExtra("index", 0)
                
                // For test app, just pick the zoom recycler view as the source
                val itemView = resultImagesRecyclerViewZoom.layoutManager?.findViewByPosition(index)
                    ?: resultImagesRecyclerViewFade.layoutManager?.findViewByPosition(index)
                    ?: resultImagesRecyclerViewSlide.layoutManager?.findViewByPosition(index)
                
                val view = itemView?.findViewById<android.view.View>(R.id.resultImageView) ?: itemView
                
                if (view != null) {
                    val location = IntArray(2)
                    view.getLocationInWindow(location)
                    val updateIntent = android.content.Intent("com.rnturboimagepicker.UPDATE_COORDINATES")
                    updateIntent.putExtra("startX", location[0].toFloat())
                    updateIntent.putExtra("startY", location[1].toFloat())
                    updateIntent.putExtra("startWidth", view.width.toFloat())
                    updateIntent.putExtra("startHeight", view.height.toFloat())
                    androidx.localbroadcastmanager.content.LocalBroadcastManager.getInstance(this@MainActivity).sendBroadcast(updateIntent)
                }
            }
        }
    }

    // ─── Permission ───
    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        if (isGranted) {
            Toast.makeText(this, "Permission granted", Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(this, "Permission denied.", Toast.LENGTH_LONG).show()
        }
    }

    // ─── Lifecycle ───
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        bindViews()
        setupResultRecyclerView()
        setupButtons()
        checkPermission()
        
        androidx.localbroadcastmanager.content.LocalBroadcastManager.getInstance(this)
            .registerReceiver(pageChangeReceiver, android.content.IntentFilter("com.rnturboimagepicker.PAGE_CHANGED"))
            
        log("MainActivity initialized")
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
        androidx.localbroadcastmanager.content.LocalBroadcastManager.getInstance(this).unregisterReceiver(pageChangeReceiver)
    }

    // ─── Bind ───
    private fun bindViews() {
        btnSingleSelect          = findViewById(R.id.btnSingleSelect)
        btnSingleEdit            = findViewById(R.id.btnSingleEdit)
        btnMultiSelect           = findViewById(R.id.btnMultiSelect)
        btnMultiEdit             = findViewById(R.id.btnMultiEdit)
        btnProfileCropOnly       = findViewById(R.id.btnProfileCropOnly)
        btnProfileCrop           = findViewById(R.id.btnProfileCrop)
        btnCacheTest             = findViewById(R.id.btnCacheTest)
        resultText               = findViewById(R.id.resultText)
        logText                  = findViewById(R.id.logText)
        formatRadioGroup         = findViewById(R.id.formatRadioGroup)
        inputMaxWidth            = findViewById(R.id.inputMaxWidth)
        inputMaxHeight           = findViewById(R.id.inputMaxHeight)
        resultImagesLabelZoom        = findViewById(R.id.resultImagesLabelZoom)
        resultImagesLabelFade        = findViewById(R.id.resultImagesLabelFade)
        resultImagesLabelSlide       = findViewById(R.id.resultImagesLabelSlide)
        resultImagesRecyclerViewZoom = findViewById(R.id.resultImagesRecyclerViewZoom)
        resultImagesRecyclerViewFade = findViewById(R.id.resultImagesRecyclerViewFade)
        resultImagesRecyclerViewSlide = findViewById(R.id.resultImagesRecyclerViewSlide)
    }

    private fun setupResultRecyclerView() {
        resultImagesRecyclerViewZoom.layoutManager = LinearLayoutManager(this, LinearLayoutManager.HORIZONTAL, false)
        resultImagesRecyclerViewZoom.adapter = resultAdapterZoom
        
        resultImagesRecyclerViewFade.layoutManager = LinearLayoutManager(this, LinearLayoutManager.HORIZONTAL, false)
        resultImagesRecyclerViewFade.adapter = resultAdapterFade
        
        resultImagesRecyclerViewSlide.layoutManager = LinearLayoutManager(this, LinearLayoutManager.HORIZONTAL, false)
        resultImagesRecyclerViewSlide.adapter = resultAdapterSlide
    }

    private fun setupButtons() {
        btnSingleSelect.setOnClickListener {
            log("1개 선택 (에디터 OFF)")
            requestPermissionIfNeeded { openImagePicker(maxSelection = 1, enableEditor = false) }
        }
        btnSingleEdit.setOnClickListener {
            log("1개 편집 (에디터 ON)")
            requestPermissionIfNeeded { openImagePicker(maxSelection = 1, enableEditor = true) }
        }
        btnMultiSelect.setOnClickListener {
            log("멀티 선택 (에디터 OFF)")
            requestPermissionIfNeeded { openImagePicker(maxSelection = 10, enableEditor = false) }
        }
        btnMultiEdit.setOnClickListener {
            log("멀티 편집 (에디터 ON)")
            requestPermissionIfNeeded { openImagePicker(maxSelection = 10, enableEditor = true) }
        }
        btnProfileCropOnly.setOnClickListener {
            log("프로필 크롭 (에디터 OFF)")
            requestPermissionIfNeeded { openImagePicker(maxSelection = 1, enableEditor = false, profileMode = true) }
        }
        btnProfileCrop.setOnClickListener {
            log("프로필 편집 (프로필 모드 ON, 에디터 ON)")
            requestPermissionIfNeeded { openImagePicker(maxSelection = 1, enableEditor = true, profileMode = true) }
        }
        btnCacheTest.setOnClickListener {
            log("원격 캐시 테스트 (20장)")
            val urls = (10..29).map { "https://picsum.photos/id/$it/800/1200" }
            val intent = android.content.Intent(this, com.rnturboimagepicker.ImageViewerActivity::class.java).apply {
                putStringArrayListExtra(com.rnturboimagepicker.ImageViewerActivity.EXTRA_IMAGES, java.util.ArrayList(urls))
                putExtra(com.rnturboimagepicker.ImageViewerActivity.EXTRA_INITIAL_INDEX, 0)
                
                val location = IntArray(2)
                btnCacheTest.getLocationInWindow(location)
                putExtra("startX", location[0].toFloat())
                putExtra("startY", location[1].toFloat())
                putExtra("startWidth", btnCacheTest.width.toFloat())
                putExtra("startHeight", btnCacheTest.height.toFloat())
            }
            // Optional: Pass animationType for testing
            // intent.putExtra("animationType", "fade")
            // intent.putExtra("animationType", "slide")
            intent.putExtra("animationType", "zoom")
            
            startActivity(intent)
            overridePendingTransition(0, 0)
        }
    }

    // ─── Picker ───
    private fun openImagePicker(maxSelection: Int, enableEditor: Boolean, profileMode: Boolean = false) {
        intent.putExtra("extra_theme_color", "#FFD700") // Use yellow theme color for testing
        bottomSheet = ImagePickerBottomSheet.newInstance(
            maxSelection = maxSelection, 
            languageCode = "en", 
            enableEditor = enableEditor,
            profileMode = profileMode,
            maxWidth = maxWidth(),
            maxHeight = maxHeight()
        )

        bottomSheet?.setOnImagesSelectedListener { uris ->
            if (uris.isEmpty()) {
                log("No images selected")
                showStatus("이미지를 선택하지 않았습니다")
            } else {
                log("Received ${uris.size} image(s) — processing...")
                showStatus("처리 중... (${uris.size}개)")
                processAndDisplayImages(uris)
            }
        }

        bottomSheet?.setOnCancelledListener {
            log("Picker cancelled")
            showStatus("취소됨")
        }

        bottomSheet?.show(supportFragmentManager, "ImagePickerBottomSheet")
    }

    private fun openImageViewer(index: Int, view: android.view.View, animationType: String) {
        val images = java.util.ArrayList(resultAdapterZoom.getItems().map { it.uri.toString() })
        val intent = android.content.Intent(this, com.rnturboimagepicker.ImageViewerActivity::class.java).apply {
            putStringArrayListExtra(com.rnturboimagepicker.ImageViewerActivity.EXTRA_IMAGES, images)
            putExtra(com.rnturboimagepicker.ImageViewerActivity.EXTRA_INITIAL_INDEX, index)
            putExtra("animationType", animationType)
            
            val location = IntArray(2)
            view.getLocationInWindow(location)
            putExtra("startX", location[0].toFloat())
            putExtra("startY", location[1].toFloat())
            putExtra("startWidth", view.width.toFloat())
            putExtra("startHeight", view.height.toFloat())
        }
        startActivity(intent)
        overridePendingTransition(0, 0)
    }

    // ─── Image Processing ───

    private fun selectedFormat(): String = when (formatRadioGroup.checkedRadioButtonId) {
        R.id.radioJpg -> "JPG"
        R.id.radioPng -> "PNG"
        else          -> "WEBP"  // WebP 기본값
    }

    private fun maxWidth(): Int  = inputMaxWidth.text.toString().trim().toIntOrNull()  ?: 1024
    private fun maxHeight(): Int = inputMaxHeight.text.toString().trim().toIntOrNull() ?: 1024

    private fun processAndDisplayImages(uris: List<Uri>) {
        val format    = selectedFormat()
        val maxW      = maxWidth()
        val maxH      = maxHeight()

        scope.launch {
            val startTime = System.currentTimeMillis()
            val results = withContext(Dispatchers.IO) {
                uris.mapIndexed { idx, uri ->
                    processImage(uri, format, maxW, maxH, idx)
                }
            }
            val durationMs = System.currentTimeMillis() - startTime

            // Update UI
            resultAdapterZoom.setItems(results)
            resultAdapterFade.setItems(results)
            resultAdapterSlide.setItems(results)
            
            resultImagesRecyclerViewZoom.visibility = android.view.View.VISIBLE
            resultImagesLabelZoom.visibility = android.view.View.VISIBLE
            resultImagesRecyclerViewFade.visibility = android.view.View.VISIBLE
            resultImagesLabelFade.visibility = android.view.View.VISIBLE
            resultImagesRecyclerViewSlide.visibility = android.view.View.VISIBLE
            resultImagesLabelSlide.visibility = android.view.View.VISIBLE

            val totalSize = results.sumOf { it.fileSizeBytes }
            val totalKb = totalSize / 1024.0
            val sizeStr = if (totalKb >= 1024) "%.1f MB".format(totalKb / 1024.0) else "%.1f KB".format(totalKb)
            showStatus("✅ ${results.size}개 선택  |  포맷: $format  |  총 용량: $sizeStr")
            log("처리 완료: ${results.size}개, 총 $sizeStr (소요: ${durationMs}ms)")
            results.forEachIndexed { i, info ->
                val kb = info.fileSizeBytes / 1024.0
                val s = if (kb >= 1024) "%.1f MB".format(kb / 1024.0) else "%.1f KB".format(kb)
                log("[$i] ${info.format}  ${info.width}×${info.height}  $s  → ${info.uri.path?.substringAfterLast('/')}")
            }
        }
    }

    private fun processImage(uri: Uri, format: String, maxW: Int, maxH: Int, index: Int): ResultImageInfo {
        // 1. Read EXIF Orientation
        var orientation = android.media.ExifInterface.ORIENTATION_NORMAL
        try {
            contentResolver.openInputStream(uri)?.use { exifInputStream ->
                val exif = android.media.ExifInterface(exifInputStream)
                orientation = exif.getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, android.media.ExifInterface.ORIENTATION_NORMAL)
            }
        } catch (e: Exception) {}

        // 2. Decode
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = false }
        var bmp: Bitmap = contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) }
            ?: return ResultImageInfo(uri, format, 0L, 0, 0)

        // 3. Read original dimensions before scale
        var originalWidth  = bmp.width
        var originalHeight = bmp.height

        // Swap if rotated 90 or 270
        if (orientation == android.media.ExifInterface.ORIENTATION_ROTATE_90 || orientation == android.media.ExifInterface.ORIENTATION_ROTATE_270) {
            val temp = originalWidth
            originalWidth = originalHeight
            originalHeight = temp
        }

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
            val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
            if (rotated != bmp) {
                bmp.recycle()
                bmp = rotated
            }
        }

        // 4. Scale if needed
        val scaled = scaleBitmap(bmp, maxW, maxH)
        if (scaled !== bmp) bmp.recycle()

        // 4. Compress to chosen format
        val ext = format.lowercase()
        val outFile = File(cacheDir, "result_${System.currentTimeMillis()}_$index.$ext")
        FileOutputStream(outFile).use { out ->
            when (format) {
                "PNG"  -> scaled.compress(Bitmap.CompressFormat.PNG,  100, out)
                "WEBP" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        scaled.compress(Bitmap.CompressFormat.WEBP_LOSSLESS, 100, out)
                    } else {
                        @Suppress("DEPRECATION")
                        scaled.compress(Bitmap.CompressFormat.WEBP, 90, out)
                    }
                }
                else   -> scaled.compress(Bitmap.CompressFormat.JPEG, 90, out)  // JPG
            }
        }

        val finalUri = Uri.fromFile(outFile)
        val width    = scaled.width
        val height   = scaled.height
        scaled.recycle()

        return ResultImageInfo(
            uri           = finalUri,
            format        = format,
            fileSizeBytes = outFile.length(),
            width         = width,
            height        = height,
            originalWidth  = originalWidth,
            originalHeight = originalHeight
        )
    }

    private fun scaleBitmap(src: Bitmap, maxW: Int, maxH: Int): Bitmap {
        val srcW = src.width.toFloat()
        val srcH = src.height.toFloat()
        var scale = 1f
        if (srcW > maxW) scale = minOf(scale, maxW / srcW)
        if (srcH > maxH) scale = minOf(scale, maxH / srcH)
        if (scale >= 1f) return src
        val newW = (srcW * scale).toInt().coerceAtLeast(1)
        val newH = (srcH * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, newW, newH, true)
    }

    // ─── Helpers ───

    private fun showStatus(message: String) {
        resultText.text = message
    }

    private fun checkPermission() {
        val perm = storagePermission()
        val has  = ContextCompat.checkSelfPermission(this, perm) == PackageManager.PERMISSION_GRANTED
        if (!has) Toast.makeText(this, "갤러리 권한을 허용해 주세요", Toast.LENGTH_LONG).show()
    }

    private fun requestPermissionIfNeeded(onGranted: () -> Unit) {
        val perm = storagePermission()
        if (ContextCompat.checkSelfPermission(this, perm) == PackageManager.PERMISSION_GRANTED) {
            onGranted()
        } else {
            requestPermissionLauncher.launch(perm)
        }
    }

    private fun storagePermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            Manifest.permission.READ_MEDIA_IMAGES
        else
            Manifest.permission.READ_EXTERNAL_STORAGE

    private fun log(message: String) {
        Log.d(TAG, message)
        val current  = logText.text.toString()
        val newText  = "[${System.currentTimeMillis() % 100000}] $message\n$current"
        logText.text = newText.take(3000)
    }
}
