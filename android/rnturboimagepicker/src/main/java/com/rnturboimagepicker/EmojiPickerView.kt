package com.rnturboimagepicker

import android.content.Context
import android.graphics.Typeface
import android.util.AttributeSet
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.max
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

class EmojiPickerView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null, defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {

    var onEmojiSelected: ((String) -> Unit)? = null
    var onCancel: (() -> Unit)? = null
    var onDone: (() -> Unit)? = null

    var themeColor: Int = 0xFFFFCC00.toInt()
        set(value) {
            field = value
            if (::tabAdapter.isInitialized) {
                tabAdapter.notifyDataSetChanged()
            }
        }

    private var selectedCategoryIndex = 0
    private var isGridVisible = true

    private val tabRecyclerView: RecyclerView
    private val emojiRecyclerView: RecyclerView
    private val dimView: View
    private val panelView: View

    private lateinit var tabAdapter: TabAdapter
    private lateinit var emojiAdapter: EmojiAdapter

    init {
        LayoutInflater.from(context).inflate(R.layout.layout_emoji_picker, this, true)

        tabRecyclerView = findViewById(R.id.tabRecyclerView)
        emojiRecyclerView = findViewById(R.id.emojiRecyclerView)
        dimView = findViewById(R.id.dimView)
        panelView = findViewById(R.id.panelView)

        // Handle system navigation bar overlap
        ViewCompat.setOnApplyWindowInsetsListener(panelView) { view, insets ->
            val navInsets = insets.getInsets(WindowInsetsCompat.Type.navigationBars())
            view.setPadding(0, 0, 0, navInsets.bottom)
            insets
        }

        findViewById<View>(R.id.btnCancel).setOnClickListener { onCancel?.invoke() }
        findViewById<View>(R.id.btnConfirm).setOnClickListener { onDone?.invoke() }

        // Setup Tab RecyclerView
        tabAdapter = TabAdapter { index ->
            selectedCategoryIndex = index
            tabAdapter.notifyDataSetChanged()
            emojiAdapter.notifyDataSetChanged()
            emojiRecyclerView.scrollToPosition(0)
            showGrid(true)
        }
        tabRecyclerView.layoutManager = LinearLayoutManager(context, LinearLayoutManager.HORIZONTAL, false)
        tabRecyclerView.adapter = tabAdapter

        // Setup Emoji RecyclerView
        val spanCount = 4
        emojiRecyclerView.layoutManager = GridLayoutManager(context, spanCount)
        emojiAdapter = EmojiAdapter { emoji ->
            onEmojiSelected?.invoke(emoji)
            showGrid(false)
        }
        emojiRecyclerView.adapter = emojiAdapter

        // Dim view tap to close/hide grid if needed, or pass through
        dimView.setOnClickListener {
            // Do nothing, but consume touch so it doesn't pass to image if grid is visible
        }
    }

    override fun onInterceptTouchEvent(ev: android.view.MotionEvent?): Boolean {
        // If grid is hidden, we want to let touches pass through to the parent (ImageEditorActivity)
        // so the user can interact with the image/stickers.
        // Wait, if this view is an overlay, how do we pass touches through?
        // We handle that in ImageEditorActivity by setting the visibility of dimView or setting isClickable.
        return super.onInterceptTouchEvent(ev)
    }

    fun showGrid(_visible: Boolean) {
        isGridVisible = _visible
        if (isGridVisible) {
            emojiRecyclerView.visibility = View.VISIBLE
            dimView.visibility = View.VISIBLE
        } else {
            emojiRecyclerView.visibility = View.GONE
            dimView.visibility = View.GONE
        }
    }

    fun isGridShowing() = isGridVisible

    // -- Adapters --

    private inner class TabAdapter(val onTabClick: (Int) -> Unit) : RecyclerView.Adapter<TabAdapter.TabViewHolder>() {
        inner class TabViewHolder(view: View) : RecyclerView.ViewHolder(view) {
            val tvIcon: TextView = view.findViewById(R.id.tvIcon)
            val indicatorView: View = view.findViewById(R.id.indicatorView)
            init {
                view.setOnClickListener { onTabClick(adapterPosition) }
            }
        }
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): TabViewHolder {
            val view = LayoutInflater.from(parent.context).inflate(R.layout.item_emoji_tab, parent, false)
            return TabViewHolder(view)
        }
        override fun onBindViewHolder(holder: TabViewHolder, position: Int) {
            holder.tvIcon.text = EmojiData.getCategories(context)[position].icon
            holder.tvIcon.alpha = if (position == selectedCategoryIndex) 1.0f else 0.4f
            holder.indicatorView.visibility = if (position == selectedCategoryIndex) View.VISIBLE else View.INVISIBLE
            holder.indicatorView.setBackgroundColor(themeColor)
        }
        override fun getItemCount() = EmojiData.getCategories(context).size
    }

    private inner class EmojiAdapter(val onEmojiClick: (String) -> Unit) : RecyclerView.Adapter<EmojiAdapter.EmojiViewHolder>() {
        
        private fun getEmojiUrl(emoji: String): String {
            val hex = emoji.codePoints().toArray().joinToString("_") { Integer.toHexString(it) }
            return "https://fonts.gstatic.com/s/e/notoemoji/latest/$hex/512.png"
        }

        inner class EmojiViewHolder(view: View) : RecyclerView.ViewHolder(view) {
            val tvEmoji: android.widget.ImageView = view.findViewById(R.id.tvEmoji)
            val progressBar: android.widget.ProgressBar = view.findViewById(R.id.progressBar)
            init {
                view.setOnClickListener {
                    val cat = EmojiData.getCategories(context)[selectedCategoryIndex]
                    onEmojiClick(cat.emojis[adapterPosition])
                }
            }
        }
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): EmojiViewHolder {
            val view = LayoutInflater.from(parent.context).inflate(R.layout.item_emoji, parent, false)
            return EmojiViewHolder(view)
        }
        override fun onBindViewHolder(holder: EmojiViewHolder, position: Int) {
            val cat = EmojiData.getCategories(context)[selectedCategoryIndex]
            val emojiStr = cat.emojis[position]
            holder.progressBar.visibility = View.VISIBLE
            com.bumptech.glide.Glide.with(context)
                .load(getEmojiUrl(emojiStr))
                .diskCacheStrategy(com.bumptech.glide.load.engine.DiskCacheStrategy.ALL)
                .listener(GlideHelper.getListener(holder.progressBar))
                .into(holder.tvEmoji)
        }
        override fun getItemCount(): Int {
            return EmojiData.getCategories(context)[selectedCategoryIndex].emojis.size
        }
    }
}
