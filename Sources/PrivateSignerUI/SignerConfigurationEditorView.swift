#if os(iOS)
import SwiftUI
import PrivateSignerKit

/// Collects the Worker URL and Signing Request Token, and — before saving — says which of the two
/// is wrong when something does not work.
public struct SignerConfigurationEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let context: SignerUIContext
    private let onSaved: (SignerConfiguration, SignerEnvironment) -> Void

    @State private var environment: SignerEnvironment
    @State private var workerURLText: String
    @State private var tokenText: String
    @State private var errorMessage: String?
    @State private var verification: ConfigurationVerification?
    @State private var isVerifying = false

    public init(
        context: SignerUIContext,
        environment: SignerEnvironment = .default,
        onSaved: @escaping (SignerConfiguration, SignerEnvironment) -> Void
    ) {
        self.context = context
        self.onSaved = onSaved
        let existing = try? context.store(for: environment).load()
        _environment = State(initialValue: environment)
        _workerURLText = State(initialValue: existing?.workerURL.absoluteString ?? "")
        _tokenText = State(initialValue: existing?.requestToken ?? "")
    }

    public var body: some View {
        Form {
            if context.environments.count > 1 {
                Section(UIStrings.string("editor.environment")) {
                    Picker(UIStrings.string("editor.environment"), selection: $environment) {
                        ForEach(context.environments, id: \.self) { candidate in
                            Text(candidate.name).tag(candidate)
                        }
                    }
                    .onChange(of: environment) { newValue in reload(for: newValue) }
                }
            }

            Section(UIStrings.string("editor.section")) {
                TextField(UIStrings.string("editor.worker_placeholder"), text: $workerURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField(UIStrings.string("editor.token_placeholder"), text: $tokenText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    Task { await verify() }
                } label: {
                    if isVerifying {
                        HStack { ProgressView(); Text(UIStrings.string("editor.verifying")) }
                    } else {
                        Label(UIStrings.string("editor.verify"), systemImage: "checkmark.shield")
                    }
                }
                .disabled(isVerifying || workerURLText.isEmpty || tokenText.isEmpty)

                if let verification {
                    Text(verification.message)
                        .font(.footnote)
                        .foregroundStyle(verification.isUsable ? .green : .red)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                Text(UIStrings.string("editor.storage_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(UIStrings.string("editor.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(UIStrings.string("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(UIStrings.string("common.save")) { save() }
            }
        }
    }

    private func reload(for environment: SignerEnvironment) {
        verification = nil
        errorMessage = nil
        let existing = try? context.store(for: environment).load()
        workerURLText = existing?.workerURL.absoluteString ?? ""
        tokenText = existing?.requestToken ?? ""
    }

    @MainActor
    private func verify() async {
        isVerifying = true
        verification = nil
        errorMessage = nil
        defer { isVerifying = false }
        do {
            let workerURL = try SignerConfigurationStore.validatedWorkerURL(workerURLText)
            let token = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { throw SignerConfigurationError.emptyToken }
            let client = SigningClient(
                configuration: SignerConfiguration(workerURL: workerURL, requestToken: token),
                userAgent: context.userAgent
            )
            verification = await client.verifyConfiguration()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            let configuration = try context.store(for: environment).save(
                workerURL: workerURLText,
                requestToken: tokenText
            )
            onSaved(configuration, environment)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
