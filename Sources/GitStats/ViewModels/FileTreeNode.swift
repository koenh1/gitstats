import Foundation
import SwiftUI

/// Represents a node (file or directory) in the repository file tree.
/// Supports three-state selection: all selected, none selected, or mixed.
@Observable
final class FileTreeNode: Identifiable {
    let name: String
    let fullPath: String  // relative path within repo (empty string for root)
    let isDirectory: Bool
    var isExpanded: Bool
    var children: [FileTreeNode]
    
    /// Internal selection state – use `select(_:)` to modify.
    private(set) var selectionState: SelectionState = .all
    
    enum SelectionState {
        case all    // this node and all descendants are selected
        case none   // none selected
        case mixed  // some descendants selected
    }
    
    var id: String { fullPath.isEmpty ? "ROOT" : fullPath }
    
    weak var parent: FileTreeNode?
    
    init(name: String, fullPath: String, isDirectory: Bool) {
        self.name = name
        self.fullPath = fullPath
        self.isDirectory = isDirectory
        self.isExpanded = false
        self.children = []
    }
    
    // MARK: - Selection
    
    /// Toggle this node's selection. If mixed or none → select all; if all → deselect all.
    func toggle() {
        switch selectionState {
        case .all:
            select(false)
        case .none, .mixed:
            select(true)
        }
    }
    
    /// Set selection for this node and all descendants, then propagate up.
    func select(_ selected: Bool) {
        setSelectionRecursive(selected)
        parent?.recalculateFromChildren()
    }
    
    private func setSelectionRecursive(_ selected: Bool) {
        selectionState = selected ? .all : .none
        for child in children {
            child.setSelectionRecursive(selected)
        }
    }
    
    private func recalculateFromChildren() {
        guard !children.isEmpty else { return }
        
        let allAll = children.allSatisfy { $0.selectionState == .all }
        let allNone = children.allSatisfy { $0.selectionState == .none }
        
        if allAll {
            selectionState = .all
        } else if allNone {
            selectionState = .none
        } else {
            selectionState = .mixed
        }
        
        parent?.recalculateFromChildren()
    }
    
    // MARK: - Queries
    
    /// Returns the set of selected file paths (leaves only).
    var selectedFilePaths: Set<String> {
        if isDirectory {
            switch selectionState {
            case .none:
                return []
            case .all:
                return allFilePaths
            case .mixed:
                var result = Set<String>()
                for child in children {
                    result.formUnion(child.selectedFilePaths)
                }
                return result
            }
        } else {
            return selectionState == .all ? [fullPath] : []
        }
    }
    
    /// Returns all file paths under this node.
    private var allFilePaths: Set<String> {
        if isDirectory {
            var result = Set<String>()
            for child in children {
                result.formUnion(child.allFilePaths)
            }
            return result
        } else {
            return [fullPath]
        }
    }
    
    // MARK: - Extension-based preselection
    
    /// Select files matching any extension in the set, deselect others.
    func selectByExtensions(_ extensions: Set<String>) {
        if isDirectory {
            for child in children {
                child.selectByExtensions(extensions)
            }
            recalculateFromChildren()
        } else {
            let ext = "." + ((fullPath as NSString).pathExtension)
            selectionState = extensions.contains(ext) ? .all : .none
        }
    }
    
    // MARK: - Building from flat path list
    
    /// Build a tree from a sorted list of relative file paths.
    static func buildTree(from paths: [String], textExtensions: Set<String>) -> FileTreeNode {
        let root = FileTreeNode(name: "/", fullPath: "", isDirectory: true)
        root.isExpanded = true
        
        for path in paths {
            let components = path.split(separator: "/").map(String.init)
            var current = root
            
            for (i, component) in components.enumerated() {
                let isLast = (i == components.count - 1)
                let partialPath = components[0...i].joined(separator: "/")
                
                if let existing = current.children.first(where: { $0.name == component && $0.isDirectory == !isLast }) {
                    current = existing
                } else {
                    let node = FileTreeNode(
                        name: component,
                        fullPath: partialPath,
                        isDirectory: !isLast
                    )
                    node.parent = current
                    if isLast {
                        // File: preselect if it's a known text type
                        let ext = "." + ((path as NSString).pathExtension)
                        node.selectionState = textExtensions.contains(ext.lowercased()) ? .all : .none
                    }
                    current.children.append(node)
                    current = node
                }
            }
        }
        
        // Sort children: directories first, then alphabetically
        sortChildren(root)
        // Recalculate directory selection states from leaf states
        recalculateAll(root)
        
        return root
    }
    
    private static func sortChildren(_ node: FileTreeNode) {
        node.children.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        for child in node.children where child.isDirectory {
            sortChildren(child)
        }
    }
    
    private static func recalculateAll(_ node: FileTreeNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        for child in node.children {
            recalculateAll(child)
        }
        let allAll = node.children.allSatisfy { $0.selectionState == .all }
        let allNone = node.children.allSatisfy { $0.selectionState == .none }
        if allAll {
            node.selectionState = .all
        } else if allNone {
            node.selectionState = .none
        } else {
            node.selectionState = .mixed
        }
    }
}
