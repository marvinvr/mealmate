import Foundation

/// Turns what the user typed into candidate server URLs.
///
/// Accepts `mealie.example.com`, `http://mealie.local:9000/`, a pasted web-UI
/// link (`https://mealie.example.com/g/home/r/soup`) or an API URL. Without a
/// scheme, https is tried first, then http (many self-hosted servers on a LAN
/// or VPN are plain HTTP).
enum ServerAddress {
    static func candidates(for input: String) -> [URL] {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return [] }

        let hasScheme = text.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) != nil
        if !hasScheme { text = "https://" + text }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return [] }

        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        components.path = normalizedPath(components.path)

        guard let primary = components.url else { return [] }
        if hasScheme { return [primary] }
        components.scheme = "http"
        return [primary, components.url].compactMap { $0 }
    }

    /// Strips trailing slashes and known web-UI / API suffixes, keeping a
    /// reverse-proxy sub-path such as `/mealie`.
    static func normalizedPath(_ path: String) -> String {
        var segments = path.split(separator: "/").map(String.init)
        let markers: Set<String> = ["api", "g", "login", "docs", "recipe", "recipes", "user", "admin", "shopping-lists"]
        if let index = segments.firstIndex(where: { markers.contains($0.lowercased()) }) {
            segments = Array(segments[..<index])
        }
        return segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
    }
}

/// A validated server: where it lives and what it supports.
struct ResolvedServer: Hashable, Sendable {
    var url: URL
    var info: AppInfo

    /// "mealie.example.com" (+ port / path if any).
    var displayAddress: String {
        var text = url.host() ?? url.absoluteString
        if let port = url.port { text += ":\(port)" }
        if !url.path().isEmpty, url.path() != "/" { text += url.path() }
        return text
    }

    var isInsecure: Bool { url.scheme == "http" }
}
