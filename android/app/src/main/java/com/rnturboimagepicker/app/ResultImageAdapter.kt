package com.rnturboimagepicker.app

import android.graphics.BitmapFactory
import android.net.Uri
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

data class ResultImageInfo(
    val uri: Uri,
    val format: String,
    val fileSizeBytes: Long,
    val width: Int,
    val height: Int,
    val originalWidth: Int = 0,
    val originalHeight: Int = 0
)

class ResultImageAdapter : RecyclerView.Adapter<ResultImageAdapter.VH>() {

    private val items = mutableListOf<ResultImageInfo>()
    var onItemClick: ((Int, View) -> Unit)? = null

    fun setItems(list: List<ResultImageInfo>) {
        items.clear()
        items.addAll(list)
        notifyDataSetChanged()
    }

    fun getItems(): List<ResultImageInfo> = items

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_result_image, parent, false)
        return VH(view)
    }

    override fun getItemCount() = items.size

    override fun onBindViewHolder(holder: VH, position: Int) {
        holder.bind(items[position])
        holder.itemView.setOnClickListener {
            onItemClick?.invoke(position, holder.imageView)
        }
    }

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val imageView: ImageView = view.findViewById(R.id.resultImageView)
        private val formatBadge: TextView = view.findViewById(R.id.resultFormatBadge)
        private val sizeText: TextView = view.findViewById(R.id.resultSizeText)
        private val dimensText: TextView = view.findViewById(R.id.resultDimensText)

        fun bind(info: ResultImageInfo) {
            imageView.setImageBitmap(null)
            try {
                val ctx = imageView.context
                val bmp = ctx.contentResolver.openInputStream(info.uri)?.use { stream ->
                    // Images are already processed (≤1024px), safe to decode directly
                    BitmapFactory.decodeStream(stream)
                }
                imageView.setImageBitmap(bmp)
            } catch (e: Exception) {
                e.printStackTrace()
            }

            // Format badge color
            formatBadge.text = info.format
            val badgeColor = when (info.format) {
                "WEBP" -> android.graphics.Color.parseColor("#00897B")
                "PNG"  -> android.graphics.Color.parseColor("#7B1FA2")
                else   -> android.graphics.Color.parseColor("#1565C0") // JPG
            }
            (formatBadge.background as? android.graphics.drawable.GradientDrawable)
                ?.setColor(badgeColor)
                ?: run { formatBadge.setBackgroundColor(badgeColor) }

            // File size
            val kb = info.fileSizeBytes / 1024.0
            val sizeStr = if (kb >= 1024) "%.1f MB".format(kb / 1024.0) else "%.1f KB".format(kb)
            sizeText.text = "용량: $sizeStr  (${info.fileSizeBytes} bytes)"

            // Resolution: show original → output when resized
            val hasOriginal = info.originalWidth > 0
            dimensText.text = if (hasOriginal && (info.originalWidth != info.width || info.originalHeight != info.height)) {
                "해상도: ${info.originalWidth}×${info.originalHeight} → ${info.width}×${info.height} (리사이즈됨)"
            } else {
                "해상도: ${info.width}×${info.height}" + if (hasOriginal) " (원본과 동일)" else ""
            }
        }
    }
}
