//
//  PixelCropApp.swift
//  PixelCrop
//
//  App 入口。Apple Silicon 专属、macOS 26+。
//

import SwiftUI
import AppKit

@main
struct PixelCropApp: App {
    private let appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .frame(minWidth: 1000, minHeight: 660)
                .background(.windowBackground)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开图像…") { openPanel() }
                    .keyboardShortcut("o")
            }
            // 替代系统默认的「编辑 → 撤销/重做」菜单
            CommandGroup(replacing: .undoRedo) {
                Button("撤销剪裁") { undoAction() }
                    .keyboardShortcut("z")
                    .disabled(!canUndo)
                Button("重做剪裁") { redoAction() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!canRedo)
            }
        }
    }

    @MainActor
    private var canUndo: Bool {
        appState.activeTabID.map { appState.canUndoApply($0) } ?? false
    }
    @MainActor
    private var canRedo: Bool {
        appState.activeTabID.map { appState.canRedoApply($0) } ?? false
    }

    @MainActor
    private func undoAction() {
        if let id = appState.activeTabID { appState.undoApply(tabID: id) }
    }
    @MainActor
    private func redoAction() {
        if let id = appState.activeTabID { appState.redoApply(tabID: id) }
    }

    @MainActor
    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ImageFormat.openableTypes
        if panel.runModal() == .OK {
            for url in panel.urls {
                appState.openImage(url: url)
            }
        }
    }
}
