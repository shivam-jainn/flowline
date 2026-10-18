import Foundation

/// Shared validation for Settings forms.
/// Keeps inline error messaging consistent across gateway / capture panes.
public enum SettingsValidation {
    /// Normalizes a gateway endpoint and reports whether it is usable.
    /// Accepts `http://localhost` / `http://127.0.0.1` for local providers,
    /// requires https (or http localhost) otherwise.
    public static func gatewayEndpointError(baseURL: String, providerIsLocal: Bool) -> String? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return providerIsLocal ? nil : "Endpoint URL is required."
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else {
            return "Enter a valid URL, e.g. https://openrouter.ai/api/v1"
        }
        if scheme != "https" {
            let isLocalHost = host == "localhost" || host == "127.0.0.1" || host == "::1"
            if scheme == "http" && (providerIsLocal || isLocalHost) {
                return nil
            }
            return "Use https:// for remote gateways — http is only allowed for localhost."
        }
        return nil
    }

    public static func isCLIProvider(providerName: String) -> Bool {
        providerName == "cli"
    }
}
