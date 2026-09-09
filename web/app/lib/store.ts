// Where a person is sent to get Plated, and it is two different places.
//
// The App Store listing is NOT published yet, so `apps.apple.com/...id6804332064`
// resolves to Apple's own not-found page. That is fine behind Apple's download
// badge, which promises the App Store and would be a lie pointing anywhere else,
// and it is not fine on an invitation: "Get Plated" is the first thing somebody
// taps after a friend invites them, and it landed them on a 404. An invitation
// that cannot be accepted is the Honesty rule broken at the front door.
//
// So the invitation sends people to the public TestFlight link, which is where
// Plated actually is today. When the listing goes live, point INSTALL_URL at
// APP_STORE_URL and delete TESTFLIGHT_URL: one edit, here.
export const APP_STORE_URL = "https://apps.apple.com/app/plated/id6804332064";

export const TESTFLIGHT_URL = "https://testflight.apple.com/join/2exAQgYs";

/// The link an invited person follows to get the app.
export const INSTALL_URL = TESTFLIGHT_URL;

/// What that button says. It names where the tap actually goes, because
/// TestFlight is a different thing from the App Store and somebody who
/// expected one and got the other has been told something untrue.
export const INSTALL_LABEL = "Get Plated on TestFlight";
