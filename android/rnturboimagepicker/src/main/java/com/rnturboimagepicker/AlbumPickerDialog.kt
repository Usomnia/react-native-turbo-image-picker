package com.rnturboimagepicker

import android.Manifest
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.fragment.app.DialogFragment
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import android.content.ContentUris
import java.util.Locale
import kotlinx.coroutines.*

class AlbumPickerDialog : DialogFragment() {
    
    companion object {
        private const val TAG = "AlbumPickerDialog"
        private const val ARG_LANGUAGE_CODE = "arg_language_code"
        
        fun newInstance(languageCode: String = "en"): AlbumPickerDialog {
            return AlbumPickerDialog().apply {
                arguments = Bundle().apply {
                    putString(ARG_LANGUAGE_CODE, languageCode)
                }
            }
        }
    }
    
    private var albumRecyclerView: RecyclerView? = null
    private var albumAdapter: AlbumListAdapter? = null
    private var onAlbumSelected: ((Album) -> Unit)? = null
    private var offsetY: Int = 0
    private var languageCode: String = "en"
    
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        languageCode = arguments?.getString(ARG_LANGUAGE_CODE, "en") ?: "en"
        setStyle(STYLE_NORMAL, R.style.AlbumPickerDialogTheme)
    }
    
    private fun setLocale(languageCode: String) {
        try {
            val locale = Locale(languageCode)
            Locale.setDefault(locale)
            val config = Configuration()
            config.setLocale(locale)
            // Only update configuration if context is available
            context?.let { ctx ->
                val localizedContext = ctx.createConfigurationContext(config)
                resources.updateConfiguration(config, resources.displayMetrics)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error setting locale: ${e.message}", e)
        }
    }
    
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        try {
            // Use regular inflater - don't use localizedInflater for layout inflation
            // Localization will be handled in data loading, not in layout
            val view = inflater.inflate(R.layout.dialog_album_list, container, false)
            
            albumRecyclerView = view.findViewById(R.id.albumListRecyclerView)
            
            // Setup RecyclerView
            albumRecyclerView?.apply {
                val ctx = this@AlbumPickerDialog.context
                if (ctx != null) {
                    layoutManager = LinearLayoutManager(ctx)
                    setHasFixedSize(false)
                } else {
                    Log.w(TAG, "Context is null when setting up RecyclerView")
                }
            }
            
            // Load albums after view is created
            view.post {
                loadAlbums()
            }
            
            return view
        } catch (e: Exception) {
            Log.e(TAG, "Error in onCreateView", e)
            e.printStackTrace()
            return null
        }
    }
    
    override fun onStart() {
        super.onStart()
        
        // Configure window to display below header (dropdown style)
        dialog?.window?.apply {
            val displayMetrics = resources.displayMetrics
            val screenWidth = displayMetrics.widthPixels
            val screenHeight = displayMetrics.heightPixels
            
            // Make popup 60% of screen width, max 300dp height
            val dialogHeight = (300 * resources.displayMetrics.density).toInt()
            
            setLayout((screenWidth * 0.6).toInt(), dialogHeight)
            
            // Use y param to position dialog below header
            val params = attributes
            params.y = offsetY
            attributes = params
            setGravity(Gravity.TOP or Gravity.CENTER_HORIZONTAL)
            
            // Set background to transparent
            statusBarColor = Color.TRANSPARENT
            navigationBarColor = Color.TRANSPARENT
        }
    }
    
    fun setOnAlbumSelectedListener(listener: (Album) -> Unit) {
        onAlbumSelected = listener
    }
    
    fun setOffsetY(offset: Int) {
        offsetY = offset
    }
    
    private fun setAdapterSafely(recyclerView: RecyclerView, albums: List<Album>) {
        try {
            if (!isAdded || albums.isEmpty()) {
                Log.w(TAG, "Cannot set adapter: fragment not added or albums empty")
                return
            }
            
            Log.d(TAG, "Setting adapter safely with ${albums.size} albums")
            
            // Create adapter
            albumAdapter = AlbumListAdapter(albums) { album ->
                if (isAdded) {
                    try {
                        onAlbumSelected?.invoke(album)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in album selection callback", e)
                    }
                    try {
                        dismiss()
                    } catch (e: Exception) {
                        Log.e(TAG, "Error dismissing dialog", e)
                    }
                }
            }
            
            // Set adapter with null check
            if (recyclerView.adapter == null) {
                recyclerView.adapter = albumAdapter
                Log.d(TAG, "Adapter set successfully")
            } else {
                Log.w(TAG, "Adapter already set, skipping")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in setAdapterSafely: ${e.message}", e)
            e.printStackTrace()
        }
    }
    
    private fun loadAlbums() {
        val contextRef = context ?: run {
            Log.w(TAG, "Context is null, cannot load albums")
            return
        }
        
        if (!hasPermission(contextRef)) {
            Log.w(TAG, "No permission to read images")
            return
        }
        
        Log.d(TAG, "Starting to load albums...")
        
        // Get localized string - use simple fallback to avoid createConfigurationContext issues
        // This avoids potential crashes with configuration context creation
        val recentItemsName = when (languageCode) {
            "ko" -> "최근 항목"
            "ja" -> "最近"
            "zh" -> "最近项目"
            "es" -> "Recientes"
            "fr" -> "Récents"
            "de" -> "Zuletzt verwendet"
            "it" -> "Recenti"
            "pt" -> "Recentes"
            "ru" -> "Недавние"
            "pl" -> "Ostatnie"
            "nl" -> "Recente"
            "tr" -> "Son"
            "th" -> "ล่าสุด"
            "vi" -> "Gần đây"
            "ms" -> "Terkini"
            "id" -> "Terbaru"
            "hi" -> "हाल का"
            "da" -> "Seneste"
            else -> "Recents"
        }
        
        Log.d(TAG, "Using recentItemsName: $recentItemsName for language: $languageCode")
        
        scope.launch(Dispatchers.Main) {
            try {
                val albums = withContext(Dispatchers.IO) {
                    loadAlbumsFromDevice(contextRef, recentItemsName)
                }
                
                Log.d(TAG, "Loaded ${albums.size} albums")
                
                // Check if fragment is still attached and view exists
                if (!isAdded) {
                    Log.w(TAG, "Fragment not attached, cannot set adapter")
                    return@launch
                }
                
                val currentView = view
                if (currentView == null) {
                    Log.w(TAG, "View is null, cannot set adapter")
                    return@launch
                }
                
                // Check if RecyclerView still exists
                val recyclerView = albumRecyclerView
                if (recyclerView == null) {
                    Log.w(TAG, "RecyclerView is null, cannot set adapter")
                    return@launch
                }
                
                // Use post to ensure view is fully laid out
                recyclerView.post {
                    if (isAdded && recyclerView.isAttachedToWindow) {
                        setAdapterSafely(recyclerView, albums)
                    } else {
                        Log.w(TAG, "RecyclerView not ready, retrying...")
                        recyclerView.postDelayed({
                            if (isAdded && recyclerView.isAttachedToWindow) {
                                setAdapterSafely(recyclerView, albums)
                            }
                        }, 100)
                    }
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "Error loading albums: ${e.message}", e)
                e.printStackTrace()
            }
        }
    }
    
    private fun loadAlbumsFromDevice(contextRef: android.content.Context, recentItemsName: String): List<Album> {
        val albums = mutableListOf<Album>()
        val albumMap = mutableMapOf<String, Album>()
        
        val projection = arrayOf(
            MediaStore.Images.Media.BUCKET_ID,
            MediaStore.Images.Media.BUCKET_DISPLAY_NAME,
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DATE_ADDED
        )
        
        val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"
        
        val cursor = contextRef.contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            null,
            null,
            sortOrder
        )
        
        cursor?.use {
            val bucketIdColumn = it.getColumnIndexOrThrow(MediaStore.Images.Media.BUCKET_ID)
            val bucketNameColumn = it.getColumnIndexOrThrow(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
            val idColumn = it.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            
            while (it.moveToNext()) {
                val bucketId = it.getString(bucketIdColumn)
                val bucketName = it.getString(bucketNameColumn) ?: "Unknown"
                val imageId = it.getLong(idColumn)
                val imageUri = ContentUris.withAppendedId(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    imageId
                )
                
                // Get or create album
                val album = albumMap.getOrPut(bucketId) {
                    Album(
                        bucketId = bucketId,
                        bucketName = bucketName,
                        coverImageUri = imageUri,
                        imageCount = 0
                    )
                }
                
                // Update cover image
                if (album.coverImageUri == null) {
                    val updatedAlbum = album.copy(coverImageUri = imageUri)
                    albumMap[bucketId] = updatedAlbum
                }
            }
            
            // Count images in each album
            albums.addAll(albumMap.values.map { album ->
                val countCursor = contextRef.contentResolver.query(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    arrayOf(MediaStore.Images.Media._ID),
                    "${MediaStore.Images.Media.BUCKET_ID} = ?",
                    arrayOf(album.bucketId),
                    null
                )
                val count = countCursor?.count ?: 0
                countCursor?.close()
                
                album.copy(imageCount = count)
            })
        }
        
        // Sort albums: Priority to common folders
        albums.sortWith { a, b ->
            val priorityA = when {
                a.bucketName.equals("Pictures", ignoreCase = true) -> 0
                a.bucketName.equals("Camera", ignoreCase = true) -> 1
                a.bucketName.equals("DCIM", ignoreCase = true) -> 2
                else -> 3
            }
            val priorityB = when {
                b.bucketName.equals("Pictures", ignoreCase = true) -> 0
                b.bucketName.equals("Camera", ignoreCase = true) -> 1
                b.bucketName.equals("DCIM", ignoreCase = true) -> 2
                else -> 3
            }
            
            if (priorityA != priorityB) {
                priorityA.compareTo(priorityB)
            } else {
                a.bucketName.compareTo(b.bucketName, ignoreCase = true)
            }
        }
        
        // Add "Recent Items" at the beginning - represents all images
        val totalCount = albums.sumOf { it.imageCount }
        val mostRecentImage = albums.firstOrNull()?.coverImageUri
        
        val recentItemsAlbum = Album(
            bucketId = "ALL_IMAGES",
            bucketName = recentItemsName,
            coverImageUri = mostRecentImage,
            imageCount = totalCount
        )
        
        return listOf(recentItemsAlbum) + albums
    }
    
    private fun hasPermission(contextRef: android.content.Context): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        
        return ContextCompat.checkSelfPermission(
            contextRef,
            permission
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        scope.cancel()
        albumRecyclerView = null
        albumAdapter = null
    }
}

