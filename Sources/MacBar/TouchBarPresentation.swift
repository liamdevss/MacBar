import AppKit
import TouchBarBridge

@MainActor
protocol TouchBarPresenting {
    func present(_ bar: NSTouchBar, trayIdentifier: String?) -> Bool
    func dismiss(_ bar: NSTouchBar)
    func register(_ item: NSTouchBarItem) -> Bool
    func remove(_ item: NSTouchBarItem)
}

@MainActor
struct SystemTouchBarPresentation: TouchBarPresenting {
    func present(_ bar: NSTouchBar, trayIdentifier: String?) -> Bool {
        MBPresentTouchBar(bar, trayIdentifier)
    }
    func dismiss(_ bar: NSTouchBar) { MBDismissTouchBar(bar) }
    func register(_ item: NSTouchBarItem) -> Bool { MBRegisterControlStripItem(item) }
    func remove(_ item: NSTouchBarItem) { MBRemoveControlStripItem(item) }
}
