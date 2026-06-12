import Orion
import UIKit

private func showHighQualityPopUp() {
    PopUpHelper.showPopUp(
        message: "high_audio_quality_popup".localized,
        buttonText: "OK".uiKitLocalized
    )
}

class StreamQualitySettingsSectionHook: ClassHook<NSObject> {
    typealias Group = IOS14PremiumPatchingGroup
    static let targetName = "StreamQualitySettingsSection"

    func shouldResetSelection() -> Bool {
        showHighQualityPopUp()
        return true
    }
}

class ListRowInteractionListenerViewHook: ClassHook<UIView> {
    typealias Group = NonIOS14PremiumPatchingGroup
    static let targetName = "_TtC15Settings_ECMKit30ListRowInteractionListenerView"

    func performAction() {
        guard
            let accessibilityLabel = target.subviews.first?.accessibilityLabel,
            accessibilityLabel.hasSuffix("Premium")
        else {
            orig.performAction()
            return
        }
        
        showHighQualityPopUp()
    }
}

class ContentOffliningUIHelperImplementationHook: ClassHook<NSObject> {
    typealias Group = IOS14And15PremiumPatchingGroup
    static let targetName = "Offline_ContentOffliningUIImpl.ContentOffliningUIHelperImplementation"
    
    func downloadToggledWithCurrentAvailability(
        _ availability: NSInteger,
        addAction: NSObject,
        removeAction: NSObject,
        pageIdentifier: NSString,
        pageURI: NSURL
    ) {
        OfflineDownloadManager.shared.handleDownloadToggle(uri: pageURI as URL)
        orig.downloadToggledWithCurrentAvailability(
            availability,
            addAction: addAction,
            removeAction: removeAction,
            pageIdentifier: pageIdentifier,
            pageURI: pageURI
        )
    }
}

class ContentOffliningUIHelperImplementationModernHook: ClassHook<NSObject> {
    typealias Group = LatestPremiumPatchingGroup
    static let targetName = "Offline_ContentOffliningUIImpl.ContentOffliningUIHelperImplementation"
    
    func downloadToggledWithCurrentAvailability(
        _ availability: NSInteger,
        addAction: NSObject,
        removeAction: NSObject,
        pageIdentifier: NSString,
        pageURI: NSURL,
        interactionID: NSString
    ) {
        OfflineDownloadManager.shared.handleDownloadToggle(uri: pageURI as URL)
        orig.downloadToggledWithCurrentAvailability(
            availability,
            addAction: addAction,
            removeAction: removeAction,
            pageIdentifier: pageIdentifier,
            pageURI: pageURI,
            interactionID: interactionID
        )
    }
}
