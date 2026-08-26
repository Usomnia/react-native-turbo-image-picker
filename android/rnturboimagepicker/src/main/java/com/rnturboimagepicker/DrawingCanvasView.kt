package com.rnturboimagepicker

import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import kotlin.math.sqrt

/**
 * DrawingCanvasView
 *
 * iOS DrawingCanvasView에 대응하는 Android View.
 * - Pen: 라운드 캡/조인 경로 렌더링
 * - Mosaic: 화면(캔버스) 크기 기준 고정 타일 수로 픽셀화 → 이미지 해상도 무관
 * - Eraser: 오버레이 레이어에서 CLEAR 블렌드 (원본 이미지 보호)
 * - Undo/Redo/ClearAll
 */
class DrawingCanvasView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    var originalBitmap: Bitmap? = null
        set(value) {
            field = value
            // 모자이크 캐시 초기화 (캔버스 크기 확정 후 getDisplayMosaic()에서 재생성)
            displayMosaicBitmap?.recycle()
            displayMosaicBitmap = null
            invalidate()
        }

    val paths = mutableListOf<DrawingPath>()
    val undonePaths = mutableListOf<DrawingPath>()
    private var currentPath: DrawingPath? = null
    private var lastX = 0f
    private var lastY = 0f

    var currentTool: DrawingToolType = DrawingToolType.PEN
    var currentColor: Int = Color.YELLOW
    var currentLineWidth: Float = 30f

    var onStateChanged: (() -> Unit)? = null
    var onDrawingStarted: (() -> Unit)? = null
    var onDrawingEnded: (() -> Unit)? = null

    // ─── Paint setups ──────────────────────────────────────
    private val basePaint = Paint().apply {
        isAntiAlias = true
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    // ─── Touch handling ────────────────────────────────────
    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                val path = Path().apply { moveTo(event.x, event.y) }
                lastX = event.x
                lastY = event.y
                // 모자이크 툴은 브러시 크기 중간(고정)
                val lineWidth = if (currentTool == DrawingToolType.MOSAIC) MOSAIC_FIXED_LINE_WIDTH else currentLineWidth
                currentPath = DrawingPath(path, currentTool, currentColor, lineWidth)
                undonePaths.clear()
                invalidate()
                onStateChanged?.invoke()
                onDrawingStarted?.invoke()
            }
            MotionEvent.ACTION_MOVE -> {
                val cp = currentPath ?: return true
                val dx = event.x - lastX
                val dy = event.y - lastY
                val dist = sqrt(dx * dx + dy * dy)
                if (dist < 3f) return true

                val midX = (lastX + event.x) / 2f
                val midY = (lastY + event.y) / 2f
                cp.path.quadTo(lastX, lastY, midX, midY)
                lastX = event.x
                lastY = event.y
                invalidate()
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val cp = currentPath ?: return true
                cp.path.lineTo(event.x, event.y)
                paths.add(cp)
                currentPath = null
                invalidate()
                onStateChanged?.invoke()
                onDrawingEnded?.invoke()
            }
        }
        return true
    }

    // ─── Mosaic (화면 크기 기준) ───────────────────────────
    private var displayMosaicBitmap: Bitmap? = null
    private var displayMosaicWidth: Int = 0
    private var displayMosaicHeight: Int = 0
    private var displayMosaicBlockSize: Float = -1f // 캐시 무효화 감지용

    /**
     * 모자이크 타일 블록 크기 (dp 단위).
     * 클수록 강한 모자이크 (픽셀이 큼), 범위: 6dp(미세) ~ 20dp(강함), 기본: 6dp (가장 약하게)
     */
    var mosaicBlockSizeDp: Float = 6f
        set(value) {
            field = value
            // 블록 크기 변경 시 모자이크 캐시 무효화
            displayMosaicBitmap?.recycle()
            displayMosaicBitmap = null
            displayMosaicBlockSize = -1f
            invalidate()
        }

    private var cachedOverlayBmp: Bitmap? = null
    private var cachedOverlayCanvas: Canvas? = null

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        // 캔버스 크기가 바뀌면 모자이크 캐시 무효화
        displayMosaicBitmap?.recycle()
        displayMosaicBitmap = null
        cachedOverlayBmp?.recycle()
        cachedOverlayBmp = null
        if (w > 0 && h > 0) {
            cachedOverlayBmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            cachedOverlayCanvas = Canvas(cachedOverlayBmp!!)
        }
    }

    /**
     * 화면(캔버스) 크기 기준, mosaicBlockSizeDp로 타일 크기를 조절해 모자이크 생성.
     */
    private fun getDisplayMosaic(): Bitmap? {
        val src = originalBitmap ?: return null
        val cw = width; val ch = height
        if (cw <= 0 || ch <= 0) return null

        val density = context.resources.displayMetrics.density
        val blockPx = mosaicBlockSizeDp * density // dp → px

        if (displayMosaicBitmap == null || displayMosaicWidth != cw || displayMosaicHeight != ch
            || displayMosaicBlockSize != mosaicBlockSizeDp) {
            // 화면 너비 기준 타일 수 결정: 블록 클수록 타일 수 적음 (강한 모자이크)
            val tilesX = maxOf(5, (cw / blockPx).toInt())
            val tilesY = (tilesX * (src.height.toFloat() / src.width.toFloat())).toInt().coerceAtLeast(1)

            // 원본 이미지 → 타일 크기로 다운스케일 → 캔버스 크기로 필터 없이 업스케일
            val smallBmp = Bitmap.createScaledBitmap(src, tilesX, tilesY, true)
            val noFilterPaint = Paint().apply { isFilterBitmap = false }
            val result = Bitmap.createBitmap(cw, ch, Bitmap.Config.ARGB_8888)
            Canvas(result).drawBitmap(
                Bitmap.createScaledBitmap(smallBmp, cw, ch, false), 0f, 0f, noFilterPaint
            )
            smallBmp.recycle()

            displayMosaicBitmap?.recycle()
            displayMosaicBitmap = result
            displayMosaicWidth = cw
            displayMosaicHeight = ch
            displayMosaicBlockSize = mosaicBlockSizeDp
        }
        return displayMosaicBitmap
    }

    // ─── Drawing ───────────────────────────────────────────
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val obmp = cachedOverlayBmp ?: return
        val ocvs = cachedOverlayCanvas ?: return

        obmp.eraseColor(Color.TRANSPARENT)

        val allPaths = paths + listOfNotNull(currentPath)
        renderPathsToCanvas(ocvs, allPaths, getDisplayMosaic())

        canvas.drawBitmap(obmp, 0f, 0f, null)
    }

    // Pre-allocated paints for drawing
    private val cachedPathPaint = Paint(basePaint)
    private val mosaicTilePaint = Paint().apply { isAntiAlias = false }
    private val mosaicMaskPaint = Paint().apply {
        isAntiAlias = false
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        color = Color.BLACK
    }

    private fun renderPathsToCanvas(targetCanvas: Canvas, pathsToDraw: List<DrawingPath>, mosaicImg: Bitmap?) {
        var i = 0
        while (i < pathsToDraw.size) {
            val p = pathsToDraw[i]

            if (p.type == DrawingToolType.MOSAIC) {
                var j = i + 1
                while (j < pathsToDraw.size && pathsToDraw[j].type == DrawingToolType.MOSAIC) {
                    j++
                }
                val mosaicGroup = pathsToDraw.subList(i, j)
                if (mosaicImg != null) {
                    renderMosaicTileSnapped(targetCanvas, mosaicGroup, mosaicImg)
                }
                i = j
            } else {
                cachedPathPaint.strokeWidth = p.lineWidth
                if (p.type == DrawingToolType.ERASER) {
                    cachedPathPaint.xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
                    cachedPathPaint.color = Color.TRANSPARENT
                    targetCanvas.drawPath(p.path, cachedPathPaint)
                    cachedPathPaint.xfermode = null
                } else {
                    cachedPathPaint.color = p.color
                    targetCanvas.drawPath(p.path, cachedPathPaint)
                }
                i++
            }
        }
    }

    /**
     * 모자이크 타일 단위 렌더링:
     * 경로를 타일 격자 해상도의 작은 마스크 비트맵으로 렌더링 후,
     * 덮인 타일만 완전 불투명하게 채워 가장자리 반투명 현상을 제거한다.
     */
    private fun renderMosaicTileSnapped(targetCanvas: Canvas, mosaicGroup: List<DrawingPath>, mosaicImg: Bitmap) {
        val cw = width; val ch = height
        if (cw <= 0 || ch <= 0 || mosaicImg.isRecycled) return

        val density = context.resources.displayMetrics.density
        val targetTilePx = density * 8f
        val numTilesX = maxOf(40, (cw / targetTilePx).toInt())
        val numTilesY = maxOf(1, (numTilesX * ch / cw) + 1)
        val tileW = cw.toFloat() / numTilesX
        val tileH = ch.toFloat() / numTilesY

        // 1. 경로를 타일 격자 크기의 작은 마스크 비트맵에 렌더링 (픽셀 = 타일)
        val maskBmp = Bitmap.createBitmap(numTilesX, numTilesY, Bitmap.Config.ARGB_8888)
        val maskCanvas = Canvas(maskBmp)
        maskCanvas.scale(numTilesX.toFloat() / cw, numTilesY.toFloat() / ch)
        for (mp in mosaicGroup) {
            mosaicMaskPaint.strokeWidth = mp.lineWidth
            maskCanvas.drawPath(mp.path, mosaicMaskPaint)
        }
        val maskPixels = IntArray(numTilesX * numTilesY)
        maskBmp.getPixels(maskPixels, 0, numTilesX, 0, 0, numTilesX, numTilesY)
        maskBmp.recycle()

        // 2. 모자이크 이미지를 타일 해상도로 다운스케일하여 타일 색상 추출
        val tileColorBmp = Bitmap.createScaledBitmap(mosaicImg, numTilesX, numTilesY, false)
        val tileColors = IntArray(numTilesX * numTilesY)
        tileColorBmp.getPixels(tileColors, 0, numTilesX, 0, 0, numTilesX, numTilesY)
        tileColorBmp.recycle()

        // 3. 덮인 타일만 완전 불투명하게 그리기
        val dstRect = RectF()
        for (ty in 0 until numTilesY) {
            for (tx in 0 until numTilesX) {
                if (Color.alpha(maskPixels[ty * numTilesX + tx]) > 0) {
                    mosaicTilePaint.color = tileColors[ty * numTilesX + tx]
                    dstRect.set(
                        tx * tileW, ty * tileH,
                        minOf((tx + 1) * tileW, cw.toFloat()),
                        minOf((ty + 1) * tileH, ch.toFloat())
                    )
                    targetCanvas.drawRect(dstRect, mosaicTilePaint)
                }
            }
        }
    }

    // ─── Undo / Redo / Clear ───────────────────────────────
    fun undo() {
        if (paths.isEmpty()) return
        undonePaths.add(paths.removeLast())
        invalidate()
        onStateChanged?.invoke()
    }

    fun redo() {
        if (undonePaths.isEmpty()) return
        paths.add(undonePaths.removeLast())
        invalidate()
        onStateChanged?.invoke()
    }

    fun clearAll() {
        paths.clear()
        undonePaths.clear()
        invalidate()
        onStateChanged?.invoke()
    }

    fun cancelCurrentPath() {
        currentPath = null
        invalidate()
    }

    // ─── Merged bitmap export ──────────────────────────────
    fun generateMergedBitmap(): Bitmap? {
        val src = originalBitmap ?: return null

        val overlayBmp = Bitmap.createBitmap(width.coerceAtLeast(1), height.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        val overlayCanvas = Canvas(overlayBmp)

        renderPathsToCanvas(overlayCanvas, paths, getDisplayMosaic())

        val scaledOverlay = Bitmap.createScaledBitmap(overlayBmp, src.width, src.height, true)
        overlayBmp.recycle()

        val result = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        val finalCanvas = Canvas(result)
        finalCanvas.drawBitmap(src, 0f, 0f, null)
        finalCanvas.drawBitmap(scaledOverlay, 0f, 0f, null)
        scaledOverlay.recycle()

        return result
    }

    companion object {
        /** 모자이크 툴 사용 시 고정 브러시 크기 (px) */
        const val MOSAIC_FIXED_LINE_WIDTH = 40f
    }
}
