package com.brudcast.reactnative.inapp

import android.os.Handler
import android.os.Looper
import com.brudcast.sdk.BrudcastApiError
import com.brudcast.sdk.inapp.BrudcastAsyncMessageHandler
import com.brudcast.sdk.inapp.BrudcastInAppMessage
import com.brudcast.sdk.inapp.BrudcastMessageDecision
import com.brudcast.sdk.inapp.BrudcastUnreadCountListener
import com.brudcast.sdk.inapp.InAppFormat
import com.brudcast.sdk.inapp.InAppModule
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.CxxCallbackImpl
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.WritableMap
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * The Brudcast in-app TurboModule: forwards JavaScript calls to the native in-app module, and
 * routes the message handler and the unread count to JavaScript. React Native creates one per
 * JavaScript runtime. Every call is moved to the main thread.
 *
 * @param reactContext The React Native context.
 */
public class BrudcastInAppModule(reactContext: ReactApplicationContext) : NativeBrudcastInAppSpec(reactContext) {
    private val pending = HashMap<String, (BrudcastMessageDecision) -> Unit>()

    private val unreadListener = BrudcastUnreadCountListener { count -> emitOnUnreadCountChange(count.toDouble()) }

    /**
     * Starts following the unread count once React Native has attached the event emitter, since an
     * event sent before then has nowhere to go.
     *
     * @param eventEmitterCallback The emitter React Native attaches.
     */
    override fun setEventEmitterCallback(eventEmitterCallback: CxxCallbackImpl) {
        super.setEventEmitterCallback(eventEmitterCallback)
        main.post { InAppModule.inbox.addUnreadCountListener(unreadListener) }
    }

    override fun invalidate() {
        main.post {
            InAppModule.inbox.removeUnreadCountListener(unreadListener)
            clearMessageHandler()
            val waiting = pending.values.toList()
            pending.clear()
            waiting.forEach { it(BrudcastMessageDecision.SHOW) }
        }
        super.invalidate()
    }

    override fun pauseDisplay() {
        main.post { InAppModule.pauseDisplay() }
    }

    override fun resumeDisplay() {
        main.post { InAppModule.resumeDisplay() }
    }

    override fun sync() {
        main.post { InAppModule.sync() }
    }

    override fun setMessageHandlerEnabled(enabled: Boolean) {
        main.post {
            if (!enabled) return@post clearMessageHandler()
            handlerOwner = this
            InAppModule.setAsyncMessageHandler(BrudcastAsyncMessageHandler { message, decide ->
                remember(message)
                val owner = handlerOwner ?: return@BrudcastAsyncMessageHandler decide(BrudcastMessageDecision.SHOW)
                val requestId = UUID.randomUUID().toString()
                owner.pending[requestId] = decide
                owner.emitOnMessageRequest(Arguments.createMap().apply {
                    putString("requestId", requestId)
                    putMap("message", message.toMap())
                })
            })
        }
    }

    override fun resolveMessage(requestId: String, decision: String) {
        main.post {
            pending.remove(requestId)?.invoke(
                when (decision) {
                    "suppress" -> BrudcastMessageDecision.SUPPRESS
                    "defer" -> BrudcastMessageDecision.DEFER
                    "custom" -> BrudcastMessageDecision.CUSTOM
                    else -> BrudcastMessageDecision.SHOW
                },
            )
        }
    }

    override fun reportImpression(messageId: String) {
        main.post { InAppModule.reportImpression(messageId) }
    }

    override fun reportClick(messageId: String, buttonId: String) {
        main.post { InAppModule.reportClick(messageId, buttonId) }
    }

    override fun reportDismiss(messageId: String) {
        main.post { InAppModule.reportDismiss(messageId) }
    }

    override fun presentInbox(title: String) {
        main.post {
            val context = reactApplicationContext.currentActivity ?: reactApplicationContext.applicationContext
            InAppModule.inbox.present(context, title)
        }
    }

    override fun listInbox(beforeMillis: Double?, limit: Double, promise: Promise) {
        main.post {
            InAppModule.inbox.list(beforeMillis?.toLong(), limit.toInt()) { result ->
                result.fold(
                    onSuccess = { page ->
                        page.messages.forEach(::remember)
                        promise.resolve(Arguments.createMap().apply {
                            putArray("messages", Arguments.createArray().apply { page.messages.forEach { pushMap(it.toMap()) } })
                            putInt("unreadCount", page.unreadCount)
                            putBoolean("hasMore", page.hasMore)
                        })
                    },
                    onFailure = { error -> promise.reject((error as? BrudcastApiError)?.code ?: "inbox_failed", error.message, error) },
                )
            }
        }
    }

    override fun markRead(messageId: String) {
        main.post { InAppModule.inbox.markRead(messageId) }
    }

    override fun deleteMessage(messageId: String) {
        main.post { InAppModule.inbox.delete(messageId) }
    }

    override fun getUnreadCount(promise: Promise) {
        main.post { promise.resolve(InAppModule.inbox.unreadCount.value) }
    }

    private fun clearMessageHandler() {
        if (handlerOwner !== this) return
        handlerOwner = null
        InAppModule.setAsyncMessageHandler(null)
    }

    internal companion object {
        private val main = Handler(Looper.getMainLooper())

        /** The runtime whose JavaScript set the message handler, so an old runtime cannot answer. */
        @Volatile
        private var handlerOwner: BrudcastInAppModule? = null

        private val seen = ConcurrentHashMap<String, BrudcastInAppMessage>()

        /**
         * Keeps a message that crossed to JavaScript, so an inbox message view can draw it by id.
         *
         * @param message The message.
         */
        fun remember(message: BrudcastInAppMessage) {
            seen[message.id] = message
        }

        /**
         * Finds a message that crossed to JavaScript.
         *
         * @param id The message id.
         * @return The message, or null when JavaScript never saw it.
         */
        fun message(id: String): BrudcastInAppMessage? = seen[id]
    }
}

private fun BrudcastInAppMessage.toMap(): WritableMap = Arguments.createMap().apply {
    putString("id", id)
    campaignId?.let { putString("campaignId", it) }
    putString(
        "format",
        when (format) {
            InAppFormat.MODAL -> "modal"
            InAppFormat.BANNER -> "banner"
            InAppFormat.FULLSCREEN -> "fullscreen"
            InAppFormat.INBOX_ONLY -> "inboxOnly"
        },
    )
    putBoolean("isTest", isTest)
    putString("title", title)
    putString("preview", preview)
    thumbnailUrl?.let { putString("thumbnailUrl", it) }
    putBoolean("isRead", isRead)
    putDouble("createdAtMillis", createdAt.toDouble())
    putString("design", design)
}
