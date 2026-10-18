package com.brudcast.reactnative.inapp

import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.viewmanagers.BrudcastInboxMessageViewManagerDelegate
import com.facebook.react.viewmanagers.BrudcastInboxMessageViewManagerInterface

/** Creates the views behind `BrudcastInboxMessage`. */
@ReactModule(name = BrudcastInboxMessageViewManager.NAME)
internal class BrudcastInboxMessageViewManager :
    SimpleViewManager<BrudcastInboxMessageView>(),
    BrudcastInboxMessageViewManagerInterface<BrudcastInboxMessageView> {
    private val delegate = BrudcastInboxMessageViewManagerDelegate(this)

    override fun getDelegate(): ViewManagerDelegate<BrudcastInboxMessageView> = delegate

    override fun getName(): String = NAME

    override fun createViewInstance(context: ThemedReactContext): BrudcastInboxMessageView = BrudcastInboxMessageView(context)

    @ReactProp(name = "messageId")
    override fun setMessageId(view: BrudcastInboxMessageView, value: String?) {
        view.setMessageId(value)
    }

    override fun getExportedCustomDirectEventTypeConstants(): Map<String, Any> =
        mapOf(ContentHeightChangeEvent.NAME to mapOf("registrationName" to "onContentHeightChange"))

    companion object {
        const val NAME: String = "BrudcastInboxMessageView"
    }
}
