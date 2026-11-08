//
//  ImageLoader.swift
//  PixelCrop
//
//  图像加载服务 —— 整个 App 内存占用的核心控制点。
//
//  策略（在 Apple Silicon / macOS 26 上）：
//  1. 永远不把原图全像素加载到内存。用 `CGImageSourceCreateThumbnailAtIndex`
//     按当前视图尺寸降采样。
//  2. 加载只保留 `CGImageSource`（仅文件描述符 + 解码缓存），不保留全像素 CGImage。
//  3. 显示用的 CGImage 是「视图级」临时对象，离开当前视图即释放。
//  4. 导出时用 ImageIO 流式写入，不通过 CGImage 全像素中转。
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 一个被打开的图像。轻量：只持 source + 原图尺寸元信息。
final class LoadedImage: Identifiable, Equatable, @unchecked Sendable {
    let id = UUID()
    let url: URL
    let source: CGImageSource
    /// 原图像素尺寸（未应用 EXIF 方向）。
    let pixelSize: CGSize
    /// 显示尺寸（应用 EXIF 方向后）。若 EXIF orientation 旋转 90°/270°，宽高互换。
    let displaySize: CGSize
    let utType: UTType
    let displayName: String

    init(url: URL,
         source: CGImageSource,
         pixelSize: CGSize,
         displaySize: CGSize,
         utType: UTType,
         displayName: String) {
        self.url = url
        self.source = source
        self.pixelSize = pixelSize
        self.displaySize = displaySize
        self.utType = utType
        self.displayName = displayName
    }

    static func == (lhs: LoadedImage, rhs: LoadedImage) -> Bool { lhs.id == rhs.id }

    /// 按需生成一个适合 `targetSize` 显示的 CGImage。
    /// 不会一次性把原图全像素加载进内存。
    func makeDisplayCGImage(maxDimension: CGFloat) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCache: false,                 // 关键：不缓存全像素
            kCGImageSourceCreateThumbnailWithTransform: true, // 应用 EXIF 方向
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
    }

    /// 生成原图全像素 CGImage（已应用 EXIF 方向）。**仅在导出时调用**。
    /// 用 Thumbnail API + 大 maxPixelSize 来确保 orientation 被 bake in。
    func makeFullResolutionCGImage() -> CGImage? {
        // 用 Thumbnail API 是因为只有它支持 kCGImageSourceCreateThumbnailWithTransform
        // （应用 EXIF orientation）。maxPixelSize 设大值确保不降采样。
        let maxDim = max(pixelSize.width, pixelSize.height)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
    }

    /// 从剪裁区域生成最终 CGImage（直接在原图分辨率上剪裁，不降采样）。
    /// 仅在导出路径上使用。
    func makeCroppedCGImage(rect: CGRect) -> CGImage? {
        guard let full = makeFullResolutionCGImage() else { return nil }
        // 裁剪到整数边界，避免亚像素伪影。
        let r = CGRect(x: floor(rect.minX),
                       y: floor(rect.minY),
                       width: floor(rect.width),
                       height: floor(rect.height))
        guard r.width > 0, r.height > 0,
              r.minX >= 0, r.minY >= 0,
              r.maxX <= CGFloat(full.width), r.maxY <= CGFloat(full.height) else {
            return full
        }
        return full.cropping(to: r)
    }
}

enum ImageLoaderError: LocalizedError {
    case unsupportedFormat
    case cannotOpen
    case noPixels

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "不支持的图像格式"
        case .cannotOpen:        return "无法打开图像"
        case .noPixels:          return "图像为空"
        }
    }
}

enum ImageLoader {
    /// 打开一个图像文件，构造轻量的 `LoadedImage`。
    /// 失败时返回错误，不会让 App 崩溃。
    static func open(_ url: URL) throws -> LoadedImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageLoaderError.cannotOpen
        }
        let typeID = CGImageSourceGetType(src) as String?
        let utType = (typeID.flatMap { UTType($0) }) ?? .image

        // 读取原图尺寸 + EXIF orientation（不加载像素数据）。
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else {
            throw ImageLoaderError.noPixels
        }

        // EXIF orientation: 1=正常, 3=180°, 6=90° CW, 8=270° CW
        // 5,7 = 镜像 + 旋转。其中 5,6,7,8 会让宽高互换。
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let displaySize: CGSize
        if orientation == 5 || orientation == 6 || orientation == 7 || orientation == 8 {
            // 宽高互换
            displaySize = CGSize(width: h, height: w)
        } else {
            displaySize = CGSize(width: w, height: h)
        }

        return LoadedImage(url: url,
                           source: src,
                           pixelSize: CGSize(width: w, height: h),
                           displaySize: displaySize,
                           utType: utType,
                           displayName: url.lastPathComponent)
    }
}
