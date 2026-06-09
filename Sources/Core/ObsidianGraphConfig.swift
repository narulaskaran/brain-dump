import Foundation

/// Syncs the `colorGroups` array in `.obsidian/graph.json` so that each
/// group subfolder under the PARA folders gets a stable, distinct colour.
///
/// All other keys in `graph.json` are preserved verbatim.
public struct ObsidianGraphConfig {

    // MARK: - Palette

    /// 10-colour palette as Obsidian `rgb` integer values (hex → decimal).
    private static let palette: [Int] = [
        0x00A63A, // green   = 42554
        0x4A8FD4, // blue    = 4886484  (0x4A8FD4 = 4886484? let's keep hex literal)
        0xE8A838, // amber
        0xE05C5C, // red
        0x9B59B6, // purple
        0x1ABC9C, // teal
        0xE67E22, // orange
        0x2ECC71, // mint
        0xE91E8C, // pink
        0x607D8B, // slate
    ]

    // MARK: - Public API

    /// Sync `colorGroups` in `<vaultPath>/.obsidian/graph.json`.
    ///
    /// - Any group subfolder that already has an entry is left untouched.
    /// - New group subfolders are appended with the next colour in the palette
    ///   (wrapping when all 10 are used).
    /// - All other keys in `graph.json` are preserved.
    ///
    /// Must be called inside a `VaultPathManager.withVaultAccess` block so the
    /// security-scoped resource is already open.
    public static func sync(vaultPath: URL) throws {
        let graphURL = vaultPath
            .appendingPathComponent(".obsidian")
            .appendingPathComponent("graph.json")

        // ── 1. Read existing graph.json (or start with an empty dict) ──────────
        var root: [String: Any]
        if FileManager.default.fileExists(atPath: graphURL.path) {
            let data = try Data(contentsOf: graphURL)
            let parsed = try JSONSerialization.jsonObject(with: data)
            root = (parsed as? [String: Any]) ?? [:]
        } else {
            root = [:]
        }

        // ── 2. Load the existing colorGroups array ─────────────────────────────
        var colorGroups = root["colorGroups"] as? [[String: Any]] ?? []

        // Build a set of query strings already present so we can skip them
        let existingQueries = Set(colorGroups.compactMap { $0["query"] as? String })

        // ── 3. Enumerate group subfolders ──────────────────────────────────────
        let paraFolders = ["10 Projects", "20 Areas", "30 Resources", "00 Inbox"]
        var allGroupPaths: [String] = []

        let fm = FileManager.default
        for para in paraFolders {
            let paraURL = vaultPath.appendingPathComponent(para)
            guard let contents = try? fm.contentsOfDirectory(
                at: paraURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    allGroupPaths.append("\(para)/\(url.lastPathComponent)")
                }
            }
        }

        // Sort for stable ordering when assigning colours
        allGroupPaths.sort()

        // ── 4. Assign colours to groups not yet in colorGroups ─────────────────
        //   Colour index = position in the sorted full list, wrapping at 10.
        for (index, groupPath) in allGroupPaths.enumerated() {
            let query = "path:\(groupPath)"
            guard !existingQueries.contains(query) else { continue }

            let rgb = palette[index % palette.count]
            let entry: [String: Any] = [
                "query": query,
                "color": [
                    "a": 1,
                    "rgb": rgb
                ]
            ]
            colorGroups.append(entry)
        }

        // ── 5. Write back ──────────────────────────────────────────────────────
        root["colorGroups"] = colorGroups

        // Create .obsidian directory if needed
        let obsidianDir = vaultPath.appendingPathComponent(".obsidian")
        try fm.createDirectory(at: obsidianDir, withIntermediateDirectories: true)

        let outData = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try outData.write(to: graphURL, options: .atomic)
    }
}
