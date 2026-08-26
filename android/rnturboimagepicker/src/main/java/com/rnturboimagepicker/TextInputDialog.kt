package com.rnturboimagepicker

import android.app.Dialog
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.fragment.app.DialogFragment

class TextInputDialog : DialogFragment() {

    interface OnTextSavedListener {
        fun onTextSaved(text: String, color: Int)
    }

    var onConfirmListener: ((String, Int) -> Unit)? = null
    var onCancelListener: (() -> Unit)? = null
    private var initialText: String = ""
    private var initialColor: Int = Color.WHITE

    companion object {
        /** Pre-parsed color palette — avoids Color.parseColor on every dialog open. */
        private val COLORS = intArrayOf(
            0xFFFFFFFF.toInt(), // White
            0xFFC0C0C0.toInt(), // Light Gray
            0xFF808080.toInt(), // Gray
            0xFF404040.toInt(), // Dark Gray
            0xFF000000.toInt(), // Black
            0xFFFF3B30.toInt(), // Red
            0xFFFF9500.toInt(), // Orange
            0xFFFFCC00.toInt(), // Yellow
            0xFF4CD964.toInt(), // Green
            0xFF5AC8FA.toInt(), // Teal
            0xFF007AFF.toInt(), // Blue
            0xFF5856D6.toInt(), // Purple
            0xFFFF2D55.toInt()  // Pink
        )

        /** Shared typeface loaded once per process. */
        private var cachedTypeface: Typeface? = null
        private fun getTypeface(context: android.content.Context): Typeface {
            cachedTypeface?.let { return it }
            return try {
                Typeface.createFromAsset(context.assets, "fonts/Pretendard-SemiBold.otf").also {
                    cachedTypeface = it
                }
            } catch (e: Exception) {
                Typeface.DEFAULT_BOLD
            }
        }

        fun newInstance(text: String, color: Int): TextInputDialog {
            val dialog = TextInputDialog()
            dialog.initialText = text
            dialog.initialColor = color
            return dialog
        }
    }

    fun setInitialText(text: String) {
        this.initialText = text
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setStyle(STYLE_NORMAL, android.R.style.Theme_Translucent_NoTitleBar)
    }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = super.onCreateDialog(savedInstanceState)
        dialog.window?.requestFeature(Window.FEATURE_NO_TITLE)
        dialog.window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        return dialog
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.setLayout(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
    }

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.dialog_text_input, container, false)
    }

    // State for O(1) color selection
    private var selectedColorIndex: Int = 0
    private val colorViews = mutableListOf<View>()

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val editText = view.findViewById<EditText>(R.id.textInputEditText)
        val cancelBtn = view.findViewById<TextView>(R.id.textInputCancel)
        val confirmBtn = view.findViewById<TextView>(R.id.textInputConfirm)
        val colorContainer = view.findViewById<LinearLayout>(R.id.colorPickerContainer)

        editText.typeface = getTypeface(requireContext())
        editText.setText(initialText)
        editText.setSelection(editText.text.length)
        editText.setTextColor(initialColor)

        // Find initial selected index
        selectedColorIndex = COLORS.indexOfFirst { it == initialColor }.coerceAtLeast(0)

        val density = resources.displayMetrics.density
        val size = (36 * density).toInt()
        val margin = (8 * density).toInt()

        colorViews.clear()
        for ((index, color) in COLORS.withIndex()) {
            val cv = View(requireContext())
            val params = LinearLayout.LayoutParams(size, size)
            params.setMargins(margin, margin, margin, margin)
            cv.layoutParams = params
            cv.tag = index

            applyColorButtonStyle(cv, color, index == selectedColorIndex)

            cv.setOnClickListener { v ->
                val newIndex = v.tag as Int
                if (newIndex == selectedColorIndex) return@setOnClickListener

                // Deselect previous (O(1))
                applyColorButtonStyle(colorViews[selectedColorIndex], COLORS[selectedColorIndex], false)

                // Select new (O(1))
                selectedColorIndex = newIndex
                initialColor = COLORS[newIndex]
                applyColorButtonStyle(v, COLORS[newIndex], true)
                editText.setTextColor(initialColor)
            }
            colorViews.add(cv)
            colorContainer.addView(cv)
        }

        editText.requestFocus()
        editText.postDelayed({
            val imm = requireContext().getSystemService(android.content.Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
            imm.showSoftInput(editText, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
        }, 100)

        dialog?.window?.let { window ->
            window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE or WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
        }

        ViewCompat.setOnApplyWindowInsetsListener(view) { v, insets ->
            val insetsCompat = insets.getInsets(WindowInsetsCompat.Type.ime() or WindowInsetsCompat.Type.systemBars())
            // Add extra top padding so the top buttons aren't too close to the status bar
            val extraTopPadding = (16 * resources.displayMetrics.density).toInt()
            v.setPadding(0, insetsCompat.top + extraTopPadding, 0, insetsCompat.bottom)
            insets
        }

        cancelBtn.setOnClickListener {
            onCancelListener?.invoke()
            dismiss()
        }
        confirmBtn.setOnClickListener {
            val text = editText.text.toString().trim()
            if (text.isNotEmpty()) {
                onConfirmListener?.invoke(text, initialColor)
            } else {
                onCancelListener?.invoke()
            }
            dismiss()
        }
    }

    /** Applies oval background with appropriate border based on selection state. */
    private fun applyColorButtonStyle(view: View, color: Int, isSelected: Boolean) {
        val gd = GradientDrawable()
        gd.shape = GradientDrawable.OVAL
        gd.setColor(color)
        if (isSelected) {
            gd.setStroke(6, Color.WHITE)
        } else {
            gd.setStroke(2, Color.parseColor("#66FFFFFF"))
        }
        view.background = gd
    }
}
