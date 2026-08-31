import AppKit
import SwiftUI

struct SpacesSettingsView: View {
    let model: WallpaperModel
    let spaceProvider: (any SpaceAPIProviding)?

    @Environment(WallPainterPreferences.self) private var preferences
    @State private var snapshot: SpaceSnapshot?
    @State private var editingSpace: SpaceDescriptor?

    private var regularSpaces: [SpaceDescriptor] {
        snapshot?.spaces
            .filter { !$0.isFullscreen }
            .sorted { lhs, rhs in
                if lhs.displayID != rhs.displayID {
                    return lhs.displayID < rhs.displayID
                }
                if lhs.number != rhs.number {
                    return lhs.number < rhs.number
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            } ?? []
    }

    private var displayGroups: [WallpaperDisplayGroup] {
        Dictionary(grouping: regularSpaces, by: \.displayID)
            .map { displayID, spaces in
                WallpaperDisplayGroup(
                    id: displayID,
                    name: spaces.first?.displayName ?? displayID,
                    spaces: spaces
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var activeSpaceIDs: Set<String> {
        Set(snapshot?.currentSpaceIDs ?? [])
    }

    var body: some View {
        SettingsContainer(.spaces) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Space Arrangement") {
                    SettingsRow(
                        "Reset space overrides",
                        helperText: "Every space will use the All Spaces rule again."
                    ) {
                        Button("Reset") {
                            preferences.resetSpaceRules()
                        }
                        .disabled(preferences.automationSpaceRules.isEmpty)
                    }
                }

                if displayGroups.isEmpty {
                    SettingsSection("Available Spaces") {
                        SettingsRow(
                            "SpaceAPI availability",
                            warningText: spaceProvider?.isAvailable == true
                                ? "No regular Mission Control spaces were reported."
                                : "Enable DesktopRenamer SpaceAPI to manage wallpapers by space."
                        ) {
                            Text(spaceProvider?.isAvailable == true ? "No spaces" : "Unavailable")
                                .foregroundStyle(
                                    spaceProvider?.isAvailable == true
                                        ? Color.secondary
                                        : Color.orange
                                )
                                .frame(minHeight: 24)
                        }
                    }
                } else {
                    ForEach(displayGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.name)
                                .font(.headline)
                                .padding(.leading, 4)

                            SpaceTable(
                                group: group,
                                activeSpaceIDs: activeSpaceIDs,
                                model: model,
                                defaultRule: preferences.automationDefaultRule,
                                overrides: preferences.automationSpaceRules
                            ) { space in
                                editingSpace = space
                            }
                            .clipShape(.rect(cornerRadius: 8))
                            .padding(.bottom, 10)
                        }
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            updateSnapshot()
            spaceProvider?.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .wallPainterSpaceSnapshotDidChange
        )) { _ in
            updateSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .wallPainterSpaceAvailabilityDidChange
        )) { _ in
            updateSnapshot()
        }
        .sheet(item: $editingSpace) { space in
            SpaceRuleEditor(
                space: space,
                model: model,
                existingRule: preferences.spaceRule(for: space.id),
                defaultRule: preferences.automationDefaultRule
            )
            .environment(preferences)
            .frame(minWidth: 430, minHeight: 330)
        }
    }

    private func updateSnapshot() {
        snapshot = spaceProvider?.snapshot
    }
}

private struct WallpaperDisplayGroup: Identifiable {
    let id: String
    let name: String
    let spaces: [SpaceDescriptor]
}

private struct SpaceTable: View {
    let group: WallpaperDisplayGroup
    let activeSpaceIDs: Set<String>
    let model: WallpaperModel
    let defaultRule: WallpaperRule
    let overrides: [String: WallpaperRule]
    let select: (SpaceDescriptor) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Color.clear
                    .frame(width: 16)
                Text("#")
                    .frame(width: 30, alignment: .leading)
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Rule")
                    .frame(width: 150, alignment: .trailing)
                Text("Actions")
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ForEach(group.spaces) { space in
                spaceRow(for: space)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(sectionBackgroundColor.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                )
        )
    }

    private func spaceRow(for space: SpaceDescriptor) -> some View {
        VStack(spacing: 0) {
            Button {
                select(space)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: activeSpaceIDs.contains(space.id) ? "circle.fill" : "circle")
                        .font(.caption2)
                        .foregroundStyle(
                            activeSpaceIDs.contains(space.id) ? Color.accentColor : Color.clear
                        )
                        .frame(width: 16)
                        .accessibilityHidden(true)

                    Text(activeSpaceIDs.contains(space.id)
                         ? "[\(space.number)]"
                         : "\(space.number)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(
                            activeSpaceIDs.contains(space.id) ? Color.accentColor : Color.primary
                        )
                        .fontWeight(activeSpaceIDs.contains(space.id) ? .bold : .regular)
                        .frame(width: 30, alignment: .leading)

                    Text(space.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(ruleTitle(for: space))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 150, alignment: .trailing)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .background(
                    activeSpaceIDs.contains(space.id)
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear
                )
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Edit the wallpaper rule for this space")

            if space.id != group.spaces.last?.id {
                Divider()
                    .padding(.leading, 12)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var sectionBackgroundColor: Color {
        let nsColor = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 0.20, alpha: 1.0)
            } else {
                return NSColor(calibratedWhite: 1.00, alpha: 1.0)
            }
        }
        return Color(nsColor: nsColor)
    }

    private func ruleTitle(for space: SpaceDescriptor) -> String {
        guard let rule = overrides[space.id] else {
            return defaultRule.isValid(installedWallpaperIDs: Set(model.items.map(\.id)))
                ? "Use All Spaces"
                : "All Spaces unavailable"
        }

        guard rule.isValid(installedWallpaperIDs: Set(model.items.map(\.id))) else {
            return "Unavailable"
        }

        switch rule.mode {
        case .fixed:
            guard let wallpaperID = rule.fixedWallpaperID else { return "Unavailable" }
            return model.items.first(where: { $0.id == wallpaperID })?.name ?? "Unavailable"
        case .appearance:
            return "Follow appearance"
        }
    }
}

private struct SpaceRuleEditor: View {
    let space: SpaceDescriptor
    let model: WallpaperModel
    let existingRule: WallpaperRule?
    let defaultRule: WallpaperRule

    @Environment(WallPainterPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var selection: SpaceRuleSelection
    @State private var fixedWallpaperID: String?
    @State private var lightWallpaperID: String?
    @State private var darkWallpaperID: String?

    init(
        space: SpaceDescriptor,
        model: WallpaperModel,
        existingRule: WallpaperRule?,
        defaultRule: WallpaperRule
    ) {
        self.space = space
        self.model = model
        self.existingRule = existingRule
        self.defaultRule = defaultRule

        let startingRule = existingRule ?? defaultRule
        _selection = State(
            initialValue: existingRule == nil
                ? .allSpaces
                : SpaceRuleSelection(mode: startingRule.mode)
        )
        _fixedWallpaperID = State(initialValue: startingRule.fixedWallpaperID)
        _lightWallpaperID = State(initialValue: startingRule.lightWallpaperID)
        _darkWallpaperID = State(initialValue: startingRule.darkWallpaperID)
    }

    var body: some View {
        @Bindable var preferences = preferences

        VStack(alignment: .leading, spacing: 20) {
            Text(space.name)
                .font(.title2)

            SettingsSection("Wallpaper Rule") {
                SettingsRow("Rule") {
                    Picker("", selection: $selection) {
                        ForEach(SpaceRuleSelection.allCases) { option in
                            Text(option.title)
                                .tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 190, alignment: .trailing)
                }

                if selection == .fixed {
                    Divider()

                    SettingsRow("Fixed wallpaper") {
                        WallpaperPicker(
                            selection: $fixedWallpaperID,
                            wallpapers: model.items
                        )
                    }
                } else if selection == .appearance {
                    Divider()

                    SettingsRow("Light wallpaper") {
                        WallpaperPicker(
                            selection: $lightWallpaperID,
                            wallpapers: model.items
                        )
                    }

                    Divider()

                    SettingsRow("Dark wallpaper") {
                        WallpaperPicker(
                            selection: $darkWallpaperID,
                            wallpapers: model.items
                        )
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    save(using: preferences)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func save(using preferences: WallPainterPreferences) {
        switch selection {
        case .allSpaces:
            preferences.setSpaceRule(nil, for: space.id)
        case .fixed:
            preferences.setSpaceRule(
                WallpaperRule.fixed(fixedWallpaperID),
                for: space.id
            )
        case .appearance:
            preferences.setSpaceRule(
                WallpaperRule.appearance(
                    lightWallpaperID: lightWallpaperID,
                    darkWallpaperID: darkWallpaperID
                ),
                for: space.id
            )
        }
        dismiss()
    }
}

private enum SpaceRuleSelection: String, CaseIterable, Identifiable {
    case allSpaces
    case fixed
    case appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allSpaces:
            return "Use All Spaces"
        case .fixed:
            return "Fixed wallpaper"
        case .appearance:
            return "Follow system appearance"
        }
    }

    init(mode: WallpaperRuleMode) {
        switch mode {
        case .fixed:
            self = .fixed
        case .appearance:
            self = .appearance
        }
    }
}
