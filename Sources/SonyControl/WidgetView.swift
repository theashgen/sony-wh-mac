import SwiftUI

/// The menu bar surface uses system typography, materials, and standard controls.
struct WidgetView: View {
    @ObservedObject var model: ControlModel
    private var selectedMode: String {
        model.pendingMode ?? (model.status?.mode.lowercased() ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "headphones")
                    .font(.system(size: 25, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("WH-CH720N").font(.headline)
                    Text(model.connected ? "Connected" : "Disconnected")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label(model.status?.battery.map { "\($0)%" } ?? "—", systemImage: batterySymbol)
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(model.connected ? .primary : .secondary)
                    .help(model.connected ? "Headphone battery" : "Last known battery")
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Noise Control").font(.subheadline.weight(.semibold))
                Picker("Noise Control", selection: Binding(
                    get: { selectedMode }, set: { model.enqueue(.mode($0)) }
                )) {
                    Text("Noise Cancelling").tag("anc")
                    Text("Ambient").tag("ambient")
                    Text("Off").tag("off")
                }.pickerStyle(.segmented).labelsHidden().disabled(!model.connected)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Ambient Sound").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(model.sliderLevel))").font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.1").foregroundStyle(.secondary)
                    Slider(value: $model.sliderLevel, in: 1...20, step: 1) { editing in
                        model.sliderEditing = editing
                        if !editing { model.enqueue(.level(Int(model.sliderLevel))) }
                    }.accessibilityLabel("Ambient sound level")
                    Image(systemName: "speaker.wave.3").foregroundStyle(.secondary)
                }
                Toggle("Focus on Voice", isOn: Binding(
                    get: { model.pendingVoice ?? model.status?.voice ?? false },
                    set: { model.enqueue(.voice($0)) }
                )).toggleStyle(.switch).controlSize(.small)
            }
            .padding(14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            .disabled(!model.connected)
            Picker("Equalizer", selection: Binding(
                get: { model.pendingPreset ?? model.status?.preset ?? "off" },
                set: { model.enqueue(.eq($0)) }
            )) {
                ForEach(presets.map(\.0), id: \.self) { name in Text(presetLabel(name)).tag(name) }
            }.disabled(!model.connected)
            Divider()
            HStack(spacing: 7) {
                if model.working { ProgressView().controlSize(.mini) }
                Text(model.error ?? (model.working ? model.message : "Sony Control"))
                    .font(.caption).foregroundStyle(model.error == nil ? Color.secondary : Color.orange)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button { model.enqueue(.refresh) } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.borderless).help(model.connected ? "Refresh" : "Reconnect")
            }
        }
        .padding(20)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }
    private var batterySymbol: String {
        switch model.status?.battery ?? 0 {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

func presetLabel(_ name: String) -> String {
    switch name {
    case "off": return "Off"
    case "treble": return "Treble Boost"
    case "bass": return "Bass Boost"
    case "speech": return "Speech"
    case "custom1": return "Custom 1"
    case "custom2": return "Custom 2"
    default: return name.capitalized
    }
}
