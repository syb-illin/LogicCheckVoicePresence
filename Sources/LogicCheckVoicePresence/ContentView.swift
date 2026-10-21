import SwiftUI
import AppKit
import UniformTypeIdentifiers
import VoicePresenceCore

struct ContentView: View {
    @State private var model = ScanViewModel()
    @State private var selection: ProjectInspection.ID?
    @State private var showingAbout = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            resultsPane
        }
        .navigationTitle(AppInfo.name)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingAbout) { AboutView(model: model) }
        .task { await model.checkForUpdates() }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
    }

    // MARK: - Barre latérale

    private var sidebar: some View {
        List(selection: $model.verdictFilter) {
            Section("Dossier") {
                if let folder = model.folder {
                    Label(folder.lastPathComponent, systemImage: "folder.fill")
                        .help(folder.path)
                    Text(folder.deletingLastPathComponent().path)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head)
                } else {
                    Text("Aucun dossier choisi")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Choisir un dossier…", systemImage: "folder.badge.plus") { pickFolder() }
                    .buttonStyle(.link)
            }

            Section("Bus recherché") {
                TextField("voice bus", text: $model.busName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.rescan() }
                Text("Comparaison par inclusion, casse ignorée.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if !model.inspections.isEmpty {
                Section("Verdicts") {
                    verdictRow(nil, label: "Tout", count: model.inspections.count)
                    ForEach(model.verdictCounts) { entry in
                        verdictRow(entry.verdict,
                                   label: VerdictStyle.shortLabel(entry.verdict),
                                   count: entry.count)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 230)
    }

    private func verdictRow(_ verdict: Verdict?, label: String, count: Int) -> some View {
        HStack {
            if let verdict {
                Image(systemName: VerdictStyle.symbol(verdict))
                    .foregroundStyle(VerdictStyle.color(verdict))
            } else {
                Image(systemName: "list.bullet").foregroundStyle(.secondary)
            }
            Text(label)
            Spacer()
            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
        }
        .contentShape(.rect)
        .onTapGesture { model.verdictFilter = verdict }
        .background(model.verdictFilter == verdict && verdict != nil
                    ? Color.accentColor.opacity(0.12) : .clear)
        .help(verdict?.rationale ?? "Tous les projets analysés")
    }

    // MARK: - Panneau de résultats

    private var resultsPane: some View {
        VStack(spacing: 0) {
            if model.phase.isBusy || model.progress.total > 0 {
                progressBanner
                Divider()
            }
            if model.inspections.isEmpty {
                emptyState
            } else {
                resultsTable
            }
        }
    }

    private var progressBanner: some View {
        HStack(spacing: 12) {
            if model.phase.isBusy {
                ProgressView(value: model.progress.fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 180)
            }
            Text(statusText)
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            if model.phase.isBusy {
                Button("Annuler", role: .cancel) { model.cancel() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private var statusText: String {
        switch model.phase {
        case .idle: ""
        case .scanning, .analyzingAudio: model.progress.label
        case .done(let message): message
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Aucun projet analysé", systemImage: "waveform.badge.magnifyingglass")
        } description: {
            Text("Choisis un dossier contenant tes projets .logicx, ou dépose-le ici.")
        } actions: {
            Button("Choisir un dossier…") { pickFolder() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var resultsTable: some View {
        Table(model.filteredInspections, selection: $selection) {
            TableColumn("Projet") { item in
                Text(item.name).fontWeight(item.verdict == .undecidable ? .semibold : .regular)
            }
            .width(min: 160, ideal: 220)

            TableColumn("Verdict") { item in VerdictBadge(verdict: item.verdict) }
                .width(min: 150, ideal: 170)

            TableColumn("Bus") { item in
                Text(item.busLabel).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 90, ideal: 130)

            TableColumn("Liés") { item in
                Text(item.analysis.hasBus ? "\(item.linkedChannelCount)" : "—").monospacedDigit()
            }
            .width(48)

            TableColumn("Régions") { item in
                Text(item.analysis.hasBus ? "\(item.firmRegions)" : "—").monospacedDigit()
            }
            .width(62)

            TableColumn("Ambiguës") { item in
                Text(item.ambiguousRegions > 0 ? "\(item.ambiguousRegions)" : "—")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .width(72)

            TableColumn("Fichiers") { item in
                Text("\(item.audioFileCount)").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(62)

            TableColumn("Audio") { item in
                Text(item.audioNote ?? "—")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .width(min: 110, ideal: 160)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: ProjectInspection.ID.self) { ids in
            if let id = ids.first, let item = inspection(id) {
                Button("Ouvrir le détail") { selection = id }
                Button("Révéler dans le Finder") { reveal(item.url) }
                if item.audioFileCount > 0 {
                    Button("Analyser l'audio") { model.analyzeAudio(for: item) }
                }
            }
        } primaryAction: { ids in
            selection = ids.first
        }
        .sheet(item: Binding(
            get: { selection.flatMap(inspection) },
            set: { if $0 == nil { selection = nil } }
        )) { item in
            ProjectDetailView(inspection: item) { model.analyzeAudio(for: item) }
        }
    }

    private func inspection(_ id: ProjectInspection.ID) -> ProjectInspection? {
        model.inspections.first { $0.id == id }
    }

    // MARK: - Barre d'outils

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if model.pendingAudioAnalysisCount > 0 && !model.phase.isBusy {
                Button {
                    model.analyzePendingAudio()
                } label: {
                    Label("Analyser l'audio (\(model.pendingAudioAnalysisCount))",
                          systemImage: "waveform")
                }
                .help("Décode les fichiers audio des seuls projets indécidables. "
                      + "Coûteux : le scan ne le fait jamais automatiquement.")
            }

            Button {
                model.rescan()
            } label: {
                Label("Relancer", systemImage: "arrow.clockwise")
            }
            .disabled(model.folder == nil || model.phase.isBusy)

            Button {
                exportCSV()
            } label: {
                Label("Exporter CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(!model.canExport)

            Button {
                showingAbout = true
            } label: {
                Label("À propos", systemImage: "info.circle")
            }
        }
    }

    // MARK: - Actions

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choisis le dossier contenant tes projets .logicx"
        panel.prompt = "Analyser"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.scan(folder: url)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.hasDirectoryPath || url.pathExtension == ProjectLocator.bundleExtension
            else { return }
            Task { @MainActor in model.scan(folder: url) }
        }
        return true
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.defaultExportFileName()
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.csv().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.ui.error("Export impossible : \(error.localizedDescription, privacy: .public)")
            NSAlert(error: error).runModal()
        }
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
