package com.brudcast.reactnative

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.brudcast.sdk.Brudcast
import com.brudcast.sdk.BrudcastAction
import com.brudcast.sdk.BrudcastActionResult
import com.brudcast.sdk.BrudcastAppearance
import com.brudcast.sdk.BrudcastEnvironment
import com.brudcast.sdk.BrudcastLogLevel
import com.brudcast.sdk.BrudcastLogger
import com.brudcast.sdk.BrudcastOptions
import com.brudcast.sdk.BrudcastSdk
import com.brudcast.sdk.BrudcastTraits
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.LifecycleEventListener
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableMap
import java.util.UUID

/**
 * The core Brudcast TurboModule: forwards JavaScript calls to the native SDK, and the native SDK's
 * actions to the JavaScript action handler. React Native creates one per JavaScript runtime. Every
 * call is moved to the main thread, where the native SDK and the action router expect it.
 *
 * @param reactContext The React Native context.
 */
public class BrudcastReactNativeModule(reactContext: ReactApplicationContext) :
    NativeBrudcastSpec(reactContext), ActionRouter.Target, LifecycleEventListener {
    private val pending = HashMap<String, (BrudcastActionResult) -> Unit>()
    private var waitingForActivity = false

    init {
        main.post { router.moduleCreated() }
    }

    override fun invalidate() {
        main.post {
            router.clearTarget(this)
            val waiting = pending.values.toList()
            pending.clear()
            waiting.forEach { it(BrudcastActionResult.USE_DEFAULT) }
        }
        reactApplicationContext.removeLifecycleEventListener(this)
        super.invalidate()
    }

    override fun initialize(publishableKey: String, options: ReadableMap) {
        main.post {
            BrudcastSdk.setWrapper("ReactNative", options.getString("wrapperVersion") ?: "unknown")
            Brudcast.initialize(reactApplicationContext.applicationContext, publishableKey, options.toNative())
            attachCurrentActivity()
        }
    }

    override fun identify(externalId: String, userHash: String?, traits: ReadableMap) {
        main.post { Brudcast.identify(externalId, userHash, traits.toTraits()) }
    }

    override fun reset() {
        main.post { Brudcast.reset() }
    }

    override fun track(name: String, properties: ReadableMap) {
        val values = properties.toHashMap()
        main.post { Brudcast.track(name, values) }
    }

    override fun screen(name: String, properties: ReadableMap) {
        val values = properties.toHashMap()
        main.post { Brudcast.screen(name, values) }
    }

    override fun setOptedOut(optedOut: Boolean) {
        main.post { if (optedOut) Brudcast.optOut() else Brudcast.optIn() }
    }

    override fun setTrackingEnabled(enabled: Boolean) {
        main.post { if (enabled) Brudcast.enableTracking() else Brudcast.disableTracking() }
    }

    override fun flush() {
        main.post { Brudcast.flush() }
    }

    override fun setActionHandlerEnabled(enabled: Boolean) {
        main.post { if (enabled) router.setTarget(this) else router.clearTarget(this) }
    }

    override fun resolveAction(requestId: String, result: String) {
        main.post {
            pending.remove(requestId)?.invoke(if (result == "handled") BrudcastActionResult.HANDLED else BrudcastActionResult.USE_DEFAULT)
        }
    }

    override fun getDeviceId(promise: Promise) {
        main.post { promise.resolve(Brudcast.deviceId) }
    }

    override fun handle(action: BrudcastAction, decide: (BrudcastActionResult) -> Unit) {
        val requestId = UUID.randomUUID().toString()
        pending[requestId] = decide
        emitOnActionRequest(action.toRequest(requestId))
    }

    override fun onHostResume() {
        if (!waitingForActivity) return
        attachCurrentActivity()
    }

    override fun onHostPause() {}

    override fun onHostDestroy() {}

    /**
     * Gives the SDK the activity on screen, which JavaScript's late `initialize` missed, so in-app
     * messages can show and the launching push tap is read. With no activity yet, it waits for the
     * next resume.
     */
    private fun attachCurrentActivity() {
        val activity = reactApplicationContext.currentActivity
        if (activity == null) {
            if (!waitingForActivity) {
                waitingForActivity = true
                reactApplicationContext.addLifecycleEventListener(this)
            }
            return
        }
        if (waitingForActivity) {
            waitingForActivity = false
            reactApplicationContext.removeLifecycleEventListener(this)
        }
        Brudcast.attachActivity(activity)
    }

    public companion object {
        /** The module's name in JavaScript. */
        public const val NAME: String = NativeBrudcastSpec.NAME

        private val main = Handler(Looper.getMainLooper())

        private val router = ActionRouter(
            clock = SystemClock::uptimeMillis,
            schedule = { delay, task -> main.postDelayed(task, delay) },
            install = Brudcast::setAsyncActionHandler,
            performDefault = Brudcast::performDefaultAction,
        )
    }
}

private fun ReadableMap.string(key: String): String? = if (hasKey(key) && !isNull(key)) getString(key) else null

private fun ReadableMap.toNative(): BrudcastOptions = BrudcastOptions(
    environment = (if (hasKey("environment")) getMap("environment") else null).toEnvironment(),
    logLevel = when (string("logLevel")) {
        "verbose" -> BrudcastLogLevel.VERBOSE
        "debug" -> BrudcastLogLevel.DEBUG
        "info" -> BrudcastLogLevel.INFO
        "error" -> BrudcastLogLevel.ERROR
        "none" -> BrudcastLogLevel.NONE
        else -> BrudcastLogLevel.WARNING
    },
    appearance = when (string("appearance")) {
        "light" -> BrudcastAppearance.LIGHT
        "dark" -> BrudcastAppearance.DARK
        else -> BrudcastAppearance.SYSTEM
    },
    modules = BrudcastModuleRegistry.resolve(
        if (hasKey("modules")) getArray("modules")?.toArrayList()?.filterIsInstance<String>().orEmpty() else emptyList()
    ),
    accentColor = if (hasKey("accentColor") && !isNull("accentColor")) getDouble("accentColor").toLong().toInt() else null,
)

private fun ReadableMap?.toEnvironment(): BrudcastEnvironment = when (this?.string("kind")) {
    "staging" -> BrudcastEnvironment.Staging
    "uat" -> BrudcastEnvironment.Uat
    "development" -> BrudcastEnvironment.Development
    "local" -> BrudcastEnvironment.Local(
        string("androidHost") ?: "10.0.2.2",
        if (hasKey("port") && !isNull("port")) getDouble("port").toInt() else 8191,
    )
    "custom" -> string("baseUrl")?.let { BrudcastEnvironment.Custom(it) } ?: run {
        BrudcastLogger.error("A custom environment needs a base URL; using production")
        BrudcastEnvironment.Production
    }
    else -> BrudcastEnvironment.Production
}

private fun ReadableMap.toTraits(): BrudcastTraits? {
    val traits = BrudcastTraits(string("email"), string("phone"), string("firstName"), string("lastName"), string("language"), string("timezone"))
    return if (listOf(traits.email, traits.phone, traits.firstName, traits.lastName, traits.language, traits.timezone).all { it == null }) null else traits
}

private fun BrudcastAction.toRequest(requestId: String): WritableMap = Arguments.createMap().apply {
    putString("requestId", requestId)
    putString(
        "kind",
        when (kind) {
            BrudcastAction.Kind.DEEPLINK -> "deeplink"
            BrudcastAction.Kind.URL -> "url"
            BrudcastAction.Kind.CUSTOM_EVENT -> "customEvent"
        },
    )
    putString("value", value)
    putBoolean("opensInApp", opensInApp)
    putBoolean("verified", verified)
    when (val origin = source) {
        is BrudcastAction.Source.InApp -> {
            putString("source", "inApp")
            putString("messageId", origin.messageId)
            origin.buttonId?.let { putString("buttonId", it) }
        }
        is BrudcastAction.Source.Push -> {
            putString("source", "push")
            putString("messageId", origin.messageId)
        }
    }
}
