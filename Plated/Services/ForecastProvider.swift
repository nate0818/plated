import Foundation
import CoreLocation
import WeatherKit

/// Wraps WeatherKit + CoreLocation and reduces a forecast down to the single
/// thing Plated cares about: what kind of day is tomorrow.
///
/// WeatherKit requires the WeatherKit capability and a paid developer account.
/// Without it, every call returns `nil` and the suggestion banner simply hides
/// rather than surfacing an error the user can do nothing about.
@MainActor
@Observable
final class ForecastProvider: NSObject {
    static let shared = ForecastProvider()

    private(set) var dailyForecasts: [DayForecast] = []
    private(set) var lastError: String?
    private(set) var isLoading = false

    private let locationManager = CLLocationManager()
    private let weather = WeatherKit.WeatherService.shared
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    struct DayForecast: Identifiable {
        let id = UUID()
        let date: Date
        let highF: Double
        let lowF: Double
        let precipitationChance: Double
        let conditionDescription: String
        let symbolName: String
        let mood: WeatherMood
    }

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Loads a multi-day forecast for the user's current location. Silently
    /// gives up when location or WeatherKit is unavailable.
    func refresh(days: Int = 7) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let location = try await currentLocation()
            let forecast = try await weather.weather(for: location, including: .daily)
            dailyForecasts = forecast.forecast.prefix(days).map { day in
                let highF = day.highTemperature.converted(to: .fahrenheit).value
                let lowF = day.lowTemperature.converted(to: .fahrenheit).value
                let isClear = [.clear, .mostlyClear, .partlyCloudy].contains(day.condition)
                return DayForecast(
                    date: day.date.startOfDay,
                    highF: highF,
                    lowF: lowF,
                    precipitationChance: day.precipitationChance,
                    conditionDescription: day.condition.description,
                    symbolName: day.symbolName,
                    mood: WeatherMood.from(
                        highF: highF,
                        precipitationChance: day.precipitationChance,
                        isClear: isClear
                    )
                )
            }
            lastError = nil
        } catch {
            dailyForecasts = []
            lastError = error.localizedDescription
        }
    }

    func forecast(for date: Date) -> DayForecast? {
        let day = date.startOfDay
        return dailyForecasts.first { Calendar.current.isSameDay($0.date, day) }
    }

    private func currentLocation() async throws -> CLLocation {
        if let cached = locationManager.location { return cached }

        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }
}

extension ForecastProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }
}
