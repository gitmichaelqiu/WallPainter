import AppKit
import SwiftUI

struct SpacesSettingsView: View {
    let model: WallpaperModel
    let spaceProvider: (any SpaceAPIProviding)?

    @Environment(WallPainterPreferences.self) private var preferences
    @State private var snapshot: SpaceSnapshot?
    @Binding var selectedDisplayID: String?
    @Binding var selectedSpaceID: String?

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
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private var selectedDisplayGroup: WallpaperDisplayGroup? {
        if let selectedDisplayID,
           let group = displayGroups.first(where: { $0.id == selectedDisplayID }) {
            return group
        }

        if let selectedSpaceID,
           let group = displayGroups.first(where: { group in
               group.spaces.contains { $0.id == selectedSpaceID }
           }) {
            return group
        }

        return displayGroups.first
    }

    private var selectedSpace: SpaceDescriptor? {
        guard let group = selectedDisplayGroup else { return nil }

        if let selectedSpaceID,
           let space = group.spaces.first(where: { $0.id == selectedSpaceID }) {
            return space
        }

        return group.spaces.first
    }

    private var activeSpaceIDs: Set<String> {
        let regularSpaceIDs = Set(regularSpaces.map(\.id))
        return Set(snapshot?.currentSpaceIDs ?? []).intersection(regularSpaceIDs)
    }

    var body: some View {
        SettingsContainer(.spaces) {
            VStack(alignment: .leading, spacing: 20) {
                if let group = selectedDisplayGroup {
                    SpaceSwitcher(
                        spaces: group.spaces,
                        activeSpaceIDs: activeSpaceIDs,
                        selection: $selectedSpaceID
                    )
                }

                if displayGroups.count > 1 {
                    SettingsSection(nil) {
                        SettingsRow("Display") {
                            Picker("", selection: $selectedDisplayID) {
                                ForEach(displayGroups) { group in
                                    Text(group.name)
                                        .tag(Optional(group.id))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(minWidth: 190, alignment: .trailing)
                        }

                        Divider()
                    }
                } else if displayGroups.isEmpty {
                    SettingsSection(nil) {
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
                }

                if let selectedSpace {
                    SpaceRuleEditor(
                        space: selectedSpace,
                        model: model,
                        existingRule: preferences.spaceRule(for: selectedSpace.id),
                        defaultRule: preferences.automationDefaultRule
                    )
                    .id(selectedSpace.id)
                }

                SettingsSection(nil) {
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
        .onChange(of: selectedDisplayID) { _, newValue in
            guard let group = displayGroups.first(where: { $0.id == newValue }) else { return }
            selectedSpaceID = preferredSpace(in: group)?.id
        }
    }

    private func updateSnapshot() {
        snapshot = spaceProvider?.snapshot
        reconcileSelection()
    }

    private func reconcileSelection() {
        guard !displayGroups.isEmpty else {
            selectedDisplayID = nil
            selectedSpaceID = nil
            return
        }

        let group: WallpaperDisplayGroup
        if let selectedDisplayID,
           let selectedGroup = displayGroups.first(where: { $0.id == selectedDisplayID }) {
            group = selectedGroup
        } else if let selectedSpaceID,
                  let selectedGroup = displayGroups.first(where: { group in
                      group.spaces.contains { $0.id == selectedSpaceID }
                  }) {
            group = selectedGroup
        } else {
            group = displayGroups.first(where: { preferredSpace(in: $0) != nil })
                ?? displayGroups[0]
        }

        selectedDisplayID = group.id
        if !group.spaces.contains(where: { $0.id == selectedSpaceID }) {
            selectedSpaceID = preferredSpace(in: group)?.id
        }
    }

    private func preferredSpace(in group: WallpaperDisplayGroup) -> SpaceDescriptor? {
        group.spaces.first(where: { activeSpaceIDs.contains($0.id) })
            ?? group.spaces.first
    }
}

private struct SpaceSwitcher: View {
    let spaces: [SpaceDescriptor]
    let activeSpaceIDs: Set<String>
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal) {
            spacePicker
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var spacePicker: some View {
        if #available(macOS 27.0, *) {
            Picker("Space", selection: $selection) {
                spacePickerOptions
            }
            .labelsHidden()
            .pickerStyle(.tabs)
            .controlSize(.large)
        } else {
            Picker("Space", selection: $selection) {
                spacePickerOptions
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var spacePickerOptions: some View {
        ForEach(spaces) { space in
            let isActive = activeSpaceIDs.contains(space.id)

            Text(isActive ? "○ \(space.name)" : space.name)
                .lineLimit(1)
                .accessibilityLabel(isActive ? "\(space.name), active" : space.name)
                .tag(Optional(space.id))
        }
    }
}

private struct WallpaperDisplayGroup: Identifiable {
    let id: String
    let name: String
    let spaces: [SpaceDescriptor]
}

private struct SpaceRuleEditor: View {
    let space: SpaceDescriptor
    let model: WallpaperModel
    let existingRule: WallpaperRule?
    let defaultRule: WallpaperRule

    @Environment(WallPainterPreferences.self) private var preferences
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

    private var effectiveRule: WallpaperRule {
        switch selection {
        case .allSpaces:
            return defaultRule
        case .fixed:
            return .fixed(fixedWallpaperID)
        case .appearance:
            return .appearance(
                lightWallpaperID: lightWallpaperID,
                darkWallpaperID: darkWallpaperID
            )
        }
    }

    var body: some View {
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

            Divider()

            SpaceWallpaperPreview(
                rule: effectiveRule,
                wallpapers: model.items,
                title: selection == .allSpaces ? "All Spaces preview" : "Preview"
            )
        }
        .onChange(of: selection) { _, _ in
            saveIfNeeded()
        }
        .onChange(of: fixedWallpaperID) { _, _ in
            saveIfNeeded()
        }
        .onChange(of: lightWallpaperID) { _, _ in
            saveIfNeeded()
        }
        .onChange(of: darkWallpaperID) { _, _ in
            saveIfNeeded()
        }
        .onChange(of: existingRule) { _, newRule in
            load(newRule ?? defaultRule, isInherited: newRule == nil)
        }
        .onChange(of: defaultRule) { _, newRule in
            guard existingRule == nil else { return }
            load(newRule, isInherited: true)
        }
    }

    private func saveIfNeeded() {
        switch selection {
        case .allSpaces:
            preferences.setSpaceRule(nil, for: space.id)
        case .fixed:
            preferences.setSpaceRule(
                .fixed(fixedWallpaperID),
                for: space.id
            )
        case .appearance:
            preferences.setSpaceRule(
                .appearance(
                    lightWallpaperID: lightWallpaperID,
                    darkWallpaperID: darkWallpaperID
                ),
                for: space.id
            )
        }
    }

    private func load(_ rule: WallpaperRule, isInherited: Bool) {
        selection = isInherited ? .allSpaces : SpaceRuleSelection(mode: rule.mode)
        fixedWallpaperID = rule.fixedWallpaperID
        lightWallpaperID = rule.lightWallpaperID
        darkWallpaperID = rule.darkWallpaperID
    }
}

private struct SpaceWallpaperPreview: View {
    let rule: WallpaperRule
    let wallpapers: [WallpaperItem]
    let title: String

    private var fixedWallpaper: WallpaperItem? {
        wallpaper(withID: rule.fixedWallpaperID)
    }

    private var lightWallpaper: WallpaperItem? {
        wallpaper(withID: rule.lightWallpaperID)
    }

    private var darkWallpaper: WallpaperItem? {
        wallpaper(withID: rule.darkWallpaperID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            switch rule.mode {
            case .fixed:
                SpaceWallpaperPreviewCard(
                    wallpaper: fixedWallpaper,
                    label: "Fixed"
                )
            case .appearance:
                HStack(spacing: 12) {
                    SpaceWallpaperPreviewCard(
                        wallpaper: lightWallpaper,
                        label: "Light"
                    )

                    SpaceWallpaperPreviewCard(
                        wallpaper: darkWallpaper,
                        label: "Dark"
                    )
                }
            }
        }
        .padding(10)
    }

    private func wallpaper(withID id: String?) -> WallpaperItem? {
        guard let id else { return nil }
        return wallpapers.first { $0.id == id }
    }
}

private struct SpaceWallpaperPreviewCard: View {
    let wallpaper: WallpaperItem?
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let wallpaper {
                WallpaperThumbnail(url: wallpaper.thumbnailURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipShape(.rect(cornerRadius: 8))

                HStack(spacing: 8) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Text(wallpaper.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("Wallpaper unavailable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
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
