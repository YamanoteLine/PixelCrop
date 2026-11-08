//
//  CropRatio.swift
//  PixelCrop
//
//  Created by Mai on 2026/8/8.
//

import Foundation
import CoreGraphics

/// 预设剪裁比例。`aspectRatio` = width / height。
struct CropRatio: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let width: Int
    let height: Int

    var aspectRatio: CGFloat { CGFloat(width) / CGFloat(height) }

    /// 用户预设比例。单列从宽到窄，1:1 在最上方。
    /// 顺序：1:1 → 横版（aspect 从大到小）→ 竖版（aspect 从大到小）。
    static let presets: [CropRatio] = [
        .init(id: "1:1",   displayName: "1:1",   width: 1,  height: 1),
        .init(id: "21:9",  displayName: "21:9",  width: 21, height: 9),
        .init(id: "16:9",  displayName: "16:9",  width: 16, height: 9),
        .init(id: "3:2",   displayName: "3:2",   width: 3,  height: 2),
        .init(id: "4:3",   displayName: "4:3",   width: 4,  height: 3),
        .init(id: "3:4",   displayName: "3:4",   width: 3,  height: 4),
        .init(id: "2:3",   displayName: "2:3",   width: 2,  height: 3),
        .init(id: "9:16",  displayName: "9:16",  width: 9,  height: 16),
        .init(id: "9:21",  displayName: "9:21",  width: 9,  height: 21)
    ]
}
