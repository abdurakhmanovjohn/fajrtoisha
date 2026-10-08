import Foundation
import Observation

/// Where prayer times are fetched for.
nonisolated enum LocationQuery: Hashable, Sendable {
    case coordinates(latitude: Double, longitude: Double)
    case city(name: String, country: String)

    /// Cache key, rounded like the bot's loc_key (lat/lon to 2 decimals).
    func cacheKey(method: Int, school: Int) -> String {
        switch self {
        case let .coordinates(lat, lon):
            String(format: "%.2f,%.2f|m%d|s%d", lat, lon, method, school)
        case let .city(name, country):
            "city:\(name.lowercased()),\(country.lowercased())|m\(method)|s\(school)"
        }
    }
}

/// Port of the `users` row, persisted in UserDefaults.
@Observable
final class SettingsStore {
    private enum Key {
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let city = "city"
        static let country = "country"
        static let timezoneID = "timezoneID"
        static let reminderOffset = "reminderOffsetMins"
        static let asrSchool = "asrSchool"
        static let calcMethod = "calcMethod"
        static let hasOnboarded = "hasOnboarded"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var latitude: Double? { didSet { save(latitude, Key.latitude) } }
    var longitude: Double? { didSet { save(longitude, Key.longitude) } }
    var city: String? { didSet { save(city, Key.city) } }
    var country: String? { didSet { save(country, Key.country) } }
    var timezoneID: String? { didSet { save(timezoneID, Key.timezoneID) } }
    var reminderOffsetMins: Int { didSet { defaults.set(reminderOffsetMins, forKey: Key.reminderOffset) } }
    var asrSchool: Int { didSet { defaults.set(asrSchool, forKey: Key.asrSchool) } }
    var calcMethod: Int { didSet { defaults.set(calcMethod, forKey: Key.calcMethod) } }
    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: Key.hasOnboarded) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        latitude = defaults.object(forKey: Key.latitude) as? Double
        longitude = defaults.object(forKey: Key.longitude) as? Double
        city = defaults.string(forKey: Key.city)
        country = defaults.string(forKey: Key.country)
        timezoneID = defaults.string(forKey: Key.timezoneID)
        reminderOffsetMins = defaults.object(forKey: Key.reminderOffset) as? Int ?? AppConfig.defaultOffset
        asrSchool = defaults.object(forKey: Key.asrSchool) as? Int ?? AppConfig.defaultAsrSchool
        calcMethod = defaults.object(forKey: Key.calcMethod) as? Int ?? AppConfig.defaultCalcMethod
        hasOnboarded = defaults.bool(forKey: Key.hasOnboarded)
    }

    private func save<T>(_ value: T?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    var timeZone: TimeZone {
        timezoneID.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    var locationQuery: LocationQuery? {
        if let latitude, let longitude { return .coordinates(latitude: latitude, longitude: longitude) }
        if let city, let country { return .city(name: city, country: country) }
        return nil
    }

    var locationLabel: String {
        if let city, let country { return "\(city), \(country)" }
        if let latitude, let longitude { return String(format: "%.4f, %.4f", latitude, longitude) }
        return "Not set"
    }

    func setLocation(_ query: LocationQuery, timezoneID: String) {
        switch query {
        case let .coordinates(lat, lon):
            latitude = lat; longitude = lon; city = nil; country = nil
        case let .city(name, c):
            latitude = nil; longitude = nil; city = name; country = c
        }
        self.timezoneID = timezoneID
    }

    /// "Delete all data": back to defaults and onboarding.
    func resetAll() {
        latitude = nil; longitude = nil; city = nil; country = nil; timezoneID = nil
        reminderOffsetMins = AppConfig.defaultOffset
        asrSchool = AppConfig.defaultAsrSchool
        calcMethod = AppConfig.defaultCalcMethod
        hasOnboarded = false
    }
}
