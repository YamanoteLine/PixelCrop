//
//  CropWorkspace.swift
//  PixelCrop
//
//  剪裁工作区：
//  - 画布占满
//  - 右侧检查器作为浮层（Liquid Glass 风格）
//  - 拖入新图自动追加到队列
//

import SwiftUI

struct CropWorkspace: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack(alignment: .trailing) {
            // 画布占满
            if let id = state.activeTabID {
                CropCanvas(tabID: id)
            }

            // 右侧浮层检查器：宽度压缩，高度适应内容
            CropInspector()
                .frame(width: 150)
                .fixedSize(horizontal: false, vertical: true)  // 高度适应内容
                .nativeLiquidGlassPanel(cornerRadius: 18)
                .padding(.trailing, 16)
        }
        .onDrop(of: [.fileURL], delegate: ImageDropDelegate(onOpen: { url in
            state.openImage(url: url)
        }))
    }
}
