//
//  ImageExporter.swift
//  PixelCrop
//
//  导出系统：JPEG / PNG / HEIC / WebP，全部丢弃元数据。
//
//  内存策略：
//  - 不在内存里持有完整未压缩位图。
//  - 用 ImageIO 的 `CGImageDestination` 流式写入。
//  - 元数据通过 `kCFNull` 显式丢弃（用户的偏好：全部丢弃）。
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct ExportOptions: Sendable {
    var format: ImageFormat
    /// 0.0 ~ 1.0，仅对有损格式有效。
    var quality: CGFloat
    /// 是否丢弃全部元数据。用户偏好固定为 true。
    var stripMetadata: Bool = true
    /// 缩放比例：1.0 = 原尺寸，0.5 = 缩小到 50%。
    var scale: CGFloat = 1.0

    static let `default` = ExportOptions(format: .jpeg, quality: 0.85)
}

enum ExportError: LocalizedError {
    case noSource
    case cannotCreateDestination
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .noSource:               return "没有可导出的图像"
        case .cannotCreateDestination: return "无法创建导出文件"
        case .writeFailed:            return "写入失败"
        }
    }
}

enum ImageExporter {
    /// 把 `loaded` 完整导出为 `options` 指定的格式。
    /// 「所见即所得」：调用方传入的 `loaded` 已经是应用过剪裁后的图。
    static func export(_ loaded: LoadedImage,
                       options: ExportOptions,
                       to destinationURL: URL) throws {
        guard let fullCG = loaded.makeFullResolutionCGImage() else {
            throw ExportError.noSource
        }

        // 如果缩放比例不为 1，先缩放图像
        let finalCG: CGImage
        if abs(options.scale - 1.0) > 0.001 {
            guard let scaled = scaleCGImage(fullCG, by: options.scale) else {
                throw ExportError.writeFailed
            }
            finalCG = scaled
        } else {
            finalCG = fullCG
        }

        // 删除已存在文件
        try? FileManager.default.removeItem(at: destinationURL)

        // 用 Data 中转再写文件，比直接 URL 更稳定（避免 sandbox 权限问题）
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            options.format.utType,
            1,
            nil
        ) else {
            throw ExportError.cannotCreateDestination
        }

        // 属性字典：最小化，避免某些键让 finalize 失败
        var props: [CFString: Any] = [:]
        if options.format.supportsQuality {
            props[kCGImageDestinationLossyCompressionQuality] = options.quality
        }

        CGImageDestinationAddImage(dest, finalCG, props as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw ExportError.writeFailed
        }

        // 写入文件
        do {
            try (data as Data).write(to: destinationURL, options: .atomic)
        } catch {
            throw ExportError.writeFailed
        }
    }

    /// 用 Core Graphics 缩放 CGImage。
    /// 返回新尺寸的 CGImage（保持原色彩空间）。
    private static func scaleCGImage(_ image: CGImage, by scale: CGFloat) -> CGImage? {
        let newW = max(1, Int(CGFloat(image.width) * scale))
        let newH = max(1, Int(CGFloat(image.height) * scale))

        guard let cs = image.colorSpace,
              let ctx = CGContext(
                data: nil,
                width: newW,
                height: newH,
                bitsPerComponent: image.bitsPerComponent,
                bytesPerRow: 0,
                space: cs,
                bitmapInfo: image.bitmapInfo.rawValue
              ) else {
            // 退路：用 device RGB
            guard let ctx2 = CGContext(
                data: nil, width: newW, height: newH,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx2.interpolationQuality = .high
            ctx2.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
            return ctx2.makeImage()
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage()
    }

    /// 生成一个默认的导出文件名。
    static func suggestedFilename(originalName: String,
                                  format: ImageFormat,
                                  imageSize: CGSize,
                                  scale: CGFloat = 1.0) -> String {
        let base = (originalName as NSString).deletingPathExtension
        let actualW = Int(imageSize.width * scale)
        let actualH = Int(imageSize.height * scale)
        let mp = PixelCalculator.megapixels(width: actualW, height: actualH)
        let mpStr = mp == mp.rounded() ? "\(Int(mp))mp" : String(format: "%.1fmp", mp)
        return "\(base)-\(mpStr).\(format.fileExtension)"
    }
}
