import Foundation

/// What went wrong and what to do next, in plain words, for any error the app shows.
/// System errors otherwise surface as "The operation couldn't be completed
/// (NSURLErrorDomain error -1009)".
public enum UserFacingError {
    public static func message(for error: Error) -> String {
        switch error {
        case let error as AirQualityError:
            return message(for: error)
        case let error as URLError:
            return message(for: error)
        case is DecodingError:
            return "The air quality service sent something unexpected. Try again in a few minutes."
        default:
            return "Something went wrong loading the air quality. Try again."
        }
    }

    static func message(for error: AirQualityError) -> String {
        switch error {
        case .apiError:
            "The air quality service returned an error. Try again in a minute."
        case .stationOffline:
            "This station is offline right now. Try again later, or choose another station nearby."
        case .noData:
            "There's no air quality data for this place right now. Try again in a few minutes."
        case .noNearbyStation:
            "No monitoring station is reporting near here right now. Try again in a few minutes."
        case .staleData(let lastReport):
            "This station hasn't reported since \(lastReport.formatted(date: .abbreviated, time: .omitted)). Choose another station nearby."
        }
    }

    static func message(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            "You're offline. Connect to the internet and try again."
        case .timedOut:
            "The air quality service took too long to answer. Try again in a minute."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            "Couldn't reach the air quality service. Try again in a minute."
        default:
            "Something went wrong loading the air quality. Try again."
        }
    }
}
