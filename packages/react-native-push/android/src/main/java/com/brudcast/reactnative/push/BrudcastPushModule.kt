package com.brudcast.reactnative.push

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.brudcast.sdk.push.BrudcastAsyncNotificationHandler
import com.brudcast.sdk.push.BrudcastNotificationDecision
import com.brudcast.sdk.push.BrudcastPushNotification
import com.brudcast.sdk.push.BrudcastPushPermission
import com.brudcast.sdk.push.PushModule
import com.facebook.react.bridge.ActivityEventListener
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.CxxCallbackImpl
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableMap
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch

/**
 * The Brudcast push TurboModule: forwards JavaScript calls to the native push module, routes the
 * notification handler and the permission status to JavaScript, and passes notification taps on a
 * running activity to the SDK. React Native creates one per JavaScript runtime. Every call is
 * moved to the main thread.
 *
 * @param reactContext The React Native context.
 */
public class BrudcastPushModule(reactContext: ReactApplicationContext) :
    NativeBrudcastPushSpec(reactContext), ActivityEventListener {
    private val pending = HashMap<String, (BrudcastNotificationDecision) -> Unit>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    init {
        reactContext.addActivityEventListener(this)
    }

    /**
     * Starts following the permission status once React Native has attached the event emitter,
     * since an event sent before then has nowhere to go.
     *
     * @param eventEmitterCallback The emitter React Native attaches.
     */
    override fun setEventEmitterCallback(eventEmitterCallback: CxxCallbackImpl) {
        super.setEventEmitterCallback(eventEmitterCallback)
        scope.launch { PushModule.permissionStatus.drop(1).collect { emitOnPermissionChange(it.name()) } }
    }

    override fun invalidate() {
        reactApplicationContext.removeActivityEventListener(this)
        scope.cancel()
        main.post {
            clearNotificationHandler()
            val waiting = pending.values.toList()
            pending.clear()
            waiting.forEach { it(BrudcastNotificationDecision.SHOW) }
        }
        super.invalidate()
    }

    override fun onNewIntent(intent: Intent) {
        PushModule.handleIntent(intent)
    }

    override fun onActivityResult(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?) {}

    override fun setToken(token: String) {
        main.post { PushModule.setToken(token) }
    }

    override fun requestPermission(provisional: Boolean, promise: Promise) {
        main.post {
            val activity = reactApplicationContext.currentActivity ?: return@post promise.resolve(PushModule.permissionStatus.value.name())
            PushModule.requestPermission(activity) { granted ->
                promise.resolve(if (granted) "authorized" else "denied")
            }
        }
    }

    override fun getPermissionStatus(promise: Promise) {
        main.post { promise.resolve(PushModule.permissionStatus.value.name()) }
    }

    override fun setNotificationHandlerEnabled(enabled: Boolean) {
        main.post {
            if (!enabled) return@post clearNotificationHandler()
            handlerOwner = this
            PushModule.setAsyncNotificationHandler(BrudcastAsyncNotificationHandler { notification, decide ->
                val owner = handlerOwner ?: return@BrudcastAsyncNotificationHandler decide(BrudcastNotificationDecision.SHOW)
                val requestId = UUID.randomUUID().toString()
                owner.pending[requestId] = decide
                owner.emitOnNotificationRequest(Arguments.createMap().apply {
                    putString("requestId", requestId)
                    putMap("notification", notification.toMap())
                })
            })
        }
    }

    override fun resolveNotification(requestId: String, decision: String) {
        main.post {
            pending.remove(requestId)?.invoke(if (decision == "suppress") BrudcastNotificationDecision.SUPPRESS else BrudcastNotificationDecision.SHOW)
        }
    }

    override fun handleForegroundMessage(data: ReadableMap, title: String?, body: String?, imageUrl: String?, promise: Promise) {
        val strings = data.toHashMap().mapNotNull { (key, value) -> value?.let { key to it.toString() } }.toMap()
        main.post {
            val notification = BrudcastPushNotification.from(strings, title, body, imageUrl) ?: return@post promise.resolve(false)
            promise.resolve(PushModule.onMessageReceived(reactApplicationContext.applicationContext, notification))
        }
    }

    private fun clearNotificationHandler() {
        if (handlerOwner !== this) return
        handlerOwner = null
        PushModule.setAsyncNotificationHandler(null)
    }

    private companion object {
        val main = Handler(Looper.getMainLooper())

        /** The runtime whose JavaScript set the notification handler, so an old runtime cannot answer. */
        @Volatile
        var handlerOwner: BrudcastPushModule? = null
    }
}

private fun BrudcastPushPermission.name(): String = when (this) {
    BrudcastPushPermission.NOT_DETERMINED -> "notDetermined"
    BrudcastPushPermission.DENIED -> "denied"
    BrudcastPushPermission.AUTHORIZED -> "authorized"
}

private fun BrudcastPushNotification.toMap(): WritableMap = Arguments.createMap().apply {
    putString("messageId", messageId)
    campaignId?.let { putString("campaignId", it) }
    applicationId?.let { putString("applicationId", it) }
    title?.let { putString("title", it) }
    body?.let { putString("body", it) }
    imageUrl?.let { putString("imageUrl", it) }
    clickUrl?.let { putString("clickUrl", it) }
    putMap("data", Arguments.createMap().apply { data.forEach { (key, value) -> putString(key, value) } })
}
