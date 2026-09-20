import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var exporter: SleepExporter
    @State private var isChoosingFolder = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    LabeledContent("State", value: exporter.status)
                    LabeledContent("Sessions", value: String(exporter.sessionCount))
                    LabeledContent("Samples", value: String(exporter.sampleCount))

                    if let lastExport = exporter.lastExport {
                        LabeledContent("Last export") {
                            Text(lastExport, style: .relative)
                        }
                    }
                }

                Section("Output") {
                    LabeledContent("Folder", value: exporter.outputFolderName)
                    Text("Selected folder ▸ sleep.json")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    Text("Choose a folder in iCloud Drive. The file contains the latest 14 days of sleep sessions and syncs to Macs signed into the same Apple Account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button(exporter.hasOutputFolder ? "Change Output Folder" : "Choose Output Folder") {
                        isChoosingFolder = true
                    }
                }

                Section {
                    Button {
                        Task {
                            await exporter.requestAuthorizationAndExport()
                        }
                    } label: {
                        HStack {
                            Text("Export Now")
                            Spacer()
                            if exporter.isWorking {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(exporter.isWorking)
                }

                if let error = exporter.lastError {
                    Section("Last error") {
                        Text(error)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }

                Section("Background updates") {
                    Text("HealthKit can wake Sleep Sync when sleep samples change. Delivery timing is controlled by iOS and is not a fixed schedule.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sleep Sync")
            .fileImporter(
                isPresented: $isChoosingFolder,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    await exporter.handleFolderSelection(result)
                }
            }
        }
    }
}
