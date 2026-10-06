import AppKit
import SwiftUI

struct WallpaperTimeScheduleEditor: View {
    @Binding var periods: [WallpaperTimePeriod]
    let wallpapers: [WallpaperItem]

    @State private var isPresentingEditor = false

    var body: some View {
        SettingsRow(
            "Time periods",
            helperText: "Periods repeat daily in local time. An end time earlier than its start is on the next day. The current wallpaper stays active when no period matches."
        ) {
            Button(periods.isEmpty ? "Set Up…" : "Edit…") {
                isPresentingEditor = true
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            WallpaperTimeScheduleEditorSheet(
                periods: periods,
                wallpapers: wallpapers
            ) { savedPeriods in
                periods = savedPeriods
            }
            .frame(width: 720, height: 660)
            .environment(\.isSettingsSearchRegistrationEnabled, false)
        }
    }
}

private struct WallpaperTimeScheduleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var periods: [WallpaperTimePeriod]
    @State private var periodIDToReveal: UUID?

    let wallpapers: [WallpaperItem]
    let onSave: ([WallpaperTimePeriod]) -> Void

    init(
        periods: [WallpaperTimePeriod],
        wallpapers: [WallpaperItem],
        onSave: @escaping ([WallpaperTimePeriod]) -> Void
    ) {
        _periods = State(initialValue: periods)
        self.wallpapers = wallpapers
        self.onSave = onSave
    }

    private var installedWallpaperIDs: Set<String> {
        Set(wallpapers.map(\.id))
    }

    private var validationIssues: [WallpaperTimeScheduleValidationIssue] {
        var issues: [WallpaperTimeScheduleValidationIssue] = []

        if periods.isEmpty {
            issues.append(.empty)
        } else {
            if periods.contains(where: { !$0.hasValidTimeRange }) {
                issues.append(.invalidTime)
            }
            if WallpaperTimeSchedule.hasOverlaps(periods) {
                issues.append(.overlap)
            }
            if periods.contains(where: { period in
                period.wallpaperID.map(installedWallpaperIDs.contains) != true
            }) {
                issues.append(.missingWallpaper)
            }
        }

        return issues
    }

    private var canSave: Bool {
        validationIssues.isEmpty
            && WallpaperTimeSchedule.isValid(
                periods,
                installedWallpaperIDs: installedWallpaperIDs
            )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Time Schedule")
                    .font(.headline)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(height: 48)

            Divider()

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsSectionHeader(
                            "Time periods",
                            helperText: "Periods repeat daily in local time. An end time earlier than its start is on the next day; gaps keep the current wallpaper."
                        )

                        ForEach(periods) { period in
                            periodSection(period, number: periodNumber(for: period.id))
                                .padding(.top, 10)
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    )
                                )
                        }

                        SettingsSection {
                            SettingsRow("Add time period", id: "schedule.add") {
                                Button("Add", systemImage: "plus") {
                                    addPeriod()
                                }
                            }
                        }
                        .padding(.top, 10)

                        if !validationIssues.isEmpty {
                            SettingsSection(
                                "Fix before saving",
                                helperText: "Save becomes available after every issue is resolved."
                            ) {
                                ForEach(validationIssues.indices, id: \.self) { index in
                                    let issue = validationIssues[index]
                                    if index > 0 {
                                        Divider()
                                    }

                                    SettingsRow(
                                        issue.title,
                                        id: "schedule.validation.\(issue.id)"
                                    ) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onChange(of: periodIDToReveal) { _, periodID in
                    guard let periodID else { return }
                    withSettingsAnimation {
                        scrollProxy.scrollTo(periodTitleID(for: periodID), anchor: .center)
                    }
                    periodIDToReveal = nil
                }
            }

            Divider()

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    onSave(periods)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func periodSection(_ period: WallpaperTimePeriod, number: Int) -> some View {
        let periodID = period.id
        let isOvernight = period.startMinute > period.endMinute

        SettingsSection {
            SettingsRow(
                "Period \(number)",
                id: periodTitleID(for: periodID)
            ) {
                Button(role: .destructive) {
                    withSettingsAnimation {
                        removePeriod(id: periodID)
                    }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }

            Divider()

            SettingsRow(
                "Start",
                id: "schedule.\(periodID.uuidString).start"
            ) {
                AlignedTimePicker(
                    selection: dateBinding(for: minuteBinding(for: periodID, keyPath: \.startMinute))
                )
                .accessibilityLabel("Start")
                .frame(minHeight: 24, alignment: .center)
            }

            Divider()

            SettingsRow(
                isOvernight ? "End (next day)" : "End",
                id: "schedule.\(periodID.uuidString).end"
            ) {
                AlignedTimePicker(
                    selection: dateBinding(for: minuteBinding(for: periodID, keyPath: \.endMinute))
                )
                .accessibilityLabel("End")
                .frame(minHeight: 24, alignment: .center)
            }

            Divider()

            SettingsRow(
                "Wallpaper",
                id: "schedule.\(periodID.uuidString).wallpaper"
            ) {
                WallpaperPicker(
                    selection: wallpaperBinding(for: periodID),
                    wallpapers: wallpapers
                )
            }

            Divider()

            SettingsRow(
                "Wallpaper preview",
                id: "schedule.\(periodID.uuidString).preview"
            ) {
                ScheduledWallpaperPreview(
                    wallpaper: wallpaper(for: period.wallpaperID),
                    isUnavailable: period.wallpaperID != nil && wallpaper(for: period.wallpaperID) == nil
                )
            }
        }
    }

    private func removePeriod(id: UUID) {
        periods.removeAll { $0.id == id }
    }

    private func periodNumber(for id: UUID) -> Int {
        (periods.firstIndex(where: { $0.id == id }) ?? 0) + 1
    }

    private func addPeriod() {
        let startMinute = nextAvailableStartMinute()
        let period = WallpaperTimePeriod(
            startMinute: startMinute,
            endMinute: (startMinute + 60) % WallpaperTimeSchedule.minutesPerDay
        )
        withSettingsAnimation {
            periods.append(period)
            periodIDToReveal = period.id
        }
    }

    private func periodTitleID(for id: UUID) -> String {
        "schedule.\(id.uuidString).title"
    }

    private func nextAvailableStartMinute() -> Int {
        let preferredStart = 9 * 60
        for offset in stride(from: 0, to: WallpaperTimeSchedule.minutesPerDay, by: 30) {
            let start = (preferredStart + offset) % WallpaperTimeSchedule.minutesPerDay
            let candidate = WallpaperTimePeriod(
                startMinute: start,
                endMinute: (start + 60) % WallpaperTimeSchedule.minutesPerDay
            )
            if !WallpaperTimeSchedule.hasOverlaps(periods + [candidate]) {
                return start
            }
        }
        return preferredStart
    }

    private func dateBinding(for minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { date(for: minute.wrappedValue) },
            set: { minute.wrappedValue = minuteOfDay(for: $0) }
        )
    }

    private func minuteBinding(
        for id: UUID,
        keyPath: WritableKeyPath<WallpaperTimePeriod, Int>
    ) -> Binding<Int> {
        Binding(
            get: { periods.first(where: { $0.id == id })?[keyPath: keyPath] ?? 0 },
            set: { newValue in
                guard let index = periods.firstIndex(where: { $0.id == id }) else { return }
                periods[index][keyPath: keyPath] = newValue
            }
        )
    }

    private func wallpaperBinding(for id: UUID) -> Binding<String?> {
        Binding(
            get: { periods.first(where: { $0.id == id })?.wallpaperID },
            set: { newValue in
                guard let index = periods.firstIndex(where: { $0.id == id }) else { return }
                periods[index].wallpaperID = newValue
            }
        )
    }

    private func wallpaper(for id: String?) -> WallpaperItem? {
        guard let id else { return nil }
        return wallpapers.first { $0.id == id }
    }

    private func date(for minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = .current
        components.timeZone = .current
        components.year = 2001
        components.month = 1
        components.day = 15
        components.hour = minute / 60
        components.minute = minute % 60
        return Calendar.current.date(from: components) ?? .now
    }

    private func minuteOfDay(for date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

private struct AlignedTimePicker: NSViewRepresentable {
    @Binding var selection: Date

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerMode = .single
        picker.datePickerElements = .hourMinute
        picker.calendar = .current
        picker.locale = .current
        picker.timeZone = .current
        picker.controlSize = .regular
        picker.font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular))

        let cell = VerticallyAlignedTimePickerCell(textCell: "")
        cell.datePickerStyle = .textField
        cell.datePickerMode = .single
        cell.datePickerElements = .hourMinute
        cell.calendar = .current
        cell.locale = .current
        cell.timeZone = .current
        cell.controlSize = .regular
        cell.font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular))
        picker.cell = cell

        picker.dateValue = selection
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.selectionDidChange(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.selection = $selection

        let displayedTime = Calendar.current.dateComponents([.hour, .minute], from: picker.dateValue)
        let selectedTime = Calendar.current.dateComponents([.hour, .minute], from: selection)
        if displayedTime.hour != selectedTime.hour || displayedTime.minute != selectedTime.minute {
            picker.dateValue = selection
        }
    }

    final class Coordinator: NSObject {
        var selection: Binding<Date>

        init(selection: Binding<Date>) {
            self.selection = selection
        }

        @objc func selectionDidChange(_ sender: NSDatePicker) {
            selection.wrappedValue = sender.dateValue
        }
    }
}

private final class VerticallyAlignedTimePickerCell: NSDatePickerCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        // Center the active segment highlight within the bezeled time field.
        super.titleRect(forBounds: rect).offsetBy(dx: 0, dy: -1)
    }
}

private struct ScheduledWallpaperPreview: View {
    let wallpaper: WallpaperItem?
    let isUnavailable: Bool

    var body: some View {
        Group {
            if let wallpaper {
                WallpaperThumbnail(url: wallpaper.thumbnailURL)
                    .frame(width: 144, height: 81)
                    .clipShape(.rect(cornerRadius: 8))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(wallpaper.name))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.quaternary.opacity(0.35))
                        Image(systemName: isUnavailable ? "exclamationmark.triangle" : "photo")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                }
                .frame(width: 144, height: 81)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    isUnavailable ? Text("Wallpaper unavailable") : Text("No wallpaper selected")
                )
            }
        }
    }
}

private enum WallpaperTimeScheduleValidationIssue: String, Identifiable {
    case empty
    case invalidTime
    case overlap
    case missingWallpaper

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .empty:
            return "Add at least one time period."
        case .invalidTime:
            return "Each period needs a different start and end time."
        case .overlap:
            return "Time periods cannot overlap."
        case .missingWallpaper:
            return "Choose an installed wallpaper for every period."
        }
    }
}
