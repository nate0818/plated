import Foundation
import CoreLocation
import WeatherKit

/// Weather for the selected dinner day, including the permission and failure
/// states needed by Plan. Fetching stays outside SwiftUI body evaluation.
@MainActor
@Observable
final class ForecastProvider: NSObject {
    static let shared = ForecastProvider()

    private(set) var dailyForecasts: [DayForecast] = []
    private(set) var lastError: String?
    private(set) var isLoading = false
    private(set) var locationAuthorization: CLAuthorizationStatus = .notDetermined
    private(set) var attribution: WeatherAttribution?
    private(set) var isPreview = false

    var needsLocationPermission: Bool { locationAuthorization == .notDetermined }
    var locationDenied: Bool { locationAuthorization == .denied || locationAuthorization == .restricted }

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
        locationAuthorization = locationManager.authorizationStatus
    }

    /// Passive refreshes never raise a location prompt. Plan's explicit
    /// weather action or opening a day can opt in with `mayAsk`.
    func refresh(days: Int = 7, mayAsk: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-plated-design-review") {
            if arguments.contains("-plated-review-weather-permission") {
                locationAuthorization = .notDetermined; dailyForecasts = []; lastError = nil
                return
            }
            if arguments.contains("-plated-review-weather-denied") {
                locationAuthorization = .denied; dailyForecasts = []; lastError = nil
                return
            }
            if arguments.contains("-plated-review-weather-failed") {
                locationAuthorization = .authorizedWhenInUse; dailyForecasts = []; lastError = "Review fixture"
                return
            }
        }
        // WeatherKit needs the provisioned entitlement and a real fix, so the
        // day column is simply blank in the simulator. This seeds a plausible
        // week so the layout can be seen and reviewed without a device.
        if ProcessInfo.processInfo.arguments.contains("-plated-fake-weather") {
            dailyForecasts = Self.sampleWeek(days: days)
            lastError = nil
            isPreview = true
            return
        }
        #endif

        isPreview = false
        locationAuthorization = locationManager.authorizationStatus
        guard mayAsk || !needsLocationPermission else { return }

        do {
            let location = try await currentLocation()
            let forecast = try await weather.weather(for: location, including: .daily)
            // Publish weather only with its required attribution available.
            if attribution == nil { attribution = try await weather.attribution }
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
        guard !locationDenied else { throw CLError(.denied) }
        if !needsLocationPermission, let cached = locationManager.location,
           abs(cached.timestamp.timeIntervalSinceNow) < 15 * 60 { return cached }

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
            locationAuthorization = status
            if status == .denied || status == .restricted {
                dailyForecasts = []
                lastError = nil
            }
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
