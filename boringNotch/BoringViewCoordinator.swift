//
//  BoringViewCoordinator.swift
//  boringNotch
//
//  Created by Alexander on 2024-11-20.
//

import AppKit
import Combine
import Defaults
import SwiftUI

enum SneakContentType: Equatable {
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
    case download
}

struct sneakPeek: Equatable {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
}

struct SharedSneakPeek: Codable {
    var show: Bool
    var type: String
    var value: String
    var icon: String
}

enum BrowserType: Equatable {
    case chromium
    case safari
}

struct ExpandedItem: Equatable {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
    var browser: BrowserType = .chromium
}

@MainActor
class BoringViewCoordinator: ObservableObject {
    static let shared = BoringViewCoordinator()

    @Published var currentView: NotchViews = .home
    @Published var helloAnimationRunning: Bool = false
    private var sneakPeekDispatch: DispatchWorkItem?
    private var expandingViewDispatch: DispatchWorkItem?
    private var hudEnableTask: Task<Void, Never>?

    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true
    @AppStorage("currentMicStatus") var currentMicStatus: Bool = true

    @AppStorage("alwaysShowTabs") var alwaysShowTabs: Bool = true {
        didSet {
            if !alwaysShowTabs {
                openLastTabByDefault = false
                if ShelfStateViewModel.shared.isEmpty || !Defaults[.openShelfByDefault] {
                    currentView = .home
                }
            }
        }
    }

    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {
                alwaysShowTabs = true
            }
        }
    }
    
    @Default(.hudReplacement) var hudReplacement: Bool
    
    // Legacy storage for migration
    @AppStorage("preferred_screen_name") private var legacyPreferredScreenName: String?
    
    // New UUID-based storage
    @AppStorage("preferred_screen_uuid") var preferredScreenUUID: String? {
        didSet {
            if let uuid = preferredScreenUUID {
                selectedScreenUUID = uuid
            }
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }

    @Published var selectedScreenUUID: String = NSScreen.main?.displayUUID ?? ""

    @Published var optionKeyPressed: Bool = true
    private var accessibilityObserver: Any?
    private var hudReplacementCancellable: AnyCancellable?

    private init() {
        // Perform migration from name-based to UUID-based storage
        if preferredScreenUUID == nil, let legacyName = legacyPreferredScreenName {
            // Try to find screen by name and migrate to UUID
            if let screen = NSScreen.screens.first(where: { $0.localizedName == legacyName }),
               let uuid = screen.displayUUID {
                preferredScreenUUID = uuid
                NSLog("✅ Migrated display preference from name '\(legacyName)' to UUID '\(uuid)'")
            } else {
                // Fallback to main screen if legacy screen not found
                preferredScreenUUID = NSScreen.main?.displayUUID
                NSLog("⚠️ Could not find display named '\(legacyName)', falling back to main screen")
            }
            // Clear legacy value after migration
            legacyPreferredScreenName = nil
        } else if preferredScreenUUID == nil {
            // No legacy value, use main screen
            preferredScreenUUID = NSScreen.main?.displayUUID
        }
        
        selectedScreenUUID = preferredScreenUUID ?? NSScreen.main?.displayUUID ?? ""
        // Observe changes to accessibility authorization and react accordingly
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.accessibilityAuthorizationChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if Defaults[.hudReplacement] {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
            }
        }

        // Observe changes to hudReplacement
        hudReplacementCancellable = Defaults.publisher(.hudReplacement)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self = self else { return }

                    self.hudEnableTask?.cancel()
                    self.hudEnableTask = nil

                    if change.newValue {
                        self.hudEnableTask = Task { @MainActor in
                            let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
                            if Task.isCancelled { return }

                            if granted {
                                await MediaKeyInterceptor.shared.start()
                            } else {
                                Defaults[.hudReplacement] = false
                            }
                        }
                    } else {
                        MediaKeyInterceptor.shared.stop()
                    }
                }
            }

        Task { @MainActor in
            helloAnimationRunning = firstLaunch

            if Defaults[.hudReplacement] {
                let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
                if authorized {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
            }
        }
    }
    
    // JSONDecoder / NumberFormatter 每次新建都不便宜（后者涉及 ICU 初始化），
    // 事件高频到达时复用同一份；本方法只在主线程调用，静态共享安全。
    private static let sneakPeekDecoder = JSONDecoder()
    private static let sneakPeekValueFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        return formatter
    }()

    @objc func sneakPeekEvent(_ notification: Notification) {
        if let decodedData = try? Self.sneakPeekDecoder.decode(
            SharedSneakPeek.self, from: notification.userInfo?.first?.value as! Data)
        {
            let contentType =
                decodedData.type == "brightness"
                ? SneakContentType.brightness
                : decodedData.type == "volume"
                    ? SneakContentType.volume
                    : decodedData.type == "backlight"
                        ? SneakContentType.backlight
                        : decodedData.type == "mic"
                            ? SneakContentType.mic : SneakContentType.brightness

            let value = CGFloat((Self.sneakPeekValueFormatter.number(from: decodedData.value) ?? 0.0).floatValue)
            let icon = decodedData.icon

            #if DEBUG
            print("Decoded: \(decodedData), Parsed value: \(value)")
            #endif

            toggleSneakPeek(status: decodedData.show, type: contentType, value: value, icon: icon)

        } else {
            #if DEBUG
            print("Failed to decode JSON data")
            #endif
        }
    }

    func toggleSneakPeek(
        status: Bool, type: SneakContentType, duration: TimeInterval = 1.5, value: CGFloat = 0,
        icon: String = ""
    ) {
        sneakPeekDuration = duration
        if type != .music {
            // close()
            if !Defaults[.hudReplacement] {
                return
            }
        }

        // 同值重复到达不再发布：原来逐字段赋值会触发 4 次 objectWillChange，
        // 每次都让整棵 ContentView（含已展开的 NotchHomeView、MusicLiveActivity）
        // 重算 body；14 条通知连发时就是 14 次整树重算。只重计时隐藏。
        let newValue = sneakPeek(show: status, type: type, value: value, icon: icon)
        if newValue == sneakPeek {
            if status {
                scheduleSneakPeekHide(after: duration)
            } else {
                sneakPeekTask?.cancel()
            }
            updateMicStatusIfNeeded(type: type, value: value)
            return
        }

        // 本类已是 @MainActor，调用方也都在主线程（音量/亮度管理器、
        // MediaKeyInterceptor、MusicManager 的 @MainActor 路径、电池主线程回调），
        // 不再经 Task { @MainActor in } 跳一次：原来每个事件都新建一个 Task，
        // 14 条通知就是 14 个任务 + 14 次独立动画事务。整 struct 一次赋值，
        // 只触发一次 objectWillChange。
        withAnimation(.smooth) {
            sneakPeek = newValue
        }
        updateMicStatusIfNeeded(type: type, value: value)
    }

    /// 只有值真的变了才写 @AppStorage，避免同值重复写触发无关观察者。
    private func updateMicStatusIfNeeded(type: SneakContentType, value: CGFloat) {
        guard type == .mic else { return }
        let muted = value == 1
        if currentMicStatus != muted {
            currentMicStatus = muted
        }
    }

    private var sneakPeekDuration: TimeInterval = 1.5
    private var sneakPeekTask: Task<Void, Never>?

    // Helper function to manage sneakPeek timer using Swift Concurrency
    private func scheduleSneakPeekHide(after duration: TimeInterval) {
        sneakPeekTask?.cancel()

        sneakPeekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    self.toggleSneakPeek(status: false, type: .music)
                    self.sneakPeekDuration = 1.5
                }
            }
        }
    }

    @Published var sneakPeek: sneakPeek = .init() {
        didSet {
            if sneakPeek.show {
                scheduleSneakPeekHide(after: sneakPeekDuration)
            } else {
                sneakPeekTask?.cancel()
            }
        }
    }

    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0,
        browser: BrowserType = .chromium
    ) {
        // 同 toggleSneakPeek：同值重复到达不再整 struct 重发。
        // 电池一次插拔会扇出多条事件（电源/充电/低电量），靠这里合并成一次有效更新。
        let newValue = ExpandedItem(show: status, type: type, value: value, browser: browser)
        if newValue == expandingView {
            // 值未变：不重复发布，但仍按原语义重计时隐藏。
            scheduleExpandingViewHideIfNeeded()
            return
        }
        withAnimation(.smooth) {
            expandingView = newValue
        }
    }

    private var expandingViewTask: Task<Void, Never>?

    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            scheduleExpandingViewHideIfNeeded()
        }
    }

    /// 展开态显示时重计时自动收起；收起时取消待收起任务。
    /// 从 didSet 抽出，供同值重复调用复用（只重计时、不重复发布）。
    private func scheduleExpandingViewHideIfNeeded() {
        if expandingView.show {
            expandingViewTask?.cancel()
            let duration: TimeInterval = (expandingView.type == .download ? 2 : 3)
            let currentType = expandingView.type
            expandingViewTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard let self = self, !Task.isCancelled else { return }
                self.toggleExpandingView(status: false, type: currentType)
            }
        } else {
            expandingViewTask?.cancel()
        }
    }
    
    func showEmpty() {
        currentView = .home
    }
}
