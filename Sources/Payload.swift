import Foundation

// MARK: - Kinds

enum PayloadKind: String, CaseIterable, Identifiable {
    case link, text, wifi, contact, email, sms, phone, location, event

    var id: String { rawValue }

    var title: String {
        switch self {
        case .link:     return "Link"
        case .text:     return "Plain Text"
        case .wifi:     return "Wi-Fi Network"
        case .contact:  return "Contact Card"
        case .email:    return "Email"
        case .sms:      return "SMS"
        case .phone:    return "Phone Number"
        case .location: return "Location"
        case .event:    return "Calendar Event"
        }
    }

    var symbol: String {
        switch self {
        case .link:     return "link"
        case .text:     return "text.alignleft"
        case .wifi:     return "wifi"
        case .contact:  return "person.crop.square"
        case .email:    return "envelope"
        case .sms:      return "message"
        case .phone:    return "phone"
        case .location: return "mappin.and.ellipse"
        case .event:    return "calendar"
        }
    }
}

enum WiFiSecurity: String, CaseIterable, Identifiable {
    case wpa = "WPA", wep = "WEP", open = "nopass"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wpa:  return "WPA/WPA2/WPA3"
        case .wep:  return "WEP"
        case .open: return "None"
        }
    }
}

// MARK: - Form state

/// One flat bag of fields for every payload kind — the UI shows the subset
/// that applies, and `encoded(_:)` assembles the string that gets encoded.
struct Payload {
    // link / text
    var text = ""
    // wifi
    var ssid = "", password = "", hiddenNetwork = false
    var security: WiFiSecurity = .wpa
    // contact
    var firstName = "", lastName = "", organization = "", jobTitle = ""
    var contactPhone = "", contactEmail = "", contactURL = "", address = ""
    // email
    var emailTo = "", emailSubject = "", emailBody = ""
    // sms
    var smsNumber = "", smsBody = ""
    // phone
    var phoneNumber = ""
    // location
    var latitude = "", longitude = ""
    // event
    var eventTitle = "", eventLocation = "", eventNotes = ""
    var eventStart = Payload.nextHour()
    var eventEnd = Payload.nextHour().addingTimeInterval(3600)
    var eventAllDay = false

    private static func nextHour() -> Date {
        let cal = Calendar.current
        return cal.nextDate(after: Date(), matching: DateComponents(minute: 0),
                            matchingPolicy: .nextTime) ?? Date()
    }

    // MARK: Encoding

    func encoded(_ kind: PayloadKind) -> String {
        switch kind {
        case .link:     return Payload.normalizedURL(text)
        case .text:     return text
        case .wifi:     return wifiString
        case .contact:  return vCardString
        case .email:    return mailtoString
        case .sms:      return smsString
        case .phone:    return phoneString
        case .location: return geoString
        case .event:    return eventString
        }
    }

    /// Bare hostnames are the common case — send them somewhere a browser can follow.
    static func normalizedURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("://") { return trimmed }
        let lower = trimmed.lowercased()
        for scheme in ["mailto:", "tel:", "sms:", "geo:", "wifi:", "smsto:"] where lower.hasPrefix(scheme) {
            return trimmed
        }
        return "https://" + trimmed
    }

    private var wifiString: String {
        let name = trimmed(ssid)
        guard !name.isEmpty else { return "" }
        var out = "WIFI:T:\(security.rawValue);S:\(Payload.wifiEscaped(name));"
        if security != .open, !password.isEmpty {
            out += "P:\(Payload.wifiEscaped(password));"
        }
        if hiddenNetwork { out += "H:true;" }
        return out + ";"
    }

    private var vCardString: String {
        let full = [trimmed(firstName), trimmed(lastName)]
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard !full.isEmpty || !trimmed(organization).isEmpty else { return "" }
        var lines = ["BEGIN:VCARD", "VERSION:3.0"]
        lines.append("N:\(esc(lastName));\(esc(firstName));;;")
        lines.append("FN:\(esc(full.isEmpty ? organization : full))")
        if !trimmed(organization).isEmpty { lines.append("ORG:\(esc(organization))") }
        if !trimmed(jobTitle).isEmpty     { lines.append("TITLE:\(esc(jobTitle))") }
        if !trimmed(contactPhone).isEmpty { lines.append("TEL;TYPE=CELL:\(esc(contactPhone))") }
        if !trimmed(contactEmail).isEmpty { lines.append("EMAIL;TYPE=INTERNET:\(esc(contactEmail))") }
        if !trimmed(contactURL).isEmpty   { lines.append("URL:\(esc(Payload.normalizedURL(contactURL)))") }
        if !trimmed(address).isEmpty      { lines.append("ADR;TYPE=WORK:;;\(esc(address));;;;") }
        lines.append("END:VCARD")
        return lines.joined(separator: "\r\n")
    }

    private var mailtoString: String {
        let to = trimmed(emailTo)
        guard !to.isEmpty else { return "" }
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = to
        var items: [URLQueryItem] = []
        if !trimmed(emailSubject).isEmpty { items.append(URLQueryItem(name: "subject", value: emailSubject)) }
        if !emailBody.isEmpty             { items.append(URLQueryItem(name: "body", value: emailBody)) }
        comps.queryItems = items.isEmpty ? nil : items
        return comps.string ?? "mailto:\(to)"
    }

    private var smsString: String {
        let number = Payload.dialable(smsNumber)
        guard !number.isEmpty else { return "" }
        let body = trimmed(smsBody)
        return body.isEmpty ? "SMSTO:\(number):" : "SMSTO:\(number):\(body)"
    }

    private var phoneString: String {
        let number = Payload.dialable(phoneNumber)
        return number.isEmpty ? "" : "tel:\(number)"
    }

    private var geoString: String {
        let lat = trimmed(latitude), lon = trimmed(longitude)
        guard let a = Double(lat), let b = Double(lon) else { return "" }
        return "geo:\(a),\(b)"
    }

    private var eventString: String {
        let title = trimmed(eventTitle)
        guard !title.isEmpty else { return "" }
        var lines = ["BEGIN:VEVENT", "SUMMARY:\(esc(title))"]
        if eventAllDay {
            lines.append("DTSTART;VALUE=DATE:\(Payload.dayFormatter.string(from: eventStart))")
            let next = eventEnd.addingTimeInterval(86400)   // DTEND is exclusive
            lines.append("DTEND;VALUE=DATE:\(Payload.dayFormatter.string(from: max(next, eventStart)))")
        } else {
            lines.append("DTSTART:\(Payload.stampFormatter.string(from: eventStart))")
            lines.append("DTEND:\(Payload.stampFormatter.string(from: max(eventEnd, eventStart)))")
        }
        if !trimmed(eventLocation).isEmpty { lines.append("LOCATION:\(esc(eventLocation))") }
        if !trimmed(eventNotes).isEmpty    { lines.append("DESCRIPTION:\(esc(eventNotes))") }
        lines.append("END:VEVENT")
        return lines.joined(separator: "\r\n")
    }

    // MARK: Helpers

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// vCard / iCalendar text escaping.
    private func esc(_ s: String) -> String {
        trimmed(s)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    static func wifiEscaped(_ s: String) -> String {
        let reserved: Set<Character> = ["\\", ";", ",", ":", "\""]
        var out = ""
        for ch in s {
            if reserved.contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    static func dialable(_ s: String) -> String {
        let keep = Set("+0123456789")
        return String(s.filter { keep.contains($0) })
    }

    static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Filenames

enum Filename {
    static func slug(_ raw: String, fallback: String = "qrcode") -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var out = String(String.UnicodeScalarView(
            raw.unicodeScalars.map { allowed.contains($0) ? $0 : "-" }))
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        if out.count > 48 { out = String(out.prefix(48)) }
        return out.isEmpty ? fallback : out.lowercased()
    }

    /// A readable base name for whatever the payload describes.
    static func base(for payload: Payload, kind: PayloadKind) -> String {
        switch kind {
        case .link:
            let normalized = Payload.normalizedURL(payload.text)
            if let host = URL(string: normalized)?.host { return slug(host) }
            return slug(payload.text)
        case .text:     return slug(String(payload.text.prefix(48)))
        case .wifi:     return slug("wifi-" + payload.ssid)
        case .contact:  return slug([payload.firstName, payload.lastName, payload.organization]
                                        .filter { !$0.isEmpty }.joined(separator: "-"), fallback: "contact")
        case .email:    return slug(payload.emailTo, fallback: "email")
        case .sms:      return slug("sms-" + payload.smsNumber)
        case .phone:    return slug("tel-" + payload.phoneNumber)
        case .location: return slug("geo-\(payload.latitude)-\(payload.longitude)")
        case .event:    return slug(payload.eventTitle, fallback: "event")
        }
    }
}
