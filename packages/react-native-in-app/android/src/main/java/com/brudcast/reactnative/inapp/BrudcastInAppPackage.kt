package com.brudcast.reactnative.inapp

import com.brudcast.reactnative.BrudcastModuleRegistry
import com.brudcast.sdk.inapp.InAppModule
import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.facebook.react.uimanager.ViewManager

/**
 * Provides the in-app TurboModule and the inbox message view, and registers the native in-app
 * module with the core package. Autolinking creates it before JavaScript runs.
 */
public class BrudcastInAppPackage : BaseReactPackage() {
    init {
        BrudcastModuleRegistry.register(InAppModule)
    }

    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? =
        if (name == NativeBrudcastInAppSpec.NAME) BrudcastInAppModule(reactContext) else null

    override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> =
        listOf(BrudcastInboxMessageViewManager())

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider = ReactModuleInfoProvider {
        mapOf(
            NativeBrudcastInAppSpec.NAME to ReactModuleInfo(
                name = NativeBrudcastInAppSpec.NAME,
                className = NativeBrudcastInAppSpec.NAME,
                canOverrideExistingModule = false,
                needsEagerInit = false,
                isCxxModule = false,
                isTurboModule = true,
            ),
        )
    }
}
