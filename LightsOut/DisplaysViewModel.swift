//
//  DisplaysViewModel.swift
//  BlackoutTest

import CoreGraphics
import SwiftUI

@_silgen_name("CGSConfigureDisplayEnabled")
func CGSConfigureDisplayEnabled(_ cid: CGDisplayConfigRef, _ display: UInt32, _ enabled: Bool) -> Int

class DisplaysViewModel: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    private var gammaService = GammaUpdateService()
    private var arrengementCache = DisplayArrangementCacheService()
    
    // Auto-restore configuration
    private let autoRestoreDelay: TimeInterval = 3.0 // seconds - configurable
    private var autoRestoreWorkItem: DispatchWorkItem?
    private var wasAutoRestored: Bool = false // Track if built-in was auto-restored
    
    // Helper for timestamped debug logging
    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
    
    // Persistent storage for built-in display ID
    private let builtInDisplayIDKey = "LightsOut.BuiltInDisplayID"
    private var savedBuiltInDisplayID: CGDirectDisplayID? {
        get {
            let id = UserDefaults.standard.integer(forKey: builtInDisplayIDKey)
            return id > 0 ? CGDirectDisplayID(id) : nil
        }
        set {
            if let id = newValue {
                UserDefaults.standard.set(Int(id), forKey: builtInDisplayIDKey)
            }
        }
    }
    
    init() {
        fetchDisplays()
        registerDisplayReconfigurationCallback()
    }
    
    deinit {
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
        autoRestoreWorkItem?.cancel()
    }
    
    // MARK: - Display Configuration Monitoring
    
    private func registerDisplayReconfigurationCallback() {
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
    }
    
    /// Built-in (internal) display if available
    private var builtInDisplay: DisplayInfo? {
        return displays.first { CGDisplayIsBuiltin($0.id) != 0 }
    }
    
    /// Check if the built-in display is the only display and is currently disabled
    private func shouldAutoRestoreBuiltInDisplay() -> Bool {
        // Get all active physical displays from the system
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &activeDisplays, &displayCount)
        
        // Check if we have a built-in display in our tracked list that is disabled
        guard let builtIn = builtInDisplay else {
            return false
        }
        
        guard builtIn.state.isOff() else {
            return false
        }
        
        // Check if there are NO active external displays
        // Note: When external displays are unplugged with internal disabled, macOS may create
        // a temporary "headless" display. We need to detect this scenario.
        let externalDisplays = activeDisplays.filter { displayID in
            CGDisplayIsBuiltin(displayID) == 0
        }
        
        // Check if any external displays are KNOWN/PHYSICAL (not headless/temporary)
        // A headless display will not be in our tracked displays list with a real name
        let hasPhysicalExternalDisplay = externalDisplays.contains { displayID in
            // Check if this display is in our tracked list with a non-empty name
            if let trackedDisplay = displays.first(where: { $0.id == displayID }) {
                return trackedDisplay.state == .active && !trackedDisplay.name.isEmpty && trackedDisplay.name != "Display \(displayID)"
            }
            return false
        }
        
        guard !hasPhysicalExternalDisplay else {
            return false
        }
        
        return true
    }
    
    /// Auto-disable built-in display if it was auto-restored and external displays are now available
    private func autoDisableBuiltInIfNeeded() {
        guard wasAutoRestored,
              let builtIn = builtInDisplay,
              builtIn.state == .active else {
            return
        }
        
        // Check if we now have physical external displays
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &activeDisplays, &displayCount)
        
        let hasPhysicalExternalDisplay = activeDisplays.contains { displayID in
            guard CGDisplayIsBuiltin(displayID) == 0 else { return false }
            
            if let trackedDisplay = displays.first(where: { $0.id == displayID }) {
                return trackedDisplay.state == .active && !trackedDisplay.name.isEmpty && trackedDisplay.name != "Display \(displayID)"
            }
            return false
        }
        
        guard hasPhysicalExternalDisplay else {
            return
        }
        
        print("[\(timestamp())] Auto-disabling built-in display (external display reconnected)...")
        
        do {
            try disconnectDisplay(display: builtIn)
            wasAutoRestored = false
            print("[\(timestamp())] ✅ Successfully auto-disabled built-in display.")
        } catch {
            print("[\(timestamp())] ❌ Failed to auto-disable built-in display: \(error)")
        }
    }
    
    /// Schedule auto-restore of built-in display after the configured delay
    private func scheduleAutoRestoreIfNeeded() {
        // Cancel any existing scheduled restore
        autoRestoreWorkItem?.cancel()
        
        guard shouldAutoRestoreBuiltInDisplay() else {
            return
        }
        
        #if DEBUG
        print("[\(timestamp())] ⏰ [DEBUG] Scheduling auto-restore of built-in display in \(autoRestoreDelay) seconds...")
        #endif
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            #if DEBUG
            let ts = self.timestamp()
            print("[\(ts)] ⏰ [DEBUG] Timer fired! Re-checking auto-restore conditions...")
            #endif
            
            // Re-check conditions before restoring
            guard self.shouldAutoRestoreBuiltInDisplay(),
                  let builtIn = self.builtInDisplay else {
                #if DEBUG
                print("[\(self.timestamp())] ⏰ [DEBUG] Auto-restore conditions no longer met, cancelling.")
                #endif
                return
            }
            
            print("[\(self.timestamp())] Auto-restoring built-in display '\(builtIn.name)'...")
            do {
                try self.turnOnDisplay(display: builtIn)
                self.wasAutoRestored = true
                print("[\(self.timestamp())] ✅ Successfully auto-restored built-in display.")
            } catch {
                print("[\(self.timestamp())] ❌ Failed to auto-restore built-in display: \(error)")
            }
        }
        
        autoRestoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autoRestoreDelay, execute: workItem)
    }
    
    /// Called when display configuration changes
    fileprivate func handleDisplayReconfiguration(display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        // Only respond after the reconfiguration is complete (not during begin)
        guard !flags.contains(.beginConfigurationFlag) else { return }
        
        if flags.contains(.removeFlag) {
            DispatchQueue.main.async { [weak self] in
                self?.fetchDisplays()
                self?.scheduleAutoRestoreIfNeeded()
            }
        } else if flags.contains(.addFlag) {
            // If a display is added, cancel any pending auto-restore
            autoRestoreWorkItem?.cancel()
            autoRestoreWorkItem = nil
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.fetchDisplays()
                
                // If the built-in was auto-restored and we just added an external display, disable the built-in again
                if self.wasAutoRestored {
                    self.autoDisableBuiltInIfNeeded()
                }
            }
        } else {
            // For other configuration changes, update displays and check auto-restore
            DispatchQueue.main.async { [weak self] in
                self?.fetchDisplays()
                self?.scheduleAutoRestoreIfNeeded()
            }
        }
    }
    
    func fetchDisplays() {
        #if DEBUG
        print("📺 [DEBUG] Fetching displays...")
        #endif
        
        // Get active displays
        var activeCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &activeCount)
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(activeCount))
        CGGetActiveDisplayList(activeCount, &activeDisplays, &activeCount)
        let activeSet = Set(activeDisplays)
        
        #if DEBUG
        print("📺 [DEBUG] Active displays count: \(activeCount)")
        for id in activeDisplays {
            print("   - Active ID: \(id) (Built-in: \(CGDisplayIsBuiltin(id) != 0))")
        }
        #endif
        
        // Get all online displays (includes disabled ones)
        var onlineCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &onlineCount)
        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: Int(onlineCount))
        CGGetOnlineDisplayList(onlineCount, &onlineDisplays, &onlineCount)
        
        #if DEBUG
        print("📺 [DEBUG] Online displays count: \(onlineCount)")
        for id in onlineDisplays {
            print("   - Online ID: \(id) (Built-in: \(CGDisplayIsBuiltin(id) != 0), Active: \(activeSet.contains(id)))")
        }
        #endif
        
        var new_displays: Set<DisplayInfo> = Set()
        
        let primaryDisplayID = CGMainDisplayID()
        
        // Add all online displays, marking inactive ones as disconnected
        for displayID in onlineDisplays {
            let isActive = activeSet.contains(displayID)
            var displayName = "Display \(displayID)"
            
            if isActive, let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) {
                displayName = screen.localizedName
            } else if CGDisplayIsBuiltin(displayID) != 0 {
                displayName = "Built-in Display"
            }
            
            let state: DisplayState = isActive ? .active : .disconnected
            
            // Save built-in display ID for persistence
            if CGDisplayIsBuiltin(displayID) != 0 {
                savedBuiltInDisplayID = displayID
            }
            
            new_displays.insert(DisplayInfo(
                id: displayID,
                name: displayName,
                state: state,
                isPrimary: isActive && displayID == primaryDisplayID
            ))
        }
        
        // If we have a saved built-in display ID and it's not in the list, add it as disconnected
        // This handles the case where the display was disabled and the app was restarted
        if let builtInID = savedBuiltInDisplayID,
           !new_displays.contains(where: { $0.id == builtInID }) {
            #if DEBUG
            print("📺 [DEBUG] Restoring previously saved built-in display ID: \(builtInID)")
            #endif
            new_displays.insert(DisplayInfo(
                id: builtInID,
                name: "Built-in Retina Display",
                state: .disconnected,
                isPrimary: false
            ))
        }
        
        // Fallback: If no built-in display found yet, actively search for one
        // MacBooks always have a built-in display even if it's disabled
        if !new_displays.contains(where: { CGDisplayIsBuiltin($0.id) != 0 }) {
            #if DEBUG
            print("📺 [DEBUG] No built-in display detected, searching for it...")
            #endif
            
            // Try display IDs 1-10 (built-in is typically ID 1 but could vary)
            for testID in 1...10 {
                let displayID = CGDirectDisplayID(testID)
                if CGDisplayIsBuiltin(displayID) != 0 {
                    #if DEBUG
                    print("📺 [DEBUG] Found built-in display with ID: \(displayID)")
                    #endif
                    savedBuiltInDisplayID = displayID
                    new_displays.insert(DisplayInfo(
                        id: displayID,
                        name: "Built-in Retina Display",
                        state: .disconnected,
                        isPrimary: false
                    ))
                    break
                }
            }
        }
        
        // Ensuring the off/pending/disconnected displays are not "deleted" - manually adding them to the new list.
        // This handles mirrored displays, displays in pending state, and disconnected displays
        for display in displays {
            if display.state == .mirrored || display.state == .pending || display.state == .disconnected {
                display.isPrimary = false
                new_displays.insert(display)
            }
        }
        
        displays = Array(new_displays)
        
        displays.sort {
            if $0.isPrimary {
                return true
            }
            if $1.isPrimary {
                return false
            }
            return $0.id < $1.id
        }
        
        try! arrengementCache.cache()
        
        #if DEBUG
        print("📺 [DEBUG] Found \(displays.count) displays:")
        for display in displays {
            let builtIn = CGDisplayIsBuiltin(display.id) != 0
            print("   - \(display.name) (ID: \(display.id)) State: \(display.state) Primary: \(display.isPrimary) Built-in: \(builtIn)")
        }
        #endif
        
        // Check if auto-restore should be scheduled after fetching displays
        scheduleAutoRestoreIfNeeded()
    }
    
    func disconnectDisplay(display: DisplayInfo) throws(DisplayError) {
        display.state = .pending
        var cid: CGDisplayConfigRef?
        let beginStatus = CGBeginDisplayConfiguration(&cid)
        
        guard beginStatus == .success, let config = cid else {
            throw DisplayError(msg: "Failed to begin configuring '\(display.name)'.")
        }
        
        let status = CGSConfigureDisplayEnabled(config, display.id, false)
        guard status == 0 else {
            CGCancelDisplayConfiguration(config)
            throw DisplayError(msg: "Failed to disconnect '\(display.name)'.")
        }
        
        let completeStatus = CGCompleteDisplayConfiguration(config, .forAppOnly)
        guard completeStatus == .success else {
            throw DisplayError(msg: "Failed to finish configuring '\(display.name)'.")
        }
        
        display.state = .disconnected
        unRegisterMirrors(display: display)
    }

    
    func disableDisplay(display: DisplayInfo) throws(DisplayError) {
        display.state = .pending
        
        
        do {
            try mirrorDisplay(display)
            gammaService.setZeroGamma(for: display)
        } catch {
            throw DisplayError(msg: "Faild to apply a mirror-based disable to '\(display.name)'.")
        }
        unRegisterMirrors(display: display)
    }
    
    func turnOnDisplay(display: DisplayInfo) throws(DisplayError) {
        switch display.state {
        case .disconnected:
            try reconnectDisplay(display: display)
        case .mirrored:
            try enableDisplay(display: display)
        default:
            break
        }
    }
    
    func resetAllDisplays() {
        for display in displays {
            try? turnOnDisplay(display: display)
        }
        CGDisplayRestoreColorSyncSettings()
        CGRestorePermanentDisplayConfiguration()
    }
    
    func unRegisterMirrors(display: DisplayInfo) {
        for mirror in display.mirroredTo {
            mirror.state = .active
        }
    }
    
}

// MARK: - TurnOn logic

extension DisplaysViewModel {
    fileprivate func reconnectDisplay(display: DisplayInfo) throws(DisplayError) {
        var cid: CGDisplayConfigRef?
        let beginStatus = CGBeginDisplayConfiguration(&cid)
        guard beginStatus == .success, let config = cid else {
            throw DisplayError(
                msg: "Failed to begin configuration for '\(display.name)'."
            )
        }
        
        let status = CGSConfigureDisplayEnabled(config, display.id, true)
        guard status == 0 else {
            CGCancelDisplayConfiguration(config)
            throw DisplayError(
                msg: "Failed to reconnect '\(display.name)'."
            )
        }
        
        let completeStatus = CGCompleteDisplayConfiguration(config, .forAppOnly)
        guard completeStatus == .success else {
            throw DisplayError(
                msg: "Failed to complete configuration for '\(display.name)'.")
        }
        
        display.state = .active
    }
    
    fileprivate func enableDisplay(display: DisplayInfo) throws(DisplayError) {
        gammaService.restoreGamma(for: display)
        
        do {
            try unmirrorDisplay(display)
            try arrengementCache.restore()
            print("Unmirrored display \(display.name)!")
        } catch {
            throw DisplayError(
                msg: "Failed to enable '\(display.name)'."
            )
        }
        
        display.state = .active
    }
}

// MARK: - Mirroring Extention

extension DisplaysViewModel {
    fileprivate func mirrorDisplay(_ display: DisplayInfo) throws {
        let targetDisplayID = display.id
        
        guard let alternateDisplay = selectAlternateDisplay(excluding: targetDisplayID) else {
            throw DisplayError(msg: "No suitable alternate display found for mirroring.")
        }
        
        var configRef: CGDisplayConfigRef?
        let beginConfigError = CGBeginDisplayConfiguration(&configRef)
        guard beginConfigError == .success, let config = configRef else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(beginConfigError.rawValue), userInfo: [
                NSLocalizedDescriptionKey: "Failed to begin display configuration."
            ])
        }
        
        let mirrorError = CGConfigureDisplayMirrorOfDisplay(config, targetDisplayID, alternateDisplay.id)
        guard mirrorError == .success else {
            CGCancelDisplayConfiguration(config)
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(mirrorError.rawValue), userInfo: [
                NSLocalizedDescriptionKey: "Failed to mirror display \(alternateDisplay.name) to display \(display.name)."
            ])
        }
        
        let completeConfigError = CGCompleteDisplayConfiguration(config, .forAppOnly)
        guard completeConfigError == .success else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(completeConfigError.rawValue), userInfo: [
                NSLocalizedDescriptionKey: "Failed to complete display configuration."
            ])
        }
        
        alternateDisplay.mirroredTo.append(display)
        print("Successfully mirrored display \(display.name) to \(alternateDisplay.name).")
    }
    
    fileprivate func unmirrorDisplay(_ display: DisplayInfo) throws {
        var configRef: CGDisplayConfigRef?
        let beginConfigError = CGBeginDisplayConfiguration(&configRef)
        guard beginConfigError == .success, let config = configRef else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(beginConfigError.rawValue),
                userInfo: [NSLocalizedDescriptionKey: "Failed to begin display configuration."]
            )
        }

        let unmirrorError = CGConfigureDisplayMirrorOfDisplay(config, display.id, kCGNullDirectDisplay)
        guard unmirrorError == .success else {
            CGCancelDisplayConfiguration(config)
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(unmirrorError.rawValue),
                userInfo: [NSLocalizedDescriptionKey: "Failed to unmirror display \(display.name)."]
            )
        }

        let completeConfigError = CGCompleteDisplayConfiguration(config, .forAppOnly)
        guard completeConfigError == .success else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(completeConfigError.rawValue),
                userInfo: [NSLocalizedDescriptionKey: "Failed to complete display configuration."]
            )
        }

        // Update the mirroredTo and mirrorSource relationships
        display.mirrorSource?.mirroredTo.remove(at: display.mirrorSource!.mirroredTo.firstIndex(of: display)!)

        print("Successfully unmirrored display \(display.name).")
    }
    
    private func selectAlternateDisplay(excluding currentDisplayID: CGDirectDisplayID) -> DisplayInfo? {
        return displays.first { $0.id != currentDisplayID && $0.state == .active}
    }
}

// MARK: - NScreen Extentrion

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as! CGDirectDisplayID
    }
}

// MARK: - Display Reconfiguration Callback

/// Global callback function for display configuration changes
/// This is required because CGDisplayRegisterReconfigurationCallback needs a C-style function pointer
private func displayReconfigurationCallback(
    display: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo = userInfo else { return }
    let viewModel = Unmanaged<DisplaysViewModel>.fromOpaque(userInfo).takeUnretainedValue()
    viewModel.handleDisplayReconfiguration(display: display, flags: flags)
}
