package com.brudcast.reactnative

import com.brudcast.sdk.BrudcastLogger
import com.brudcast.sdk.BrudcastModule
import java.util.concurrent.ConcurrentHashMap

/**
 * The native modules the installed Brudcast packages provide. `@brudcast/react-native-in-app` and
 * `@brudcast/react-native-push` register theirs when autolinking creates their packages, before
 * JavaScript runs, so the registry is complete by the time JavaScript calls `initialize`.
 */
public object BrudcastModuleRegistry {
    private val modules = ConcurrentHashMap<String, BrudcastModule>()

    /**
     * Registers a module under the name JavaScript uses for it.
     *
     * @param module The module; its [BrudcastModule.name] is the key.
     */
    @JvmStatic
    public fun register(module: BrudcastModule) {
        modules[module.name] = module
    }

    /**
     * Finds the modules JavaScript listed, logging each one whose package is not installed.
     *
     * @param names The module names, such as `in_app` and `push`.
     * @return The modules found, in the order given.
     */
    internal fun resolve(names: List<String>): List<BrudcastModule> = names.distinct().mapNotNull { name ->
        modules[name] ?: run {
            BrudcastLogger.error("The $name module was listed, but its package is not installed; add ${packageFor(name)} to package.json")
            null
        }
    }

    private fun packageFor(name: String): String = when (name) {
        "in_app" -> "@brudcast/react-native-in-app"
        "push" -> "@brudcast/react-native-push"
        else -> "the package for $name"
    }
}
