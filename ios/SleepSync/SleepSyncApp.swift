import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { @MainActor in
            await SleepExporter.shared.resumeBackgroundObservation()
        }
        return true
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        Task { @MainActor in
            await SleepExporter.shared.export(reason: "device unlocked")
        }
    }
}

@main
struct SleepSyncApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var exporter = SleepExporter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(exporter)
                .task {
                    await exporter.requestAuthorizationAndExport()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await exporter.export(reason: "app became active")
            }
        }
    }
}
