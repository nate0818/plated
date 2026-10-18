# Apple Weather attribution visibility — October 18, 2026

The Plan attribution selected `combinedMarkLightURL` in dark appearance and
`combinedMarkDarkURL` in light appearance. WeatherKit names the variants for
the background, not the artwork color. Apple's live attribution response maps
`logoDark` to white artwork and `logoLight` to black artwork. Reversing them
made the logo disappear against green and cream respectively.

The selection now matches the view's color scheme. The supplied image uses
original rendering so Link styling cannot tint Apple's artwork. The existing
100-point image width, minimum 44-point link target and source URL are preserved.
No decorative redesign or motion was added (standard SwiftUI profile).

The earlier visual fixture displayed only “Preview weather,” bypassing this
production row. The opt-in `-plated-review-weather-attribution` flag now fetches
real WeatherKit attribution alongside clearly labeled sample weather. Three
UI checks require the downloaded image to exist, not just its fallback label.

Evidence:

- [Green](green.png), [cream](cream.png), [cream at AX5](cream-AX5.png): captured
  from Plated on the iOS 27 iPhone simulator and visually inspected. White/black
  Apple artwork is legible; the source link reflows at accessibility sizes.
- `build/weather-attribution-unit.xcresult`: 522 native tests, four opt-in
  Calendar skips, zero failures.
- `build/weather-attribution-final-ui.xcresult`: three attribution UI checks.
- Main app and widget build; design/token/schema checks and whitespace check.
- Targeted SwiftUI audit: zero high findings; four existing medium flags for
  bounded icons/artwork, divider thickness and weather symbol size reviewed.
- Accessibility label and 44-point link target checked through XCTest. Physical
  VoiceOver, phone rendering, iPad and unrelated Plan interactions were not
  retested for this local appearance fix. No custom graphics or motion to profile.

Localized design assessment: provisional 84/100 (hierarchy 14/15, platform 14/15,
layout 13/15, typography 13/15, motion 9/10, accessibility 12/15, runtime 9/15).
This is capped by the absence of a physical assistive-technology check and is
not a score for the whole app.

Primary sources: [Apple attribution metadata](https://weatherkit.apple.com/attribution/en),
[Apple REST attribution definition](https://developer.apple.com/documentation/weatherkitrestapi/attribution).

Release: build 42, with TestFlight processing/distribution recorded after upload.
