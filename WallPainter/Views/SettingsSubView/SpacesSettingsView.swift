import AppKit
import SwiftUI

struct SpacesSettingsView: View {
    let model: WallpaperModel
    let spaceProvider: (any SpaceAPIProviding)?

    @Environment(WallPainterPreferences.self) private var preferences
    @Environment(\.isSettingsPreRendering) private var isPreRendering
    @State private var snapshot: SpaceSnapshot?
    @State private var isShowingResetConfirmation = false
    @Binding var selectedDisplayID: String?
    @Binding var selectedSpaceID: String

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

        if !selectedSpaceID.isEmpty,
           let group = displayGroups.first(where: { group in
               group.spaces.contains { $0.id == selectedSpaceID }
           }) {
            return group
        }

        return displayGroups.first
    }

    private var selectedSpace: SpaceDescriptor? {
        guard let group = selectedDisplayGroup else { return nil }

        if !selectedSpaceID.isEmpty,
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
                if let group = selectedDisplayGroup, !isPreRendering {
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
                    SettingsSection("Spaces") {
                        SettingsRow(
                            "Available spaces",
                            warningText: spaceProvider?.isAvailable == true
                                ? "No regular Mission Control spaces were reported."
                                : "Automatic space-based wallpaper changes are paused. Reconnect DesktopRenamer SpaceAPI in Permissions."
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
                        defaultRule: preferences.defaultWallpaperRule
                    )
                    .id(selectedSpace.id)
                }

                SettingsSection(nil) {
                    SettingsRow(
                        "Reset all space overrides",
                        helperText: "Every space will use the default rule again."
                    ) {
                        Button("Reset") {
                            isShowingResetConfirmation = true
                        }
                        .disabled(preferences.spaceOverrides.isEmpty)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .confirmationDialog(
            "Reset all space overrides?",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Overrides", role: .destructive) {
                preferences.resetSpaceOverrides()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All spaces will use the Default rule again.")
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
            selectedSpaceID = preferredSpace(in: group)?.id ?? ""
        }
    }

    private func updateSnapshot() {
        snapshot = spaceProvider?.snapshot
        reconcileSelection()
    }

    private func reconcileSelection() {
        guard !displayGroups.isEmpty else {
            selectedDisplayID = nil
            selectedSpaceID = ""
            return
        }

        let group: WallpaperDisplayGroup
        if let selectedDisplayID,
           let selectedGroup = displayGroups.first(where: { $0.id == selectedDisplayID }) {
            group = selectedGroup
        } else if !selectedSpaceID.isEmpty,
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
            selectedSpaceID = preferredSpace(in: group)?.id ?? ""
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
    @Binding var selection: String

    var body: some View {
        ModularSettingsTabBar(
            "Space",
            items: spaces,
            selection: selectedSelection,
            accessibilityLabel: { space in
                activeSpaceIDs.contains(space.id)
                    ? "\(space.name), active"
                    : space.name
            }
        ) { space in
            Text(activeSpaceIDs.contains(space.id) ? "○ \(space.name)" : space.name)
        }
        .padding(.vertical, 2)
    }

    private var selectedSelection: Binding<String?> {
        Binding(
            get: { selection.isEmpty ? spaces.first?.id : selection },
            set: { selection = $0 ?? "" }
        )
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
        case .manual:
            return .manual
        }
    }

    var body: some View {
        SettingsSection(
            "Space Behavior",
            helperText: "Use the default rule unless this space needs its own wallpaper."
        ) {
            SettingsRow("Behavior") {
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

            WallpaperRulePreview(
                rule: effectiveRule,
                wallpapers: model.items,
                title: selection == .allSpaces ? "Effective wallpaper" : "Preview"
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
        case .manual:
            preferences.setSpaceRule(.manual, for: space.id)
        }
    }

    private func load(_ rule: WallpaperRule, isInherited: Bool) {
        selection = isInherited ? .allSpaces : SpaceRuleSelection(mode: rule.mode)
        fixedWallpaperID = rule.fixedWallpaperID
        lightWallpaperID = rule.lightWallpaperID
        darkWallpaperID = rule.darkWallpaperID
    }
}

private enum SpaceRuleSelection: String, CaseIterable, Identifiable {
    case allSpaces
    case manual
    case fixed
    case appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allSpaces:
            return "Use default rule"
        case .manual:
            return "Manual"
        case .fixed:
            return "Fixed wallpaper"
        case .appearance:
            return "Follow system appearance"
        }
    }

    init(mode: WallpaperRuleMode) {
        switch mode {
        case .manual:
            self = .manual
        case .fixed:
            self = .fixed
        case .appearance:
            self = .appearance
        }
    }
}
