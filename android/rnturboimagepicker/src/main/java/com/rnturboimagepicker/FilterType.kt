package com.rnturboimagepicker

import android.graphics.ColorMatrix

data class FilterState(
    var filterId: String = "original",
    var intensity: Float = 1.0f
)

data class ImageFilter(
    val id: String,
    val name: String,
    val targetMatrix: ColorMatrix
) {
    fun apply(intensity: Float): ColorMatrix {
        if (id == "original" || intensity == 0f) {
            return ColorMatrix() // Identity
        }
        val identity = ColorMatrix()
        val result = ColorMatrix()
        val idArray = identity.array
        val tgtArray = targetMatrix.array
        val resArray = FloatArray(20)
        
        for (i in 0 until 20) {
            resArray[i] = idArray[i] + (tgtArray[i] - idArray[i]) * intensity
        }
        result.set(resArray)
        return result
    }
}
