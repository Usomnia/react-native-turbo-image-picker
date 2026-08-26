package com.rnturboimagepicker

import android.graphics.Path

data class DrawingPath(
    val path: Path,
    val type: DrawingToolType,
    val color: Int,
    val lineWidth: Float
)
