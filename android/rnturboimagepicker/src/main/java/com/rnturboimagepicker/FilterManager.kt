package com.rnturboimagepicker

import android.graphics.ColorMatrix
import android.content.Context

class FilterManager private constructor() {
    private var _filters: List<ImageFilter>? = null
    fun getFilters(context: Context): List<ImageFilter> {

    if (_filters != null) return _filters!!
        
        val list = mutableListOf<ImageFilter>()
        
        // 1. Original
        list.add(ImageFilter("original", context.getString(R.string.filter_original), ColorMatrix()))
        
        // Helper lambdas
        fun createMatrix(block: (ColorMatrix) -> Unit): ColorMatrix {
            val m = ColorMatrix()
            block(m)
            return m
        }
        
        fun brightnessContrast(brightness: Float, contrast: Float): ColorMatrix {
            val m = ColorMatrix()
            val t = (1.0f - contrast) / 2.0f * 255f + brightness * 255f
            m.set(floatArrayOf(
                contrast, 0f, 0f, 0f, t,
                0f, contrast, 0f, 0f, t,
                0f, 0f, contrast, 0f, t,
                0f, 0f, 0f, 1f, 0f
            ))
            return m
        }

        fun tintMatrix(r: Float, g: Float, b: Float): ColorMatrix {
            val m = ColorMatrix()
            m.set(floatArrayOf(
                r, 0f, 0f, 0f, 0f,
                0f, g, 0f, 0f, 0f,
                0f, 0f, b, 0f, 0f,
                0f, 0f, 0f, 1f, 0f
            ))
            return m
        }

        // 2. Soft (Low contrast, slight brightness)
        list.add(ImageFilter("soft", context.getString(R.string.filter_soft), brightnessContrast(0.05f, 0.9f)))
        
        // 3. Clean (Slight contrast boost, desaturate slightly)
        list.add(ImageFilter("clean", context.getString(R.string.filter_clean), createMatrix { 
            it.setSaturation(0.9f)
            it.postConcat(brightnessContrast(0.02f, 1.1f))
        }))
        
        // 4. Cold (Blue tint)
        list.add(ImageFilter("cold", context.getString(R.string.filter_cold), tintMatrix(0.9f, 0.95f, 1.1f)))
        
        // 5. Warm (Red/Yellow tint)
        list.add(ImageFilter("warm", context.getString(R.string.filter_warm), tintMatrix(1.1f, 1.05f, 0.9f)))
        
        // 6. Shining (High brightness, high contrast)
        list.add(ImageFilter("shining", context.getString(R.string.filter_shining), brightnessContrast(0.1f, 1.15f)))
        
        // 7. Romantic (Pinkish)
        list.add(ImageFilter("romantic", context.getString(R.string.filter_romantic), createMatrix {
            it.postConcat(tintMatrix(1.1f, 0.95f, 1.05f))
            it.postConcat(brightnessContrast(0.05f, 1.0f))
        }))
        
        // 8. Calm (Desaturated, slight fade)
        list.add(ImageFilter("calm", context.getString(R.string.filter_calm), createMatrix {
            it.setSaturation(0.7f)
            it.postConcat(brightnessContrast(-0.02f, 0.95f))
        }))
        
        // 9. Vintage
        list.add(ImageFilter("vintage", context.getString(R.string.filter_vintage), createMatrix {
            it.setSaturation(0.6f)
            it.postConcat(tintMatrix(1.1f, 1.0f, 0.8f))
        }))
        
        // 10. Mono
        list.add(ImageFilter("mono", context.getString(R.string.filter_mono), createMatrix { it.setSaturation(0f) }))
        
        // 11. Sepia
        list.add(ImageFilter("sepia", context.getString(R.string.filter_sepia), createMatrix {
            it.set(floatArrayOf(
                0.393f, 0.769f, 0.189f, 0f, 0f,
                0.349f, 0.686f, 0.168f, 0f, 0f,
                0.272f, 0.534f, 0.131f, 0f, 0f,
                0f, 0f, 0f, 1f, 0f
            ))
        }))
        
        // 12. Film
        list.add(ImageFilter("film", context.getString(R.string.filter_film), createMatrix {
            it.setSaturation(1.1f)
            it.postConcat(brightnessContrast(0f, 1.2f))
        }))
        
        // 13. Analog
        list.add(ImageFilter("analog", context.getString(R.string.filter_instant), createMatrix {
            it.setSaturation(0.8f)
            val fade = ColorMatrix(floatArrayOf(
                0.9f, 0f, 0f, 0f, 25f,
                0f, 0.9f, 0f, 0f, 25f,
                0f, 0f, 0.9f, 0f, 25f,
                0f, 0f, 0f, 1f, 0f
            ))
            it.postConcat(fade)
            it.postConcat(tintMatrix(1.05f, 1.0f, 0.95f))
        }))
        
        // 14. Noir
        list.add(ImageFilter("noir", context.getString(R.string.filter_noir), createMatrix {
            it.setSaturation(0f)
            it.postConcat(brightnessContrast(-0.1f, 1.3f))
        }))
        
        // 15. Process
        list.add(ImageFilter("process", context.getString(R.string.filter_process), createMatrix {
            // Teal/Orange shift approximation
            it.set(floatArrayOf(
                1.1f, 0f, 0f, 0f, 10f,
                0f, 1.0f, 0.1f, 0f, 0f,
                0f, 0.1f, 1.1f, 0f, 10f,
                0f, 0f, 0f, 1f, 0f
            ))
            it.postConcat(brightnessContrast(0.05f, 1.1f))
        }))
        
        // 16. Tonal
        list.add(ImageFilter("tonal", context.getString(R.string.filter_tonal), createMatrix {
            it.setSaturation(0f)
            it.postConcat(brightnessContrast(0.05f, 0.8f))
        }))
        
        // 17. Transfer
        list.add(ImageFilter("transfer", context.getString(R.string.filter_transfer), createMatrix {
            it.setSaturation(0.8f)
            it.postConcat(tintMatrix(1.1f, 1.0f, 0.9f))
            it.postConcat(brightnessContrast(0.0f, 1.1f))
        }))
        
        // 18. Chrome
        list.add(ImageFilter("chrome", context.getString(R.string.filter_chrome), createMatrix {
            it.setSaturation(1.3f)
            it.postConcat(brightnessContrast(0f, 1.15f))
        }))
        
        // 19. Fade
        list.add(ImageFilter("fade", context.getString(R.string.filter_fade), createMatrix {
            val fade = ColorMatrix(floatArrayOf(
                0.8f, 0f, 0f, 0f, 40f,
                0f, 0.8f, 0f, 0f, 40f,
                0f, 0f, 0.8f, 0f, 40f,
                0f, 0f, 0f, 1f, 0f
            ))
            it.postConcat(fade)
        }))
        
        // 20. Curve (영화같은)
        list.add(ImageFilter("curve", context.getString(R.string.filter_cinematic), createMatrix {
            it.setSaturation(0.9f)
            it.postConcat(tintMatrix(0.95f, 1.0f, 1.05f))
            it.postConcat(brightnessContrast(0f, 1.1f))
        }))

        _filters = list
        return list
    }

    companion object {
        val instance = FilterManager()
    }
}
