import SwiftUI
import AppKit

// MARK: - 引用类型节点
// NSOutlineView 以对象标识(===)持有 item，必须用 class 而非 struct。

final class KeyOutlineNode {
    let name: String
    let path: String
    let item: KeyValueItem?
    var children: [KeyOutlineNode]

    var isLeaf: Bool { item != nil }

    init(name: String, path: String, item: KeyValueItem? = nil, children: [KeyOutlineNode] = []) {
        self.name = name
        self.path = path
        self.item = item
        self.children = children
    }
}

// MARK: - 从 KeyValueItem 构建树

enum KeyOutlineBuilder {
    static func build(items: [KeyValueItem]) -> [KeyOutlineNode] {
        let root = Mutable(name: "", path: "")
        for item in items.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }) {
            let parts = item.key.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            let normalized = parts.isEmpty ? [item.key] : parts
            root.insert(parts: normalized, fullKey: item.key, item: item)
        }
        return root.children.map { $0.freeze() }.sorted(by: Mutable.order)
    }

    private final class Mutable {
        let name: String
        let path: String
        var item: KeyValueItem?
        var children: [Mutable] = []

        init(name: String, path: String, item: KeyValueItem? = nil) {
            self.name = name
            self.path = path
            self.item = item
        }

        func insert(parts: [String], fullKey: String, item: KeyValueItem) {
            guard let head = parts.first else { return }
            if parts.count == 1 {
                if let existing = children.first(where: { $0.name == head && $0.path == fullKey }) {
                    existing.item = item
                } else {
                    children.append(Mutable(name: head, path: fullKey, item: item))
                }
                return
            }
            let childPath = path.isEmpty ? head : "\(path)/\(head)"
            let child: Mutable
            if let existing = children.first(where: { $0.name == head && $0.item == nil }) {
                child = existing
            } else {
                child = Mutable(name: head, path: childPath)
                children.append(child)
            }
            child.insert(parts: Array(parts.dropFirst()), fullKey: fullKey, item: item)
        }

        func freeze() -> KeyOutlineNode {
            KeyOutlineNode(
                name: name,
                path: path,
                item: item,
                children: children.map { $0.freeze() }.sorted(by: KeyOutlineBuilder.frozenOrder)
            )
        }

        static func order(_ lhs: KeyOutlineNode, _ rhs: KeyOutlineNode) -> Bool {
            KeyOutlineBuilder.frozenOrder(lhs, rhs)
        }
    }

    static func frozenOrder(_ lhs: KeyOutlineNode, _ rhs: KeyOutlineNode) -> Bool {
        if lhs.isLeaf != rhs.isLeaf {
            return !lhs.isLeaf // 文件夹在前
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

// MARK: - NSViewRepresentable 封装

struct KeyOutlineView: NSViewRepresentable {
    var nodes: [KeyOutlineNode]
    var selectedKey: String?
    /// 搜索状态：为 true 时默认展开全部目录，方便直接看到匹配结果。
    var expandAll: Bool = false
    var onSelect: (String) -> Void
    var onCopy: (String) -> Void
    var onCopyValue: (KeyValueItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onCopy: onCopy, onCopyValue: onCopyValue)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.headerView = nil
        outline.rowSizeStyle = .default
        outline.indentationPerLevel = 14
        outline.autoresizesOutlineColumn = false
        outline.usesAlternatingRowBackgroundColors = false
        outline.allowsEmptySelection = true
        outline.allowsMultipleSelection = false
        outline.focusRingType = .none
        if #available(macOS 11.0, *) {
            outline.style = .sourceList
        } else {
            outline.selectionHighlightStyle = .sourceList
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("key"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column

        let menu = NSMenu()
        menu.delegate = context.coordinator
        let copyKeyItem = NSMenuItem(title: "复制键", action: #selector(Coordinator.copyKey(_:)), keyEquivalent: "")
        copyKeyItem.target = context.coordinator
        menu.addItem(copyKeyItem)
        let copyValueItem = NSMenuItem(title: "复制值", action: #selector(Coordinator.copyValue(_:)), keyEquivalent: "")
        copyValueItem.target = context.coordinator
        menu.addItem(copyValueItem)
        outline.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        context.coordinator.outlineView = outline
        context.coordinator.apply(nodes: nodes, selectedKey: selectedKey, expandAll: expandAll, initial: true)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.onCopy = onCopy
        context.coordinator.onCopyValue = onCopyValue
        context.coordinator.apply(nodes: nodes, selectedKey: selectedKey, expandAll: expandAll, initial: false)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        weak var outlineView: NSOutlineView?
        var onSelect: (String) -> Void
        var onCopy: (String) -> Void
        var onCopyValue: (KeyValueItem) -> Void

        private var roots: [KeyOutlineNode] = []
        private var signature: String = ""
        private var isApplyingSelection = false
        private var didExpandAll = false

        init(
            onSelect: @escaping (String) -> Void,
            onCopy: @escaping (String) -> Void,
            onCopyValue: @escaping (KeyValueItem) -> Void
        ) {
            self.onSelect = onSelect
            self.onCopy = onCopy
            self.onCopyValue = onCopyValue
        }

        /// 仅在树结构变化时 reloadData，避免打断 NSOutlineView 自带的展开动画。
        /// expandAll 为 true 时（如搜索中）展开全部目录；从 true 切回 false 时恢复折叠默认态。
        func apply(nodes: [KeyOutlineNode], selectedKey: String?, expandAll: Bool, initial: Bool) {
            guard let outline = outlineView else { return }
            let newSignature = Self.signature(of: nodes)
            let structureChanged = newSignature != signature

            if structureChanged {
                // 记录已展开路径，reload 后恢复
                let expanded = expandedPaths()
                roots = nodes
                signature = newSignature
                outline.reloadData()
                if expandAll {
                    outline.expandItem(nil, expandChildren: true)
                } else {
                    restoreExpanded(expanded)
                }
                didExpandAll = expandAll
            } else if expandAll != didExpandAll {
                // 结构未变但搜索态切换：展开全部 / 折叠全部
                if expandAll {
                    outline.expandItem(nil, expandChildren: true)
                } else {
                    outline.collapseItem(nil, collapseChildren: true)
                }
                didExpandAll = expandAll
            }

            syncSelection(to: selectedKey)
        }

        private func syncSelection(to selectedKey: String?) {
            guard let outline = outlineView else { return }
            guard let key = selectedKey, let node = findNode(path: key, in: roots) else {
                if selectedKey == nil {
                    isApplyingSelection = true
                    outline.deselectAll(nil)
                    isApplyingSelection = false
                }
                return
            }
            let row = outline.row(forItem: node)
            if row >= 0, outline.selectedRow != row {
                isApplyingSelection = true
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                isApplyingSelection = false
            }
        }

        // MARK: 展开状态保持

        private func expandedPaths() -> Set<String> {
            guard let outline = outlineView else { return [] }
            var result = Set<String>()
            for row in 0..<outline.numberOfRows {
                if let node = outline.item(atRow: row) as? KeyOutlineNode,
                   outline.isItemExpanded(node) {
                    result.insert(node.path)
                }
            }
            return result
        }

        private func restoreExpanded(_ paths: Set<String>) {
            guard let outline = outlineView, !paths.isEmpty else { return }
            func walk(_ nodes: [KeyOutlineNode]) {
                for node in nodes where !node.isLeaf {
                    if paths.contains(node.path) {
                        outline.expandItem(node)
                    }
                    walk(node.children)
                }
            }
            walk(roots)
        }

        private func findNode(path: String, in nodes: [KeyOutlineNode]) -> KeyOutlineNode? {
            for node in nodes {
                if node.path == path { return node }
                if let found = findNode(path: path, in: node.children) { return found }
            }
            return nil
        }

        private static func signature(of nodes: [KeyOutlineNode]) -> String {
            var parts: [String] = []
            func walk(_ nodes: [KeyOutlineNode]) {
                for node in nodes {
                    parts.append(node.isLeaf ? "f:\(node.path)" : "d:\(node.path)")
                    walk(node.children)
                }
            }
            walk(nodes)
            return parts.joined(separator: "\n")
        }

        // MARK: NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let node = item as? KeyOutlineNode else { return roots.count }
            return node.children.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let node = item as? KeyOutlineNode else { return roots[index] }
            return node.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? KeyOutlineNode else { return false }
            return !node.isLeaf
        }

        // MARK: NSOutlineViewDelegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? KeyOutlineNode else { return nil }
            let id = NSUserInterfaceItemIdentifier("KeyCell")
            let cell: KeyCellView
            if let reused = outlineView.makeView(withIdentifier: id, owner: self) as? KeyCellView {
                cell = reused
            } else {
                cell = KeyCellView()
                cell.identifier = id
            }
            cell.configure(with: node)
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection, let outline = outlineView else { return }
            let row = outline.selectedRow
            guard row >= 0, let node = outline.item(atRow: row) as? KeyOutlineNode else { return }
            if node.isLeaf {
                onSelect(node.path)
            }
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            // 文件夹行不进入选中态（点击仅展开/折叠）
            guard let node = item as? KeyOutlineNode else { return false }
            return node.isLeaf
        }

        // MARK: 右键菜单

        /// 右键时根据点击行的类型启用菜单项：复制键对任意有路径的行可用，
        /// 复制值仅对叶子节点（真正持有值的键）可用。
        func menuNeedsUpdate(_ menu: NSMenu) {
            guard let outline = outlineView, let node = targetNode() else {
                menu.items.forEach { $0.isEnabled = false }
                return
            }
            _ = outline
            for item in menu.items {
                switch item.action {
                case #selector(copyKey(_:)):
                    item.isEnabled = !node.path.isEmpty
                case #selector(copyValue(_:)):
                    item.isEnabled = node.isLeaf && node.item != nil
                default:
                    item.isEnabled = true
                }
            }
        }

        /// 优先取右键点击行，没有则回退到当前选中行。
        private func targetNode() -> KeyOutlineNode? {
            guard let outline = outlineView else { return nil }
            let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
            guard row >= 0 else { return nil }
            return outline.item(atRow: row) as? KeyOutlineNode
        }

        @objc func copyKey(_ sender: Any?) {
            guard let node = targetNode() else { return }
            onCopy(node.path)
        }

        @objc func copyValue(_ sender: Any?) {
            guard let node = targetNode(), let item = node.item else { return }
            onCopyValue(item)
        }
    }
}

// MARK: - Cell

final class KeyCellView: NSTableCellView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.cell?.usesSingleLineMode = true
        addSubview(icon)
        addSubview(label)
        self.textField = label
        self.imageView = icon

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func configure(with node: KeyOutlineNode) {
        if node.isLeaf {
            icon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
            icon.contentTintColor = .systemPurple
            label.stringValue = node.name.isEmpty ? "/" : node.name
        } else {
            icon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            icon.contentTintColor = .secondaryLabelColor
            label.stringValue = node.name
        }
    }
}
