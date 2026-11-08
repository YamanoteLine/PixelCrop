//
//  CompareWorkspace.swift
//  PixelCrop
//
//  对比工作区：
//  - 底图（tabs[0]）恒定
//  - 通过侧栏/标签页选择"对比图"，叠在底图之上
//  - 隐藏显现式 / 拖动浮现式 两种对比
//  - 布局：侧栏 / 标签页 可选
//

import SwiftUI

struct CompareWorkspace: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 对比画布占满
            CompareCanvas()

            // 左侧浮层：图像列表（高度适应内容）
            if state.layout == .sidebar {
                SidebarColumn()
                    .frame(width: 220)
                    .fixedSize(horizontal: false, vertical: true)  // 高度适应内容
                    .nativeLiquidGlassPanel(cornerRadius: 18)
                    .transaction { $0.animation = nil }
                    .padding(.leading, 16)
                    .padding(.top, 12)
            }

            // 标签页模式：顶部 TabBar 浮层
            if state.layout == .tabs {
                VStack {
                    TabBar()
                        .frame(width: min(760, max(240, CGFloat(state.tabs.count) * 205 + 36)))
                        .fixedSize(horizontal: false, vertical: true)
                        .nativeLiquidGlassPanel(cornerRadius: 18)
                        .transaction { $0.animation = nil }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    Spacer()
                }
            }
        }
        .onDrop(of: [.fileURL], delegate: ImageDropDelegate(onOpen: { url in
            state.openImage(url: url)
        }))
    }
}

// MARK: - 侧栏

struct SidebarColumn: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            // 图像列表
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(state.tabs) { tab in
                        SidebarRow(tab: tab,
                                   isActive: tab.id == state.activeTabID,
                                   isBase: tab.id == state.baseTabID,
                                   onSetBase: { state.setBase(tabID: tab.id) },
                                   onSelect: { state.activeTabID = tab.id },
                                   onHoldChange: { held in
                                       if held, tab.id == state.activeTabID,
                                          tab.id != state.baseTabID {
                                           CompareHoldState.shared.holdActive = true
                                       } else if !held {
                                           CompareHoldState.shared.holdActive = false
                                       }
                                   })
                        .contextMenu {
                            if tab.id != state.baseTabID {
                                Button("设为底图") { state.setBase(tabID: tab.id) }
                            }
                            Button("关闭", role: .destructive) {
                                state.closeTab(id: tab.id)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 8)
            }

            // 底部：清空按钮（统一 padding，视觉协调）
            HStack {
                Spacer()
                Button(role: .destructive) {
                    for tab in state.tabs {
                        if let temp = tab.tempURL {
                            try? FileManager.default.removeItem(at: temp)
                        }
                    }
                    state.tabs.removeAll()
                    state.undoStacks.removeAll()
                    state.activeTabID = nil
                    state.baseTabID = nil
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("清空全部")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .padding(.top, 6)
        }
    }
}

struct SidebarRow: View {
    let tab: ImageTab
    let isActive: Bool
    let isBase: Bool
    var onSetBase: (() -> Void)? = nil
    var onSelect: (() -> Void)? = nil
    var onHoldChange: ((Bool) -> Void)? = nil

    @State private var isPressed: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailView(loaded: tab.loaded, size: 40)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isBase {
                        Text("底图")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(tab.loaded.displayName)
                        .font(.callout)
                        .lineLimit(1)
                }
                Text("\(Int(tab.loaded.displaySize.width)) × \(Int(tab.loaded.displaySize.height))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if !isBase {
                Button {
                    onSetBase?()
                } label: {
                    Image(systemName: "square.dashed")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("设为底图")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive && !isBase
                      ? AnyShapeStyle(Color.accentColor.opacity(0.15))
                      : AnyShapeStyle(Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isPressed ? Color.accentColor.opacity(0.4) : Color.clear,
                              lineWidth: 1)
        )
        .contentShape(Rectangle())
        // 鼠标按下 → 触发 hold；松开 → 取消 hold + 选中
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        onHoldChange?(true)
                    }
                }
                .onEnded { v in
                    isPressed = false
                    onHoldChange?(false)
                    // 拖动距离很短算作点击
                    if abs(v.translation.width) < 5 && abs(v.translation.height) < 5 {
                        onSelect?()
                    }
                }
        )
        .onTapGesture(count: 2) {
            if !isBase { onSetBase?() }
        }
    }
}

// MARK: - 标签页栏

struct TabBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(state.tabs) { tab in
                    TabChip(tab: tab,
                            active: tab.id == state.activeTabID,
                            isBase: tab.id == state.baseTabID,
                            onSelect: { state.activeTabID = tab.id },
                            onHoldChange: { held in
                                if held, tab.id == state.activeTabID,
                                   tab.id != state.baseTabID {
                                    CompareHoldState.shared.holdActive = true
                                } else if !held {
                                    CompareHoldState.shared.holdActive = false
                                }
                            })
                        .contextMenu {
                            if tab.id != state.baseTabID {
                                Button("设为底图") { state.setBase(tabID: tab.id) }
                            }
                            Button("关闭", role: .destructive) {
                                state.closeTab(id: tab.id)
                            }
                        }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }
}

struct TabChip: View {
    let tab: ImageTab
    let active: Bool
    let isBase: Bool
    var onSelect: (() -> Void)? = nil
    var onHoldChange: ((Bool) -> Void)? = nil
    @Environment(AppState.self) private var state
    @State private var isPressed: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            ThumbnailView(loaded: tab.loaded, size: 38)
                .id(tab.loaded.id)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.loaded.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text("\(Int(tab.loaded.displaySize.width)) × \(Int(tab.loaded.displaySize.height))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if isBase {
                        Text("底图")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .frame(width: 118, alignment: .leading)

            Button {
                state.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .opacity(active ? 1 : 0.5)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(active
                      ? AnyShapeStyle(Color.accentColor.opacity(0.15))
                      : AnyShapeStyle(Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isPressed ? Color.accentColor.opacity(0.4) : Color.clear,
                              lineWidth: 1)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        onHoldChange?(true)
                    }
                }
                .onEnded { v in
                    isPressed = false
                    onHoldChange?(false)
                    if abs(v.translation.width) < 5 && abs(v.translation.height) < 5 {
                        onSelect?()
                    }
                }
        )
    }
}
