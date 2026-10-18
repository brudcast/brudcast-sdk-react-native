import Foundation

/// The native modules the installed Brudcast packages provide. `@brudcast/react-native-in-app` and
/// `@brudcast/react-native-push` register theirs when their pods load, before JavaScript runs, so the
/// registry is complete by the time JavaScript calls `initialize`.
public enum RNBrudcastModuleRegistry {
    private static let lock = NSLock()
    private static var modules: [String: BrudcastModule] = [:]

    /// Registers a module under the name JavaScript uses for it.
    ///
    /// - Parameter module: The module; its `name` is the key.
    public static func register(_ module: BrudcastModule) {
        lock.lock()
        defer { lock.unlock() }
        modules[module.name] = module
    }

    /// Finds the modules JavaScript listed, logging each one whose package is not installed.
    ///
    /// - Parameter names: The module names, such as `in_app` and `push`.
    /// - Returns: The modules found, in the order given.
    static func resolve(_ names: [String]) -> [BrudcastModule] {
        lock.lock()
        let installed = modules
        lock.unlock()
        var seen: Set<String> = []
        return names.compactMap { name in
            guard seen.insert(name).inserted else { return nil }
            guard let module = installed[name] else {
                BrudcastLogger.shared.error("The \(name) module was listed, but its package is not installed; add \(packageName(for: name)) and run pod install")
                return nil
            }
            return module
        }
    }

    private static func packageName(for name: String) -> String {
        switch name {
        case "in_app": return "@brudcast/react-native-in-app"
        case "push": return "@brudcast/react-native-push"
        default: return "the package for \(name)"
        }
    }
}
