import Foundation
import Testing
@testable import AirTodayCore

@Suite("Error messages people see")
struct UserFacingErrorTests {
    @Test("Being offline says so, and what to do")
    func offline() {
        #expect(UserFacingError.message(for: URLError(.notConnectedToInternet)) == "You're offline. Connect to the internet and try again.")
    }

    @Test("A slow service is named as slow, not as a code")
    func timeout() {
        #expect(UserFacingError.message(for: URLError(.timedOut)).hasPrefix("The air quality service took too long"))
    }

    @Test("The app's own errors keep their meaning and add a next step")
    func appErrors() {
        #expect(UserFacingError.message(for: AirQualityError.stationOffline).hasSuffix("choose another station nearby."))
        #expect(UserFacingError.message(for: AirQualityError.apiError("over quota")) == "The air quality service returned an error. Try again in a minute.")
    }

    @Test("Nothing shown is a system error string, and none ends in an exclamation mark")
    func noSystemText() {
        let errors: [Error] = [
            URLError(.badServerResponse), URLError(.cannotFindHost), AirQualityError.noData,
            DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "")),
            NSError(domain: "x", code: 1),
        ]
        for error in errors {
            let message = UserFacingError.message(for: error)
            #expect(!message.contains("NSURLErrorDomain") && !message.contains("operation couldn"), "\(message)")
            #expect(!message.contains("!"), "\(message)")
            #expect(message.hasSuffix("."), "\(message)")
        }
    }
}
