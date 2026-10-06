import SwiftUI

struct WallpaperTimeScheduleEditor: View {
    @Binding var periods: [WallpaperTimePeriod]
    let wallpapers: [WallpaperItem]

    @State private var isPresentingEditor = false

    var body: some View {
        SettingsRow(
            "Time periods",
            helperText: "Periods repeat every day in your local time. The current wallpaper stays active when no period matches."
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
            .frame(width: 720, height: 520)
            .environment(\.isSettingsSearchRegistrationEnabled, false)
        }
    }
}

private struct WallpaperTimeScheduleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var periods: [WallpaperTimePeriod]

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SettingsSection(
                        "Time periods",
                        helperText: "Periods repeat daily in local time and may cross midnight. Outside configured periods, the current wallpaper stays active."
                    ) {
                        ForEach(periods.indices, id: \.self) { index in
                            let periodID = periods[index].id

                            if index > 0 {
                                Divider()
                            }

                            SettingsRow(
                                "Period \(index + 1)",
                                id: "schedule.\(periodID.uuidString).title"
                            ) {
                                Button(role: .destructive) {
                                    removePeriod(id: periodID)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }

                            Divider()

                            SettingsRow(
                                "Start",
                                id: "schedule.\(periodID.uuidString).start"
                            ) {
                                DatePicker(
                                    "Start",
                                    selection: dateBinding(for: $periods[index].startMinute),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                                .datePickerStyle(.field)
                            }

                            Divider()

                            SettingsRow(
                                "End",
                                id: "schedule.\(periodID.uuidString).end"
                            ) {
                                DatePicker(
                                    "End",
                                    selection: dateBinding(for: $periods[index].endMinute),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                                .datePickerStyle(.field)
                            }

                            Divider()

                            SettingsRow(
                                "Wallpaper",
                                id: "schedule.\(periodID.uuidString).wallpaper"
                            ) {
                                WallpaperPicker(
                                    selection: $periods[index].wallpaperID,
                                    wallpapers: wallpapers
                                )
                            }
                        }

                        if !periods.isEmpty {
                            Divider()
                        }

                        SettingsRow("Add time period", id: "schedule.add") {
                            Button("Add", systemImage: "plus") {
                                addPeriod()
                            }
                        }
                    }

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
            .navigationTitle("Time Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(periods)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func removePeriod(id: UUID) {
        periods.removeAll { $0.id == id }
    }

    private func addPeriod() {
        let startMinute = nextAvailableStartMinute()
        periods.append(
            WallpaperTimePeriod(
                startMinute: startMinute,
                endMinute: (startMinute + 60) % WallpaperTimeSchedule.minutesPerDay
            )
        )
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
