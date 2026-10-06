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
            .frame(minWidth: 560, idealWidth: 640, minHeight: 420, idealHeight: 580)
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

    private var canSave: Bool {
        WallpaperTimeSchedule.isValid(
            periods,
            installedWallpaperIDs: installedWallpaperIDs
        )
    }

    private var validationMessages: [LocalizedStringKey] {
        var messages: [LocalizedStringKey] = []

        if periods.isEmpty {
            messages.append("Add at least one time period.")
        } else {
            if periods.contains(where: { !$0.hasValidTimeRange }) {
                messages.append("Each period needs a different start and end time.")
            }
            if WallpaperTimeSchedule.hasOverlaps(periods) {
                messages.append("Time periods cannot overlap.")
            }
            if periods.contains(where: { period in
                period.wallpaperID.map(installedWallpaperIDs.contains) != true
            }) {
                messages.append("Choose an installed wallpaper for every period.")
            }
        }

        return messages
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Periods repeat daily using your Mac’s local time. Periods may cross midnight.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(Array(periods.indices), id: \.self) { index in
                        WallpaperTimePeriodEditorCard(
                            period: $periods[index],
                            index: index,
                            wallpapers: wallpapers,
                            onRemove: { removePeriod(at: index) }
                        )
                    }

                    Button {
                        addPeriod()
                    } label: {
                        Label("Add Time Period", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)

                    if !validationMessages.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(validationMessages.indices, id: \.self) { index in
                                Label {
                                    Text(validationMessages[index])
                                } icon: {
                                    Image(systemName: "exclamationmark.circle.fill")
                                }
                                .foregroundStyle(.red)
                            }
                        }
                        .font(.callout)
                        .padding(.top, 4)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private func removePeriod(at index: Int) {
        guard periods.indices.contains(index) else { return }
        periods.remove(at: index)
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
}

private struct WallpaperTimePeriodEditorCard: View {
    @Binding var period: WallpaperTimePeriod
    let index: Int
    let wallpapers: [WallpaperItem]
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Period \(index + 1)")
                    .font(.headline)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .help("Remove this time period")
            }

            HStack(spacing: 16) {
                timePicker("Start", minute: $period.startMinute)
                timePicker("End", minute: $period.endMinute)
            }

            HStack {
                Text("Wallpaper")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                WallpaperPicker(selection: $period.wallpaperID, wallpapers: wallpapers)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
    }

    private func timePicker(_ title: LocalizedStringKey, minute: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker(
                title,
                selection: dateBinding(for: minute),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.field)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
