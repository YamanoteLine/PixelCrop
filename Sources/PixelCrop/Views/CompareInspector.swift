//
//  CompareInspector.swift
//  PixelCrop
//
//  对比模式右侧检查器：
//  - 展示底图 + 当前选中对比图信息
//  - 操作说明
//

import SwiftUI

struct CompareInspector: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 对比图像信息
            InfoCard(title: "对比图像") {
                if let base = state.baseTab {
                    VStack(alignment: .leading, spacing: 10) {
                        // 底图
                        VStack(alignment: .leading, spacing: 4) {
                            Text("底图（下层）")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            imageRow(tab: base)
                        }

                        Divider()

                        // 对比图
                        if let active = state.activeTab,
                           active.id != base.id {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("对比图（上层）")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                imageRow(tab: active)
                            }
                        } else {
                            Text("当前选中的是底图。从左侧列表选择其他图作为对比图。")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            // 操作说明
            InfoCard(title: "操作说明") {
                VStack(alignment: .leading, spacing: 6) {
                    Bullet(text: "底图恒为第一张打开的图")
                    Bullet(text: "点击列表中其他图 → 与底图对比")
                    Bullet(text: "单张图可拖动定位、双指缩放")
                    Divider().frame(width: 60).padding(.vertical, 4)
                    if state.mode == .compare {
                        Bullet(text: "隐藏显现：按住底部按钮显示底图")
                        Bullet(text: "拖动浮现：拖分隔线左右对比")
                    }
                }
            }

            // 图像队列（紧凑列表）
            if state.tabs.count > 1 {
                InfoCard(title: "图像队列 (\(state.tabs.count))") {
                    VStack(spacing: 6) {
                        ForEach(Array(state.tabs.enumerated()), id: \.element.id) { idx, tab in
                            HStack(spacing: 8) {
                                Text("\(idx + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                ThumbnailView(loaded: tab.loaded, size: 24)
                                    .frame(width: 24, height: 24)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                Text(tab.loaded.displayName)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                if idx == 0 {
                                    Text("底")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            Spacer()
        }
    }

    private func imageRow(tab: ImageTab) -> some View {
        HStack(spacing: 8) {
            ThumbnailView(loaded: tab.loaded, size: 36)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.loaded.displayName)
                    .font(.callout)
                    .lineLimit(1)
                Text("\(Int(tab.loaded.displaySize.width)) × \(Int(tab.loaded.displaySize.height))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct Bullet: View {
    let text: String
    init(text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }
}
