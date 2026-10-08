import SwiftUI
import AppKit

/// Paste a list, pick a folder, get one file per line.
struct BatchView: View {
    let level: CorrectionLevel
    let quiet: Int
    let format: ExportFormat
    let size: Int

    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var asLinks = true
    @State private var status = ""
    @State private var working = false

    private var lines: [String] {
        input.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 22, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Batch Export").font(.headline)
                    Text("One entry per line — each becomes its own \(format.rawValue), "
                         + "named after its contents.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            ZStack(alignment: .topLeading) {
                TextEditor(text: $input)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                if input.isEmpty {
                    Text("https://example.com\nhttps://example.org/pricing")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 480, height: 240)
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack(spacing: 12) {
                Picker("", selection: $asLinks) {
                    Text("Links").tag(true)
                    Text("Plain text").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 170)

                Text(summary)
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Choose Folder…", action: export)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(lines.isEmpty || working)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(width: 480)
    }

    private var summary: String {
        if !status.isEmpty { return status }
        if lines.isEmpty { return "Nothing to export" }
        return "\(lines.count) entr\(lines.count == 1 ? "y" : "ies")"
    }

    private func export() {
        let entries = lines
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        working = true
        status = "Exporting…"
        let level = self.level, quiet = self.quiet, format = self.format
        let size = self.size, asLinks = self.asLinks

        Task.detached {
            var used = Set<String>()
            var written = 0
            var failed = 0

            for entry in entries {
                let value = asLinks ? Payload.normalizedURL(entry) : entry
                guard let data = QR.data(value, level: level, quiet: quiet, format: format, size: size) else {
                    failed += 1
                    continue
                }
                let stem = asLinks ? (URL(string: value)?.host ?? entry) : entry
                let base = Filename.slug(String(stem.prefix(48)))
                var name = base
                var n = 2
                while used.contains(name) { name = "\(base)-\(n)"; n += 1 }
                used.insert(name)

                do {
                    try data.write(to: folder.appendingPathComponent("\(name).\(format.ext)"))
                    written += 1
                } catch {
                    failed += 1
                }
            }

            let done = written, bad = failed
            await MainActor.run {
                working = false
                status = bad == 0 ? "Wrote \(done) file\(done == 1 ? "" : "s")"
                                  : "Wrote \(done), \(bad) failed"
            }
        }
    }
}
