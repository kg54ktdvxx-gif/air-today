import Foundation

public enum AppConstants {
    /// XOR-obfuscated WAQI token — not visible via `strings` dump of the binary.
    public static var waqiToken: String {
        // Obfuscated bytes: each byte XOR'd with key 0xA7
        let obfuscated: [UInt8] = [
            0xC5, 0xC4, 0x97, 0xC3, 0x96, 0xC5, 0xC1, 0x9F,
            0x9E, 0x94, 0x92, 0xC3, 0xC3, 0x9E, 0xC1, 0xC6,
            0xC6, 0x97, 0x96, 0xC3, 0x9E, 0xC6, 0x95, 0x9E,
            0x90, 0x96, 0x9F, 0xC6, 0x95, 0x94, 0xC4, 0x9F,
            0x9F, 0x9F, 0x93, 0xC4, 0x9E, 0x94, 0x97, 0x94
        ]
        let key: UInt8 = 0xA7
        return String(obfuscated.map { Character(UnicodeScalar($0 ^ key)) })
    }

    public static let appGroupID = "group.com.airtoday.shared"
    public static let cacheTTL: TimeInterval = 60 * 60  // 1 hour
    public static let backgroundRefreshInterval: TimeInterval = 60 * 60
    public static let liveActivityStaleMinutes: TimeInterval = 45 * 60
    public static let temperatureUnitKey = "temp_unit"
}
