import SwiftUI
import AppKit

@main
struct SubZeroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(AppSettings.shared)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var dashboardWindow: NSWindow?
    private var settingsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Firestore telemetry only; Firebase Auth is intentionally never started
        // because local macOS signing cannot access its Keychain credentials.
        FirebaseManager.shared.configure()
        _ = SensorManager.shared
        StandManager.shared.start()
        
        let controller = MenuBarController()
        controller.onOpenDashboard = { [weak self] in
            self?.showDashboardWindow()
        }
        controller.onOpenSettings = { [weak self] in
            self?.showSettingsWindow()
        }
        self.menuBarController = controller
    }
    
    func showDashboardWindow() {
        if let window = dashboardWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let dashboardView = DashboardView()
            .environmentObject(SensorManager.shared)
            .environmentObject(AppSettings.shared)
            .environmentObject(HistoryStore.shared)
        
        let hostingController = NSHostingController(rootView: dashboardView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dashboard"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 800, height: 550)
        
        self.dashboardWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func showSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsView()
            .environmentObject(AppSettings.shared)
        
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
