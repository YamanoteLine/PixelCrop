//
//  UndoStack.swift
//  PixelCrop
//
//  轻量撤销栈。仅会话内有效，关闭即清空。最多 10 步。
//

import Foundation

/// 通用的撤销/重做栈。`T` 必须是值类型。
struct UndoStack<T: Equatable>: Sendable where T: Sendable {
    private(set) var undo: [T] = []
    private(set) var redo: [T] = []
    let maxDepth: Int

    init(maxDepth: Int = 10) { self.maxDepth = maxDepth }

    var canUndo: Bool { !undo.isEmpty }
    var canRedo: Bool { !redo.isEmpty }

    /// 提交一个新状态。`current` 是当前状态（会被推入 undo 栈）。
    mutating func commit(current: T) {
        undo.append(current)
        if undo.count > maxDepth { undo.removeFirst() }
        redo.removeAll()
    }

    /// 撤销。返回撤销后的状态。调用方需把视图状态设置为返回值。
    mutating func undo(current: T) -> T? {
        guard let prev = undo.popLast() else { return nil }
        redo.append(current)
        return prev
    }

    /// 重做。
    mutating func redo(current: T) -> T? {
        guard let next = redo.popLast() else { return nil }
        undo.append(current)
        return next
    }

    mutating func clear() {
        undo.removeAll()
        redo.removeAll()
    }
}
