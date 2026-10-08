import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("payloadKind")       private var kindRaw   = PayloadKind.link.rawValue
    @AppStorage("correctionLevel")   private var levelRaw  = CorrectionLevel.medium.rawValue
    @AppStorage("exportFormat")      private var formatRaw = ExportFormat.png.rawValue
    @AppStorage("exportSize")        private var size      = 1024
    @AppStorage("quietZone")         private var quiet     = QR.defaultQuietZone
    @AppStorage("lastSaveDirectory") private var lastSaveDirectory = ""

    @State private var payload: Payload
    @State private var status = ""
    @State private var showingBatch = false
    @State private var headroom: Int?

    init(initial: Payload = Payload()) {
        _payload = State(initialValue: initial)
    }

    private var kind: PayloadKind { PayloadKind(rawValue: kindRaw) ?? .link }
    private var level: CorrectionLevel { CorrectionLevel(rawValue: levelRaw) ?? .medium }
    private var format: ExportFormat { ExportFormat(rawValue: formatRaw) ?? .png }
    private var encoded: String { payload.encoded(kind) }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            formPane
        } detail: {
            previewPane
        }
        .navigationTitle(kind.title)
        .frame(minWidth: 820, minHeight: 700)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingBatch = true } label: {
                    Label("Batch Export", systemImage: "square.grid.2x2")
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .help("Turn a list into one file per line")
            }
        }
        .onAppear(perform: prefillFromClipboard)
        .task(id: "\(encoded)\u{1}\(levelRaw)") {
            let text = encoded, level = self.level
            headroom = await Task.detached { QR.headroom(text, level: level) }.value
        }
        .sheet(isPresented: $showingBatch) {
            BatchView(level: level, quiet: quiet, format: format, size: size)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: Binding<String?>(
            get: { kindRaw },
            set: { if let new = $0 { kindRaw = new } }
        )) {
            Section("Type") {
                ForEach(PayloadKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.symbol)
                        .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 176, ideal: 190, max: 240)
    }

    // MARK: - Form

    private var formPane: some View {
        Form {
            switch kind {
            // Long values get the full column width instead of an inline label.
            case .link:
                Section {
                    TextField("Link", text: $payload.text, prompt: Text("example.com"))
                        .labelsHidden()
                } header: {
                    Text("Link")
                } footer: {
                    hint("Without a scheme it's saved as https://")
                }

            case .text:
                Section {
                    TextField("Text", text: $payload.text, prompt: Text("Anything at all"),
                              axis: .vertical)
                        .labelsHidden()
                        .lineLimit(6...16)
                } header: {
                    Text("Text")
                }

            case .wifi:
                Section {
                    TextField("Network", text: $payload.ssid, prompt: Text("SSID"))
                    Picker("Security", selection: $payload.security) {
                        ForEach(WiFiSecurity.allCases) { Text($0.title).tag($0) }
                    }
                    if payload.security != .open {
                        SecureField("Password", text: $payload.password)
                    }
                    Toggle("Hidden network", isOn: $payload.hiddenNetwork)
                } footer: {
                    hint("Scanning joins the network on iOS and Android.")
                }

            case .contact:
                Section("Name") {
                    TextField("First", text: $payload.firstName)
                    TextField("Last", text: $payload.lastName)
                }
                Section("Work") {
                    TextField("Organization", text: $payload.organization)
                    TextField("Job title", text: $payload.jobTitle)
                }
                Section("Reach") {
                    TextField("Phone", text: $payload.contactPhone)
                    TextField("Email", text: $payload.contactEmail)
                    TextField("Website", text: $payload.contactURL)
                    TextField("Address", text: $payload.address, axis: .vertical)
                        .lineLimit(2...4)
                }

            case .email:
                Section {
                    TextField("To", text: $payload.emailTo, prompt: Text("name@example.com"))
                    TextField("Subject", text: $payload.emailSubject)
                    TextField("Body", text: $payload.emailBody, axis: .vertical)
                        .lineLimit(4...10)
                }

            case .sms:
                Section {
                    TextField("Number", text: $payload.smsNumber, prompt: Text("+15551234567"))
                    TextField("Message", text: $payload.smsBody, axis: .vertical)
                        .lineLimit(3...8)
                }

            case .phone:
                Section {
                    TextField("Number", text: $payload.phoneNumber, prompt: Text("+15551234567"))
                }

            case .location:
                Section {
                    TextField("Latitude", text: $payload.latitude, prompt: Text("37.7749"))
                    TextField("Longitude", text: $payload.longitude, prompt: Text("-122.4194"))
                } footer: {
                    hint("Decimal degrees. Opens in Maps.")
                }

            case .event:
                Section {
                    TextField("Title", text: $payload.eventTitle)
                    TextField("Location", text: $payload.eventLocation)
                }
                Section("When") {
                    Toggle("All day", isOn: $payload.eventAllDay)
                    DatePicker("Starts", selection: $payload.eventStart,
                               displayedComponents: payload.eventAllDay
                                   ? [.date] : [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $payload.eventEnd,
                               displayedComponents: payload.eventAllDay
                                   ? [.date] : [.date, .hourAndMinute])
                }
                Section {
                    TextField("Notes", text: $payload.eventNotes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }

            Section("Details") {
                if details.isEmpty {
                    Text("Nothing encoded yet")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(details, id: \.label) { row in
                        LabeledContent(row.label) {
                            Text(row.value)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if !encoded.isEmpty {
                Section("Encoded payload") {
                    Text(encoded)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help("The exact string written into the symbol")
                }
            }
        }
        .formStyle(.grouped)
        .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 480)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    // MARK: - Preview + export

    private var previewPane: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                card
                caption
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 286)
            .padding(.horizontal, 24)
            .background(
                LinearGradient(colors: [Color(nsColor: .controlBackgroundColor),
                                        Color(nsColor: .windowBackgroundColor)],
                               startPoint: .top, endPoint: .bottom)
            )

            Divider()
            exportOptions
            Divider()
            actionBar
        }
        .navigationSplitViewColumnWidth(min: 300, ideal: 330, max: 460)
    }

    /// The image fills the frame edge to edge with no decorative inset, so the
    /// white margin you see is exactly the quiet zone being exported. The
    /// hairline marks the file's outer bounds.
    private var card: some View {
        ZStack {
            if let image = preview {
                Rectangle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                Rectangle()
                    .strokeBorder(.black.opacity(0.18), lineWidth: 1)
            } else {
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    .foregroundStyle(.quaternary)
                VStack(spacing: 10) {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 32, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                    Text("Fill in the \(kind.title.lowercased())")
                        .font(.callout)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 220, height: 220)
        .onDrag(dragProvider)
        .help(preview == nil ? "" : "Drag out to save a \(format.rawValue)")
    }

    private var caption: some View {
        Text(preview == nil ? " " : "Drag it straight into another app")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private var exportOptions: some View {
        Form {
            Section {
                Picker("", selection: Binding(get: { format }, set: { formatRaw = $0.rawValue })) {
                    ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Format")
            }

            Section {
                Picker("Correction", selection: Binding(get: { level },
                                                        set: { levelRaw = $0.rawValue })) {
                    ForEach(CorrectionLevel.allCases) { Text($0.label).tag($0) }
                }

                Picker("Size", selection: $size) {
                    ForEach([512, 1024, 2048], id: \.self) { n in
                        Text(format == .pdf ? "\(n) pt" : "\(n) px").tag(n)
                    }
                }
                .disabled(format == .svg)

                Stepper(value: $quiet, in: QR.quietZoneRange) {
                    HStack {
                        Text("Quiet zone")
                        Spacer()
                        Text("\(quiet) mod")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Symbol")
            } footer: {
                hint(quiet < 4 ? "Below the ISO 18004 minimum of 4 modules."
                               : "ISO 18004 specifies 4 modules as the minimum.")
                    .help(quiet < 4
                          ? "Scanners may fail unless the code already sits on white space."
                          : "Higher correction survives damage and small print, at the cost of a denser symbol.")
            }

        }
        .formStyle(.grouped)
        .frame(height: 316)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button { copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button { save() } label: { Label("Save…", systemImage: "square.and.arrow.down") }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .disabled(preview == nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Derived

    private var preview: NSImage? {
        guard let cg = QR.cgImage(encoded, level: level, quiet: quiet, targetPixels: 512) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: 256, height: 256))
    }

    struct Detail: Identifiable {
        let label: String, value: String
        var id: String { label }
    }

    /// Everything measurable about the symbol and the file it will produce.
    private var details: [Detail] {
        guard let grid = QR.grid(encoded, level: level) else { return [] }
        let geo = QR.geometry(grid, quiet: quiet, targetPixels: size)
        let total = grid.size * grid.size
        let dark = grid.darkCount
        let density = String(format: "%.1f", Double(dark) / Double(total) * 100)

        var rows: [Detail] = [
            Detail(label: "Version",
                   value: grid.version.map { "v\($0) · \(grid.size)×\(grid.size)" }
                          ?? "\(grid.size)×\(grid.size)"),
            Detail(label: "Correction",
                   value: "level \(level.rawValue) · \(level.recovery)% recovery"),
            Detail(label: "Payload",
                   value: "\(encoded.utf8.count) bytes · \(encoded.count) chars"),
        ]
        if let room = headroom, let v = grid.version {
            rows.append(Detail(label: "Headroom",
                               value: room == 0 ? "full at v\(v)"
                                                : "+\(room) chars before v\(v + 1)"))
        }
        rows.append(Detail(label: "Dark modules", value: "\(dark)/\(total) · \(density)%"))

        switch format {
        case .png:
            rows.append(Detail(label: "Quiet zone",
                               value: "\(geo.quiet) mod · \(geo.quiet * geo.scale) px"))
            rows.append(Detail(label: "Output",
                               value: "\(geo.pixels.formatted()) × \(geo.pixels.formatted()) px"))
            rows.append(Detail(label: "Scale", value: "\(geo.scale) px/module"))
        case .pdf:
            rows.append(Detail(label: "Quiet zone",
                               value: "\(geo.quiet) of \(geo.side) modules"))
            rows.append(Detail(label: "Output", value: "\(size) × \(size) pt · vector"))
        case .svg:
            rows.append(Detail(label: "Quiet zone",
                               value: "\(geo.quiet) of \(geo.side) modules"))
            rows.append(Detail(label: "Output", value: "\(geo.side)-module viewBox · vector"))
        }
        return rows
    }

    private var suggestedName: String {
        "\(Filename.base(for: payload, kind: kind)).\(format.ext)"
    }

    // MARK: - Actions

    private func save() {
        guard let data = QR.data(encoded, level: level, quiet: quiet, format: format, size: size) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = suggestedName
        if !lastSaveDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: lastSaveDirectory)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            lastSaveDirectory = url.deletingLastPathComponent().path
            status = "Saved \(url.lastPathComponent)"
        } catch {
            status = "Save failed: \(error.localizedDescription)"
        }
    }

    private func copy() {
        let board = NSPasteboard.general
        board.clearContents()
        switch format {
        case .svg:
            guard let data = QR.svgData(encoded, level: level, quiet: quiet),
                  let text = String(data: data, encoding: .utf8) else { return }
            board.setString(text, forType: .string)
            status = "Copied SVG source"
        case .pdf:
            guard let data = QR.pdfData(encoded, level: level, quiet: quiet, points: CGFloat(size)) else { return }
            board.setData(data, forType: .pdf)
            status = "Copied PDF"
        case .png:
            guard let cg = QR.cgImage(encoded, level: level, quiet: quiet, targetPixels: size) else { return }
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            board.writeObjects([image])
            status = "Copied \(cg.width)×\(cg.height) image"
        }
    }

    /// Writes a real file so the drag lands in Finder, Mail, Slack, Figma — anywhere.
    private func dragProvider() -> NSItemProvider {
        guard let data = QR.data(encoded, level: level, quiet: quiet, format: format, size: size) else {
            return NSItemProvider()
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QRGenerator-\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent(suggestedName)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url)
        } catch {
            return NSItemProvider()
        }
        return NSItemProvider(contentsOf: url) ?? NSItemProvider()
    }

    private func prefillFromClipboard() {
        guard kind == .link, payload.text.isEmpty,
              let raw = NSPasteboard.general.string(forType: .string) else { return }
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.count < 2000, !candidate.contains(where: \.isNewline),
              candidate.contains("://") || looksLikeDomain(candidate) else { return }
        payload.text = candidate
        status = "Filled from the clipboard"
    }

    private func looksLikeDomain(_ s: String) -> Bool {
        guard !s.contains(" "), s.contains(".") else { return false }
        let host = s.split(separator: "/").first.map(String.init) ?? s
        let parts = host.split(separator: ".")
        guard parts.count >= 2, let tld = parts.last else { return false }
        return tld.count >= 2 && tld.allSatisfy(\.isLetter)
    }
}
