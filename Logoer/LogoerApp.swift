//
//  LogoerApp.swift
//  Logoer
//
//  Created by apple on 2024/7/18.
//

import SwiftUI
import Sparkle
import CoreGraphics
import SDWebImageSwiftUI

let ud = UserDefaults.standard
var deviceType = "Mac"
var maskLock = false
var aboveSonoma = false
var aboveSequoia = false
var dataModel = DataModel()
var updaterController: SPUStandardUpdaterController!
var maskTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

@main
struct LogoerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    
    var body: some Scene {
        Settings {
            SettingsView().fixedSize()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("logoStyle") var logoStyle = "rainbow"
    @AppStorage("maskInterval") var maskInterval = 5
    let th = DispatchQueue.global(qos: .background)
    let NC = NSWorkspace.shared.notificationCenter

    func applicationDidFinishLaunching(_ notification: Notification) {
        th.async {
            while true {
                Thread.sleep(forTimeInterval: TimeInterval(self.maskInterval))
                DispatchQueue.main.async {
                    if !maskLock { refeshMask() } else { maskLock = false }
                }
            }
        }
        th.async {
            var tick = 0
            while true {
                // The menu bar slides in over a full-screen Space in a fraction of a
                // second, and the Apple glyph is drawn from the first frame. The pointer
                // check is cheap, the CGS / window-list queries in `getFullScreens()` are
                // not, so split them: a pointer-only check every 25 ms (about one frame,
                // the finest this can usefully be) puts the mask up with the bar, and the
                // full Space / status-item query runs every 0.2 s.
                Thread.sleep(forTimeInterval: 0.025)
                tick += 1
                let fullCheck = tick % 8 == 0
                DispatchQueue.main.async {
                    if fullCheck { getFullScreens() } else { updatePointerReveal() }
                }
            }
        }
        th.async {
            while true {
                Thread.sleep(forTimeInterval: 2)
                DispatchQueue.main.async { dataModel.battery = getPowerState() }
            }
        }
        deviceType = getMacDeviceType()
        if #available(macOS 14, *) { aboveSonoma = true }
        if #available(macOS 15, *) { aboveSequoia = true }
        adoptAutoMaskSilentlyIfPossible(for: logoStyle)
        refeshMask()
        createLogo()
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, nil)
        NC.addObserver(self, selector: #selector(onDisplayWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        NC.addObserver(self, selector: #selector(didActivateApplication(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        // Nothing on screen advertises how to reach the settings panel, so on the very
        // first launch show it outright instead of relying on the tips to explain the
        // "run it again" trick.
        let isFirstLaunch = !ud.bool(forKey: "hasLaunchedBefore")
        ud.set(true, forKey: "hasLaunchedBefore")
        if isFirstLaunch { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showSettings() } }

        // Queue the tips after the panel so they stack on top of it instead of
        // fighting it for the key window.
        DispatchQueue.main.asyncAfter(deadline: .now() + (isFirstLaunch ? 1.0 : 0)) {
            tips(id: "logoer.first-start.note", text: "When Logoer is running, you can run it again to bring up the settings panel.")
            tips(id: "logoer.full-screen.note", text: "Enabling \"Visible in Full Screen Mode\" will keep the logo visible in full screen mode.")
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        createLogo()
        NSApp.activate(ignoringOtherApps: true)
        showSettings()
        return true
    }
    
    @objc func onDisplayWake() { print("Display WakeUp"); createLogo() }
    
    @objc func didActivateApplication(_ notification: Notification) {
        if logoStyle == "appicon",
           let userInfo = notification.userInfo,
           let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            dataModel.appIcon = getIcon(app: app)
            createLogo()
        }
    }
}

/// Looks up a logo image in both build flavours.
///
/// Xcode's `actool` compiles `Assets.xcassets` into `Assets.car`; the Command Line
/// Tools build has no `actool`, so it ships the same artwork as loose files in
/// `Contents/Resources`. `Image("name")` only consults the asset catalog — it does
/// **not** fall back to loose bundle resources (verified on macOS 26) — while
/// `NSImage(named:)` checks both. Route every logo image through here.
///
/// `template` mirrors `template-rendering-intent` from the imageset: pass true only
/// for monochrome silhouettes meant to be tinted with `foregroundColor`.
func logoImage(_ name: String, template: Bool = false) -> Image {
    guard let image = NSImage(named: name) else { return Image(name) }
    image.isTemplate = template
    return Image(nsImage: image).renderingMode(template ? .template : .original)
}

/// Same idea for colors: `Color("my_green")` needs the asset catalog. Without
/// `actool` the four battery colors fall back to the exact display-P3 values from
/// their colorsets in `Assets.xcassets`.
func logoColor(_ name: String) -> Color {
    if #available(macOS 12, *), let color = NSColor(named: name) { return Color(nsColor: color) }
    func p3(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(.displayP3, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
    switch name {
    case "my_green": return p3(0x4E, 0xCE, 0x51)
    case "my_red": return p3(0xEA, 0x4E, 0x3D)
    case "my_yellow": return p3(0xFF, 0xB8, 0x00)
    default: return p3(0x99, 0x99, 0x99)
    }
}

func getIcon(app: NSRunningApplication?) -> NSImage {
    if let app = app, let path = app.bundleURL?.path {
        if let rep = NSWorkspace.shared.icon(forFile: path)
            .bestRepresentation(for: NSRect(x: 0, y: 0, width: 128, height: 128), context: nil, hints: nil) {
            let icon = NSImage(size: rep.size)
            icon.addRepresentation(rep)
            return icon
        } else {
            return NSWorkspace.shared.icon(forFile: path)
        }
    }
    return NSImage(named: "appicon_back") ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
}

func displayReconfigurationCallback(display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags, userInfo: UnsafeMutableRawPointer?) {
    print("Display Re-Configuration: \(flags)")
    createLogo()
}

/// Auto-Mask reads the menu-bar colour by shelling out to `screencapture`, which needs
/// Screen Recording permission (shown as "Screen & System Audio Recording" on macOS 15+).
///
/// That permission is granted to the app's code identity, and an ad-hoc signed
/// development build gets a new identity on every rebuild — so the grant is lost each
/// time. The important part: *every* capture attempted without a grant makes macOS raise
/// the system dialog again, and `refeshMask()` is called from a timer every
/// `maskInterval` seconds. Capturing blindly therefore re-prompted forever. Ask once at
/// launch instead, and never attempt a capture while the answer is "no".
func hasScreenCaptureAccess() -> Bool {
    CGPreflightScreenCaptureAccess()
}

@discardableResult
func requestScreenCaptureAccess() -> Bool {
    if CGPreflightScreenCaptureAccess() { return true }
    return CGRequestScreenCaptureAccess()
}

func refeshMask() {
    @AppStorage("maskMode") var maskMode: Bool = false
    if !maskMode { return }
    // Never attempt a capture we are not allowed to make: the attempt itself is what
    // re-opens the system permission dialog, and this runs on a timer. Without the
    // grant, fall back to the last captured mask on disk — it is only wrong after a
    // light/dark switch, which is better than an uncovered system Apple logo.
    let canCapture = hasScreenCaptureAccess()
    var masks = [maskImage]()
    let screens = NSScreen.screens
    // Only a *drawn* menu bar is worth sampling. `revealedMenuBars` deliberately treats a
    // pointer at the top edge as revealed so the mask is already there when the bar slides
    // in; for a capture that is too early — the sample point still shows the app's own
    // content, and painting that over the logo leaves a solid block. Ask for the slower,
    // unambiguous signal instead: status items actually on screen.
    let drawnMenuBars = revealedMenuBarScreens(in: dataModel.fullScreens, includingPointer: false)
    for index in screens.indices {
        let screen = screens[index]
        let maskURL = getMaskURL(index: index)
        // While a full-screen Space keeps the menu bar hidden there is nothing to cover,
        // and what sits at the sample point is the app's own content — capturing now
        // would overwrite a good mask with, say, the terminal's background colour. Keep
        // the last real menu-bar mask instead; it is refreshed when the bar comes back.
        let hiddenMenuBar = dataModel.fullScreens.contains(screen.frame)
            && !drawnMenuBars.contains(screen.frame)
        if canCapture && !hiddenMenuBar {
            // Sample 10pt inboard of the screen's top-left. The exact corner is where the
            // display rounds off its corners: on the secondary display it reads the black
            // behind the rounding (28,28,28) instead of the menu bar (38,41,43), and the
            // mask then paints a visibly wrong rectangle. 10pt is inside every menu bar
            // and outside every corner radius.
            let origin = getOrigin(of: screen, in: screens)
            let sample = CGPoint(x: origin.x + 10, y: origin.y + 10)
            _ = process(path: "/usr/sbin/screencapture", arguments: ["-x", "-R", "\(Int(sample.x)),\(Int(sample.y)),4,4", maskURL.path])
        }
        if let image = NSImage(contentsOf: maskURL) { masks.append(maskImage(url: maskURL, image: image)) }
    }
    dataModel.masks = masks
}

/// Styles drawn on the Apple silhouette. macOS keeps drawing its own Apple menu glyph
/// behind our overlay window; an Apple-shaped style hides it by painting over the same
/// shape in the same place. Any other style (penguin, window, emoji, app icon, custom
/// image) leaves the system Apple visible in the gaps — that is why "Battery: Linux"
/// showed a penguin *and* an Apple. Auto-Mask is what paints the menu-bar colour over
/// the system glyph, so the non-Apple styles need it enabled to render correctly.
let appleShapedLogoStyles: Set<String> = ["rainbow", "chrome", "glass", "aqua", "battery", "color"]

/// Enable Auto-Mask and ask for the Screen Recording permission it needs, once, at the
/// moment the user picks a style that cannot work without it. Called from the picker
/// only: asking on a plain launch would be an unexplained permission prompt.
func enableAutoMaskIfNeeded(for style: String) {
    @AppStorage("maskMode") var maskMode = false
    if appleShapedLogoStyles.contains(style) || maskMode { return }
    maskMode = true
    if requestScreenCaptureAccess() {
        refeshMask()
    } else {
        tips(id: "logoer.screen-recording.note",
             text: "This logo style has to cover the system Apple logo, which needs Screen Recording permission to read the menu bar colour. Allow it in System Settings → Privacy & Security → Screen & System Audio Recording and the logo will fix itself.")
    }
}

/// Same idea for a style restored from preferences at launch (or set via `defaults
/// write`): switch the mask on without prompting when the permission is already there.
/// If it is not, leave the setting alone — a permission dialog on launch would be
/// unexplained, and the picker asks properly when the user next changes style.
func adoptAutoMaskSilentlyIfPossible(for style: String) {
    @AppStorage("maskMode") var maskMode = false
    if appleShapedLogoStyles.contains(style) || maskMode { return }
    guard hasScreenCaptureAccess() else { return }
    maskMode = true
    refeshMask()
}

func createLogo(noCache: Bool = false) {
    @AppStorage("logoStyle") var logoStyle = "rainbow"
    print("refesh logo at: \(Date())")
    for w in NSApp.windows.filter({ $0.title == "logo" }) { w.close() }

    if noCache {
        SDImageCache.shared.clearMemory()
        SDImageCache.shared.clearDisk()
    }
    
    let screens = NSScreen.screens
    for index in screens.indices {
        let screen = screens[index]
        let maskURL = getMaskURL(index: index)
        let appleMenuBarHeight = screen.frame.height - screen.visibleFrame.height - (screen.visibleFrame.origin.y - screen.frame.origin.y) - 1
        let logo = NSWindow(contentRect: NSRect(x:0, y: 0, width: 24, height: 24), styleMask: [.fullSizeContentView], backing: .buffered, defer: false)
        logo.contentView = NSHostingView(rootView: ContentView(model: dataModel, screen: screen, maskURL: maskURL))
        logo.title = "logo".local
        logo.isOpaque = false
        logo.hasShadow = false
        logo.isRestorable = false
        logo.ignoresMouseEvents = true
        logo.isReleasedWhenClosed = false
        logo.level = .statusBar
        logo.backgroundColor = .clear
        logo.collectionBehavior = [.canJoinAllSpaces, .transient]
        //if pinOnScreen { logo.collectionBehavior = [.canJoinAllSpaces, .transient] }
        logo.setFrameOrigin(NSPoint(x: 15 + screen.frame.minX, y: screen.frame.minY + screen.frame.height - appleMenuBarHeight/2 - 12))
        logo.orderFront(nil)
    }
}

// Private CoreGraphics "Spaces" API. We ask the window server which displays are
// currently showing a native full-screen Space. This is the only reliable signal:
// on notched Macs a full-screen window's bounds are identical to a merely *maximized*
// window's (both render below the notch), so comparing window rectangles can never
// tell full screen from maximized. Asking about the Space type sidesteps that entirely,
// works for any app, and is per-display.
typealias CGSConnectionID = UInt32
@_silgen_name("_CGSDefaultConnection")
func _CGSDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> Unmanaged<CFArray>

// CGS reports a native full-screen Space with type == 4.
private let kCGSSpaceTypeFullscreen = 4

// Stable UUID string for a screen, used to match an NSScreen to a CGS managed display.
func screenUUID(_ screen: NSScreen) -> String? {
    guard let num = screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber,
          let cf = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(num.uint32Value))?.takeRetainedValue()
    else { return nil }
    return CFUUIDCreateString(nil, cf) as String
}

func getFullScreens() {
    // Which displays currently show a native full-screen Space?
    var fullScreenDisplayIDs = Set<String>()
    if let displays = CGSCopyManagedDisplaySpaces(_CGSDefaultConnection()).takeRetainedValue() as? [[String: Any]] {
        for display in displays {
            guard let id = display["Display Identifier"] as? String,
                  let current = display["Current Space"] as? [String: Any],
                  let type = current["type"] as? Int else { continue }
            if type == kCGSSpaceTypeFullscreen { fullScreenDisplayIDs.insert(id) }
        }
    }

    // Map those displays back to NSScreen frames (the unit ContentView compares against).
    // "Main" is accepted as a fallback identifier for the primary display on some macOS versions.
    var screenList = [NSRect]()
    for screen in NSScreen.screens {
        let matchesUUID = screenUUID(screen).map { fullScreenDisplayIDs.contains($0) } ?? false
        let matchesMain = fullScreenDisplayIDs.contains("Main") && screen.isMainScreen
        if matchesUUID || matchesMain { screenList.append(screen.frame) }
    }

    if screenList != dataModel.fullScreens {
        if screenList.count < dataModel.fullScreens.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                maskLock = true
                refeshMask()
            }
        }
        dataModel.fullScreens = screenList
    }

    // A full-screen Space hides the menu bar — until the pointer is pulled to the top
    // edge, which draws the system Apple glyph again over whatever the app is showing.
    // Follow that state so the mask can cover the Apple while the bar is up.
    let revealed = revealedMenuBarScreens(in: screenList)
    if revealed != dataModel.revealedMenuBars {
        // Compare the sets, not the counts: with two displays one bar can appear in the
        // same tick the other hides, and equal counts would hide the fresh capture.
        let barAppeared = revealed.contains { !dataModel.revealedMenuBars.contains($0) }
        dataModel.revealedMenuBars = revealed
        // Captures were skipped while the bar was hidden, so the mask on disk may be
        // stale or missing — take a fresh one now that the menu bar is really there.
        if barAppeared { refreshMaskOnceMenuBarLands(attemptsLeft: 8) }
    }
}

/// Pointer-only half of `revealedMenuBarScreens`, cheap enough to run many times a second.
///
/// The bar starts sliding in within a frame of the pointer hitting the top edge, and the
/// Apple is already drawn behind it — polling the Space and window list at that rate would
/// be wasteful, so this tick only looks at the pointer. Entries are added here and removed
/// by the full `getFullScreens()` pass, which still owns the authoritative answer.
private func updatePointerReveal() {
    guard !dataModel.fullScreens.isEmpty else { return }
    let pointer = NSEvent.mouseLocation
    let atEdge = dataModel.fullScreens.filter { frame in
        pointer.y >= frame.maxY - 2 && pointer.x >= frame.minX && pointer.x < frame.maxX
    }
    guard !atEdge.isEmpty else { return }
    var added = false
    for frame in atEdge where !dataModel.revealedMenuBars.contains(frame) {
        dataModel.revealedMenuBars.append(frame)
        added = true
    }
    // The mask on disk was skipped while the bar was hidden, so once the bar is really
    // drawn it has to be captured again — the full pass would normally trigger this, but
    // it now sees the screen as already revealed.
    if added { refreshMaskOnceMenuBarLands(attemptsLeft: 8) }
}

/// Captures are only valid once the menu bar is actually drawn: the reveal animation
/// takes a moment, and a capture taken too early records the app's own content, which
/// would then be painted over the Apple glyph as a solid block. Wait for the status
/// items to be on screen (not merely for the pointer to be at the edge), and give up
/// if the bar goes away again before it lands.
private func refreshMaskOnceMenuBarLands(attemptsLeft: Int) {
    guard attemptsLeft > 0 else { return }
    if !revealedMenuBarScreens(in: dataModel.fullScreens, includingPointer: false).isEmpty {
        refeshMask()
        return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        refreshMaskOnceMenuBarLands(attemptsLeft: attemptsLeft - 1)
    }
}

/// Which of the given full-screen displays are drawing their menu bar anyway — because
/// the pointer reached the top edge, or because the user asked for a menu bar that stays
/// visible in full screen?
///
/// There is no public API for "is the menu bar revealed", and the private SkyLight calls
/// that sound like one (`CGSIsMenuBarVisibleOnSpace` and friends) crash when called via
/// `dlsym`. What does change is Control Centre's status items: they live at window layer
/// 25 and are present-but-not-on-screen while a full-screen Space keeps the bar hidden,
/// then become on-screen the moment it is revealed (measured: 0 on-screen items hidden vs
/// 13 revealed). Their window bounds also tell us *which* display was revealed.
///
/// That signal trails the animation by a poll interval, and the Apple glyph is drawn on
/// the first frame of it — so `includingPointer` also counts a pointer resting on a
/// screen's top edge as revealed, which lets the mask land before the bar slides in.
/// Pass false when the question is whether the bar is *drawn* right now, e.g. before
/// sampling its colour.
func revealedMenuBarScreens(in fullScreens: [NSRect], includingPointer: Bool = true) -> [NSRect] {
    guard !fullScreens.isEmpty else { return [] }

    let pointer = NSEvent.mouseLocation
    var revealed = includingPointer ? fullScreens.filter { frame in
        pointer.y >= frame.maxY - 2 && pointer.x >= frame.minX && pointer.x < frame.maxX
    } : []

    let controlCentrePIDs = Set(NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.controlcenter")
        .map { Int($0.processIdentifier) })
    guard !controlCentrePIDs.isEmpty else { return revealed }
    if revealed.count == fullScreens.count { return revealed }

    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    let statusItemTops = windows.compactMap { window -> CGPoint? in
        guard (window[kCGWindowLayer as String] as? Int) == 25,
              let pid = window[kCGWindowOwnerPID as String] as? Int,
              controlCentrePIDs.contains(pid),
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let x = (bounds["X"] as? NSNumber)?.doubleValue,
              let y = (bounds["Y"] as? NSNumber)?.doubleValue
        else { return nil }
        return CGPoint(x: x, y: y)
    }
    guard !statusItemTops.isEmpty else { return revealed }

    // CGWindowList geometry is measured from the top-left corner of the arrangement,
    // NSScreen from the bottom-left of the main screen — so a screen's top edge has to be
    // flipped. X is the same in both spaces (both start at the main display's left edge
    // and go negative to the left of it).
    let arrangementTop = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
    for frame in fullScreens where !revealed.contains(frame) {
        let top = arrangementTop - frame.maxY
        if statusItemTops.contains(where: { abs($0.y - top) < 2 && $0.x >= frame.minX && $0.x < frame.maxX }) {
            revealed.append(frame)
        }
    }
    return revealed
}

func getOrigin(of screen: NSScreen, in screens: [NSScreen]) -> NSPoint {
    if !screen.isMainScreen {
        if let mainScreen = screens.first(where: { $0.isMainScreen }) {
            let fullScreenRect = screens.reduce(NSRect.zero) { (result, screen) -> NSRect in result.union(screen.frame) }
            let screenFrame = screen.frame
            let mainScreenFrame = mainScreen.frame
            let originOffset = fullScreenRect.size.height
            let convertedMainOrigin = CGPoint(x: mainScreenFrame.origin.x, y: originOffset - mainScreenFrame.origin.y - mainScreenFrame.size.height)
            let convertedOrigin = CGPoint(x: screenFrame.origin.x, y: originOffset - screenFrame.origin.y - screenFrame.size.height)
            return NSPoint(x: convertedOrigin.x, y: convertedOrigin.y - convertedMainOrigin.y)
        }
    }
    return NSPoint(x: 0, y: 0)
}

func getMaskURL(index: Int) -> URL {
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("mask\(index).png")
}

// Identifier AppKit gives to the window backing SwiftUI's `Settings` scene.
private let settingsWindowID = "com_apple_SwiftUI_Settings_window"

private func settingsWindow() -> NSWindow? {
    // Exclude panels (our tips alerts are `NSPanel`s) and the logo overlays, or the
    // alert ends up being raised instead of the settings window.
    let candidates = NSApp.windows.filter { !$0.isKind(of: NSPanel.self) && $0.level != .statusBar }
    return candidates.first(where: { $0.identifier?.rawValue == settingsWindowID })
        ?? candidates.first(where: { !$0.title.isEmpty })
}

/// Brings the settings window to the front no matter what state it is in.
///
/// The window may not exist yet (SwiftUI creates it lazily), may exist but be hidden
/// behind other windows, or may sit on another Space. So: open it, then poll briefly
/// and force it front — simply setting `level` is not enough on macOS 26, the window
/// keeps `onscreen = 0` until it is explicitly ordered front and made key.
func showSettings() {
    if let window = settingsWindow() {
        bringSettingsWindowFront(window)
        return
    }
    openSettingsWindow()
    waitForSettingsWindow(attemptsLeft: 30, reopenAfter: 15)
}

private func openSettingsWindow() {
    if let appMenu = NSApp.mainMenu?.items.first?.submenu {
        // The Settings item is the one bound to ⌘, — matching that way survives
        // localization. Its action is SwiftUI-private (`menuAction:`), so there is
        // no stable selector to match on.
        if let item = appMenu.items.first(where: {
            $0.keyEquivalent == "," && $0.keyEquivalentModifierMask.contains(.command)
        }) {
            item.performAction()
            return
        }
        appMenu.item(at: 2)?.performAction()
        return
    }
    if #available(macOS 13, *) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    } else {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}

/// SwiftUI builds the settings window on the next run-loop turn, and the menu action
/// can be a no-op if the app menu is not fully set up yet — so retry the open once
/// before giving up.
private func waitForSettingsWindow(attemptsLeft: Int, reopenAfter: Int) {
    if let window = settingsWindow() {
        bringSettingsWindowFront(window)
        return
    }
    if attemptsLeft == reopenAfter {
        openSettingsWindow()
    }
    guard attemptsLeft > 0 else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        waitForSettingsWindow(attemptsLeft: attemptsLeft - 1, reopenAfter: reopenAfter)
    }
}

private func bringSettingsWindowFront(_ window: NSWindow) {
    // A saved window frame can end up entirely off-screen — the display arrangement
    // changed, or the frame was stored while a now-disconnected monitor was attached.
    // AppKit happily orders the window in at those coordinates and the user sees
    // nothing, which looks exactly like "the settings panel never opens".
    if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
        let target = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
        if let visible = target {
            window.setFrameOrigin(NSPoint(
                x: visible.midX - window.frame.width / 2,
                y: visible.midY - window.frame.height / 2))
        }
    }
    // A settings window stranded on another Space or under a full-screen app is
    // invisible even after ordering it front.
    window.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])
    window.level = .floating
    if window.isMiniaturized { window.deminiaturize(nil) }
    if NSApp.isHidden { NSApp.unhide(nil) }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
}

// Tips are shown non-modally and one at a time. `NSAlert.runModal()` spins a modal
// run loop that starves `applicationShouldHandleReopen`, so while a tip was up,
// relaunching the app did nothing at all — which reads as "the settings panel is gone".
final class TipCenter: NSObject {
    static let shared = TipCenter()

    private var queue = [(id: String, alert: NSAlert)]()
    private var current: (id: String, alert: NSAlert)?
    private var observer: NSObjectProtocol?

    func enqueue(id: String, text: String) {
        let never = UserDefaults.standard.object(forKey: "neverRemindMe") as? [String] ?? []
        if never.contains(id) { return }
        queue.append((id, createAlert(title: "Logoer Tips".local, message: text.local, button1: "Don't remind me again", button2: "OK")))
        presentNext()
    }

    private func presentNext() {
        guard current == nil, !queue.isEmpty else { return }
        let tip = queue.removeFirst()
        current = tip

        for (index, button) in tip.alert.buttons.enumerated() {
            button.tag = index
            button.target = self
            button.action = #selector(handleButton(_:))
        }
        // Observe rather than set `window.delegate` — NSAlert owns its window's delegate.
        // This also covers Esc and any other dismissal, so `current` never gets stuck
        // and blocks the remaining tips.
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: tip.alert.window, queue: .main
        ) { [weak self] _ in self?.tipClosed() }

        tip.alert.window.level = .floating
        tip.alert.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func handleButton(_ sender: NSButton) {
        guard let tip = current else { return }
        if sender.tag == 0 {
            var never = UserDefaults.standard.object(forKey: "neverRemindMe") as? [String] ?? []
            never.append(tip.id)
            UserDefaults.standard.setValue(never, forKey: "neverRemindMe")
        }
        tip.alert.window.close()
    }

    private func tipClosed() {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        current = nil
        presentNext()
    }
}

func tips(id: String, text: String) {
    TipCenter.shared.enqueue(id: id, text: text)
}

func createAlert(level: NSAlert.Style = .warning, title: String, message: String, button1: String, button2: String = "") -> NSAlert {
    let alert = NSAlert()
    alert.messageText = title.local
    alert.informativeText = message.local
    alert.addButton(withTitle: button1.local)
    if button2 != "" { alert.addButton(withTitle: button2.local) }
    alert.alertStyle = level
    return alert
}

func getMacDeviceType() -> String {
    guard let result = process(path: "/usr/sbin/system_profiler", arguments: ["SPHardwareDataType", "-json"]) else { return "Mac" }
    if let json = try? JSONSerialization.jsonObject(with: Data(result.utf8), options: []) as? [String: Any],
       let SPHardwareDataTypeRaw = json["SPHardwareDataType"] as? [Any],
       let SPHardwareDataType = SPHardwareDataTypeRaw[0] as? [String: Any],
       let model = SPHardwareDataType["machine_name"] as? String{
        return model
    }
    return "Mac"
}

public func process(path: String, arguments: [String], timeout: Double = 0) -> String? {
    let task = Process()
    task.launchPath = path
    task.arguments = arguments
    task.standardError = Pipe()
    
    let outputPipe = Pipe()
    defer { outputPipe.fileHandleForReading.closeFile() }
    task.standardOutput = outputPipe
    
    if timeout != 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(timeout)) {
            if task.isRunning { task.terminate() }
        }
    }
    
    do {
        try task.run()
    } catch let error {
        print("\(error.localizedDescription)")
        return nil
    }
    
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(decoding: outputData, as: UTF8.self)
    
    if output.isEmpty { return nil }
    
    return output.trimmingCharacters(in: .newlines)
}

extension String {
    var local: String { return NSLocalizedString(self, comment: "") }
    var deletingPathExtension: String { return (self as NSString).deletingPathExtension }
}

extension NSScreen {
    var hasTopNotchDesign: Bool {
        guard #available(macOS 12, *) else { return false }
        return safeAreaInsets.top != 0
    }
    var displayID: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
    var isMainScreen: Bool {
        guard let id = self.displayID else { return false }
        return (CGDisplayIsMain(id) == 1)
    }
}

extension NSMenuItem {
    func performAction() {
        guard let menu else { return }
        menu.performActionForItem(at: menu.index(of: self))
    }
}

func randomEmoji(full: Bool = false) -> String {
    let characters = Array(full ? "😀😃😄😁😆😅😂🤣🥲🥹☺️😊😇🙂🙃😉😌😍🥰😘😗😙😚😋😛😝😜🤪🤨🧐🤓😎🥸🤩🥳🙂‍↕️😏😒🙂‍↔️😞😔😟😕🙁☹️😣😖😫😩🥺😢😭😮‍💨😤😠😡🤬🤯😳🥵🥶😱😨😰😥😓🫣🤗🫡🤔🫢🤭🤫🤥😶😶‍🌫️😐😑😬🫨🫠🙄😯😦😧😮😲🥱😴🤤😪😵😵‍💫🫥🤐🥴🤢🤮🤧😷🤒🤕🤑🤠😈👿👹👺🤡💩👻💀☠️👽👾🤖🎃😺😸😹😻😼😽🙀😿😾👋🤚🖐✋🖖👌🤌🤏✌️🤞🫰🤟🤘🤙🫵🫱🫲🫸🫷🫳🫴👈👉👆🖕👇☝️👍👎✊👊🤛🤜👏🫶🙌👐🤲🤝🙏✍️💅🤳💪🦾🦵🦿🦶👣👂🦻👃🫀🫁🧠🦷🦴👀👁👅👄🫦💋🩸👶👧🧒👦👩🧑👨👩‍🦱🧑‍🦱👨‍🦱👩‍🦰🧑‍🦰👨‍🦰👱‍♀️👱👱‍♂️👩‍🦳🧑‍🦳👨‍🦳👩‍🦲🧑‍🦲👨‍🦲🧔‍♀️🧔🧔‍♂️👵🧓👴👲👳‍♀️👳👳‍♂️🧕👮‍♀️👮👮‍♂️👷‍♀️👷👷‍♂️💂‍♀️💂💂‍♂️🕵️‍♀️🕵️🕵️‍♂️👩‍⚕️🧑‍⚕️👨‍⚕️👩‍🌾🧑‍🌾👨‍🌾👩‍🍳🧑‍🍳👨‍🍳👩‍🎓🧑‍🎓👨‍🎓👩‍🎤🧑‍🎤👨‍🎤👩‍🏫🧑‍🏫👨‍🏫👩‍🏭🧑‍🏭👨‍🏭👩‍💻🧑‍💻👨‍💻👩‍💼🧑‍💼👨‍💼👩‍🔧🧑‍🔧👨‍🔧👩‍🔬🧑‍🔬👨‍🔬👩‍🎨🧑‍🎨👨‍🎨👩‍🚒🧑‍🚒👨‍🚒👩‍✈️🧑‍✈️👨‍✈️👩‍🚀🧑‍🚀👨‍🚀👩‍⚖️🧑‍⚖️👨‍⚖️👰‍♀️👰👰‍♂️🤵‍♀️🤵🤵‍♂️👸🫅🤴🥷🦸‍♀️🦸🦸‍♂️🦹‍♀️🦹🦹‍♂️🤶🧑‍🎄🎅🧙‍♀️🧙🧙‍♂️🧝‍♀️🧝🧝‍♂️🧛‍♀️🧛🧛‍♂️🧟‍♀️🧟🧟‍♂️🧞‍♀️🧞🧞‍♂️🧜‍♀️🧜🧜‍♂️🧚‍♀️🧚🧚‍♂️🧌👼🤰🫄🫃🤱👩‍🍼🧑‍🍼👨‍🍼🙇‍♀️🙇🙇‍♂️💁‍♀️💁💁‍♂️🙅‍♀️🙅🙅‍♂️🙆‍♀️🙆🙆‍♂️🙋‍♀️🙋🙋‍♂️🧏‍♀️🧏🧏‍♂️🤦‍♀️🤦🤦‍♂️🤷‍♀️🤷🤷‍♂️🙎‍♀️🙎🙎‍♂️🙍‍♀️🙍🙍‍♂️💇‍♀️💇💇‍♂️💆‍♀️💆💆‍♂️🧖‍♀️🧖🧖‍♂️💅🤳💃🕺👯‍♀️👯👯‍♂️🕴👩‍🦽👩‍🦽‍➡️🧑‍🦽🧑‍🦽‍➡️👨‍🦽👨‍🦽‍➡️👩‍🦼👩‍🦼‍➡️🧑‍🦼🧑‍🦼‍➡️👨‍🦼👨‍🦼‍➡️🚶‍♀️🚶‍♀️‍➡️🚶🚶‍➡️🚶‍♂️🚶‍♂️‍➡️👩‍🦯👩‍🦯‍➡️🧑‍🦯🧑‍🦯‍➡️👨‍🦯👨‍🦯‍➡️🧎‍♀️🧎‍♀️‍➡️🧎🧎‍➡️🧎‍♂️🧎‍♂️‍➡️🏃‍♀️🏃‍♀️‍➡️🏃🏃‍➡️🏃‍♂️🏃‍♂️‍➡️🧍‍♀️🧍🧍‍♂️👭🧑‍🤝‍🧑👬👫👩‍❤️‍👩💑👨‍❤️‍👨👩‍❤️‍👨👩‍❤️‍💋‍👩💏👨‍❤️‍💋‍👨👩‍❤️‍💋‍👨👪👨‍👩‍👦👨‍👩‍👧👨‍👩‍👧‍👦👨‍👩‍👦‍👦👨‍👩‍👧‍👧👨‍👨‍👦👨‍👨‍👧👨‍👨‍👧‍👦👨‍👨‍👦‍👦👨‍👨‍👧‍👧👩‍👩‍👦👩‍👩‍👧👩‍👩‍👧‍👦👩‍👩‍👦‍👦👩‍👩‍👧‍👧👨‍👦👨‍👦‍👦👨‍👧👨‍👧‍👦👨‍👧‍👧👩‍👦👩‍👦‍👦👩‍👧👩‍👧‍👦👩‍👧‍👧🧑‍🧑‍🧒🧑‍🧑‍🧒‍🧒🧑‍🧒🧑‍🧒‍🧒🗣👤👥🫂🧳🌂☂️🧵🪡🪢🪭🧶👓🕶🥽🥼🦺👔👕👖🧣🧤🧥🧦👗👘🥻🩴🩱🩲🩳👙👚👛👜👝🎒👞👟🥾🥿👠👡🩰👢👑👒🎩🎓🧢⛑🪖💄💍💼🐶🐱🐭🐹🐰🦊🐻🐼🐻‍❄️🐨🐯🦁🐮🐷🐽🐸🐵🙈🙉🙊🐒🐔🐧🐦🐦‍⬛🐤🐣🐥🦆🦅🦉🦇🐺🐗🐴🦄🐝🪱🐛🦋🐌🐞🐜🪰🪲🪳🦟🦗🕷🕸🦂🐢🐍🦎🦖🦕🐙🦑🦐🦞🦀🪼🪸🐡🐠🐟🐬🐳🐋🦈🐊🐅🐆🦓🫏🦍🦧🦣🐘🦛🦏🐪🐫🦒🦘🦬🐃🐂🐄🐎🐖🐏🐑🦙🐐🦌🫎🐕🐩🦮🐕‍🦺🐈🐈‍⬛🪽🪶🐓🦃🦤🦚🦜🦢🪿🦩🕊🐇🦝🦨🦡🦫🦦🦥🐁🐀🐿🦔🐾🐉🐲🐦‍🔥🌵🎄🌲🌳🌴🪹🪺🪵🌱🌿☘️🍀🎍🪴🎋🍃🍂🍁🍄🍄‍🟫🐚🪨🌾💐🌷🪷🌹🥀🌺🌸🪻🌼🌻🌞🌝🌛🌜🌚🌕🌖🌗🌘🌑🌒🌓🌔🌙🌎🌍🌏🪐💫⭐️🌟✨⚡️☄️💥🔥🌪🌈☀️🌤⛅️🌥☁️🌦🌧⛈🌩🌨❄️☃️⛄️🌬💨💧💦🫧☔️☂️🌊🍏🍎🍐🍊🍋🍋‍🟩🍌🍉🍇🍓🫐🍈🍒🍑🥭🍍🥥🥝🍅🍆🥑🥦🫛🥬🥒🌶🫑🌽🥕🫒🧄🧅🫚🥔🍠🫘🥐🥯🍞🥖🥨🧀🥚🍳🧈🥞🧇🥓🥩🍗🍖🦴🌭🍔🍟🍕🫓🥪🥙🧆🌮🌯🫔🥗🥘🫕🥫🍝🍜🍲🍛🍣🍱🥟🦪🍤🍙🍚🍘🍥🥠🥮🍢🍡🍧🍨🍦🥧🧁🍰🎂🍮🍭🍬🍫🍿🍩🍪🌰🥜🍯🥛🍼🫖☕️🍵🧃🥤🧋🫙🍶🍺🍻🥂🍷🫗🥃🍸🍹🧉🍾🧊🥄🍴🍽🥣🥡🥢🧂⚽️🏀🏈⚾️🥎🎾🏐🏉🥏🎱🪀🏓🏸🏒🏑🥍🏏🪃🥅⛳️🪁🏹🎣🤿🥊🥋🎽🛹🛼🛷⛸🥌🎿⛷🏂🪂🏋️‍♀️🏋️🏋️‍♂️🤼‍♀️🤼🤼‍♂️🤸‍♀️🤸🤸‍♂️⛹️‍♀️⛹️⛹️‍♂️🤺🤾‍♀️🤾🤾‍♂️🏌️‍♀️🏌️🏌️‍♂️🏇🧘‍♀️🧘🧘‍♂️🏄‍♀️🏄🏄‍♂️🏊‍♀️🏊🏊‍♂️🤽‍♀️🤽🤽‍♂️🚣‍♀️🚣🚣‍♂️🧗‍♀️🧗🧗‍♂️🚵‍♀️🚵🚵‍♂️🚴‍♀️🚴🚴‍♂️🏆🥇🥈🥉🏅🎖🏵🎗🎫🎟🎪🤹🤹‍♂️🤹‍♀️🎭🩰🎨🎬🎤🎧🎼🎹🥁🪘🪇🎷🎺🪗🎸🪕🎻🪈🎲♟🎯🎳🎮🎰🧩🚗🚕🚙🚌🚎🏎🚓🚑🚒🚐🛻🚚🚛🚜🦯🦽🦼🛴🚲🛵🏍🛺🚨🚔🚍🚘🚖🛞🚡🚠🚟🚃🚋🚞🚝🚄🚅🚈🚂🚆🚇🚊🚉✈️🛫🛬🛩💺🛰🚀🛸🚁🛶⛵️🚤🛥🛳⛴🚢⚓️🛟🪝⛽️🚧🚦🚥🚏🗺🗿🗽🗼🏰🏯🏟🎡🎢🛝🎠⛲️⛱🏖🏝🏜🌋⛰🏔🗻🏕⛺️🛖🏠🏡🏘🏚🏗🏭🏢🏬🏣🏤🏥🏦🏨🏪🏫🏩💒🏛⛪️🕌🕍🛕🕋⛩🛤🛣🗾🎑🏞🌅🌄🌠🎇🎆🌇🌆🏙🌃🌌🌉🌁⌚️📱📲💻⌨️🖥🖨🖱🖲🕹🗜💽💾💿📀📼📷📸📹🎥📽🎞📞☎️📟📠📺📻🎙🎚🎛🧭⏱⏲⏰🕰⌛️⏳📡🔋🪫🔌💡🔦🕯🪔🧯🛢🛍️💸💵💴💶💷🪙💰💳💎⚖️🪮🪜🧰🪛🔧🔨⚒🛠⛏🪚🔩⚙️🪤🧱⛓⛓️‍💥🧲🔫💣🧨🪓🔪🗡⚔️🛡🚬⚰️🪦⚱️🏺🔮📿🧿🪬💈⚗️🔭🔬🕳🩹🩺🩻🩼💊💉🩸🧬🦠🧫🧪🌡🧹🪠🧺🧻🚽🚰🚿🛁🛀🧼🪥🪒🧽🪣🧴🛎🔑🗝🚪🪑🛋🛏🛌🧸🪆🖼🪞🪟🛍🛒🎁🎈🎏🎀🪄🪅🎊🎉🪩🎎🏮🎐🧧✉️📩📨📧💌📥📤📦🏷🪧📪📫📬📭📮📯📜📃📄📑🧾📊📈📉🗒🗓📆📅🗑🪪📇🗃🗳🗄📋📁📂🗂🗞📰📓📔📒📕📗📘📙📚📖🔖🧷🔗📎🖇📐📏🧮📌📍✂️🖊🖋✒️🖌🖍📝✏️🔍🔎🔏🔐🔒🔓❤️🩷🧡💛💚💙🩵💜🖤🩶🤍🤎❤️‍🔥❤️‍🩹💔❣️💕💞💓💗💖💘💝💟☮️✝️☪️🪯🕉☸️✡️🔯🕎☯️☦️🛐⛎♈️♉️♊️♋️♌️♍️♎️♏️♐️♑️♒️♓️🆔⚛️🉑☢️☣️📴📳🈶🈚️🈸🈺🈷️✴️🆚💮🉐㊙️㊗️🈴🈵🈹🈲🅰️🅱️🆎🆑🅾️🆘❌⭕️🛑⛔️📛🚫💯💢♨️🚷🚯🚳🚱🔞📵🚭❗️❕❓❔‼️⁉️🔅🔆〽️⚠️🚸🔱⚜️🔰♻️✅🈯️💹❇️✳️❎🌐💠Ⓜ️🌀💤🏧🚾♿️🅿️🛗🈳🈂️🛂🛃🛄🛅🚹🚺🚼⚧🚻🚮🎦🛜📶🈁🔣ℹ️🔤🔡🔠🆖🆗🆙🆒🆕🆓0️⃣1️⃣2️⃣3️⃣4️⃣5️⃣6️⃣7️⃣8️⃣9️⃣🔟🔢#️⃣*️⃣⏏️▶️◀️🔼🔽➡️⬅️⬆️⬇️↗️↘️↙️↖️↕️↔️↪️↩️⤴️⤵️🔀🔁🔂🔄🔃🎵🎶➕➖➗✖️🟰♾💲💱™️©️®️〰️➰➿🔚🔙🔛🔝🔜✔️☑️🔘🔴🟠🟡🟢🔵🟣⚫️⚪️🟤🔺🔻🔸🔹🔶🔷🔳🔲▪️▫️◾️◽️◼️◻️🟥🟧🟨🟩🟦🟪⬛️⬜️🟫🔈🔇🔉🔊🔔🔕📣📢👁‍🗨💬💭🗯♠️♣️♥️♦️🃏🎴🀄️🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚🕛🕜🕝🕞🕟🕠🕡🕢🕣🕤🕥🕦🕧" : "😀😃😄😁😆😅😂🤣🥲🥹☺️😊😇🙂🙃😉😌😍🥰😘😗😙😚😋😛😝😜🤪🤨🧐🤓😎🥸🤩🥳🙂‍↕️😏😒🙂‍↔️😞😔😟😕🙁☹️😣😖😫😩🥺😢😭😮‍💨😤😠😡🤬🤯😳🥵🥶😱😨😰😥😓🫣🤗🤔🫢🤭🤫🤥😶😶‍🌫️😐😑😬🫨🫠🙄😯😦😧😮😲🥱😴🤤😪😵😵‍💫🤐🥴🤢🤮🤧😷🤒🤕🤑🤠😈👿🤡👽🤖🎃👹🌞🌝🌚🌕🌖🌗🌘🌑🌒🌓🌔🌎🌍🌏🌼🌺🌸🐵🦧🪨🍏🍎🍑🫑🍞🍔🍟🍚🍘🍥🧁🍱🍩🍪🌰🥡⚽️🏀🏈⚾️🥎🎾🏐🎱🎲🏵🎹🎰🚌🚑🚛🚞🚨🚔🚍🚖🚆🗺🗾🎑🏞🌅🌄🌠🎇🎆🌇🌆🏙🌃🌌🌉🌁🏨🏪🏩🏛🏠🏚🏢🏬🏣🏤🏥🏦⌚️💻🖲💽💾💿📀🎛🧭📺📟☎️⏰🕰🩻🔮🧿🪙🛎🖼🎁📦🪩📜📄📑🧾📊📈📉🗒🗓📆📅🗄📋📰📓📔📒📕📗📘📙📚📝💟☮️✝️☪️🪯🕉☸️✡️🔯🕎☯️☦️🛐⛎♈️♉️♊️♋️♌️♍️♎️♏️♐️♑️♒️♓️🆔⚛️🉑☢️☣️📴📳🈶🈚️🈸🈺🈷️✴️🆚💮🉐㊙️㊗️🈴🈵🈹🈲🅰️🅱️🆎🆑🅾️🆘🛑⛔️🚷🚯🚳🚱🔞📵🚭✅🈯️💹❇️✳️❎🌐Ⓜ️🏧🚾♿️🅿️🛗🈳🈂️🛂🛃🛄🛅🚹🚺🚼🚻🚮🎦🛜📶🈁🔣ℹ️🔤🔡🔠🆖🆗🆙🆒🆕🆓0️⃣1️⃣2️⃣3️⃣4️⃣5️⃣6️⃣7️⃣8️⃣9️⃣🔟🔢#️⃣*️⃣⏏️▶️⏩⏪⏫⏬◀️🔼🔽➡️⬅️⬆️⬇️↗️↘️↙️↖️↕️↔️↪️↩️⤴️⤵️🔀🔁🔂🔄🔃☑️🔘🔴🟠🟡🟢🔵🟣⚫️⚪️🟤🔳🔲🟥🟧🟨🟩🟦🟪⬛️⬜️🟫🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚🕛🕜🕝🕞🕟🕠🕡🕢🕣🕤🕥🕦🕧")
    if let randomString = characters.shuffled().first { return String(randomString) }
    return "🍎"
}
