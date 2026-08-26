package com.rnturboimagepicker

import android.view.MotionEvent
import kotlin.math.atan2

class RotationGestureDetector(private val listener: OnRotationGestureListener) {

    interface OnRotationGestureListener {
        fun onRotation(detector: RotationGestureDetector): Boolean
    }

    private var ptrID1: Int = MotionEvent.INVALID_POINTER_ID
    private var ptrID2: Int = MotionEvent.INVALID_POINTER_ID
    private var sX: Float = 0f
    private var sY: Float = 0f
    private var fX: Float = 0f
    private var fY: Float = 0f
    var angle: Float = 0f
        private set

    fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                ptrID1 = event.getPointerId(event.actionIndex)
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                ptrID2 = event.getPointerId(event.actionIndex)
                sX = event.getX(event.findPointerIndex(ptrID1))
                sY = event.getY(event.findPointerIndex(ptrID1))
                fX = event.getX(event.findPointerIndex(ptrID2))
                fY = event.getY(event.findPointerIndex(ptrID2))
            }
            MotionEvent.ACTION_MOVE -> {
                if (ptrID1 != MotionEvent.INVALID_POINTER_ID && ptrID2 != MotionEvent.INVALID_POINTER_ID) {
                    val nsX = event.getX(event.findPointerIndex(ptrID1))
                    val nsY = event.getY(event.findPointerIndex(ptrID1))
                    val nfX = event.getX(event.findPointerIndex(ptrID2))
                    val nfY = event.getY(event.findPointerIndex(ptrID2))

                    angle = angleBetweenLines(fX, fY, sX, sY, nfX, nfY, nsX, nsY)

                    listener.onRotation(this)
                }
            }
            MotionEvent.ACTION_UP -> {
                ptrID1 = MotionEvent.INVALID_POINTER_ID
            }
            MotionEvent.ACTION_POINTER_UP -> {
                ptrID2 = MotionEvent.INVALID_POINTER_ID
            }
            MotionEvent.ACTION_CANCEL -> {
                ptrID1 = MotionEvent.INVALID_POINTER_ID
                ptrID2 = MotionEvent.INVALID_POINTER_ID
            }
        }
        return true
    }

    private fun angleBetweenLines(
        fX: Float, fY: Float, sX: Float, sY: Float,
        nfX: Float, nfY: Float, nsX: Float, nsY: Float
    ): Float {
        val angle1 = atan2((fY - sY).toDouble(), (fX - sX).toDouble()).toFloat()
        val angle2 = atan2((nfY - nsY).toDouble(), (nfX - nsX).toDouble()).toFloat()
        var angle = Math.toDegrees((angle2 - angle1).toDouble()).toFloat()
        if (angle < -180f) angle += 360.0f
        if (angle > 180f) angle -= 360.0f
        return angle
    }
}
