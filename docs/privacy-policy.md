# Plated privacy policy

**Last updated: 7 September 2026**

Plated is a meal planner for a household. Your recipes, plans, photos and
household stay in your own iCloud account. Plated runs one small server, a
directory, and this page says exactly what it holds. The developer cannot see
your recipes, your plans, your household, or your photos.

## In your iCloud

Your recipes, meal plans, grocery lists, household members, gatherings, photos,
posts to your Table and cooking history are saved on your device and synced
through **your** private iCloud database using Apple's CloudKit. No copy is sent
to the developer or to any other company.

If you join a household, the plan, the grocery list, the cookbook and the
people list are shared with the other members of that household through
iCloud, and each member's own iCloud keeps a copy. Leaving takes your recipes
with you and removes the rest from your phone. The household keeps its copy of
the recipes you shared with it, including the ones you brought when you joined.

When you share a Table, CloudKit shares your posts with the people you invited
and nobody else. A Table guest never sees the plan, the grocery list or the
cookbook.

## On Plated's server

Plated keeps a directory so the app can answer one question: which of your
contacts already use Plated. iOS no longer offers a way to answer that on the
device, so the directory is the one part of Plated that is not in your iCloud.
It holds a salted hash of your phone number, never the number itself (the salt
lives only on the server, so the table cannot be turned back into a phone
book), the first name you already show your household, your Apple account
identifier, and a token that lets your phone ask the directory questions.

The directory is used for two things. When you look for contacts already on
Plated, the phone numbers from your address book are sent to the server over
an encrypted connection, hashed there, compared, and not stored; people who
are not on Plated are never kept. When somebody invites you and your number
is in the directory, the server sends a notice to your phone saying who it is
from, which it can do because it holds a push token for each phone you have
signed in on. The invitation link itself is never stored. What stays behind is
a record that the invitation happened: who sent it, the hashed number and the
time, so that no host can turn invitations into a mailing list. The server is
hosted by Supabase in the United States.

## Information Plated never collects

Plated contains no analytics, no advertising, no tracking, and no third-party
SDKs of any kind. Nothing you do in the app is measured, profiled, or sold.

## Permissions Plated asks for, and why

- **Sign in with Apple**: establishes who owns the table and registers you
  with the directory above. Plated never receives your password.
- **Contacts**: read on your device to fill a seat. Numbers leave the phone
  only when you ask who is already on Plated, as described above, and are not
  stored.
- **Location**: used only to request a local forecast from Apple's WeatherKit so
  Plated can suggest a meal that suits the weather. Your location is passed to
  Apple to answer that request and is not stored by Plated or shared with anyone.
- **Calendar**: when you sync a gathering, Plated writes the event to a calendar
  you choose, on your device.
- **Reminders**: when you export a grocery list, Plated writes those items to
  your own Reminders list.
- **Photos**: photos you add to a recipe are stored with that recipe in your own
  iCloud account.

Every one of these permissions is optional. Decline any of them and the rest of
Plated keeps working; the feature that needed it simply stays quiet rather than
nagging you.

## Children

Plated is rated 4+ and does not knowingly collect information from children.

## Deleting your data

Your Plated data lives in your iCloud account. Deleting the app removes the local
copy; to remove the synced copy, delete Plated's data from iCloud in
Settings › [your name] › iCloud › Manage Account Storage. To remove your entry
from the directory, write to the address below and it will be deleted.

## Changes to this policy

If this policy changes, the revised version will be posted at this address with a
new date at the top.

## Contact

Questions about privacy in Plated: <!-- TODO: your support email address -->
