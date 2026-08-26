package com.rnturboimagepicker

import android.graphics.Bitmap
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

class FilterThumbnailAdapter(
    private val filters: List<ImageFilter>,
    private val themeColor: Int,
    private val onFilterSelected: (ImageFilter, Int) -> Unit
) : RecyclerView.Adapter<FilterThumbnailAdapter.ViewHolder>() {

    private val thumbnailCache = mutableMapOf<String, Bitmap>()
    var originalThumbnail: Bitmap? = null
        private set
    private var currentFilterId: String = "original"
    private var currentIntensity: Float = 1.0f

    fun updateOriginalThumbnail(bmp: Bitmap?) {
        originalThumbnail = bmp
        thumbnailCache.clear()
        notifyDataSetChanged()
    }

    fun setThumbnail(filterId: String, bmp: Bitmap) {
        thumbnailCache[filterId] = bmp
        val idx = filters.indexOfFirst { it.id == filterId }
        if (idx != -1) {
            notifyItemChanged(idx)
        }
    }

    fun setThumbnails(map: Map<String, Bitmap>) {
        thumbnailCache.putAll(map)
        notifyDataSetChanged()
    }

    fun updateSelection(state: FilterState) {
        val oldId = currentFilterId
        currentFilterId = state.filterId
        currentIntensity = state.intensity
        
        if (oldId != currentFilterId) {
            val oldIdx = filters.indexOfFirst { it.id == oldId }
            val newIdx = filters.indexOfFirst { it.id == currentFilterId }
            if (oldIdx != -1) notifyItemChanged(oldIdx)
            if (newIdx != -1) notifyItemChanged(newIdx)
        } else {
            val idx = filters.indexOfFirst { it.id == currentFilterId }
            if (idx != -1) notifyItemChanged(idx)
        }
    }

    inner class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val imageView: ImageView = view.findViewById(R.id.filterThumbnail)
        val dimView: View = view.findViewById(R.id.filterDimView)
        val borderView: View = view.findViewById(R.id.filterBorderView)
        val nameText: TextView = view.findViewById(R.id.filterNameText)
        val intensityText: TextView = view.findViewById(R.id.filterIntensityText)

        init {
            view.setOnClickListener {
                val pos = adapterPosition
                if (pos != RecyclerView.NO_POSITION) {
                    onFilterSelected(filters[pos], pos)
                }
            }
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_filter_thumbnail, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val filter = filters[position]
        holder.nameText.text = filter.name
        
        val bmp = thumbnailCache[filter.id] ?: originalThumbnail
        holder.imageView.setImageBitmap(bmp)

        val isSelected = currentFilterId == filter.id
        holder.borderView.visibility = if (isSelected) View.VISIBLE else View.GONE
        val defaultTextColor = androidx.core.content.ContextCompat.getColor(holder.itemView.context, R.color.filter_name_text)
        holder.nameText.setTextColor(if (isSelected) themeColor else defaultTextColor)
        
        // 동적 테마 색상 적용
        val background = holder.borderView.background
        if (background is android.graphics.drawable.GradientDrawable) {
            val strokeWidth = holder.borderView.context.resources.displayMetrics.density * 2
            background.mutate()
            background.setStroke(strokeWidth.toInt(), themeColor)
        }
        
        holder.intensityText.setTextColor(themeColor)
        
        if (isSelected && filter.id != "original") {
            holder.dimView.visibility = View.VISIBLE
            holder.intensityText.visibility = View.VISIBLE
            holder.intensityText.text = "${(currentIntensity * 100).toInt()}"
        } else {
            holder.dimView.visibility = View.GONE
            holder.intensityText.visibility = View.GONE
        }
    }

    override fun getItemCount(): Int = filters.size
}
