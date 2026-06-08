import Orion
import Foundation
import ObjectiveC.runtime

// Fix for Issue #16: CarPlay launching can crash inside CarPlay.framework
// at -[CPInterfaceController clientAssistantCellUnavailableWithError:].
//
// In sideloaded/resigned Spotify builds, CarPlay sometimes reports an internal
// error via this private callback and CarPlay.framework raises an NSException,
// which terminates the app.
//
// We hook the callback and swallow it (no-op) so Spotify stays alive.
// This trades a crash for a non-fatal CarPlay-unavailable state.

struct CarPlayCrashFixGroup: HookGroup {}

final class CPInterfaceControllerCarPlayCrashFixHook: ClassHook<NSObject> {
    typealias Group = CarPlayCrashFixGroup
    static let targetName = "CPInterfaceController"

    // Private API selector (observed in crash log)
    @objc(clientAssistantCellUnavailableWithError:)
    func clientAssistantCellUnavailableWithError(_ error: Any?) {
        // Intentionally do NOT call orig — on affected OS versions this path
        // can raise an exception and crash the entire process.
        writeDebugLog("[CarPlayFix] Swallowed clientAssistantCellUnavailableWithError: \(String(describing: error))")
    }
}

func activateCarPlayCrashFix() {
    guard let cls = NSClassFromString("CPInterfaceController") else {
        writeDebugLog("[CarPlayFix] Skipped (CPInterfaceController missing)")
        return
    }

    let sel = Selector(("clientAssistantCellUnavailableWithError:"))
    guard class_getInstanceMethod(cls, sel) != nil else {
        writeDebugLog("[CarPlayFix] Skipped (selector missing)")
        return
    }

    CarPlayCrashFixGroup().activate()
    writeDebugLog("[CarPlayFix] Activated")
}
