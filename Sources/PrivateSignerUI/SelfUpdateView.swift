#if os(iOS)
import SwiftUI
import UIKit
import PrivateSignerKit
import PrivateSignerSelfUpdate

/// The self-update screen: check for a newer build, have it signed, install it.
///
/// Installing a side-by-side clone lives behind the advanced disclosure and renames the primary
/// button, because it does something visibly different — it leaves the running app in place and
/// adds a second icon.
public struct SelfUpdateView: View {
    @Environment(\.scenePhase) private var scenePhase

    private let context: SignerUIContext
    private let releaseSource: ReleaseSource
    private let currentVersion: String
    private let installedBundleIdentifier: String
    private let signingMode: SigningMode

    @State private var environment: SignerEnvironment
    @State private var configuration: SignerConfiguration?
    @State private var showingConfiguration = false
    @State private var candidate: ReleaseCandidate?
    @State private var checkedOnce = false
    @State private var isChecking = false
    @State private var isRequesting = false
    @State private var result: SelfUpdateResult?
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showingAdvanced = false
    @State private var installAsClone = false
    @State private var cloneBundleID = ""

    public init(
        context: SignerUIContext,
        releaseSource: ReleaseSource,
        currentVersion: String,
        installedBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "",
        environment: SignerEnvironment = .default,
        signingMode: SigningMode = .split
    ) {
        self.context = context
        self.releaseSource = releaseSource
        self.currentVersion = currentVersion
        self.installedBundleIdentifier = installedBundleIdentifier
        self.signingMode = signingMode
        _environment = State(initialValue: environment)
        _cloneBundleID = State(initialValue: installedBundleIdentifier.isEmpty ? "" : installedBundleIdentifier + ".clone")
    }

    public var body: some View {
        Form {
            versionSection
            configurationSection
            actionSection
            advancedSection
            resultSection
        }
        .navigationTitle(UIStrings.string("update.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingConfiguration) {
            NavigationView {
                SignerConfigurationEditorView(context: context, environment: environment) { saved, savedEnvironment in
                    configuration = saved
                    environment = savedEnvironment
                }
            }
        }
        .task {
            loadConfiguration()
            await check()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if scenePhase == .active, result?.job.isActive == true {
                    await refreshJob()
                }
            }
        }
    }

    @ViewBuilder
    private var versionSection: some View {
        Section(UIStrings.string("update.version_section")) {
            LabeledRow(title: UIStrings.string("update.installed_version"), value: currentVersion)
            if let candidate {
                LabeledRow(title: UIStrings.string("update.latest_version"), value: candidate.version)
            } else if checkedOnce && !isChecking {
                Text(UIStrings.string("update.up_to_date"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await check() }
            } label: {
                if isChecking {
                    HStack { ProgressView(); Text(UIStrings.string("update.checking")) }
                } else {
                    Label(UIStrings.string("update.check"), systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(isChecking)
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
    private var actionSection: some View {
        Section {
            Button {
                Task { await requestSignedBuild() }
            } label: {
                if isRequesting {
                    HStack { ProgressView(); Text(UIStrings.string("update.requesting")) }
                } else {
                    Label(primaryActionTitle, systemImage: installAsClone ? "plus.square.on.square" : "arrow.down.app")
                }
            }
            .disabled(configuration == nil || candidate == nil || isRequesting)

            if installAsClone {
                Text(UIStrings.string("update.clone_warning"))
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            if let notes = candidate?.notes, !notes.isEmpty {
                Text(notes).font(.caption)
            }
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        Section {
            Button(showingAdvanced ? UIStrings.string("jobs.hide_advanced") : UIStrings.string("jobs.show_advanced")) {
                showingAdvanced.toggle()
            }
            if showingAdvanced {
                Toggle(UIStrings.string("update.install_as_clone"), isOn: $installAsClone)
                if installAsClone {
                    TextField(UIStrings.string("update.clone_bundle_id"), text: $cloneBundleID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Text(UIStrings.string("update.clone_explainer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let result {
            Section(UIStrings.string("update.result_section")) {
                LabeledRow(title: UIStrings.string("update.job_status"), value: result.job.status.rawValue)
                LabeledRow(title: UIStrings.string("update.target_bundle"), value: result.targetBundleIdentifier)
                if !result.willReplaceInstalledApp {
                    Text(UIStrings.string("update.will_not_replace"))
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if let message = result.job.message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(result.job.status.isFailure ? .red : .secondary)
                }
                if let statusMessage {
                    Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                }
                if let installURL = result.installationURL {
                    Button(UIStrings.string("update.install")) { UIApplication.shared.open(installURL) }
                } else if result.job.isActive {
                    HStack { ProgressView(); Text(UIStrings.string("update.waiting")) }
                }
                Button(UIStrings.string("jobs.refresh")) { Task { await refreshJob() } }
            }
        }
    }

    private var primaryActionTitle: String {
        if installAsClone { return UIStrings.string("update.install_clone_action") }
        guard let candidate else { return UIStrings.string("update.check") }
        return UIStrings.string("update.update_to", candidate.version)
    }

    private var target: SelfUpdateTarget {
        installAsClone ? .sideBySideClone(bundleID: cloneBundleID) : .installedApp
    }

    private func coordinator() -> SelfUpdateCoordinator {
        SelfUpdateCoordinator(
            store: context.store(for: environment),
            releaseSource: releaseSource,
            currentVersion: currentVersion,
            userAgent: context.userAgent,
            installedBundleIdentifier: installedBundleIdentifier,
            profileID: context.defaultProfileID,
            signingMode: signingMode
        )
    }

    @MainActor
    private func check() async {
        isChecking = true
        errorMessage = nil
        defer {
            isChecking = false
            checkedOnce = true
        }
        do {
            candidate = try await coordinator().checkForUpdate()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func requestSignedBuild() async {
        guard let candidate else { return }
        isRequesting = true
        errorMessage = nil
        statusMessage = nil
        defer { isRequesting = false }
        do {
            result = try await coordinator().requestSignedBuild(of: candidate, target: target)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshJob() async {
        guard let current = result else { return }
        do {
            result = try await coordinator().refresh(jobID: current.job.jobID, target: target)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func loadConfiguration() {
        do { configuration = try context.store(for: environment).load() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct LabeledRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
#endif
