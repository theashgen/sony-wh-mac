import SwiftUI
import WidgetKit

struct HeadphoneEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}
struct HeadphoneProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeadphoneEntry {
        HeadphoneEntry(date: .now, snapshot: WidgetSnapshot(battery: 80, mode: "ANC", connected: true))
    }
    func getSnapshot(in context: Context, completion: @escaping (HeadphoneEntry) -> Void) {
        Task { completion(context.isPreview ? placeholder(in: context) : HeadphoneEntry(date: .now, snapshot: await .read())) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HeadphoneEntry>) -> Void) {
        Task { completion(Timeline(entries: [HeadphoneEntry(date: .now, snapshot: await .read())], policy: .after(.now.addingTimeInterval(900)))) }
    }
}
struct HeadphoneWidgetView: View {
    var entry: HeadphoneEntry
    @Environment(\.widgetFamily) private var family
    private var state: WidgetSnapshot? { entry.snapshot }
    private var isStale: Bool { state.map { Date().timeIntervalSince($0.updatedAt) > 120 } ?? true }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "headphones").font(.title2)
                Spacer()
                Text(state?.battery.map { "\($0)%" } ?? "—")
                    .font(.title3.weight(.semibold)).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("WH-CH720N").font(.headline)
                Text(state == nil ? "Open Sony Control to connect" : (isStale || state?.connected != true ? "Last known · \(state!.mode)" : modeLabel))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if family == .systemMedium {
                HStack(spacing: 8) {
                    modeLink("ANC", icon: "waveform.slash", mode: "anc")
                    modeLink("Ambient", icon: "ear", mode: "ambient")
                    modeLink("Off", icon: "power", mode: "off")
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "sonycontrol://controls"))
    }
    private var modeLabel: String { state?.mode == "ANC" ? "Noise Cancelling" : state?.mode ?? "Disconnected" }
    private func modeLink(_ title: String, icon: String, mode: String) -> some View {
        Link(destination: URL(string: "sonycontrol://mode/\(mode)")!) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(state?.mode.lowercased() == mode ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
}
struct SonyControlWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.kind, provider: HeadphoneProvider()) { entry in
            HeadphoneWidgetView(entry: entry)
        }
        .configurationDisplayName("Sony Headphones")
        .description("Headphone battery and noise control. Tap a mode to apply it through Sony Control.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SonyControlWidgets: WidgetBundle {
    var body: some Widget { SonyControlWidget() }
}
