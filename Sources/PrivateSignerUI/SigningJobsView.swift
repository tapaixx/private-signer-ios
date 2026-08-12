#if os(iOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PrivateSignerKit

/// The general-purpose signing screen: pick a source IPA, choose options, submit, and follow the
/// resulting Signing Jobs.
public struct SigningJobsView: View {
    @Environment(\.scenePhase) private var scenePhase

    private let context: SignerUIContext

    @State private var environment: SignerEnvironment
    @State private var configuration: SignerConfiguration?
    @State private var showingConfiguration = false
    @State private var sourceKind = SourceKind.url
    @State private var sourceURLText = ""
    @State private var selectedFileURL: URL?
    @State private var showingFileImporter = false
    @State private var showingAdvanced = false
    @State private var signingMode = SigningMode.split
    @State private var targetBundleID = ""
    @State private var profileID = ""
    @State private var keychainGroups = ""
    @State private var requireAllBundles = false
    @State private var requireAllEntitlements = false
    @State private var jobs: [SigningJob] = []
    @State private var linksByJob: [String: DeliveryLinks] = [:]
    @State private var isSubmitting = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    public init(context: SignerUIContext, environment: SignerEnvironment = .default) {
        self.context = context
        _environment = State(initialValue: environment)
        _profileID = State(initialValue: context.defaultProfileID ?? "")
    }

    public var body: some View {
        Form {
            configurationSection
            sourceSection
            optionsSection
            submitSection
            historySection
        }
        .navigationTitle(UIStrings.string("jobs.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingConfiguration) {
            NavigationView {
                SignerConfigurationEditorView(context: context, environment: environment) { saved, savedEnvironment in
                    configuration = saved
                    environment = savedEnvironment
                    Task { await refreshHistory() }
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                selectedFileURL = urls.first
                errorMessage = nil
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .task {
            loadConfiguration()
            await refreshHistory()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if scenePhase == .active && jobs.contains(where: \.isActive) {
                    await pollActiveJobs()
                }
            }
        }
    }

    @ViewBuilder
    private var configurationSection: some View {
        Section(UIStrings.string("jobs.service")) {
            if let configuration {
                HStack {
                    Label("Worker", systemImage: "lock.shield.fill")
                    Spacer()
                    Text(configuration.workerURL.host ?? UIStrings.string("jobs.configured"))
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }
                if context.environments.count > 1 {
                    HStack {
                        Text(UIStrings.string("editor.environment"))
                        Spacer()
                        Text(environment.name).foregroundStyle(.secondary)
                    }
                }
                Button(UIStrings.string("jobs.edit_service")) { showingConfiguration = true }
            } else {
                Text(UIStrings.string("jobs.configure_hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(UIStrings.string("jobs.configure")) { showingConfiguration = true }
            }
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        Section(UIStrings.string("jobs.source")) {
            Picker(UIStrings.string("jobs.source_kind"), selection: $sourceKind) {
                ForEach(SourceKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .pickerStyle(.segmented)

            if sourceKind == .url {
                TextField("https://example.com/App.ipa", text: $sourceURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } else {
                Button {
                    showingFileImporter = true
                } label: {
                    Label(
                        selectedFileURL?.lastPathComponent ?? UIStrings.string("jobs.pick_file"),
                        systemImage: "doc.badge.plus"
                    )
                }
                Text(UIStrings.string("jobs.upload_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        Section {
            Picker(UIStrings.string("jobs.signing_mode"), selection: $signingMode) {
                Text(UIStrings.string("jobs.mode_split")).tag(SigningMode.split)
                Text(UIStrings.string("jobs.mode_standard")).tag(SigningMode.standard)
            }
            Button(showingAdvanced ? UIStrings.string("jobs.hide_advanced") : UIStrings.string("jobs.show_advanced")) {
                showingAdvanced.toggle()
            }
            if showingAdvanced {
                TextField(UIStrings.string("jobs.target_bundle_id"), text: $targetBundleID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(UIStrings.string("jobs.profile_id"), text: $profileID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                VStack(alignment: .leading, spacing: 6) {
                    Text(UIStrings.string("jobs.keychain_groups")).font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $keychainGroups)
                        .frame(minHeight: 72)
                        .font(.footnote.monospaced())
                }
                Toggle(UIStrings.string("jobs.require_bundles"), isOn: $requireAllBundles)
                Toggle(UIStrings.string("jobs.require_entitlements"), isOn: $requireAllEntitlements)
            }
        } header: {
            Text(UIStrings.string("jobs.options"))
        } footer: {
            Text(UIStrings.string("jobs.options_footer"))
        }
    }

    @ViewBuilder
    private var submitSection: some View {
        Section {
            Button {
                Task { await submit() }
            } label: {
                if isSubmitting {
                    HStack { ProgressView(); Text(UIStrings.string("jobs.submitting")) }
                } else {
                    Label(UIStrings.string("jobs.submit"), systemImage: "signature")
                }
            }
            .disabled(configuration == nil || isSubmitting || !sourceReady)

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section {
            if jobs.isEmpty {
                Text(UIStrings.string("jobs.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(jobs) { job in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(job.actualTitle ?? job.source ?? "IPA")
                                .font(.headline)
                                .lineLimit(1)
                            Spacer()
                            statusLabel(job.status)
                        }
                        Text(job.jobID).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        if let bundle = job.actualBundleIdentifier {
                            Text(bundle).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        if let message = job.message, !message.isEmpty {
                            Text(message).font(.caption).foregroundStyle(job.status.isFailure ? .red : .secondary)
                        }
                        HStack {
                            if job.status == .completed {
                                Button(UIStrings.string("jobs.get_links")) { Task { await loadLinks(for: job) } }
                            } else if job.status.isFailure {
                                Button(UIStrings.string("jobs.retry")) { Task { await retry(job) } }
                            } else if job.isActive {
                                Button(UIStrings.string("jobs.cancel"), role: .destructive) { Task { await cancel(job) } }
                            }
                        }
                        if let links = linksByJob[job.jobID] {
                            Button(UIStrings.string("jobs.install")) { UIApplication.shared.open(links.installURL) }
                            Button(UIStrings.string("jobs.export")) { UIApplication.shared.open(links.exportURL) }
                            Text(UIStrings.string("jobs.links_expire", links.expiresAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            HStack {
                Text(UIStrings.string("jobs.recent"))
                Spacer()
                if isRefreshing { ProgressView() }
                Button(UIStrings.string("jobs.refresh")) { Task { await refreshHistory() } }.disabled(isRefreshing)
            }
        } footer: {
            Text(UIStrings.string("jobs.recent_footer"))
        }
    }

    private var sourceReady: Bool {
        switch sourceKind {
        case .url: return URL(string: sourceURLText)?.scheme?.lowercased() == "https"
        case .file: return selectedFileURL != nil
        }
    }

    private var options: SigningOptions {
        SigningOptions(
            signingMode: signingMode,
            targetBundleIdentifier: nilIfEmpty(targetBundleID),
            profileID: nilIfEmpty(profileID),
            keychainAccessGroups: keychainGroups
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            embeddedBundlePolicy: requireAllBundles ? .requireAll : .stripUnsupported,
            entitlementPolicy: requireAllEntitlements ? .requireAll : .stripUnsupported
        )
    }

    private func client(_ configuration: SignerConfiguration) -> SigningClient {
        SigningClient(configuration: configuration, userAgent: context.userAgent)
    }

    @MainActor
    private func submit() async {
        guard let configuration else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let client = client(configuration)
            let job: SigningJob
            switch sourceKind {
            case .url:
                guard let url = URL(string: sourceURLText), url.scheme?.lowercased() == "https" else {
                    throw SigningClientError.invalidURL
                }
                job = try await client.createURLJob(sourceURL: url, options: options)
            case .file:
                guard let fileURL = selectedFileURL else { throw SigningClientError.invalidURL }
                let accessed = fileURL.startAccessingSecurityScopedResource()
                defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
                job = try await client.uploadAndCreateJob(fileURL: fileURL, options: options)
            }
            jobs.removeAll { $0.jobID == job.jobID }
            jobs.insert(job, at: 0)
            await refreshHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshHistory() async {
        guard !isRefreshing, let configuration else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            jobs = try await client(configuration).history()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func pollActiveJobs() async {
        guard let configuration else { return }
        let client = client(configuration)
        for index in jobs.indices where jobs[index].isActive {
            do {
                jobs[index] = try await client.job(id: jobs[index].jobID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func retry(_ job: SigningJob) async {
        guard let configuration else { return }
        do {
            _ = try await client(configuration).retry(jobID: job.jobID)
            await refreshHistory()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func cancel(_ job: SigningJob) async {
        guard let configuration else { return }
        do {
            _ = try await client(configuration).cancel(jobID: job.jobID)
            await refreshHistory()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func loadLinks(for job: SigningJob) async {
        guard let configuration else { return }
        do {
            linksByJob[job.jobID] = try await client(configuration).links(jobID: job.jobID)
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadConfiguration() {
        do { configuration = try context.store(for: environment).load() }
        catch { errorMessage = error.localizedDescription }
    }

    @ViewBuilder
    private func statusLabel(_ status: SigningJobStatus) -> some View {
        let display: (String, Color) = switch status {
        case .completed: (UIStrings.string("status.completed"), .green)
        case .failed, .dispatchFailed: (UIStrings.string("status.failed"), .red)
        case .cancelled: (UIStrings.string("status.cancelled"), .secondary)
        case .signing: (UIStrings.string("status.signing"), .orange)
        case .following: (UIStrings.string("status.following"), .orange)
        case .dispatching, .queued: (UIStrings.string("status.queued"), .orange)
        case .unknown(let value): (UIStrings.string("status.unknown", value), .secondary)
        }
        Text(display.0).font(.caption).foregroundStyle(display.1)
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum SourceKind: String, CaseIterable, Identifiable {
    case url
    case file

    var id: String { rawValue }
    var title: String {
        self == .url ? UIStrings.string("jobs.source_url") : UIStrings.string("jobs.source_file")
    }
}
#endif
