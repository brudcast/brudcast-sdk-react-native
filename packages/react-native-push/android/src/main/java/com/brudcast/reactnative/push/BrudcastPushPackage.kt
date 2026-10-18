package com.brudcast.reactnative.push

import com.brudcast.reactnative.BrudcastModuleRegistry
import com.brudcast.sdk.push.PushModule
import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider

/**
 * Provides the push TurboModule, and registers the native push module with the core package.
 * Autolinking creates it before JavaScript runs.
 */
public class BrudcastPushPackage : BaseReactPackage() {
    init {
        BrudcastModuleRegistry.register(PushModule)
    }

    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? =
        if (name == NativeBrudcastPushSpec.NAME) BrudcastPushModule(reactContext) else null

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider = ReactModuleInfoProvider {
        mapOf(
            NativeBrudcastPushSpec.NAME to ReactModuleInfo(
                name = NativeBrudcastPushSpec.NAME,
                className = NativeBrudcastPushSpec.NAME,
                canOverrideExistingModule = false,
                needsEagerInit = true,
                isCxxModule = false,
                isTurboModule = true,
            ),
        )
    }
}
