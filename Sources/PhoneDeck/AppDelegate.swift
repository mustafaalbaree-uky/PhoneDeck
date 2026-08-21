import AppKit
import SwiftUI
import Combine
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register for launch at login by default — the whole point is that
        // plugging in the phone works without having opened PhoneDeck first.
        // The menu still has a toggle in case that's ever unwanted.
        if !LoginItem.isEnabled {
            LoginItem.setEnabled(true)
        }

        UNUserNotificationCenter.current().delegate = self
        NotificationManager.requestAuthorization()
        NotificationManager.registerCategories()

        state.refresh()
        state.deviceMonitor.start()
        state.startAutoReinstallLoop()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(connected: false)
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: RootView(state: state, monitor: state.deviceMonitor)
        )

        state.deviceMonitor.$connected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.updateIcon(connected: connected)
            }
            .store(in: &cancellables)

        // Surface the popover the moment a phone shows up, so plugging in
        // really does mean "everything you need to know" without a click.
        state.deviceMonitor.didConnect
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.state.refresh()
                self?.showPopover()
                // Don't wait out the rest of the minute-long poll: a phone
                // that appears for two minutes should still get its renewal
                // announced immediately.
                self?.state.evaluateAuto()
            }
            .store(in: &cancellables)
    }

    private func updateIcon(connected: Bool) {
        let symbolName = connected ? "iphone.gen3" : "iphone.slash"
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: connected ? "iPhone connected" : "No iPhone connected"
        )
    }

    @objc private func statusItemClicked() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        if isRightClick {
            showMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            state.refresh()
            showPopover()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(loginItem)

        // The redesign's undo button. Both looks are in the binary and share
        // the same AppState, so this swaps the popover's contents in place.
        let lookItem = NSMenuItem(
            title: "Use the Classic Look",
            action: #selector(toggleClassicLook),
            keyEquivalent: ""
        )
        lookItem.target = self
        lookItem.state = LookSettings.useClassic ? .on : .off
        menu.addItem(lookItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit PhoneDeck", action: #selector(quit), keyEquivalent: "q"))
        menu.items.last?.target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // back to popover behavior on the next plain click
    }

    @objc private func toggleClassicLook() {
        LookSettings.useClassic.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        // AppKit parks the popover well below the status item on this Mac,
        // leaving a big gap between the icon and the arrow. Pin the top of
        // the popover window to the bottom of the icon ourselves.
        if let popWindow = popover.contentViewController?.view.window,
           let buttonWindow = button.window {
            let buttonOnScreen = buttonWindow.convertToScreen(
                button.convert(button.bounds, to: nil)
            )
            var frame = popWindow.frame
            let drop = frame.maxY - buttonOnScreen.minY
            if abs(drop) > 1 {
                frame.origin.y -= drop
                popWindow.setFrame(frame, display: true)
            }
        }

        if eventMonitor == nil {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.popover.performClose(nil)
            }
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // PhoneDeck has no windows worth foregrounding, so still show the
    // banner even while it's the frontmost app when a notification fires.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// The two buttons on the "about to reinstall" banner. Tapping the body
    /// of the banner (`defaultActionIdentifier`) opens the popover instead,
    /// which is where the countdown and its Cancel button live.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        Task { @MainActor in
            switch action {
            case NotificationManager.actionInstallNow:
                self.state.runPendingAutoNow()
            case NotificationManager.actionSkip:
                self.state.cancelPendingAuto(snooze: true)
            case UNNotificationDefaultActionIdentifier:
                self.state.refresh()
                self.showPopover()
            default:
                break
            }
            completionHandler()
        }
    }
}
