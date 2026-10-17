import SwiftUI

/// Secondary context for Plan. Weather belongs to the selected date; history
/// has its own explicit period and never introduces another scrolling meal feed.
struct PlanContextView: View {
    let date: Date
    let forecast: ForecastProvider
    let history: PlanDinnerHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
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
        VStack(alignment: .leading, spacing: 12) {
            Text(title).plType(.heading, .semibold).foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            if !inForecastRange {
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
                weatherMessage("The forecast couldn’t load. Your dinner plan is still here.", action: "Try again") {
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
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        return layout {
            Image(systemName: day.symbolName)
                .font(.system(size: 32, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.olive)
                .frame(width: 44, height: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(day.conditionDescription).plType(.body, .medium).foregroundStyle(Color.ink)
                Text("\(Int((day.precipitationChance * 100).rounded()))% chance of rain")
                    .plType(.footnote).foregroundStyle(Color.inkSecondary)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                Text("H \(temperature(day.highF))").plType(.heading, .medium).foregroundStyle(Color.ink)
                Text("L \(temperature(day.lowF))").plType(.footnote).foregroundStyle(Color.inkSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.conditionDescription). High \(temperature(day.highF)), low \(temperature(day.lowF)). \(Int((day.precipitationChance * 100).rounded())) percent chance of rain.")
        .accessibilityIdentifier("plan-weather-conditions")
    }

    private func temperature(_ fahrenheit: Double) -> String {
        Measurement(value: fahrenheit, unit: UnitTemperature.fahrenheit)
            .formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    @ViewBuilder
    private var attribution: some View {
        if forecast.isPreview {
            Text("Preview weather").plType(.micro).foregroundStyle(Color.inkSecondary)
        } else if let credit = forecast.attribution {
            Link(destination: credit.legalPageURL) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    AsyncImage(url: colorScheme == .dark ? credit.combinedMarkLightURL : credit.combinedMarkDarkURL) { image in
                        image.resizable().scaledToFit().frame(width: 100, height: 20)
                    } placeholder: {
                        Label("Weather", systemImage: "apple.logo").plType(.footnote)
                    }
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Text("Weather data sources ↗").plType(.micro)
                }.foregroundStyle(Color.inkSecondary).frame(minHeight: 44)
            }
            .accessibilityLabel("Apple Weather. Weather data sources")
        }
    }

    private func weatherMessage(_ message: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message).plType(.footnote).foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action, action: perform)
                .plType(.footnote, .semibold).foregroundStyle(Color.accentText)
                .plActionLabel().plTapTarget()
        }
    }
}

private struct PlanDinnerHistoryView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let history: PlanDinnerHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let headingLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            headingLayout {
                Text("Your dinner log").plType(.heading, .semibold).foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                MicroLabel("Last 7 days")
            }
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            layout {
                count(history.cooked, label: "Cooked", symbol: "frying.pan", identifier: "plan-history-cooked")
                count(history.eatingOut, label: "Eating out", symbol: "takeoutbag.and.cup.and.straw", identifier: "plan-history-eating-out")
            }
            Text(history.cooked + history.eatingOut == 0
                 ? "Mark dinners cooked or eating out to start your household’s log."
                 : "Your household’s cooked dinners and nights marked eating out.")
                .plType(.footnote).foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func count(_ value: Int, label: String, symbol: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(value, format: .number).plType(.title, .medium).foregroundStyle(Color.ink)
                    .monospacedDigit()
                Image(systemName: symbol).plType(.body).foregroundStyle(Color.olive).accessibilityHidden(true)
            }
            Text(label).plType(.footnote).foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label.lowercased()) in the last 7 days")
        .accessibilityIdentifier(identifier)
    }
}
