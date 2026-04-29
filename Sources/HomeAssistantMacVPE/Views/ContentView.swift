import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        DetailView(model: model)
    }
}

private struct DetailView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ConnectionSection(model: model)
                        BehaviorSection(model: model)
                        AudioSection(model: model)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(minWidth: 520, idealWidth: 640)

                ActivityPane(logs: model.logs)
                    .frame(minWidth: 360, idealWidth: 420)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            StatusBadge(state: model.state)
            Spacer()
            Button {
                model.refreshAudioDevices()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh audio devices")

            Button {
                Task { await model.toggleSession() }
            } label: {
                Label(model.isSessionActive ? "Stop" : "Listen", systemImage: model.isSessionActive ? "stop.fill" : "mic.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

private struct ConnectionSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SectionBox(title: "Home Assistant", systemImage: "house") {
            TextField("http://homeassistant.local:8123", text: model.binding(\.homeAssistantURL))
                .textFieldStyle(.roundedBorder)

            SecureField("Long-lived access token", text: model.binding(\.accessToken))
                .textFieldStyle(.roundedBorder)

            PipelinePicker(model: model)
        }
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
            .help("Load Assist pipelines from Home Assistant")
        }
    }
}

private struct BehaviorSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SectionBox(title: "Behavior", systemImage: "slider.horizontal.3") {
            Toggle("Use Home Assistant wake word detection", isOn: model.binding(\.useWakeWord))

            Toggle("Launch automatically when I log in", isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.updateLoginItem($0) }
            ))

            Toggle("Start listening when the app opens", isOn: model.binding(\.startListeningOnLaunch))
        }
    }
}

private struct AudioSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SectionBox(title: "Audio", systemImage: "waveform") {
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
        }
    }
}

private struct ActivityPane: View {
    let logs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Activity", systemImage: "list.bullet.rectangle")
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)

            ScrollView {
                if logs.isEmpty {
                    Text("No activity yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(logs, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(18)
                }
            }
        }
        .background(.thinMaterial)
    }
}

private struct StatusBadge: View {
    let state: AssistantState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(state.title)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    private var color: Color {
        switch state {
        case .idle: .secondary
        case .connecting, .thinking: .orange
        case .waitingForWakeWord: .purple
        case .listening: .green
        case .speaking: .teal
        case .error: .red
        }
    }
}

private struct SectionBox<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
