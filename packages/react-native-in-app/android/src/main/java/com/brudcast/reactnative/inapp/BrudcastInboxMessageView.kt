package com.brudcast.reactnative.inapp

import android.widget.FrameLayout
import com.brudcast.sdk.inapp.InAppModule
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.PixelUtil
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.events.Event

/**
 * The view behind `BrudcastInboxMessage`: an inbox entry drawn by the native renderer, which
 * reports the height its design needs to JavaScript.
 *
 * React Native lays out only the views it created, so this view measures and lays out the drawn
 * entry itself whenever it asks for a layout.
 *
 * @param context The React Native context.
 */
internal class BrudcastInboxMessageView(private val context: ThemedReactContext) : FrameLayout(context) {
    private var messageId: String? = null
    private var emittedHeight = -1.0

    private val measureAndLayout = Runnable {
        measure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY))
        layout(left, top, right, bottom)
    }

    /**
     * Draws the entry for a message id, replacing the one drawn before.
     *
     * @param id The message id, from `BrudcastInbox.list`.
     */
    fun setMessageId(id: String?) {
        if (id == messageId) return
        messageId = id
        removeAllViews()
        emittedHeight = -1.0
        val message = id?.let { BrudcastInAppModule.message(it) } ?: return emitHeight(0.0)
        val view = InAppModule.inbox.render(context, message) { pixels ->
            emitHeight(PixelUtil.toDIPFromPixel(pixels.toFloat()).toDouble())
        } ?: return emitHeight(0.0)
        addView(view, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
    }

    override fun requestLayout() {
        super.requestLayout()
        post(measureAndLayout)
    }

    /**
     * Tells JavaScript the height the design needs, when it changed.
     *
     * @param height The height in density-independent pixels.
     */
    private fun emitHeight(height: Double) {
        if (height == emittedHeight) return
        emittedHeight = height
        val surfaceId = UIManagerHelper.getSurfaceId(this)
        UIManagerHelper.getEventDispatcherForReactTag(context, id)
            ?.dispatchEvent(ContentHeightChangeEvent(surfaceId, id, height))
    }
}

/**
 * Tells JavaScript the height an inbox entry's design needs.
 *
 * @param surfaceId The surface the view is on.
 * @param viewId The view's React tag.
 * @param height The height in density-independent pixels.
 */
internal class ContentHeightChangeEvent(surfaceId: Int, viewId: Int, private val height: Double) :
    Event<ContentHeightChangeEvent>(surfaceId, viewId) {
    override fun getEventName(): String = NAME

    override fun getEventData(): WritableMap = Arguments.createMap().apply { putDouble("height", height) }

    companion object {
        const val NAME: String = "topContentHeightChange"
    }
}
