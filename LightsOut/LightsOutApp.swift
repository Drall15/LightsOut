import SwiftUI
import AppKit
import Sparkle

@main
struct LightsOutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var eventMonitor: Any?
    let displaysViewModel = DisplaysViewModel()
    var updateController: SPUStandardUpdaterController!
    var contextMenuManager: ContextMenuManager!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        print("🚀 [DEBUG] LightsOut app launching...")
        #endif
        
        popover = NSPopover()
        popover.behavior = .applicationDefined
        
        // Set up the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(named: "menubarIcon")
            #if DEBUG
            print("🖼️ [DEBUG] Loading menubar icon: \(image != nil ? "success" : "FAILED - image is nil")")
            #endif
            button.image = image
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            #if DEBUG
            print("✅ [DEBUG] Status bar item configured successfully")
            #endif
        } else {
            #if DEBUG
            print("❌ [DEBUG] Failed to get status item button!")
            #endif
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.popover.isShown == true {
                self?.popover.performClose(nil)
            }
        }
        
        updateController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        
//        #if !DEBUG
        if updateController.updater.automaticallyChecksForUpdates {
            updateController.updater.checkForUpdatesInBackground()
        }
//        #endif
        
        contextMenuManager = ContextMenuManager(updateController: updateController.updater, statusItem: statusItem)
        
        #if DEBUG
        print("✅ [DEBUG] App launch complete. Displays loaded: \(displaysViewModel.displays.count)")
        for display in displaysViewModel.displays {
            print("   📺 \(display.name) (ID: \(display.id)) - State: \(display.state) - Primary: \(display.isPrimary)")
        }
        #endif
    }

    @objc func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            contextMenuManager.showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    func togglePopover(_ sender: NSStatusBarButton) {
        #if DEBUG
        print("🔘 [DEBUG] Toggle popover - currently \(popover.isShown ? "shown" : "hidden")")
        #endif
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            let contentView = MenuBarView().environmentObject(displaysViewModel)
            popover.contentViewController = NSHostingController(rootView: contentView)

            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                
                // Ensure the app and popover window become active
                NSApp.activate(ignoringOtherApps: true)
                popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
                popover.contentViewController?.view.window?.makeFirstResponder(popover.contentViewController?.view)
            }
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(DisplaysViewModel())
}
