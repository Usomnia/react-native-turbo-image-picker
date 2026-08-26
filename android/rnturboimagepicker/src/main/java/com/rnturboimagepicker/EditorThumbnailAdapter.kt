package com.rnturboimagepicker

import android.net.Uri
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide

class EditorThumbnailAdapter(
    private val uris: List<Uri>,
    private val onItemClick: (Int) -> Unit
) : RecyclerView.Adapter<EditorThumbnailAdapter.VH>() {

    private var selectedIndex: Int = 0

    fun setSelectedIndex(index: Int) {
        val oldIndex = selectedIndex
        selectedIndex = index
        notifyItemChanged(oldIndex)
        notifyItemChanged(selectedIndex)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_editor_thumbnail, parent, false)
        return VH(view)
    }

    override fun getItemCount(): Int = uris.size

    override fun onBindViewHolder(holder: VH, position: Int) {
        holder.bind(uris[position], position == selectedIndex)
        holder.itemView.setOnClickListener { onItemClick(position) }
    }

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        private val imageView: ImageView = view.findViewById(R.id.thumbnailImage)
        private val selectionBorder: View = view.findViewById(R.id.selectionBorder)

        fun bind(uri: Uri, isSelected: Boolean) {
            Glide.with(imageView.context)
                .load(uri)
                .centerCrop()
                .into(imageView)
            
            selectionBorder.visibility = if (isSelected) View.VISIBLE else View.GONE
        }
    }
}
