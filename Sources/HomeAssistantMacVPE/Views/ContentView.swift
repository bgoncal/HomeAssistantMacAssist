import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        AssistDashboard(model: model)
    }
}

private struct AssistDashboard: View {
    @ObservedObject var model: AppModel

    private let haBlue = HAStyle.blue
    private let haBlueDeep = HAStyle.blueDeep
    private let haOrange = HAStyle.orange
    private let haSurface = HAStyle.surface
    private let haCard = HAStyle.card
    private let haBorder = HAStyle.border

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                metrics

                HStack(alignment: .top, spacing: 20) {
                    settingsPanel
                    activityPanel
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(backgroundGradient)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 58, height: 58)

                    Image(systemName: "house.fill")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Home Assistant Mac VPE")
                        .font(.system(size: 31, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("A Home Assistant-style Mac voice endpoint for Assist pipelines.")
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.88))
                }

                Spacer(minLength: 12)
            }

            HStack(alignment: .bottom, spacing: 16) {
                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button {
                        Task { await model.refreshPipelines() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(HAOutlineButtonStyle(accent: .white))
                    .disabled(model.isLoadingPipelines)

                    Button {
                        Task { await model.toggleSession() }
                    } label: {
                        Label(model.isSessionActive ? "Stop" : "Listen", systemImage: model.isSessionActive ? "stop.fill" : "mic.fill")
                    }
                    .buttonStyle(HAActionButtonStyle(fill: haOrange, text: .white))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [haBlue, haBlueDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .shadow(color: haBlue.opacity(0.22), radius: 18, y: 8)
    }

    private var metrics: some View {
        HStack(spacing: 16) {
            MetricTile(title: "Status", value: model.state.title, accent: statusTint, symbol: "dot.radiowaves.left.and.right")
            MetricTile(title: "Pipeline", value: selectedPipelineName, accent: haBlue, symbol: "point.3.connected.trianglepath.dotted")
            MetricTile(title: "Microphone", value: selectedInputName, accent: haOrange, symbol: "mic.fill")
            MetricTile(title: "Speaker", value: selectedOutputName, accent: .green, symbol: "speaker.wave.2.fill")
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Home Assistant", icon: "house.and.flag")

            FieldGroup(title: "URL") {
                TextField("http://homeassistant.local:8123", text: model.binding(\.homeAssistantURL))
                    .textFieldStyle(.roundedBorder)
            }

            FieldGroup(title: "Long-lived Access Token") {
                SecureField("Token", text: model.binding(\.accessToken))
                    .textFieldStyle(.roundedBorder)
            }

            FieldGroup(title: "Assist Pipeline") {
                PipelinePicker(model: model)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Behavior", icon: "slider.horizontal.3")
                Toggle("Use Home Assistant wake word detection", isOn: model.binding(\.useWakeWord))
                Toggle("Launch automatically when I log in", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { model.updateLoginItem($0) }
                ))
                Toggle("Start listening when the app opens", isOn: model.binding(\.startListeningOnLaunch))
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Audio Devices", icon: "waveform")

                Picker("Microphone", selection: model.binding(\.selectedInputUID)) {
                    ForEach(model.inputDevices) { device in
                        Text(device.displayName).tag(device.uid)
                    }
                }

                Picker("Speaker", selection: model.binding(\.selectedOutputUID)) {
                    ForEach(model.outputDevices) { device in
                        Text(device.displayName).tag(device.uid)
                    }
                }

                Button {
                    model.refreshAudioDevices()
                } label: {
                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                }
                .buttonStyle(HAOutlineButtonStyle(accent: haBlue))
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Audio Processing", icon: "waveform.path.ecg")

                ProcessingSlider(
                    title: "Mic gain",
                    value: model.clampedDoubleBinding(\.micGain, range: 0.25...12.0),
                    range: 0.25...12.0,
                    step: 0.25,
                    valueText: String(format: "%.2fx", model.settings.micGain)
                )

                ProcessingSlider(
                    title: "Noise suppression",
                    value: model.integerSliderBinding(\.noiseSuppressionLevel, range: 0...4),
                    range: 0...4,
                    step: 1,
                    valueText: "\(model.settings.noiseSuppressionLevel)"
                )

                ProcessingSlider(
                    title: "Auto gain",
                    value: model.integerSliderBinding(\.autoGainDBFS, range: 0...31),
                    range: 0...31,
                    step: 1,
                    valueText: "\(model.settings.autoGainDBFS) dBFS"
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Sound Feedback", icon: "speaker.wave.2")
                Toggle("Wake word detected", isOn: model.binding(\.playWakeWordSound))
                Toggle("Processing started", isOn: model.binding(\.playProcessingSound))
                Toggle("Ready for wake word", isOn: model.binding(\.playReadyForWakeWordSound))
            }
        }
        .padding(20)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 460, alignment: .leading)
        .background(panelBackground(accent: haBlue))
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                sectionHeader("Activity", icon: "list.bullet.rectangle.portrait")

                Spacer()

                Text("\(model.logs.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(haBlue.opacity(0.10))
                    )
            }

            if model.logs.isEmpty {
                PlaceholderPanel(message: "Assist activity will appear here after the app connects to Home Assistant.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.logs, id: \.self) { line in
                            LogRow(line: line, accent: haBlue)
                        }
                    }
                    .padding(14)
                }
                .frame(minHeight: 520)
                .background(tileBackground(highlight: Color.black.opacity(0.025)))
            }
        }
        .padding(20)
        .frame(minWidth: 420, maxWidth: .infinity, alignment: .leading)
        .background(panelBackground(accent: haOrange))
    }

    private var backgroundGradient: some View {
        haSurface
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [haBlue.opacity(0.14), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
                .ignoresSafeArea()
            }
    }

    private func panelBackground(accent: Color) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(haCard)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(haBorder, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.16), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 82)
                    .mask(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .shadow(color: Color.black.opacity(0.05), radius: 10, y: 3)
    }

    private func tileBackground(highlight: Color) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(haBorder, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(highlight)
            )
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(haBlue)
            Text(title)
                .font(.title3.weight(.semibold))
        }
    }

    private var statusTint: Color {
        switch model.state {
        case .idle:
            .secondary
        case .connecting, .thinking:
            haOrange
        case .waitingForWakeWord:
            haBlueDeep
        case .listening:
            .green
        case .speaking:
            .teal
        case .error:
            .red
        }
    }

    private var selectedPipelineName: String {
        model.pipelines.first(where: { $0.id == model.settings.pipelineID })?.displayName ?? "Not selected"
    }

    private var selectedInputName: String {
        model.inputDevices.first(where: { $0.uid == model.settings.selectedInputUID })?.displayName ?? "Default"
    }

    private var selectedOutputName: String {
        model.outputDevices.first(where: { $0.uid == model.settings.selectedOutputUID })?.displayName ?? "Default"
    }
}

struct PipelinePicker: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack {
            Picker("Pipeline", selection: model.binding(\.pipelineID)) {
                if model.pipelines.isEmpty {
                    Text("Load pipelines from Home Assistant").tag("")
                } else {
                    ForEach(model.pipelines) { pipeline in
                        Text(pipeline.displayName).tag(pipeline.id)
                    }
                }
            }
            .labelsHidden()
            .disabled(model.pipelines.isEmpty || model.isLoadingPipelines)

            Button {
                Task { await model.refreshPipelines() }
            } label: {
                if model.isLoadingPipelines {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(HAOutlineButtonStyle(accent: HAStyle.blue))
            .help("Load Assist pipelines from Home Assistant")
        }
    }
}

struct ProcessingSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

private struct FieldGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let accent: Color
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(accent)
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        }
    }
}

private struct LogRow: View {
    let line: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(timestamp)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Text(message)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.06))
        )
    }

    private var timestamp: String {
        String(line.prefix(8))
    }

    private var message: String {
        let startIndex = line.index(line.startIndex, offsetBy: min(10, line.count))
        return String(line[startIndex...])
    }
}

private struct PlaceholderPanel: View {
    let message: String

    var body: some View {
        Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
    }
}

struct HAActionButtonStyle: ButtonStyle {
    let fill: Color
    let text: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.82 : 1))
            )
    }
}

struct HAOutlineButtonStyle: ButtonStyle {
    let accent: Color

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let foregroundColor = isEnabled ? accent.opacity(configuration.isPressed ? 0.82 : 1) : .secondary.opacity(0.7)
        let backgroundColor = isEnabled ? Color.white.opacity(configuration.isPressed ? 0.12 : 0.08) : Color.black.opacity(0.035)
        let borderColor = isEnabled ? accent.opacity(0.4) : Color.black.opacity(0.08)

        configuration.label
            .font(.headline)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

enum HAStyle {
    static let blue = Color(red: 3 / 255, green: 169 / 255, blue: 244 / 255)
    static let blueDeep = Color(red: 2 / 255, green: 119 / 255, blue: 189 / 255)
    static let orange = Color(red: 255 / 255, green: 152 / 255, blue: 0 / 255)
    static let surface = Color(red: 245 / 255, green: 247 / 255, blue: 250 / 255)
    static let card = Color.white.opacity(0.98)
    static let border = Color(red: 225 / 255, green: 229 / 255, blue: 234 / 255)
}
