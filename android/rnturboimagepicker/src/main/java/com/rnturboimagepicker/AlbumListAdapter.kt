package com.rnturboimagepicker

import android.net.Uri
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide

class AlbumListAdapter(
    private var albums: List<Album>,
    private val onAlbumSelected: (Album) -> Unit
) : RecyclerView.Adapter<AlbumListAdapter.AlbumViewHolder>() {

    inner class AlbumViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val coverImage: ImageView = itemView.findViewById(R.id.coverImage)
        val albumName: TextView = itemView.findViewById(R.id.albumName)
        val imageCount: TextView = itemView.findViewById(R.id.imageCount)
        val rootView: View = itemView.findViewById(R.id.albumRootView) ?: itemView
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): AlbumViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_album_list, parent, false)
        return AlbumViewHolder(view)
    }

    override fun onBindViewHolder(holder: AlbumViewHolder, position: Int) {
        val album = albums[position]
        
        // Load cover image
        if (album.coverImageUri != null) {
            Glide.with(holder.itemView.context.applicationContext)
                .asBitmap()
                .load(com.rnturboimagepicker.glide.FastThumbnail(album.coverImageUri, 200))
                .diskCacheStrategy(com.bumptech.glide.load.engine.DiskCacheStrategy.NONE)
                .centerCrop()
                .override(200, 200)
                .placeholder(R.drawable.image_placeholder)
                .error(R.drawable.image_placeholder)
                .into(holder.coverImage)
        } else {
            holder.coverImage.setImageResource(R.drawable.image_placeholder)
        }
        
        // Set album name and count
        holder.albumName.text = album.bucketName ?: ""
        holder.imageCount.text = "${album.imageCount}"
        
        // Handle click
        holder.rootView.setOnClickListener {
            onAlbumSelected(album)
        }
    }

    override fun getItemCount(): Int = albums.size
    
    fun updateAlbums(newAlbums: List<Album>) {
        albums = newAlbums
        notifyDataSetChanged()
    }
}

