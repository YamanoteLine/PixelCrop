//
//  ThumbnailView.swift
//  PixelCrop
//
//  缩略图：仅生成适合显示尺寸的降采样 CGImage，避免内存爆炸。
//

import SwiftUI
import CoreGraphics

struct ThumbnailView: View {
    let loaded: LoadedImage
    let size: CGFloat

    @State private var cgImage: CGImage?

    var body: some View {
        Group {
            if let cg = cgImage {
                Image(decorative: cg, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.gray.opacity(0.15))
            }
        }
        .task(id: size) {
            // 仅生成「size × 2」像素的缩略图，按 Retina 屏幕考虑。
            let dim = max(size * 2, 24)
            cgImage = loaded.makeDisplayCGImage(maxDimension: dim)
        }
    }
}

/// 一个全画布尺寸的显示视图。会在视图尺寸变化时重新降采样。
struct DisplayImageView: View {
    let loaded: LoadedImage
    @State private var cgImage: CGImage?
    @State private var displaySize: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let cg = cgImage {
                    Image(decorative: cg, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                }
            }
            .onAppear { displaySize = proxy.size; regenerate() }
            .onChange(of: proxy.size) { _, new in
                if abs(new.width - displaySize.width) > 32
                    || abs(new.height - displaySize.height) > 32 {
                    displaySize = new
                    regenerate()
                }
            }
        }
        .task(id: loaded.id) { regenerate() }
    }

    private func regenerate() {
        // 取视图最长边的 2 倍作为降采样目标（Retina），并封顶以保护内存。
        let dim = min(max(displaySize.width, displaySize.height) * 2, 4096)
        cgImage = loaded.makeDisplayCGImage(maxDimension: dim)
    }
}
