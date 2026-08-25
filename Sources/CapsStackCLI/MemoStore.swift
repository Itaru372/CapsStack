import Foundation

struct CLIMemoStore {
    static let applicationDomain = "com.capsstack.CapsStack"
    static let key = "quickMemo"

    private let defaults: UserDefaults
    private let domainName: String?

    /// Pass `domainName: nil` in tests to use the injected defaults suite directly.
    init(defaults: UserDefaults = .standard, domainName: String? = applicationDomain) {
        self.defaults = defaults
        self.domainName = domainName
    }

    func get() -> String? {
        let text: String?
        if let domainName {
            text = defaults.persistentDomain(forName: domainName)?[Self.key] as? String
        } else {
            text = defaults.string(forKey: Self.key)
        }
        return Self.normalized(text)
    }

    func set(_ text: String) {
        guard let normalized = Self.normalized(text) else {
            clear()
            return
        }
        write(normalized)
    }

    func clear() {
        if let domainName {
            var domain = defaults.persistentDomain(forName: domainName) ?? [:]
            domain.removeValue(forKey: Self.key)
            defaults.setPersistentDomain(domain, forName: domainName)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }

    private func write(_ value: String) {
        if let domainName {
            var domain = defaults.persistentDomain(forName: domainName) ?? [:]
            domain[Self.key] = value
            defaults.setPersistentDomain(domain, forName: domainName)
        } else {
            defaults.set(value, forKey: Self.key)
        }
    }

    private static func normalized(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
