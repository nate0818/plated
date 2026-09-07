# Plated: push notification and activity feed research

Scope: what Apple provides and asks for, what Instagram, DoorDash/Uber Eats, Messages, Slack and WhatsApp actually do, what the opt-out evidence says, and a checklist filtered for an eight-person, invite-only room. Every claim carries its source URL. Where a source is a vendor blog rather than primary documentation, it is marked as such.

---

## 1. Apple's own guidance and APIs

### HIG: Notifications
Source: https://developer.apple.com/design/human-interface-guidelines/notifications (mirrored text also at https://codershigh.github.io/guidelines/ios/human-interface-guidelines/features/notifications/index.html)

- Purpose: "timely, high-value information they can understand at a glance."
- Frequency: "Avoid sending multiple notifications for the same thing, even if someone hasn't responded... people may turn off all notifications from your app."
- Copy: complete sentences, sentence case, proper punctuation; do not truncate yourself, the system does it.
- Badges: "Keep badges up to date. Update your app's badge as soon as the corresponding information is read." The badge is for unread things, not arbitrary numbers (temperature, counts of other kinds).
- Privacy: avoid sensitive or confidential content in the body; you cannot know who is looking at the screen.
- Consent: nothing ships until the person agrees; after that they control style and delivery time in Settings.

### Permission prompt timing and provisional authorization
- `UNUserNotificationCenter.requestAuthorization(options:)` with `.alert/.sound/.badge`. iOS gives one system prompt; a second attempt after "Don't Allow" is impossible without a trip to Settings. Vendor data (OneSignal, Airship, PushEngage) consistently reports that a contextual in-app pre-prompt ("soft ask") before the system dialog lifts iOS opt-in substantially; claims range from "40% above category average" (Airship) to "2-3x" (PushEngage, vendor claim). Sources: https://www.airship.com/blog/mobile-app-engagement-benchmarks/ , https://www.pushengage.com/ios-push-notification-permission/ , https://onesignal.com/guides/how-to-use-in-app-messaging-to-create-a-better-ios-permission-prompt-1
- Airship's 2021 benchmark: iOS opt-in ranges 29% to 73% by vertical, median 51%; Android is far higher because it defaults on. Source: https://www.businessofapps.com/marketplace/push-notifications/research/push-notifications-statistics/ (citing Airship).
- `UNAuthorizationOptions.provisional` (iOS 12+): no prompt; notifications go straight to Notification Center quietly (no banner, no sound, no badge by default) with inline "Keep" / "Turn off" controls. Trade-off: nothing you send can interrupt until the person upgrades, and once they tap "Turn off" the chance they re-enable is low. Sources: https://useyourloaf.com/blog/provisional-authorization-of-user-notificatons/ , https://nilcoalescing.com/blog/TrialNotificationsWithProvisionalAuthorizationOnIOS/ , https://developer.apple.com/forums/thread/105889
- For Plated the practical implication: the moments people would want interrupted (a reply to you, a vote closing, a timer) are precisely the ones provisional delivery cannot interrupt, so provisional is a poor fit for the social path and is only sensible for low-stakes ambient items. Ask at the first moment a notification has an obvious referent (joining a household, posting a first dish, starting a timer), not at launch.

### Interruption levels (iOS 15+)
`UNNotificationContent.interruptionLevel` / APNs `interruption-level`: `passive` (no light-up, no sound, lands in the list), `active` (default), `timeSensitive` (breaks through Focus if the person allowed it; yellow "Time Sensitive" label; requires the Time Sensitive Notifications capability), `critical` (bypasses silent switch; Apple entitlement only). Sources: https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive , https://wwdcnotes.com/documentation/wwdc21-10091-send-communication-and-time-sensitive-notifications/ , https://developer.apple.com/videos/play/wwdc2021/10091/
- `relevanceScore` (0...1) orders your notifications inside the Scheduled Summary and the highest gets featured. Source: same WWDC21 session.
- `UNNotificationSettings` exposes `timeSensitiveSetting`, `scheduledDeliverySetting`, `directMessagesSetting` so the app can tell whether the person has put it in a Scheduled Summary. Source: https://developer.apple.com/documentation/usernotifications/unnotificationsettings/timesensitivesetting
- Misuse of Time Sensitive is policed: App Review Guideline 4.5.4 forbids push for marketing without explicit opt-in and says abuse "may result in revocation"; users can also strip Time Sensitive per app. Source: https://developer.apple.com/app-store/review/guidelines/ , https://acceptmy.app/guidelines/4-5-4-push-notification-consent-and-marketing

### Communication Notifications (iOS 15+)
In a `UNNotificationServiceExtension`, build an `INSendMessageIntent` (sender `INPerson` with image, `conversationIdentifier`, group name), wrap in `INInteraction` with `.direction = .incoming`, `donate()`, then `request.content.updating(from: intent)`. The notification then renders with the sender's avatar, counts as a person for Focus "Allowed People", is announced by Siri on AirPods/CarPlay, and is what the Priority Notifications model treats as highest signal. Requirements: Communication Notifications capability, `NSUserActivityTypes` containing `INSendMessageIntent` in the app's Info.plist, `IntentsSupported` in the extension. Sources: https://developer.apple.com/videos/play/wwdc2021/10091/ , https://arturgruchala.com/stay-connected-mastering-ios-notifications-for-seamless-communication/ , https://developer.apple.com/forums/thread/691684 , https://www.macworld.com/article/538733/how-to-let-important-people-get-through-ios-15s-do-not-disturb-or-focus-settings.html
For Plated: a comment or a reply on the Table is genuinely person-to-person and qualifies; a plate reaction or a vote tally does not.

### Grouping and threads (iOS 12+)
`threadIdentifier` stacks notifications; `summaryArgument` and `summaryArgumentCount` feed the "N more from X" line under a collapsed stack (the summary line was removed from the UI in iOS 13 but the thread grouping remains). Use one thread per post or per conversation, not one per app. Sources: https://www.hackingwithswift.com/example-code/system/how-to-group-user-notifications-using-threadidentifier-and-summaryargument , https://wwdcnotes.com/documentation/wwdc18-711-using-grouped-notifications/

### Actionable categories
`UNNotificationCategory` with up to four `UNNotificationAction`s (including `UNTextInputNotificationAction` for inline reply); `categoryIdentifier` on the content. Register once at launch. Source: https://cocoacasts.com/actionable-notifications-with-the-user-notifications-framework

### Foreground suppression
`UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)`: return `[]` when the relevant conversation or post is already on screen, otherwise `[.banner, .list, .sound]`. Source: https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:willpresent:withcompletionhandler:) , https://sarunw.com/posts/notification-in-foreground/

### Live Activities for timers (iOS 16.1+)
`ActivityKit`: `Activity.request(attributes:content:pushType:)`, `update`, `end(_:dismissalPolicy:)`. `Text(timerInterval:pauseTime:countsDown:)` renders a live countdown with no updates from the app; use the `ClosedRange<Date>` form or the timer counts up past zero. `staleDate` marks content out of date. Limits: 8 hours active, then up to 4 more hours on the Lock Screen (12 total); 4 KB of dynamic content; Dynamic Island compact/minimal/expanded regions. HIG: a Live Activity is for a task with a beginning and an end; not for ads or promotions. App Review 4.5.3 (2026 wording): "Developers may not use Live Activities to send spam, phishing, or unsolicited messages." Sources: https://developer.apple.com/forums/thread/759250 , https://developer.apple.com/forums/thread/797676 , https://canopas.com/integrating-live-activity-and-dynamic-island-in-i-os-a-complete-guide , https://developer.apple.com/design/human-interface-guidelines/live-activities/ , https://appcompliance.io/blog/apple-2026-app-review-guideline-changes/ , https://www.macobserver.com/news/duolingo-accused-of-using-ios-live-activities-for-dynamic-island-ads/
- iOS 26 adds `AlarmKit` for timers that must break through silent mode and Focus with a system alarm UI; a cook timer finishing is the canonical case. Source: https://dev.to/arshtechpro/wwdc-2025-wake-up-to-the-alarmkit-api-ios-26-4e67

### Focus filters (iOS 16+)
`SetFocusFilterIntent` (App Intents) with `@Parameter`s lets a person say "in Personal Focus, only this household" or "no Table notifications during Work". `perform()` runs when the app is active; an App Intents extension is needed for the filter to affect notifications and badges while the app is not running. Sources: https://developer.apple.com/documentation/appintents/setfocusfilterintent , https://wwdcnotes.com/documentation/wwdc22-10121-meet-focus-filters/

### iOS 18 and iOS 26 changes
- iOS 18.1 Notification Summaries (Apple Intelligence, iPhone 15 Pro and later): the system rewrites stacks of notifications and direct messages into an italic one-liner; per-app toggle; works on all third-party apps with no API. iOS 18.3 pulled it for News apps after inaccurate summaries; iOS 26 beta 4 re-enabled it with a "Summarized by Apple Intelligence" label. Sources: https://support.apple.com/guide/iphone/summarize-notifications-reduce-interruptions-iph1fbe7d2b9/ios , https://www.macrumors.com/2025/01/16/ios-18-3-news-notifications-removed/ , https://www.macrumors.com/2025/07/22/ios-26-beta-4-notification-summaries/
  Practical consequence: write each body as a complete, self-contained sentence with the actor and the object named ("Riley asked which night for tacos"), because the summariser will merge five of yours into one line and vague bodies become nonsense.
- iOS 18.4 Priority Notifications (Settings > Notifications > Prioritize Notifications): an on-device model lifts a few notifications to the top of the Lock Screen. Apple has not published the ranking; developer reporting says interruption level, communication intents and concrete, time-bound content are the signals it respects, and social feed updates are demoted. Source: https://www.courier.com/blog/developer-guide-to-ios-26-priority-notifications (vendor blog, marks its own speculation).
- Apple Support on Reduce Interruptions Focus: lets only notifications the model judges immediate through. Source: https://support.apple.com/guide/iphone/summarize-notifications-reduce-interruptions-iph1fbe7d2b9/ios

---

## 2. Instagram: the activity tab and preference screen

What the anatomy is (as shipped; observed in-product, corroborated by the help and press sources below):
- Sections by recency (New / Today / Yesterday / This week / This month / Earlier), avatar left, one-sentence body with actor names bold, post thumbnail right, inline follow-back or reply affordance.
- Coalescing: "A, B and 3 others liked your photo" collapses many actors on one object into one row.
- Settings > Notifications: categories (Posts, stories and comments; Following and followers; Messages and calls; Live and reels; Fundraisers; From Instagram; Shopping etc.), each item with Off / From people I follow / From everyone; "Comment daily digest"; "Pause all" for 15 minutes to 8 hours; Quiet mode with a schedule (default 11 pm to 7 am) that also sets a status and auto-replies to DMs. Sources: https://help.instagram.com/546541825361643/ , https://thenextweb.com/news/rein-in-your-instagram-notifications-once-and-for-all , https://www.tomsguide.com/how-to/how-to-use-quiet-mode-on-instagram , https://www.makeuseof.com/customize-instagram-notifications-to-be-less-annoying/
- What it does badly: some categories cannot be turned off short of the OS switch (story reminders, account suggestions); "From Instagram" promotional pushes; the mid-2025 "diversity-aware notification ranking" exists because the system was spamming repeated alerts from the same creators. Sources: https://thenextweb.com/news/rein-in-your-instagram-notifications-once-and-for-all , https://www.socialmediatoday.com/news/instagram-updates-notification-ranking-avoid-fatigue/759187/
- In 2019 Instagram removed the "Following" activity tab (what your friends liked), which was a surveillance feed rather than a you-were-addressed feed. Source: https://www.buzzfeednews.com/article/katienotopoulos/instagrams-following-activity-tab-is-going-away

Which of these are scale patterns that do not transfer to eight people:
- "From people I follow / From everyone": there is no "everyone"; the room is the allow-list.
- ML ranking, diversity re-ranking, "suggested for you", follower notices, digest of comments from strangers: all exist to manage volume that a household never produces.
- Coalescing "and 3 others" is still valuable at eight people (five plates on one dish is one row, not five), but the names should all be written out, since the cap is eight.
- Recency sections transfer directly; "Earlier" beyond a week should be a date, matching DESIGN.md's timestamp rule.

---

## 3. DoorDash and Uber Eats: time-bound events

- Uber Eats' Live Activity states: order accepted and being prepared, courier assigned, picked up, nearby, delivered; shows ETA, courier name and photo, store image; compact Dynamic Island shows the ETA. Rolled out May 2023 after Uber rides in December 2022. Sources: https://9to5mac.com/2023/05/02/wheres-my-uber-eats-dynamic-island/ , https://9to5mac.com/2022/12/09/uber-and-uber-eats-live-activities/
- DoorDash: Live Activity with current status, an arrival window and a button into the app; shipped December 2023. Source: https://9to5mac.com/2023/12/04/doordash-live-activities-and-dynamic-island-order-tracking/
- Cadence lesson: each state change is one update to the same Live Activity, not a new banner; a push notification is reserved for the state changes that need the person to act (arrived, could not deliver). The activity ends itself at delivery with a dismissal policy rather than hanging around.
- Preferences: Uber splits transactional from marketing and lets you turn off push/SMS/email per marketing category, but "You cannot unsubscribe from transactional messages, including order receipts and support responses." SMS opt-out via STOP. Sources: https://help.uber.com/en/riders/article/changing-push-notification-settings?nodeId=80305412-9928-4be0-839c-c78ee789b3ff , https://help.uber.com/riders/article/how-to-update-email-sms-or-push-notification-settings?nodeId=c113d377-25fa-4a79-aa8f-cbc66ca6e411
- Transfer to Plated: the cook timer is the one true Live Activity (definite start and end, a countdown the system renders for free with `Text(timerInterval:)`, ends itself). "Tonight's dinner" is a candidate only while cooking is in progress; a day-long "tonight is tacos" activity is the Duolingo billboard Apple was criticised for. A vote closing is a notification, not an activity.

---

## 4. Messages, Slack, WhatsApp: per-conversation control

Apple Messages
- Hide Alerts per conversation (swipe or the info sheet); the sender is not told. Settings > Messages > Notify Me: get notified when your name is mentioned even in a muted conversation. Repeat Alerts, Filter Unknown Senders. Source: https://support.apple.com/guide/iphone/stop-mute-and-change-notifications-iph62faab6a4/ios
- Read state: with Messages in iCloud on, read status for iMessage conversations syncs and clears across devices; SMS read state does not sync, which is a live complaint thread on iOS 26. Hide Alerts is reported not to sync to Mac. Sources: https://www.macobserver.com/tips/how-to/sms-read-unread-status-not-syncing-across-apple-devices-ios/ , https://www.guidingtech.com/what-does-hide-alerts-mean-in-messages-on-iphone-ipad-mac/

Slack
- Global "Notify me about": All new messages / Direct messages, mentions and keywords / Nothing; per-channel override and mute (a muted channel still badges for mentions); thread replies notify the starter, anyone who replied, or anyone mentioned; per-thread follow/unfollow; notification schedule (hours and days); mobile push only "when I'm not active on desktop" with a 1-minute-after-lock or 10-minutes-idle default. Sources: https://slack.com/help/articles/201355156-Configure-your-Slack-notifications , https://slack.com/help/articles/204411433-Mute-channels-and-direct-messages , https://slack.com/help/articles/360056534254-Manage-notifications-for-specific-channels-and-direct-messages
- Activity view: one feed filterable by Mentions, Threads, Reactions, DMs, Invitations, Apps, Reminders; mark-as-read unbolds, clear hides but keeps a "Cleared" record; read state is synced across desktop and mobile. Source: https://slack.com/help/articles/46751260742035-Introducing-the-new-Activity-view-in-Slack

WhatsApp
- Mute for 8 hours, 1 week or Always; the other side is not told; mentions and replies to you still notify ("Highlights" = @mentions, replies, other relevant messages); large groups default to Highlights, small groups to all messages; a separate toggle for reaction notifications; @all overrides mute. Sources: https://faq.whatsapp.com/694350718331007/ , https://m.gsmarena.com/whatsapp_clarifies_how_muting_group_chats_works-news-65308.php , https://www.guidingtech.com/how-to-disable-whatsapp-message-reaction-notifications/ , https://www.techtimes.com/articles/323151/20260805/whatsapp-all-mention-bypasses-group-mute-sweeping-coordination-upgrade.htm

The shared shape across all three: (a) mute is per conversation and silent to others, (b) "addressed to me" (reply, mention) survives a mute, (c) nothing banners while that conversation is on screen, (d) reading on one device clears the others.

---

## 5. What gets notifications turned off

- Frequency: one weekly push moves ~10% of users to disable; 2-5 per week, 46%; 6-10 per week, 32% (Localytics survey, widely re-cited). Nightly sends "produce the highest opt-out rates across every category" (vendor timing guides). Sources: https://www.mobiloud.com/blog/push-notification-statistics , https://clevertap.com/blog/best-time-to-send-push-notifications/ , https://www.pushwoosh.com/blog/best-time-to-send-push-notifications/
- Relevance: Braze's survey of opt-outs puts "irrelevant or not personalised" at 30% and "too frequent" at 25% of reasons; 25% opt out of everything by default, one quoted because "I don't want to grab my phone unless an actual person is trying to reach me." Source: https://www.braze.com/resources/articles/opt-out-of-push-notifications-why-users-do-it
- Category tolerance: transactional notifications (an order, an appointment) are tolerated above one a day; non-transactional spike opt-outs above one a day. Social apps sit near the bottom of opt-in by vertical (Kahuna data via Andrew Chen: Social 39% opt-in versus Ride sharing 79%). Sources: https://www.pushwoosh.com/blog/push-notification-benchmarks/ , https://andrewchen.com/why-people-are-turning-off-push/
- Copy: "vague, noisy, or off-tone" trains people to dismiss everything; specific bodies that name the actual thing outperform "check out what's new". No controlled study isolates "New activity" as a phrase; the HIG copy rule and the summariser behaviour in section 1 are the stronger argument. Sources: https://www.eleken.co/blog-posts/notification-ux , https://uiuxatlas.com/lessons/content-design/notification-and-status-message-copy/
- Own actions: a message about something the person just did is validation, not a notification; "a notification is a message about an event that the user is not currently working on." Source: https://uxpatterns.dev/patterns/social/activity-feed , https://foundey.com/blog/notification-ux
- Repeat nagging: Apple's own words, "people may turn off all notifications from your app." Source: https://developer.apple.com/design/human-interface-guidelines/notifications
- No public dataset gives opt-out by category for a small-group app; the closest is the transactional-vs-promotional split above.

---

## 6. Checklist for a best-in-class small-group notification system

(a) Table-stakes parity
- Ask for permission at a moment with a referent, with an in-app explanation first; never at first launch.
- One thread per post, per ask and per conversation (`threadIdentifier`).
- Comments and replies delivered as Communication Notifications with the person's face (`INSendMessageIntent`).
- Actionable categories: Reply inline on a comment, Vote on an ask, Done or Snooze on a timer.
- No banner when the post or conversation is already on screen (`willPresent` returns `[]`).
- Read on one device clears the badge and the notification on the others (server-side read receipts plus `removeDeliveredNotifications(withIdentifiers:)`).
- Badge equals unread activity items, updated the moment they are read; never a decorative count.
- Per-conversation mute that the muted party never learns about, with replies to you still delivered (Messages, WhatsApp, Slack all do this).
- Activity feed: recency sections, actors coalesced on one object, thumbnail of the dish, inline follow-up action, seven-day relative timestamps then dates.
- Quiet hours honoured by default (nothing non-urgent between roughly 10 pm and 8 am local), and the OS Scheduled Summary respected via `scheduledDeliverySetting`.
- A per-category preference screen the size of the categories that actually exist: replies to me, comments on my dishes, plates on my dishes, asks and votes, planning changes, grocery list, timer.
- Cook timer as a Live Activity with `Text(timerInterval:)`, ending itself; timer finish as a Time Sensitive notification, with AlarmKit as the iOS 26 upgrade.

(b) Differentiators
- "Addressed to me" as the default interrupt level: replies, mentions, asks waiting on my vote are `active`; plates and other people's comments on other people's dishes are `passive` and arrive quietly; nothing else pushes at all.
- No notification for your own actions and no reaction notice to anyone but the author (already Plated law).
- One coalesced notification per object per hour: "Sam and Priya plated your lasagne" rather than two banners; update in place using the same request identifier.
- Self-contained bodies written to survive Apple Intelligence summarisation: subject, verb, object, no "New activity".
- A Focus filter (`SetFocusFilterIntent`) with one parameter: which household, or none, may notify in this Focus.
- Household-level quiet hours set once by the owner, since dinner is the shared clock.
- Honesty rule from DESIGN.md applied to the feed: three states (still asking, nothing, could not reach iCloud); a count only when there is something to count.
- Vote-closing notice sent once, to people who have not voted, and never again.

(c) Scale patterns to refuse
- "From everyone / from people I follow" split; follower and follow-request notices.
- Ranked or ML-ordered activity feed, diversity re-ranking, "suggested" or "you might have missed" rows.
- Daily or weekly digests of activity (the room is small enough that the feed is the digest).
- "From Plated" promotional pushes, re-engagement nudges ("you haven't planned this week"), streak reminders, story-style reminders that cannot be turned off.
- Time Sensitive on anything social; Live Activities for anything without an end.
- Pause-all with a status broadcast (Instagram Quiet mode tells others you are away); Plated's mute should be silent.
- Notification bodies that summarise the feed ("You have 5 new updates").
