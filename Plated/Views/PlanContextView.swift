import SwiftUI

/// Secondary context for Plan. Weather belongs to the selected date; history
/// has its own explicit period and never introduces another scrolling meal feed.
struct PlanContextView: View {
    let date: Date
    let forecast: ForecastProvider
    let history: PlanDinnerHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PlanWeatherView(date: date, forecast: forecast)
            Rectangle().fill(Color.hairline).frame(height: 1).accessibilityHidden(true)
            PlanDinnerHistoryView(history: history)
        }
    }
}

private struct PlanWeatherView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    let date: Date
    let forecast: ForecastProvider

    private var inForecastRange: Bool {
        let days = Calendar.current.dateComponents([.day], from: Date.now.startOfDay, to: date.startOfDay).day ?? 0
        return (0..<10).contains(days)
    }

    private var title: String {
        if Calendar.current.isDateInToday(date) { return "Today’s weather" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow’s weather" }
        return date.formatted(.dateTime.month(.abbreviated).day()) + " weather"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !inForecastRange {
                Text(title).plType(.footnote, .medium).foregroundStyle(Color.ink)
                Text(date.startOfDay < Date.now.startOfDay
                     ? "Past weather isn’t available."
                     : "Check back closer to the day for a forecast.")
                    .plType(.footnote).foregroundStyle(Color.inkSecondary)
            } else if let day = forecast.forecast(for: date) {
                weather(day)
                attribution
            } else if forecast.isLoading {
                HStack(spacing: 12) {
                    ProgressView().tint(Color.inkSecondary)
                    Text("Finding your local forecast…").plType(.footnote).foregroundStyle(Color.inkSecondary)
                }.frame(minHeight: 44).accessibilityElement(children: .combine)
            } else if forecast.locationDenied {
                weatherMessage("Allow location in Settings to see the forecast for dinner.", action: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else if forecast.needsLocationPermission {
                weatherMessage("A little weather to help you plan dinner.", action: "Show local weather") {
                    Task { await forecast.refresh(days: 10, mayAsk: true) }
                }
            } else {
                weatherMessage("Your dinner plan is still available.", heading: "Forecast unavailable", action: "Try again") {
                    Task { await forecast.refresh(days: 10) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await forecast.refresh(days: 10) } }
        }
    }

    private func weather(_ day: ForecastProvider.DayForecast) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        return layout {
            Image(systemName: day.symbolName)
                .font(.system(size: 32, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.olive)
                .frame(width: 32, height: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(day.conditionDescription).plType(.body, .semibold).foregroundStyle(Color.ink)
                Text("\(dayLabel) · \(Int((day.precipitationChance * 100).rounded()))% chance of rain")
                    .plType(.caption).foregroundStyle(Color.inkSecondary)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                Text(compactTemperature(day.highF)).plType(.title).foregroundStyle(Color.ink)
                Text("High \(compactTemperature(day.highF)) · Low \(compactTemperature(day.lowF))")
                    .plType(.caption).foregroundStyle(Color.inkSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.conditionDescription). High \(temperature(day.highF)), low \(temperature(day.lowF)). \(Int((day.precipitationChance * 100).rounded())) percent chance of rain.")
        .accessibilityIdentifier("plan-weather-conditions")
    }

    private var dayLabel: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func temperature(_ fahrenheit: Double) -> String {
        Measurement(value: fahrenheit, unit: UnitTemperature.fahrenheit)
            .formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    private func compactTemperature(_ fahrenheit: Double) -> String {
        // Keep the region's weather unit while using the compact degree mark
        // in the visual forecast. VoiceOver retains the complete unit above.
        temperature(fahrenheit).replacingOccurrences(of: "°F", with: "°")
            .replacingOccurrences(of: "°C", with: "°")
    }

    @ViewBuilder
    private var attribution: some View {
        if forecast.isPreview {
            Text("Preview weather").plType(.micro).foregroundStyle(Color.inkSecondary)
        }
        if let credit = forecast.attribution {
            Link(destination: credit.legalPageURL) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    // WeatherKit names variants for the background appearance,
                    // not the ink: Dark is white artwork; Light is black artwork.
                    AsyncImage(url: colorScheme == .dark ? credit.combinedMarkDarkURL : credit.combinedMarkLightURL) { image in
                        image.renderingMode(.original).resizable().scaledToFit().frame(width: 100, height: 20)
                            .accessibilityIdentifier("plan-weather-attribution-mark")
                    } placeholder: {
                        Label("Weather", systemImage: "apple.logo").plType(.footnote)
                    }
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Text("Data sources ↗").plType(.caption)
                }.foregroundStyle(Color.inkSecondary).frame(minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Apple Weather. Weather data sources")
            .accessibilityIdentifier("plan-weather-attribution")
        }
    }

    private func weatherMessage(_ message: String, heading: String? = nil, action: String, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let heading {
                HStack(spacing: 10) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(Color.olive)
                        .frame(width: 32, height: 32).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(heading).plType(.body, .semibold).foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(message).plType(.caption).foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(message).plType(.footnote).foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: perform) {
                Text(action).plType(.footnote, .semibold).foregroundStyle(Color.accentText)
                    .plActionLabel().plTapTarget().contentShape(Rectangle())
            }.buttonStyle(.pressable)
        }
    }
}

private struct PlanDinnerHistoryView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let history: PlanDinnerHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let headingLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            headingLayout {
                Text("Household dinners").plType(.heading).foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text("Last 7 days").plType(.caption).foregroundStyle(Color.inkSecondary)
            }
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            if history.cooked + history.eatingOut > 0 {
            layout {
                count(history.cooked, label: "Cooked at home", symbol: "frying.pan", identifier: "plan-history-cooked")
                count(history.eatingOut, label: "Ate out", symbol: "takeoutbag.and.cup.and.straw", identifier: "plan-history-eating-out")
            }
            }
            Text(history.cooked + history.eatingOut == 0
                 ? "Your first dinner is a good place to start. Mark a meal cooked to build your household’s history."
                 : history.cooked + history.eatingOut == 1
                 ? "Based on 1 recorded dinner."
                 : "Based on \(history.cooked + history.eatingOut) recorded dinners.")
                .plType(.caption).foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func count(_ value: Int, label: String, symbol: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(value, format: .number).plType(.title, .medium).foregroundStyle(Color.ink)
                    .monospacedDigit()
            }
            Text(label).plType(.caption).foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label.lowercased()) in the last 7 days")
        .accessibilityIdentifier(identifier)
    }
}
