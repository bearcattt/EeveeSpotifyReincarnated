// UpsellPopupBlocker.x.swift
// Blocks Spotify's premium upsell / "Like listening without limits?" popups
// by intercepting SPTEncorePopUpPresenter.presentPopUp(_:) and dropping any
// dialog whose title or description text matches known upsell patterns.

import Orion
import UIKit

struct UpsellPopupBlockerGroup: HookGroup {}

// Keywords found in upsell / upgrade popup titles and descriptions.
// Checked case-insensitively against both the dialog title and body text.
private let upsellKeywords: [String] = [
    "premium",
    "upgrade",
    "subscribe",
    "subscription",
    "listening without limits",
    "unlimited skips",
    "play the songs you love",
    "go premium",
    "like listening",
    "free account",
    "ad-free",
    "ad free",
    "try free",
    "get premium",
    "start premium",
    "learn more",         // CTA text on the popup in the screenshot
    "upsell",
    "paywall",
    "free tier",
    "limited listening",
]

private func isUpsellText(_ text: String?) -> Bool {
    guard let text = text else { return false }
    let lower = text.lowercased()
    return upsellKeywords.contains { lower.contains($0) }
}

class SPTEncorePopUpPresenterHook: ClassHook<NSObject> {
    typealias Group = UpsellPopupBlockerGroup
    static let targetName = "SPTEncorePopUpPresenter"

    func presentPopUp(_ popUp: NSObject) {
        // Try to read the dialog model to inspect its text.
        // SPTEncorePopUpDialog has a `model` property that is an SPTEncorePopUpDialogModel.
        // SPTEncorePopUpDialogModel has `title` and `descriptionText` / `body`.
        //
        // We access them through Dynamic / KVC to stay resilient across Spotify versions.
        let mirror = Dynamic(popUp)

        // Pull title and description from the model if available
        let modelObj = mirror.model.asObject
        let titleFromModel   = (modelObj?.value(forKey: "title") as? String)
                            ?? (modelObj?.value(forKey: "dialogTitle") as? String)
        let descFromModel    = (modelObj?.value(forKey: "descriptionText") as? String)
                            ?? (modelObj?.value(forKey: "body") as? String)
                            ?? (modelObj?.value(forKey: "subtitle") as? String)

        // Fallback: try reading directly off the popUp object
        let titleDirect = (popUp.value(forKey: "title") as? String)
                       ?? (popUp.value(forKey: "dialogTitle") as? String)
        let descDirect  = (popUp.value(forKey: "descriptionText") as? String)
                       ?? (popUp.value(forKey: "body") as? String)

        let title = titleFromModel ?? titleDirect
        let desc  = descFromModel  ?? descDirect

        if isUpsellText(title) || isUpsellText(desc) {
            NSLog("[EeveeSpotify][UpsellBlock] Blocked popup — title=%@ desc=%@",
                  title ?? "(nil)", desc ?? "(nil)")
            return  // swallow the call; popup never appears
        }

        // Not an upsell popup — let it through normally (e.g. EeveeSpotify's own popups)
        orig.presentPopUp(popUp)
    }
}

func activateUpsellPopupBlocker() {
    guard NSClassFromString("SPTEncorePopUpPresenter") != nil else {
        NSLog("[EeveeSpotify][UpsellBlock] SPTEncorePopUpPresenter not found; skipping")
        return
    }
    UpsellPopupBlockerGroup().activate()
    NSLog("[EeveeSpotify][UpsellBlock] UpsellPopupBlockerGroup activated")
}
