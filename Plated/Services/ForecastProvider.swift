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

        #if DEBUG
        // WeatherKit needs the provisioned entitlement and a real fix, so the
        // day column is simply blank in the simulator. This seeds a plausible
        // week so the layout can be seen and reviewed without a device.
        if ProcessInfo.processInfo.arguments.contains("-plated-fake-weather") {
            dailyForecasts = Self.sampleWeek(days: days)
            lastError = nil
            return
        }
        #endif

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
        } catch is CancellationError {
            // A superseded refresh (tab switch mid-fix) must not blank
            // forecasts already on screen.
        } catch {
            dailyForecasts = []
            lastError = error.localizedDescription
            // The banner hides on failure by design, so the console is the
            // only place a WeatherKit or location failure is visible at all.
            print("PLATED WEATHER: refresh failed — \(error)")
        }
    }

    #if DEBUG
    /// Deterministic stand-in forecast behind `-plated-fake-weather`.
    private static func sampleWeek(days: Int) -> [DayForecast] {
        let pattern: [(high: Double, low: Double, precip: Double, text: String, symbol: String)] = [
            (78, 61, 0.05, "Mostly Clear", "sun.max"),
            (72, 58, 0.10, "Partly Cloudy", "cloud.sun"),
            (64, 52, 0.60, "Rain", "cloud.rain"),
            (59, 47, 0.20, "Cloudy", "cloud"),
            (85, 66, 0.00, "Clear", "sun.max"),
            (69, 55, 0.35, "Drizzle", "cloud.drizzle"),
            (52, 41, 0.15, "Windy", "wind")
        ]
        let start = Date().startOfDay
        return (0..<max(0, days)).compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: start)
            else { return nil }
            let sample = pattern[offset % pattern.count]
            return DayForecast(
                date: date,
                highF: sample.high,
                lowF: sample.low,
                precipitationChance: sample.precip,
                conditionDescription: sample.text,
                symbolName: sample.symbol,
                mood: WeatherMood.from(
                    highF: sample.high,
                    precipitationChance: sample.precip,
                    isClear: sample.symbol.hasPrefix("sun")
                )
            )
        }
    }
    #endif

    func forecast(for date: Date) -> DayForecast? {
        let day = date.startOfDay
        return dailyForecasts.first { Calendar.current.isSameDay($0.date, day) }
    }

    private func currentLocation() async throws -> CLLocation {
        if let cached = locationManager.location { return cached }

        // While the permission prompt is up, requestLocation fails
        // immediately with kCLErrorDenied — so ask first, and let the
        // authorization callback fire the actual fix request once the
        // user has answered.
        if locationManager.authorizationStatus == .notDetermined {
            return try await withCheckedThrowingContinuation { continuation in
                store(continuation)
                locationManager.requestWhenInUseAuthorization()
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            store(continuation)
            locationManager.requestLocation()
        }
    }

    /// A newer request supersedes an in-flight one: the old caller gets a
    /// cancellation instead of a continuation leaked forever — WeekView is
    /// rebuilt on every tab switch, so overlap is routine, not exceptional.
    private func store(_ continuation: CheckedContinuation<CLLocation, Error>) {
        locationContinuation?.resume(throwing: CancellationError())
        locationContinuation = continuation
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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard locationContinuation != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                // The continuation waiting on the permission answer gets its
                // fix via the normal didUpdateLocations path.
                locationManager.requestLocation()
            case .denied, .restricted:
                locationContinuation?.resume(throwing: CLError(.denied))
                locationContinuation = nil
            case .notDetermined:
                break // Prompt still up; keep waiting.
            @unknown default:
                break
            }
        }
    }
}
