import UIKit
import UniformTypeIdentifiers

/// Receives recipe material from Notes, Safari, Messages, Mail, and any other
/// app that participates in the system share sheet. Parsing belongs to Plated;
/// this short-lived process only moves the material into the shared inbox.
final class ShareViewController: UIViewController {
    private let appGroupID = "group.com.natemeadows.plated"
    private let payloadKey = "pending-recipe-import"
    private var started = false
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let doneButton = UIButton(type: .system)

    private struct Payload: Codable {
        var text: String
        var imageNames: [String]
        var createdAt: Date
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        spinner.startAnimating()
        statusLabel.text = "Sending to Plated…"
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .label
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textAlignment = .center

        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.textColor = .secondaryLabel
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.isHidden = true

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.titleLabel?.adjustsFontForContentSizeCategory = true
        doneButton.isHidden = true
        doneButton.addTarget(self, action: #selector(finish), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [spinner, statusLabel, detailLabel, doneButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        Task { await collectAndOpen() }
    }

    private func collectAndOpen() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        var texts: [String] = []
        var urls: [String] = []
        var imageData: [Data] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let value = await loadItem(provider, type: UTType.url.identifier) {
                if let url = value as? URL { urls.append(url.absoluteString) }
                else if let url = value as? NSURL { urls.append(url.absoluteString ?? "") }
                continue
            }
            let textType = provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                ? UTType.plainText.identifier
                : UTType.text.identifier
            if provider.hasItemConformingToTypeIdentifier(textType),
               let value = await loadItem(provider, type: textType) {
                if let text = value as? String { texts.append(text) }
                else if let text = value as? NSString { texts.append(text as String) }
                else if let text = value as? NSAttributedString { texts.append(text.string) }
                continue
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
               let data = await loadData(provider, type: UTType.image.identifier) {
                imageData.append(data)
            }
        }

        // A shared URL is the most exact source and the main app knows how to
        // fetch it. Notes usually supplies text instead. Never concatenate a
        // Safari title and URL into something that looks like a malformed
        // recipe to the importer.
        let input = urls.first(where: { !$0.isEmpty }) ?? texts.joined(separator: "\n\n")
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageData.isEmpty else {
            extensionContext?.cancelRequest(withError: NSError(
                domain: "PlatedShare",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No recipe text, link, or image was shared."]
            ))
            return
        }

        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            extensionContext?.cancelRequest(withError: NSError(
                domain: "PlatedShare",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Plated's shared inbox is unavailable."]
            ))
            return
        }

        var names: [String] = []
        for data in imageData.prefix(10) {
            let name = "recipe-share-\(UUID().uuidString).image"
            let url = container.appending(path: name)
            if (try? data.write(to: url, options: .atomic)) != nil { names.append(name) }
        }

        let payload = Payload(text: input, imageNames: names, createdAt: .now)
        guard let encoded = try? JSONEncoder().encode(payload),
              let defaults = UserDefaults(suiteName: appGroupID) else {
            extensionContext?.cancelRequest(withError: NSError(
                domain: "PlatedShare",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The recipe could not be prepared for Plated."]
            ))
            return
        }
        defaults.set(encoded, forKey: payloadKey)
        // This process exits immediately after the handoff. Force the tiny
        // preferences write through before asking iOS to tear it down.
        defaults.synchronize()

        let openURL = URL(string: "plated://import-shared")!
        extensionContext?.open(openURL) { [weak self] opened in
            DispatchQueue.main.async {
                guard let self else { return }
                if opened {
                    self.extensionContext?.completeRequest(returningItems: nil)
                } else {
                    self.spinner.stopAnimating()
                    self.spinner.isHidden = true
                    self.statusLabel.text = "Saved for Plated"
                    self.detailLabel.text = "Open Plated to review and save this recipe."
                    self.detailLabel.isHidden = false
                    self.doneButton.isHidden = false
                }
            }
        }
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func loadItem(_ provider: NSItemProvider, type: String) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    private func loadData(_ provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
