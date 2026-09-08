import Foundation
import CloudKit
import CryptoKit
import SwiftData

/// The household across Apple IDs: one zone in the host's private database,
/// one share on its root, and every synced row written as a hand-typed
/// record under it (docs/household.md §1 to §3).
///
/// `TableShare` is the template and every trap here was learned there
/// first: the share URL is server-assigned and read off the record that
/// comes back; a child needs `setParent` for the share hierarchy AND a
/// `.deleteSelf` reference for the cascade; a list minted empty is minted
/// as the wrong type forever; a Bool is an INT64; the change token belongs
/// to one zone; and zone changes, never a CKQuery, because a query with no
/// index returns nothing and calls it success.
///
/// What is different from the Table is the store. Posts are appended; the
/// plan, the roster and the cookbook are edited, by several phones, so the
/// merge is update-or-insert keyed on `shareRecordName`, a push fetches the
/// server record before writing it, and `modifiedAt` is compared as a
/// version rather than as a clock (§2).
enum HouseholdShare {

    /// One spelling each, and it lives on `TableShare`: the plan pipe
    /// (docs/plan-share.md) writes nights into this same zone, and two
    /// files holding their own copy of a zone name is how a rename ships
    /// half done.
    static let zoneName = TableShare.householdZoneName
    static let rootRecordName = TableShare.householdRootName

    // The reserved prefix is load-bearing: the SwiftData mirror adopts any
    // private-database record whose type matches one of its entity names,
    // so nothing here may ever be typed "PlannedMeal" or "Recipe".
    // `TableShare.assertNoEntityCollision` checks every one of these.
    static let rootType = TableShare.householdRootType
    static let seatType = "PlatedHouseholdSeat"
    static let mealType = "PlatedHouseholdMeal"
    static let recipeType = "PlatedHouseholdRecipe"
    static let gatheringType = "PlatedHouseholdGathering"
    static let lineType = "PlatedHouseholdGroceryLine"
    static let markType = "PlatedHouseholdGroceryMark"
    static let writtenTypes: Set<String> = [
        rootType, seatType, mealType, recipeType, gatheringType, lineType, markType
    ]

    static func mintSeatName() -> String { "seat-\(UUID().uuidString)" }

    // MARK: Membership

    /// Which household this phone is in. Cached in the app group so a
    /// SwiftUI body and the widget can answer synchronously; refreshed from
    /// CloudKit by `refreshMembership`, and only from a listing that
    /// succeeded, because a failed listing says nothing about membership.
    enum Membership: Codable, Equatable {
        case solo
        case hosting
        case member(owner: String)

        /// The zone owner's record name when this phone is a member.
        var owner: String? {
            if case .member(let owner) = self { return owner }
            return nil
        }

        var kind: String {
            switch self {
            case .solo: return "solo"
            case .hosting: return "hosting"
            case .member: return "member"
            }
        }
    }

    /// App-group keys. `HouseholdMember.Keys` names the two the model reads;
    /// `TableIdentity.reset` clears the whole set.
    enum Keys {
        /// The one membership key, spelled once (§4 of the seam between
        /// this and the plan pipe): "" while this Apple ID hosts its own
        /// household, the host's user record name while a member, absent
        /// in no household. `TableShare.resolveHousehold` reads it first.
        static let owner = TableShare.householdOwnerKey
        static let ownerName = "plated.household.ownerName"
        static let name = "plated.household.name"
        static let epoch = "plated.household.epoch"
        static let publishedAt = "plated.household.publishedAt"
        static let removedIDs = "plated.household.removedIDs"
        static let tableShareURL = "plated.household.tableShareURL"
        static let autoRotate = "plated.household.autoRotate"
        static let lastSyncedName = "plated.household.lastSyncedName"
        /// Meal references that named a record this phone has not received
        /// yet, so a recipe arriving after its meal can still repair it.
        static let unresolved = "plated.household.unresolvedRefs"
        static let sharedDatabaseToken = "plated.dbtoken.shared"
    }

    static var groupDefaults: UserDefaults {
        UserDefaults(suiteName: WidgetBridge.appGroupID) ?? .standard
    }

    static var membership: Membership {
        switch groupDefaults.string(forKey: HouseholdMember.Keys.membershipKind) {
        case "hosting": return .hosting
        case "member":
            let owner = groupDefaults.string(forKey: Keys.owner) ?? ""
            return owner.isEmpty ? .solo : .member(owner: owner)
        default: return .solo
        }
    }

    static func setMembership(_ membership: Membership, owner: String? = nil, ownerName: String? = nil) {
        let before = self.membership
        let defaults = groupDefaults
        defaults.set(membership.kind, forKey: HouseholdMember.Keys.membershipKind)
        let zoneOwner = owner ?? membership.owner
        // The owner key is a contract with the plan pipe on main
        // (docs/plan-share.md): "" when this Apple ID is the head of its
        // own zone, the host's record name when a member, ABSENT when in no
        // household. Removing it while hosting read, to that resolver, as
        // "no household", so the head's own plan never published.
        switch membership {
        case .hosting:
            defaults.set("", forKey: Keys.owner)
        case .member:
            if let zoneOwner, !zoneOwner.isEmpty {
                defaults.set(zoneOwner, forKey: Keys.owner)
            } else {
                defaults.removeObject(forKey: Keys.owner)
            }
        case .solo:
            defaults.removeObject(forKey: Keys.owner)
        }
        if let ownerName { defaults.set(ownerName, forKey: Keys.ownerName) }
        // A new household is a new epoch: nothing cached for the old one
        // may be read as a fact about this one.
        if before != membership {
            defaults.set(UUID().uuidString, forKey: Keys.epoch)
        }
        print("PLATED HOUSEHOLD: membership \(membership.kind)\(zoneOwner.map { " of \($0)" } ?? "")")
    }

    static var mySeat: String? {
        get {
            let seat = groupDefaults.string(forKey: HouseholdMember.Keys.mySeat) ?? ""
            return seat.isEmpty ? nil : seat
        }
        set {
            if let newValue, !newValue.isEmpty {
                groupDefaults.set(newValue, forKey: HouseholdMember.Keys.mySeat)
            } else {
                groupDefaults.removeObject(forKey: HouseholdMember.Keys.mySeat)
            }
        }
    }

    static var cachedOwnerName: String { groupDefaults.string(forKey: Keys.ownerName) ?? "" }
    static var cachedName: String { groupDefaults.string(forKey: Keys.name) ?? "" }
    static var cachedPublishedAt: Date? { groupDefaults.object(forKey: Keys.publishedAt) as? Date }
    static var cachedTableShareURL: URL? {
        groupDefaults.string(forKey: Keys.tableShareURL).flatMap(URL.init(string:))
    }
    static var cachedRemovedIDs: [String] {
        guard let data = groupDefaults.data(forKey: Keys.removedIDs) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// The record name the zone's owner answers to: the host's own identity
    /// on the host's phone, the zone owner on a member's. The only seat that
    /// may be head, and the only seat that may carry `role == "owner"`.
    static var zoneOwnerRecordName: String {
        membership.owner ?? TableIdentity.cached
    }

    // MARK: What travels (§3)
    //
    // Plain values, never model objects: the fetch runs off the main actor,
    // the merge on it, and nothing crosses that line but these.

    struct RemoteRoot: Equatable {
        var name = ""
        var hostName = ""
        var hostPhoto: Data?
        var banner: Data?
        var tableShareURL: URL?
        var autoRotate = true
        var publishedAt: Date?
        var removedIDs: [String] = []
        var modifiedAt = Date.now
    }

    struct RemoteSeat: Equatable {
        var recordName = ""
        var authorID = ""
        var modifiedBy = ""
        var modifiedAt = Date.now
        var name = ""
        var role = "member"
        var roleLine = ""
        var colorHex = "C86629"
        var dietaryNotes = ""
        var avoidedIngredients: [String] = []
        var cookWeekdays: [Int] = []
        var isPrimaryCook = false
        /// The raw `HouseholdMember.Seat` string.
        var seat = HouseholdMember.Seat.notOnPlated.rawValue
        var invitedAt: Date?
        var joinedAt: Date?
        var leftAt: Date?
        var participantID: String?
        var userRecordName: String?
        var bio = ""
        var photo: Data?
    }

    struct RemoteMeal: Equatable {
        var recordName = ""
        var authorID = ""
        var modifiedBy = ""
        var modifiedAt = Date.now
        /// yyyy-MM-dd, so two time zones cannot move a dinner between days.
        var day = ""
        var slot = MealSlot.dinner.rawValue
        var customTitle = ""
        var titleSnapshot = ""
        var notes = ""
        var servings = 4
        var cookedAt: Date?
        var cookReaction = 0
        var actualMinutes = 0
        var createdAt = Date.now
        var shoppingID: String?
        var tagline = ""
        var recipeRecordName = ""
        var cookRecordName = ""
        var gatheringRecordName = ""
    }

    /// One ingredient line as it rides inside `ingredientsJSON`.
    struct WireIngredient: Codable, Equatable {
        var name = ""
        var quantity = 0.0
        var unit = ""
        var aisle = GroceryAisle.other.rawValue
        var isPantryStaple = false
        var sortIndex = 0
    }

    struct RemoteRecipe: Equatable {
        var recordName = ""
        var authorID = ""
        var modifiedBy = ""
        var modifiedAt = Date.now
        var title = ""
        var summary = ""
        var instructions = ""
        var sourceURL = ""
        var sourceName = ""
        var sourceText = ""
        var importMethod = ""
        var importedAt: Date?
        var servings = 4
        var prepMinutes = 0
        var cookMinutes = 0
        var tags: [String] = []
        var category = ""
        var difficulty = ""
        var mealType = RecipeMealType.dinner.rawValue
        var steps: [String] = []
        var visibility = "household"
        var householdCanEdit = true
        var originID = ""
        var createdAt = Date.now
        var cookNotes = ""
        var weatherMoods: [String] = []
        var ingredients: [WireIngredient] = []
        var photoData: Data?
        var extraPhotos: [Data] = []
        var photoHash = ""
    }

    struct RemoteGathering: Equatable {
        var recordName = ""
        var authorID = ""
        var modifiedBy = ""
        var modifiedAt = Date.now
        var title = ""
        var notes = ""
        var startDate = Date.now
        var endDate = Date.now
        var guestCount = 0
        var location = ""
    }

    struct RemoteLine: Equatable {
        var recordName = ""
        var authorID = ""
        var modifiedBy = ""
        var modifiedAt = Date.now
        var name = ""
        var quantity = 0.0
        var unit = ""
        var aisle = GroceryAisle.other.rawValue
        /// yyyy-MM-dd of the window the line is filed under.
        var day = ""
        var originTitle = ""
        var isChecked = false
    }

    struct RemoteMark: Equatable {
        var recordName = ""
        var authorID = ""
        var modifiedBy = ""
        var modifiedAt = Date.now
        var lineKey = ""
        var purchases: [String: Double] = [:]
        var dismissedUntil: String?
        var at = Date.now
        var by = ""
    }

    /// What the zone said since we last asked.
    struct Changes {
        var root: RemoteRoot?
        var seats: [RemoteSeat] = []
        var meals: [RemoteMeal] = []
        var recipes: [RemoteRecipe] = []
        var gatherings: [RemoteGathering] = []
        var lines: [RemoteLine] = []
        var marks: [RemoteMark] = []
        var deleted: Set<String> = []
        /// The CKShare itself came back: somebody joined, or was removed.
        var sharesChanged = false
        /// A zone was read from the beginning, so this delta is history to
        /// be windowed rather than a day's events.
        var replayed = false
        /// The household's zone is gone from the shared database, on
        /// positive evidence only (§8): this phone was removed.
        var zoneGone = false
        /// A read that did not happen. An empty delta and a failed one look
        /// identical from the outside, and §Honesty says the difference has
        /// to be knowable: a join cannot seat somebody off a zone it never
        /// read, and a screen cannot say "nothing yet" about an answer it
        /// never got.
        var failed = false

        /// The plan half of this zone: collected here, folded nowhere here.
        ///
        /// One reader owns the household zone's change cursor and it is
        /// this one, so the `PlatedHouseholdPlan` records the walk goes
        /// past cannot simply be dropped: the peer plan pipe
        /// (docs/plan-share.md) needs them. They ride out in the shape that
        /// pipe already speaks, and `TablePull` hands this to
        /// `ShareAcceptor.absorb`, which is the one place `PlanLedger` is
        /// ever fed. Nothing in this file reads it.
        var plan = TableShare.Changes()

        var isEmpty: Bool {
            root == nil && seats.isEmpty && meals.isEmpty && recipes.isEmpty
                && gatherings.isEmpty && lines.isEmpty && marks.isEmpty && deleted.isEmpty
        }

        /// Sort one record into its bucket.
        mutating func add(_ record: CKRecord) {
            if record is CKShare { sharesChanged = true; return }
            switch record.recordType {
            case HouseholdShare.rootType: root = HouseholdShare.remoteRoot(from: record)
            case HouseholdShare.seatType: seats.append(HouseholdShare.remoteSeat(from: record))
            case HouseholdShare.mealType: meals.append(HouseholdShare.remoteMeal(from: record))
            case HouseholdShare.recipeType: recipes.append(HouseholdShare.remoteRecipe(from: record))
            case HouseholdShare.gatheringType: gatherings.append(HouseholdShare.remoteGathering(from: record))
            case HouseholdShare.lineType: lines.append(HouseholdShare.remoteLine(from: record))
            case HouseholdShare.markType: marks.append(HouseholdShare.remoteMark(from: record))
            case TableShare.planType: addPlan(record)
            default: break
            }
        }

        /// A night, in the plan pipe's own words. Its codec lives on
        /// `TableShare` beside the record type, so there is one spelling of
        /// a plan record rather than two that can drift.
        private mutating func addPlan(_ record: CKRecord) {
            #if PLATED_CLOUDKIT
            plan.plans.append(TableShare.remotePlan(from: record))
            #endif
        }

        mutating func absorb(_ other: Changes) {
            if let root = other.root { self.root = root }
            seats += other.seats
            meals += other.meals
            recipes += other.recipes
            gatherings += other.gatherings
            lines += other.lines
            marks += other.marks
            deleted.formUnion(other.deleted)
            plan.plans += other.plan.plans
            plan.deleted.formUnion(other.plan.deleted)
            plan.replayedOwners.formUnion(other.plan.replayedOwners)
            plan.householdShareChanged = plan.householdShareChanged || other.plan.householdShareChanged
            sharesChanged = sharesChanged || other.sharesChanged
            replayed = replayed || other.replayed
            zoneGone = zoneGone || other.zoneGone
            failed = failed || other.failed
        }

        /// Finish the plan half with what only the boundary knows, and it
        /// is the boundary that has to say it: a zone's
        /// `ownerName` is observer relative (`__defaultOwner__` to the head
        /// reading their own database, a record name to a member reading
        /// the shared one), while the ledger compares this string across
        /// pulls and across devices. "" is always my own zone.
        mutating func stampPlan(owner: String) {
            for i in plan.plans.indices { plan.plans[i].zoneOwner = owner }
            // A night taken off travels as a deletion, and only `plan-`
            // names are nights. The rest of this zone's deletions are
            // household records, which the Table's merge has no business
            // being handed.
            plan.deleted.formUnion(deleted.filter { $0.hasPrefix("plan-") })
            // A zone read from the beginning delivers every live record and
            // no deletion at all, so for this owner what arrived is the
            // whole truth and the ledger reconciles its nights against it.
            if replayed { plan.replayedOwners.insert(owner) }
            // The head sweeps a departed member's nights out of their own
            // zone when the household share changes; nothing on the server
            // cascades, and the Table's share says nothing about this one.
            plan.householdShareChanged = plan.householdShareChanged || sharesChanged
        }
    }

    struct MergeOutcome {
        var newSeats: [HouseholdMember] = []
        var leftSeats: [HouseholdMember] = []
        var newMeals: [PlannedMeal] = []
        var newRecipes: [Recipe] = []
        /// Record names whose local edit lost to a newer server version.
        /// Empty from a pull; `HouseholdOutbox.drain` fills it from the
        /// push's `remoteNewer` answers (§2, "Versions, not clocks").
        var conflicts: [String] = []
    }

    enum PushOutcome {
        case saved(modifiedAt: Date)
        /// Somebody else wrote since this device last looked, so their
        /// version was merged and the local edit dropped. It carries the
        /// server record decoded the way a pull decodes it, because the
        /// bell row that says so has to name who wrote it (§10) and the
        /// digest reads `modifiedBy` off a `Changes`, not off a row.
        case remoteNewer(theirs: Changes)
        case gone
        case retry
        case failed
    }

    // MARK: The codec
    //
    // One road each way, shared by the pull, the push and the tests: a
    // record decodes into a Remote value, and a Remote value writes its
    // fields onto a record. `CKRecord` can be built without a network, so
    // the round trip is testable on a simulator with no iCloud account.

    enum Wire {
        static func day(_ date: Date) -> String { HouseholdMember.day(date) }

        /// A calendar day, turned back into a `Date` with the reading
        /// phone's calendar so it lands on that phone's midnight.
        static func date(fromDay day: String) -> Date? {
            let parts = day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            var components = DateComponents()
            components.year = parts[0]
            components.month = parts[1]
            components.day = parts[2]
            // The day is written with an explicit Gregorian calendar
            // (`HouseholdMember.day`), so it has to be read with one. On a
            // phone set to the Buddhist or Japanese calendar, 2026 names a
            // different era and every pulled dinner would land centuries
            // away and vanish from the plan. The time zone stays the
            // reader's, so the day still lands on their own midnight.
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = .current
            return gregorian.date(from: components)
                .map { Calendar.current.startOfDay(for: $0) }
        }

        static func hash(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        /// One hash over the hero and every extra, in order, so a change to
        /// any photograph changes it and an edit to the title does not.
        static func photoHash(hero: Data?, extras: [Data]) -> String {
            guard hero != nil || !extras.isEmpty else { return "" }
            var digest = SHA256()
            if let hero { digest.update(data: hero) }
            for extra in extras { digest.update(data: extra) }
            return digest.finalize().map { String(format: "%02x", $0) }.joined()
        }

        static func data(_ record: CKRecord, _ key: String) -> Data? {
            guard let asset = record[key] as? CKAsset, let url = asset.fileURL else { return nil }
            return try? Data(contentsOf: url)
        }

        static func dataList(_ record: CKRecord, _ key: String) -> [Data] {
            guard let assets = record[key] as? [CKAsset] else { return [] }
            return assets.compactMap { $0.fileURL.flatMap { try? Data(contentsOf: $0) } }
        }

        static func double(_ record: CKRecord, _ key: String) -> Double {
            if let n = record[key] as? Double { return n }
            if let n = record[key] as? NSNumber { return n.doubleValue }
            return 0
        }

        static func string(_ record: CKRecord, _ key: String) -> String {
            record[key] as? String ?? ""
        }

        /// A list key is omitted when the list is empty, never written as
        /// `[]`: a CloudKit list field minted from an empty array is minted
        /// as the wrong type, permanently. Writing nil on a fetched record
        /// clears a value that used to be there, which is what a cleared
        /// list means.
        static func setList<T>(_ record: CKRecord, _ key: String, _ list: [T]) where T: CKRecordValueProtocol {
            set(record, key, list.isEmpty ? nil : list)
        }

        /// One door for every field write, so the ObjC and Swift subscripts
        /// on `CKRecord` can never be picked ambiguously at a call site.
        static func set(_ record: CKRecord, _ key: String, _ value: (any CKRecordValueProtocol)?) {
            record[key] = value
        }

        static func setAsset(_ record: CKRecord, _ key: String, _ data: Data?) {
            set(record, key, data.flatMap(TableShare.asset(from:)))
        }

        static func setAssets(_ record: CKRecord, _ key: String, _ list: [Data]) {
            let assets = list.compactMap(TableShare.asset(from:))
            set(record, key, assets.isEmpty ? nil : assets)
        }

        /// Temporary files created for assets on a record, removed once the
        /// save has answered. Only ours: a fetched record's assets point
        /// into CloudKit's own cache.
        static func removeTemporaryAssets(on records: [CKRecord]) {
            let temp = FileManager.default.temporaryDirectory.path
            for record in records {
                for key in record.allKeys() {
                    let assets: [CKAsset]
                    if let one = record[key] as? CKAsset { assets = [one] }
                    else if let many = record[key] as? [CKAsset] { assets = many }
                    else { continue }
                    for asset in assets {
                        guard let url = asset.fileURL, url.path.hasPrefix(temp),
                              url.lastPathComponent.hasPrefix("share-") else { continue }
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
        }
    }

    // MARK: Record -> Remote

    static func remoteRoot(from record: CKRecord) -> RemoteRoot {
        var r = RemoteRoot()
        r.name = Wire.string(record, "name")
        r.hostName = Wire.string(record, "hostName")
        r.hostPhoto = Wire.data(record, "hostPhoto")
        r.banner = Wire.data(record, "banner")
        r.tableShareURL = (record["tableShareURL"] as? String).flatMap(URL.init(string:))
        r.autoRotate = TableShare.int(record, "autoRotateOpenNights") != 0
        r.publishedAt = record["publishedAt"] as? Date
        r.removedIDs = record["removedIDs"] as? [String] ?? []
        r.modifiedAt = record["modifiedAt"] as? Date ?? .now
        return r
    }

    static func remoteSeat(from record: CKRecord) -> RemoteSeat {
        var s = RemoteSeat()
        s.recordName = record.recordID.recordName
        s.authorID = Wire.string(record, "authorID")
        s.modifiedBy = Wire.string(record, "modifiedBy")
        s.modifiedAt = record["modifiedAt"] as? Date ?? .now
        s.name = Wire.string(record, "name")
        s.role = record["role"] as? String ?? "member"
        s.roleLine = Wire.string(record, "roleLine")
        s.colorHex = record["colorHex"] as? String ?? "C86629"
        s.dietaryNotes = Wire.string(record, "dietaryNotes")
        s.avoidedIngredients = record["avoidedIngredients"] as? [String] ?? []
        s.cookWeekdays = (record["cookWeekdays"] as? [NSNumber])?.map(\.intValue)
            ?? record["cookWeekdays"] as? [Int] ?? []
        s.isPrimaryCook = TableShare.int(record, "isPrimaryCook") != 0
        s.seat = record["seat"] as? String ?? HouseholdMember.Seat.notOnPlated.rawValue
        s.invitedAt = record["invitedAt"] as? Date
        s.joinedAt = record["joinedAt"] as? Date
        s.leftAt = record["leftAt"] as? Date
        s.participantID = record["participantID"] as? String
        s.userRecordName = record["userRecordName"] as? String
        s.bio = Wire.string(record, "bio")
        s.photo = Wire.data(record, "photo")
        return s
    }

    static func remoteMeal(from record: CKRecord) -> RemoteMeal {
        var m = RemoteMeal()
        m.recordName = record.recordID.recordName
        m.authorID = Wire.string(record, "authorID")
        m.modifiedBy = Wire.string(record, "modifiedBy")
        m.modifiedAt = record["modifiedAt"] as? Date ?? .now
        m.day = Wire.string(record, "day")
        m.slot = record["slot"] as? String ?? MealSlot.dinner.rawValue
        m.customTitle = Wire.string(record, "customTitle")
        m.titleSnapshot = Wire.string(record, "titleSnapshot")
        m.notes = Wire.string(record, "notes")
        m.servings = record["servings"] == nil ? 4 : TableShare.int(record, "servings")
        m.cookedAt = record["cookedAt"] as? Date
        m.cookReaction = TableShare.int(record, "cookReaction")
        m.actualMinutes = TableShare.int(record, "actualMinutes")
        m.createdAt = record["createdAt"] as? Date ?? .now
        m.shoppingID = record["shoppingID"] as? String
        m.tagline = Wire.string(record, "tagline")
        m.recipeRecordName = Wire.string(record, "recipeRecordName")
        m.cookRecordName = Wire.string(record, "cookRecordName")
        m.gatheringRecordName = Wire.string(record, "gatheringRecordName")
        return m
    }

    static func remoteRecipe(from record: CKRecord) -> RemoteRecipe {
        var r = RemoteRecipe()
        r.recordName = record.recordID.recordName
        r.authorID = Wire.string(record, "authorID")
        r.modifiedBy = Wire.string(record, "modifiedBy")
        r.modifiedAt = record["modifiedAt"] as? Date ?? .now
        r.title = Wire.string(record, "title")
        r.summary = Wire.string(record, "summary")
        r.instructions = Wire.string(record, "instructions")
        r.sourceURL = Wire.string(record, "sourceURL")
        r.sourceName = Wire.string(record, "sourceName")
        r.sourceText = Wire.string(record, "sourceText")
        r.importMethod = Wire.string(record, "importMethod")
        r.importedAt = record["importedAt"] as? Date
        r.servings = record["servings"] == nil ? 4 : TableShare.int(record, "servings")
        r.prepMinutes = TableShare.int(record, "prepMinutes")
        r.cookMinutes = TableShare.int(record, "cookMinutes")
        r.tags = record["tags"] as? [String] ?? []
        r.category = Wire.string(record, "category")
        r.difficulty = Wire.string(record, "difficulty")
        r.mealType = record["mealType"] as? String ?? RecipeMealType.dinner.rawValue
        r.steps = record["steps"] as? [String] ?? []
        r.visibility = record["visibility"] as? String ?? "household"
        r.householdCanEdit = record["householdCanEdit"] == nil ? true : TableShare.int(record, "householdCanEdit") != 0
        r.originID = Wire.string(record, "originID")
        r.createdAt = record["createdAt"] as? Date ?? .now
        r.cookNotes = Wire.string(record, "cookNotes")
        r.weatherMoods = record["weatherMoods"] as? [String] ?? []
        if let json = record["ingredientsJSON"] as? String, let data = json.data(using: .utf8) {
            r.ingredients = (try? JSONDecoder().decode([WireIngredient].self, from: data)) ?? []
        }
        r.photoData = Wire.data(record, "photo")
        r.extraPhotos = Wire.dataList(record, "extraPhotos")
        r.photoHash = Wire.string(record, "photoHash")
        return r
    }

    static func remoteGathering(from record: CKRecord) -> RemoteGathering {
        var g = RemoteGathering()
        g.recordName = record.recordID.recordName
        g.authorID = Wire.string(record, "authorID")
        g.modifiedBy = Wire.string(record, "modifiedBy")
        g.modifiedAt = record["modifiedAt"] as? Date ?? .now
        g.title = Wire.string(record, "title")
        g.notes = Wire.string(record, "notes")
        g.startDate = record["startDate"] as? Date ?? .now
        g.endDate = record["endDate"] as? Date ?? g.startDate.addingTimeInterval(3 * 3600)
        g.guestCount = TableShare.int(record, "guestCount")
        g.location = Wire.string(record, "location")
        return g
    }

    static func remoteLine(from record: CKRecord) -> RemoteLine {
        var l = RemoteLine()
        l.recordName = record.recordID.recordName
        l.authorID = Wire.string(record, "authorID")
        l.modifiedBy = Wire.string(record, "modifiedBy")
        l.modifiedAt = record["modifiedAt"] as? Date ?? .now
        l.name = Wire.string(record, "name")
        l.quantity = Wire.double(record, "quantity")
        l.unit = Wire.string(record, "unit")
        l.aisle = record["aisle"] as? String ?? GroceryAisle.other.rawValue
        l.day = Wire.string(record, "day")
        l.originTitle = Wire.string(record, "originTitle")
        l.isChecked = TableShare.int(record, "isChecked") != 0
        return l
    }

    static func remoteMark(from record: CKRecord) -> RemoteMark {
        var m = RemoteMark()
        m.recordName = record.recordID.recordName
        m.modifiedBy = Wire.string(record, "modifiedBy")
        m.modifiedAt = record["modifiedAt"] as? Date ?? .now
        m.authorID = m.modifiedBy
        m.lineKey = Wire.string(record, "lineKey")
        if let json = record["purchasesJSON"] as? String, let data = json.data(using: .utf8) {
            m.purchases = (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
        }
        m.dismissedUntil = record["dismissedUntil"] as? String
        m.at = m.modifiedAt
        m.by = m.modifiedBy
        return m
    }

    // MARK: Remote -> record

    static func write(_ root: RemoteRoot, onto record: CKRecord) {
        Wire.set(record, "name", root.name)
        Wire.set(record, "hostName", root.hostName)
        Wire.setAsset(record, "hostPhoto", root.hostPhoto)
        Wire.setAsset(record, "banner", root.banner)
        Wire.set(record, "tableShareURL", root.tableShareURL?.absoluteString)
        Wire.set(record, "autoRotateOpenNights", root.autoRotate ? 1 : 0)
        Wire.set(record, "publishedAt", root.publishedAt)
        Wire.setList(record, "removedIDs", root.removedIDs)
        Wire.set(record, "modifiedAt", root.modifiedAt)
    }

    static func write(_ s: RemoteSeat, onto record: CKRecord) {
        Wire.set(record, "authorID", s.authorID)
        Wire.set(record, "modifiedBy", s.modifiedBy)
        Wire.set(record, "modifiedAt", s.modifiedAt)
        Wire.set(record, "name", s.name)
        Wire.set(record, "role", s.role)
        Wire.set(record, "roleLine", s.roleLine)
        Wire.set(record, "colorHex", s.colorHex)
        Wire.set(record, "dietaryNotes", s.dietaryNotes)
        Wire.setList(record, "avoidedIngredients", s.avoidedIngredients)
        Wire.setList(record, "cookWeekdays", s.cookWeekdays)
        Wire.set(record, "isPrimaryCook", s.isPrimaryCook ? 1 : 0)
        Wire.set(record, "seat", s.seat)
        Wire.set(record, "invitedAt", s.invitedAt)
        Wire.set(record, "joinedAt", s.joinedAt)
        Wire.set(record, "leftAt", s.leftAt)
        Wire.set(record, "participantID", s.participantID)
        Wire.set(record, "userRecordName", s.userRecordName)
        Wire.set(record, "bio", s.bio)
        Wire.setAsset(record, "photo", s.photo)
    }

    static func write(_ m: RemoteMeal, onto record: CKRecord) {
        Wire.set(record, "authorID", m.authorID)
        Wire.set(record, "modifiedBy", m.modifiedBy)
        Wire.set(record, "modifiedAt", m.modifiedAt)
        Wire.set(record, "day", m.day)
        Wire.set(record, "slot", m.slot)
        Wire.set(record, "customTitle", m.customTitle)
        Wire.set(record, "titleSnapshot", m.titleSnapshot)
        Wire.set(record, "notes", m.notes)
        Wire.set(record, "servings", m.servings)
        Wire.set(record, "cookedAt", m.cookedAt)
        Wire.set(record, "cookReaction", m.cookReaction)
        Wire.set(record, "actualMinutes", m.actualMinutes)
        Wire.set(record, "createdAt", m.createdAt)
        Wire.set(record, "shoppingID", m.shoppingID)
        Wire.set(record, "tagline", m.tagline)
        Wire.set(record, "recipeRecordName", m.recipeRecordName)
        Wire.set(record, "cookRecordName", m.cookRecordName)
        Wire.set(record, "gatheringRecordName", m.gatheringRecordName)
    }

    /// `includingPhotos` false leaves the photo keys of a fetched record
    /// exactly as they are, so a title edit does not re-upload six assets.
    static func write(_ r: RemoteRecipe, onto record: CKRecord, includingPhotos: Bool = true) {
        Wire.set(record, "authorID", r.authorID)
        Wire.set(record, "modifiedBy", r.modifiedBy)
        Wire.set(record, "modifiedAt", r.modifiedAt)
        Wire.set(record, "title", r.title)
        Wire.set(record, "summary", r.summary)
        Wire.set(record, "instructions", r.instructions)
        Wire.set(record, "sourceURL", r.sourceURL)
        Wire.set(record, "sourceName", r.sourceName)
        Wire.set(record, "sourceText", r.sourceText)
        Wire.set(record, "importMethod", r.importMethod)
        Wire.set(record, "importedAt", r.importedAt)
        Wire.set(record, "servings", r.servings)
        Wire.set(record, "prepMinutes", r.prepMinutes)
        Wire.set(record, "cookMinutes", r.cookMinutes)
        Wire.setList(record, "tags", r.tags)
        Wire.set(record, "category", r.category)
        Wire.set(record, "difficulty", r.difficulty)
        Wire.set(record, "mealType", r.mealType)
        Wire.setList(record, "steps", r.steps)
        Wire.set(record, "visibility", r.visibility)
        Wire.set(record, "householdCanEdit", r.householdCanEdit ? 1 : 0)
        Wire.set(record, "originID", r.originID)
        Wire.set(record, "createdAt", r.createdAt)
        Wire.set(record, "cookNotes", r.cookNotes)
        Wire.setList(record, "weatherMoods", r.weatherMoods)
        let json = (try? JSONEncoder().encode(r.ingredients))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        Wire.set(record, "ingredientsJSON", json)
        if includingPhotos {
            Wire.setAsset(record, "photo", r.photoData)
            Wire.setAssets(record, "extraPhotos", r.extraPhotos)
            Wire.set(record, "photoHash", r.photoHash)
        }
    }

    static func write(_ g: RemoteGathering, onto record: CKRecord) {
        Wire.set(record, "authorID", g.authorID)
        Wire.set(record, "modifiedBy", g.modifiedBy)
        Wire.set(record, "modifiedAt", g.modifiedAt)
        Wire.set(record, "title", g.title)
        Wire.set(record, "notes", g.notes)
        Wire.set(record, "startDate", g.startDate)
        Wire.set(record, "endDate", g.endDate)
        Wire.set(record, "guestCount", g.guestCount)
        Wire.set(record, "location", g.location)
    }

    static func write(_ l: RemoteLine, onto record: CKRecord) {
        Wire.set(record, "authorID", l.authorID)
        Wire.set(record, "modifiedBy", l.modifiedBy)
        Wire.set(record, "modifiedAt", l.modifiedAt)
        Wire.set(record, "name", l.name)
        Wire.set(record, "quantity", l.quantity)
        Wire.set(record, "unit", l.unit)
        Wire.set(record, "aisle", l.aisle)
        Wire.set(record, "day", l.day)
        Wire.set(record, "originTitle", l.originTitle)
        Wire.set(record, "isChecked", l.isChecked ? 1 : 0)
    }

    static func write(_ m: RemoteMark, onto record: CKRecord) {
        Wire.set(record, "modifiedBy", m.by)
        Wire.set(record, "modifiedAt", m.at)
        Wire.set(record, "lineKey", m.lineKey)
        // An empty map is a value (unchecked), so it is always written.
        let json = (try? JSONEncoder().encode(m.purchases))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        Wire.set(record, "purchasesJSON", json)
        Wire.set(record, "dismissedUntil", m.dismissedUntil)
    }

    // MARK: Model -> Remote

    @MainActor
    static func remote(from member: HouseholdMember) -> RemoteSeat {
        var s = RemoteSeat()
        s.recordName = member.shareRecordName
        s.authorID = member.authorID
        s.name = member.name
        s.role = member.role
        s.roleLine = member.roleLine
        s.colorHex = member.colorHex
        s.dietaryNotes = member.dietaryNotes
        s.avoidedIngredients = member.avoidedIngredients
        s.cookWeekdays = member.cookWeekdays
        s.isPrimaryCook = member.isPrimaryCook
        s.seat = member.seatRaw
        s.invitedAt = member.invitedAt
        s.joinedAt = member.joinedAt
        s.leftAt = member.leftAt
        s.participantID = member.participantID
        s.userRecordName = member.userRecordName
        s.bio = member.bio
        s.photo = member.photoData
        return s
    }

    @MainActor
    static func remote(from meal: PlannedMeal) -> RemoteMeal {
        var m = RemoteMeal()
        m.recordName = meal.shareRecordName
        m.authorID = meal.authorID
        m.day = meal.day
        m.slot = meal.slot
        m.customTitle = meal.customTitle
        m.titleSnapshot = meal.title
        m.notes = meal.notes
        m.servings = meal.servings
        m.cookedAt = meal.cookedAt
        m.cookReaction = meal.cookReaction
        m.actualMinutes = meal.actualMinutes
        m.createdAt = meal.createdAt
        m.shoppingID = meal.shoppingID
        m.tagline = meal.tagline
        // A meal can arrive before the recipe it names: the reference is
        // parked in `unresolved` and the relationship is nil until the
        // recipe lands. Writing "" for it here would tell every other phone
        // that this dinner has no recipe, and the host's own dinner would
        // lose its ingredients off the grocery list.
        let parked = unresolved[meal.shareRecordName] ?? [:]
        m.recipeRecordName = meal.recipe?.shareRecordName ?? parked["recipe"] ?? ""
        m.cookRecordName = meal.cook?.shareRecordName ?? parked["cook"] ?? ""
        m.gatheringRecordName = meal.gathering?.shareRecordName ?? parked["gathering"] ?? ""
        return m
    }

    @MainActor
    static func remote(from recipe: Recipe) -> RemoteRecipe {
        var r = RemoteRecipe()
        r.recordName = recipe.shareRecordName
        r.authorID = recipe.authorID
        r.title = recipe.title
        r.summary = recipe.summary
        r.instructions = recipe.instructions
        r.sourceURL = recipe.sourceURL
        r.sourceName = recipe.sourceName
        r.sourceText = recipe.sourceText
        r.importMethod = recipe.importMethod
        r.importedAt = recipe.importedAt
        r.servings = recipe.servings
        r.prepMinutes = recipe.prepMinutes
        r.cookMinutes = recipe.cookMinutes
        r.tags = recipe.tags
        r.category = recipe.category
        r.difficulty = recipe.difficulty
        r.mealType = recipe.mealType
        r.steps = recipe.steps
        r.visibility = recipe.visibility
        r.householdCanEdit = recipe.householdCanEdit
        r.originID = recipe.originID
        r.createdAt = recipe.createdAt
        r.cookNotes = recipe.cookNotes
        r.weatherMoods = recipe.weatherMoods
        r.ingredients = recipe.sortedIngredients.map {
            WireIngredient(name: $0.name, quantity: $0.quantity, unit: $0.unit,
                           aisle: $0.aisle, isPantryStaple: $0.isPantryStaple, sortIndex: $0.sortIndex)
        }
        r.photoData = recipe.photoData
        r.extraPhotos = recipe.sortedExtraPhotos.compactMap(\.photoData)
        r.photoHash = Wire.photoHash(hero: r.photoData, extras: r.extraPhotos)
        return r
    }

    @MainActor
    static func remote(from gathering: Gathering) -> RemoteGathering {
        var g = RemoteGathering()
        g.recordName = gathering.shareRecordName
        g.authorID = gathering.authorID
        g.title = gathering.title
        g.notes = gathering.notes
        g.startDate = gathering.startDate
        g.endDate = gathering.endDate
        g.guestCount = gathering.guestCount
        g.location = gathering.location
        return g
    }

    @MainActor
    static func remote(from line: GroceryItem) -> RemoteLine {
        var l = RemoteLine()
        l.recordName = line.shareRecordName
        l.authorID = line.authorID
        l.name = line.name
        l.quantity = line.quantity
        l.unit = line.unit
        l.aisle = line.aisle
        l.day = Wire.day(line.weekStart)
        l.originTitle = line.originTitle
        l.isChecked = line.isChecked
        return l
    }

    @MainActor
    static func remote(from mark: GroceryMarks.Mark) -> RemoteMark {
        var m = RemoteMark()
        m.recordName = GroceryMarks.recordName(for: mark.lineKey)
        m.authorID = mark.by
        m.modifiedBy = mark.by
        m.modifiedAt = mark.at
        m.lineKey = mark.lineKey
        m.purchases = mark.purchases
        m.dismissedUntil = mark.dismissedUntil
        m.at = mark.at
        m.by = mark.by
        return m
    }

    // MARK: Unresolved references
    //
    // A meal's references travel as record names and the local row keeps
    // only the relationship, so a name this phone could not resolve yet has
    // to be remembered somewhere or the recipe arriving next pull could
    // never repair the meal. A small book in the app group, pruned as each
    // reference resolves.

    private static var unresolved: [String: [String: String]] {
        get {
            guard let data = groupDefaults.data(forKey: Keys.unresolved) else { return [:] }
            return (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
        }
        set {
            if newValue.isEmpty { groupDefaults.removeObject(forKey: Keys.unresolved) }
            else if let data = try? JSONEncoder().encode(newValue) { groupDefaults.set(data, forKey: Keys.unresolved) }
        }
    }

    static func forgetUnresolved() { groupDefaults.removeObject(forKey: Keys.unresolved) }

    // MARK: Merge (§2, §3)

    /// Fold a delta into the store, keyed on `shareRecordName`, update or
    /// insert, never delete-and-reinsert: cook sessions, `PlannedMeal.recipe`
    /// and the rota all depend on row identity.
    ///
    /// `ignoringPending` is the push's door: a row whose own push found a
    /// newer server version is merged through here despite its outbox
    /// entry, which is otherwise the one thing a pull never overwrites.
    @MainActor
    @discardableResult
    static func merge(
        _ changes: Changes, into context: ModelContext,
        ignoringPending: Set<String> = []
    ) -> MergeOutcome {
        var outcome = MergeOutcome()
        guard !changes.isEmpty else { return outcome }
        HouseholdSync.suppressed = true
        defer { HouseholdSync.suppressed = false }

        let me = TableIdentity.cached
        let ownerRecordName = zoneOwnerRecordName
        let claimedSeat = mySeat
        func pending(_ name: String) -> Bool {
            !ignoringPending.contains(name) && HouseholdOutbox.shared.hasPending(name)
        }
        func stamp(_ row: any PersistentModel) -> String {
            HouseholdSync.fingerprint(of: row) ?? ""
        }

        var members = (try? context.fetch(FetchDescriptor<HouseholdMember>())) ?? []
        var recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        var gatherings = (try? context.fetch(FetchDescriptor<Gathering>())) ?? []
        var meals = (try? context.fetch(FetchDescriptor<PlannedMeal>())) ?? []
        var lines = ((try? context.fetch(FetchDescriptor<GroceryItem>())) ?? []).filter(\.isManual)

        func memberNamed(_ name: String) -> HouseholdMember? {
            guard !name.isEmpty else { return nil }
            return members.first { $0.shareRecordName == name }
        }
        func recipeNamed(_ name: String) -> Recipe? {
            guard !name.isEmpty else { return nil }
            return recipes.first { $0.shareRecordName == name }
        }
        func gatheringNamed(_ name: String) -> Gathering? {
            guard !name.isEmpty else { return nil }
            return gatherings.first { $0.shareRecordName == name }
        }
        func mealNamed(_ name: String) -> PlannedMeal? {
            guard !name.isEmpty else { return nil }
            return meals.first { $0.shareRecordName == name }
        }

        // Taken away, of any kind. Deletion wins any conflict, as CloudKit's
        // own semantics do. A deleted meal's mark is left alone: a mark is
        // about a line, and the line may still be on the list from another
        // night.
        for name in changes.deleted {
            if let member = memberNamed(name) {
                context.delete(member)
                members.removeAll { $0 === member }
            } else if let meal = mealNamed(name) {
                context.delete(meal)
                meals.removeAll { $0 === meal }
            } else if let recipe = recipeNamed(name) {
                context.delete(recipe)
                recipes.removeAll { $0 === recipe }
            } else if let gathering = gatheringNamed(name) {
                context.delete(gathering)
                gatherings.removeAll { $0 === gathering }
            } else if let line = lines.first(where: { $0.shareRecordName == name }) {
                context.delete(line)
                lines.removeAll { $0 === line }
            }
        }
        if !changes.deleted.isEmpty {
            var book = unresolved
            for name in changes.deleted { book[name] = nil }
            // A parked reference whose target has been deleted is not going
            // to resolve, and `remote(from:)` reads the book, so leaving it
            // would rewrite a dead recipe name onto the wire on every push.
            for (mealName, refs) in book {
                let kept = refs.filter { !changes.deleted.contains($0.value) }
                if kept.count != refs.count { book[mealName] = kept.isEmpty ? nil : kept }
            }
            unresolved = book
        }

        if let root = changes.root {
            applyRoot(root, in: context)
        }

        // Seats first: meals name their cook.
        let removed = Set(cachedRemovedIDs)
        let hosting: Bool = { if case .hosting = membership { return true }; return false }()
        for s in changes.seats where !s.recordName.isEmpty {
            guard !pending(s.recordName) else { continue }
            // A removed identity is never seated again (§8). Their share
            // access is gone, but a write already in flight when the host
            // removed them can still land, and the host is the one who can
            // take the record back off the zone.
            if hosting, let id = s.userRecordName, !id.isEmpty, removed.contains(id) {
                HouseholdOutbox.shared.enqueueDelete(.seat, s.recordName)
                print("PLATED HOUSEHOLD: a removed identity wrote a seat, deleting \(s.recordName)")
                continue
            }
            var member = memberNamed(s.recordName)
            if member == nil, let twin = members.first(where: {
                $0.shareRecordName.isEmpty && $0.name == s.name && !s.name.isEmpty
            }) {
                twin.shareRecordName = s.recordName
                member = twin
                print("PLATED HOUSEHOLD: adopted seat name \(s.recordName) onto \(twin.name)")
            }
            if let member {
                guard member.shareModifiedAt != s.modifiedAt else { continue }
                let was = member.seat
                applySeat(s, onto: member, isNew: false, me: me, claimedSeat: claimedSeat,
                          ownerRecordName: ownerRecordName)
                member.shareFingerprint = stamp(member)
                let isMine = member.isMe || member.shareRecordName == claimedSeat
                if member.seat == .joined, was != .joined, !isMine { outcome.newSeats.append(member) }
                if member.seat == .left, was != .left, !isMine { outcome.leftSeats.append(member) }
            } else {
                // A seat arriving `left` is history: the host deletes it
                // from the roster (§8), so a phone joining afterwards must
                // not seed it as a live "Left" row. My own seat is the
                // exception, because a leave pushed from another device is
                // how this phone learns it is out.
                let mine = (s.userRecordName.map { !$0.isEmpty && $0 == me } ?? false)
                    || s.recordName == claimedSeat
                if !mine, HouseholdMember.Seat(rawValue: s.seat) == .left { continue }
                let member = HouseholdMember(shareRecordName: s.recordName)
                context.insert(member)
                applySeat(s, onto: member, isNew: true, me: me, claimedSeat: claimedSeat,
                          ownerRecordName: ownerRecordName)
                member.shareFingerprint = stamp(member)
                members.append(member)
                let isMine = member.isMe || member.shareRecordName == claimedSeat
                if member.seat == .joined, !isMine { outcome.newSeats.append(member) }
            }
        }

        // Recipes before meals, so a meal can find its recipe.
        for r in changes.recipes where !r.recordName.isEmpty {
            guard !pending(r.recordName) else { continue }
            var recipe = recipeNamed(r.recordName)
            if recipe == nil, let twin = recipes.first(where: {
                $0.shareRecordName.isEmpty && $0.title == r.title
                    && abs($0.createdAt.timeIntervalSince(r.createdAt)) < 2
            }) {
                twin.shareRecordName = r.recordName
                recipe = twin
                print("PLATED HOUSEHOLD: adopted recipe name \(r.recordName) onto \(twin.title)")
            }
            if let recipe {
                guard recipe.shareModifiedAt != r.modifiedAt else { continue }
                applyRecipe(r, onto: recipe, in: context)
                recipe.shareFingerprint = stamp(recipe)
            } else {
                let recipe = Recipe()
                recipe.shareRecordName = r.recordName
                context.insert(recipe)
                applyRecipe(r, onto: recipe, in: context)
                recipe.shareFingerprint = stamp(recipe)
                recipes.append(recipe)
                if r.modifiedBy != me { outcome.newRecipes.append(recipe) }
            }
        }

        for g in changes.gatherings where !g.recordName.isEmpty {
            guard !pending(g.recordName) else { continue }
            var gathering = gatheringNamed(g.recordName)
            if gathering == nil, let twin = gatherings.first(where: {
                $0.shareRecordName.isEmpty && $0.title == g.title
                    && abs($0.startDate.timeIntervalSince(g.startDate)) < 1
            }) {
                twin.shareRecordName = g.recordName
                gathering = twin
            }
            if let gathering {
                guard gathering.shareModifiedAt != g.modifiedAt else { continue }
                applyGathering(g, onto: gathering)
                gathering.shareFingerprint = stamp(gathering)
            } else {
                let gathering = Gathering()
                gathering.shareRecordName = g.recordName
                context.insert(gathering)
                applyGathering(g, onto: gathering)
                gathering.shareFingerprint = stamp(gathering)
                gatherings.append(gathering)
            }
        }

        var book = unresolved
        // (day, slot) rivals hand their purchases to the winner, but that
        // rewrite stamps `now` and `me`, so it is held until this delta's
        // own marks have been folded. Otherwise the fold, not the person,
        // becomes the newest fact about the line and a remote uncheck
        // arriving in the same delta is thrown away.
        var foldsPending: [(from: String, to: String)] = []
        for m in changes.meals where !m.recordName.isEmpty {
            guard !pending(m.recordName) else { continue }
            let day = Wire.date(fromDay: m.day)
            var meal = mealNamed(m.recordName)
            if meal == nil, let day, let twin = meals.first(where: {
                $0.shareRecordName.isEmpty && $0.date == day && $0.slot == m.slot
                    && abs($0.createdAt.timeIntervalSince(m.createdAt)) < 2
            }) {
                twin.shareRecordName = m.recordName
                meal = twin
                print("PLATED HOUSEHOLD: adopted meal name \(m.recordName) onto \(twin.title)")
            }
            let target: PlannedMeal
            if let meal {
                guard meal.shareModifiedAt != m.modifiedAt else { continue }
                target = meal
            } else {
                let fresh = PlannedMeal(date: day ?? .now)
                fresh.shareRecordName = m.recordName
                context.insert(fresh)
                meals.append(fresh)
                target = fresh
                if m.modifiedBy != me { outcome.newMeals.append(fresh) }
            }
            applyMeal(m, onto: target, day: day)
            var missing: [String: String] = [:]
            if !m.recipeRecordName.isEmpty {
                target.recipe = recipeNamed(m.recipeRecordName)
                if target.recipe == nil { missing["recipe"] = m.recipeRecordName }
            } else {
                target.recipe = nil
            }
            if !m.cookRecordName.isEmpty {
                target.cook = memberNamed(m.cookRecordName)
                if target.cook == nil { missing["cook"] = m.cookRecordName }
            } else {
                target.cook = nil
            }
            if !m.gatheringRecordName.isEmpty {
                target.gathering = gatheringNamed(m.gatheringRecordName)
                if target.gathering == nil { missing["gathering"] = m.gatheringRecordName }
            } else {
                target.gathering = nil
            }
            book[m.recordName] = missing.isEmpty ? nil : missing
            target.shareFingerprint = stamp(target)

            // One dinner per (day, slot): the lexically smaller name survives
            // on every phone, so two members who planned the same night at
            // once converge without talking. The loser's purchases move to
            // the winner's mark so nothing bought is forgotten.
            let rivals = meals.filter {
                $0 !== target && !$0.shareRecordName.isEmpty
                    && $0.date == target.date && $0.slot == target.slot
            }
            for rival in rivals {
                let loser = rival.shareRecordName < target.shareRecordName ? target : rival
                let winner = loser === target ? rival : target
                if let from = loser.shoppingID, let to = winner.shoppingID {
                    foldsPending.append((from, to))
                }
                print("PLATED HOUSEHOLD: one dinner per night, \(loser.shareRecordName) yields to \(winner.shareRecordName)")
                HouseholdOutbox.shared.enqueueDelete(.meal, loser.shareRecordName)
                context.delete(loser)
                meals.removeAll { $0 === loser }
                book[loser.shareRecordName] = nil
                if loser === target { break }
            }
        }

        for l in changes.lines where !l.recordName.isEmpty {
            guard !pending(l.recordName) else { continue }
            if let line = lines.first(where: { $0.shareRecordName == l.recordName }) {
                guard line.shareModifiedAt != l.modifiedAt else { continue }
                applyLine(l, onto: line)
                line.shareFingerprint = stamp(line)
            } else {
                let line = GroceryItem(isManual: true)
                line.shareRecordName = l.recordName
                context.insert(line)
                applyLine(l, onto: line)
                line.shareFingerprint = stamp(line)
                lines.append(line)
            }
        }

        for m in changes.marks where !m.lineKey.isEmpty {
            guard !pending(m.recordName) else { continue }
            GroceryMarks.shared.fold(
                GroceryMarks.Mark(lineKey: m.lineKey, purchases: m.purchases,
                                  dismissedUntil: m.dismissedUntil, at: m.at, by: m.by),
                into: context
            )
        }

        for fold in foldsPending { foldPurchases(from: fold.from, into: fold.to) }

        // Repair, regardless of modifiedAt: a recipe arriving after its meal
        // is the ordinary case on a fresh join, where the zone is read in
        // whatever order the pages come.
        for (mealName, refs) in book {
            guard let meal = mealNamed(mealName) else { book[mealName] = nil; continue }
            var remaining = refs
            if let name = refs["recipe"], meal.recipe == nil, let recipe = recipeNamed(name) {
                meal.recipe = recipe
                remaining["recipe"] = nil
            }
            if let name = refs["cook"], meal.cook == nil, let cook = memberNamed(name) {
                meal.cook = cook
                remaining["cook"] = nil
            }
            if let name = refs["gathering"], meal.gathering == nil, let gathering = gatheringNamed(name) {
                meal.gathering = gathering
                remaining["gathering"] = nil
            }
            if remaining != refs { meal.shareFingerprint = stamp(meal) }
            book[mealName] = remaining.isEmpty ? nil : remaining
        }
        unresolved = book

        Persist.save(context, "household merge")
        return outcome
    }

    // MARK: Field rules (§3.1 to §3.6)

    private static func rank(_ seat: HouseholdMember.Seat) -> Int {
        switch seat {
        case .notOnPlated: return 0
        case .invited: return 1
        case .joined, .head: return 2
        case .left: return 3
        }
    }

    @MainActor
    private static func applySeat(
        _ s: RemoteSeat, onto member: HouseholdMember, isNew: Bool,
        me: String, claimedSeat: String?, ownerRecordName: String
    ) {
        // Identity is set once. A seat already carrying somebody else's
        // identity keeps it, whatever the wire says.
        if (member.userRecordName ?? "").isEmpty, let id = s.userRecordName, !id.isEmpty {
            member.userRecordName = id
        }
        let isOwnerSeat = !ownerRecordName.isEmpty && member.userRecordName == ownerRecordName
        let isMine = !isNew && (member.isMe || member.shareRecordName == claimedSeat)

        // Forward only, and head only on the owner's seat.
        var incoming = HouseholdMember.Seat(rawValue: s.seat) ?? .notOnPlated
        if incoming == .head, !isOwnerSeat { incoming = .joined }
        if isNew {
            member.seat = incoming
        } else if incoming == .head {
            if member.seat != .left { member.seat = .head }
        } else if rank(incoming) > rank(member.seat) || (member.seat == .head && incoming == .left) {
            member.seat = incoming
        }

        // Owner only on the owner's seat; anybody else arriving as owner is
        // a partner. The zone has exactly one head and it is the host's.
        member.role = (s.role == "owner" && !isOwnerSeat) ? "partner" : s.role
        member.roleLine = s.roleLine
        member.colorHex = s.colorHex
        member.dietaryNotes = s.dietaryNotes
        member.avoidedIngredients = s.avoidedIngredients
        member.cookWeekdays = s.cookWeekdays
        member.isPrimaryCook = s.isPrimaryCook

        // Never cleared once set.
        if member.invitedAt == nil { member.invitedAt = s.invitedAt }
        if member.joinedAt == nil { member.joinedAt = s.joinedAt }
        if member.leftAt == nil { member.leftAt = s.leftAt }
        if (member.participantID ?? "").isEmpty, let id = s.participantID, !id.isEmpty {
            member.participantID = id
        }

        // Name, bio and photo belong to the person the seat is: the wire
        // never overwrites them on my own seat. phoneE164 and inviteEmail
        // never travel and are never touched here.
        if !isMine {
            member.name = s.name
            member.bio = s.bio
            member.photoData = s.photo
        }
        if member.authorID.isEmpty { member.authorID = s.authorID }
        member.shareModifiedAt = s.modifiedAt
    }

    @MainActor
    private static func applyMeal(_ m: RemoteMeal, onto meal: PlannedMeal, day: Date?) {
        if let day { meal.date = day }
        meal.slot = m.slot
        meal.customTitle = m.customTitle
        meal.titleFallback = m.titleSnapshot
        meal.notes = m.notes
        meal.servings = m.servings
        meal.cookedAt = m.cookedAt
        meal.cookReaction = m.cookReaction
        meal.actualMinutes = m.actualMinutes
        meal.createdAt = m.createdAt
        // A wire shoppingID always wins and is never cleared.
        if let id = m.shoppingID, !id.isEmpty { meal.shoppingID = id }
        meal.tagline = m.tagline
        if meal.authorID.isEmpty { meal.authorID = m.authorID }
        meal.shareModifiedAt = m.modifiedAt
    }

    @MainActor
    private static func applyRecipe(_ r: RemoteRecipe, onto recipe: Recipe, in context: ModelContext) {
        recipe.title = r.title
        recipe.summary = r.summary
        recipe.instructions = r.instructions
        recipe.sourceURL = r.sourceURL
        recipe.sourceName = r.sourceName
        recipe.sourceText = r.sourceText
        recipe.importMethod = r.importMethod
        recipe.importedAt = r.importedAt
        recipe.servings = r.servings
        recipe.prepMinutes = r.prepMinutes
        recipe.cookMinutes = r.cookMinutes
        recipe.tags = r.tags
        recipe.category = r.category
        recipe.difficulty = r.difficulty
        recipe.mealType = r.mealType
        recipe.steps = r.steps
        recipe.visibility = r.visibility
        recipe.householdCanEdit = r.householdCanEdit
        recipe.originID = r.originID
        recipe.createdAt = r.createdAt
        recipe.cookNotes = r.cookNotes
        recipe.weatherMoods = r.weatherMoods
        // isFavorite and isPinned are per person and never travel.

        // Ingredients are one write unit with the recipe: the editor rebuilds
        // them wholesale on every save, and so does the merge.
        for old in recipe.ingredients ?? [] { context.delete(old) }
        recipe.ingredients = []
        for (index, w) in r.ingredients.sorted(by: { $0.sortIndex < $1.sortIndex }).enumerated() {
            let ingredient = Ingredient(
                name: w.name, quantity: w.quantity, unit: w.unit,
                aisle: GroceryAisle(rawValue: w.aisle) ?? .other,
                isPantryStaple: w.isPantryStaple, sortIndex: index
            )
            ingredient.recipe = recipe
            context.insert(ingredient)
        }

        // Photographs only when they changed: the hash is what makes a
        // title edit cheap in both directions.
        if r.photoHash != recipe.sharePhotoHash {
            recipe.photoData = r.photoData
            for old in recipe.extraPhotos ?? [] { context.delete(old) }
            recipe.extraPhotos = []
            for (index, data) in r.extraPhotos.enumerated() {
                let photo = RecipePhoto(photoData: data, sortIndex: index)
                photo.recipe = recipe
                context.insert(photo)
            }
            recipe.sharePhotoHash = r.photoHash
        }
        if recipe.authorID.isEmpty { recipe.authorID = r.authorID }
        recipe.shareModifiedAt = r.modifiedAt
    }

    @MainActor
    private static func applyGathering(_ g: RemoteGathering, onto gathering: Gathering) {
        gathering.title = g.title
        gathering.notes = g.notes
        gathering.startDate = g.startDate
        gathering.endDate = g.endDate
        gathering.guestCount = g.guestCount
        gathering.location = g.location
        // calendarEventID is this device's and never travels.
        if gathering.authorID.isEmpty { gathering.authorID = g.authorID }
        gathering.shareModifiedAt = g.modifiedAt
    }

    @MainActor
    private static func applyLine(_ l: RemoteLine, onto line: GroceryItem) {
        line.name = l.name
        line.quantity = l.quantity
        line.unit = l.unit
        line.aisle = l.aisle
        if let day = Wire.date(fromDay: l.day) { line.weekStart = day }
        line.originTitle = l.originTitle
        line.isChecked = l.isChecked
        line.isManual = true
        if line.authorID.isEmpty { line.authorID = l.authorID }
        line.shareModifiedAt = l.modifiedAt
    }

    @MainActor
    private static func applyRoot(_ root: RemoteRoot, in context: ModelContext) {
        let defaults = groupDefaults
        defaults.set(root.name, forKey: Keys.name)
        defaults.set(root.name, forKey: Keys.lastSyncedName)
        if !root.hostName.isEmpty { defaults.set(root.hostName, forKey: Keys.ownerName) }
        if let published = root.publishedAt {
            defaults.set(published, forKey: Keys.publishedAt)
        } else if membership != .hosting {
            // The host writes this field, so a nil arriving on the host's own
            // phone is only an older push of its own coming back around. On a
            // member's phone the wire is the authority, and a cleared value
            // means the host has not finished publishing.
            defaults.removeObject(forKey: Keys.publishedAt)
        }
        if let data = try? JSONEncoder().encode(root.removedIDs) { defaults.set(data, forKey: Keys.removedIDs) }
        if let url = root.tableShareURL { defaults.set(url.absoluteString, forKey: Keys.tableShareURL) }
        defaults.set(root.autoRotate, forKey: Keys.autoRotate)

        // The typed name, only when it changed: every write here is a save
        // the settings field would otherwise see as an edit.
        let current = UserDefaults.standard.string(forKey: "householdName") ?? ""
        if current != root.name {
            UserDefaults.standard.set(root.name, forKey: "householdName")
        }

        let profiles = (try? context.fetch(FetchDescriptor<HouseholdProfile>())) ?? []
        let profile: HouseholdProfile
        if let first = profiles.sorted(by: { $0.createdAt < $1.createdAt }).first {
            profile = first
        } else {
            profile = HouseholdProfile()
            context.insert(profile)
        }
        if profile.bannerPhotoData != root.banner {
            profile.bannerPhotoData = root.banner
        }
        profile.shareModifiedAt = root.modifiedAt
        print("PLATED HOUSEHOLD: root applied, name \"\(root.name)\", host \(root.hostName), published \(root.publishedAt.map { "\($0)" } ?? "not yet")")
    }

    /// The loser's purchases go onto the winner's shoppingID in every mark
    /// that carried them, so a check-off made against the night that lost
    /// is not lost with it. Takes the two shopping ids rather than the rows
    /// because it runs after the merge's own marks have been folded, by
    /// which time the losing row is already deleted.
    @MainActor
    private static func foldPurchases(from: String, into to: String) {
        guard !from.isEmpty, !to.isEmpty, from != to else { return }
        for mark in GroceryMarks.shared.all where mark.purchases[from] != nil {
            var purchases = mark.purchases
            let moved = purchases.removeValue(forKey: from) ?? 0
            purchases[to] = max(purchases[to] ?? 0, moved)
            GroceryMarks.shared.rewrite(lineKey: mark.lineKey, purchases: purchases)
        }
    }

    /// The root as this phone knows it, for a push of the root entry.
    @MainActor
    static func localRoot(in context: ModelContext) -> RemoteRoot {
        var root = RemoteRoot()
        let members = (try? context.fetch(FetchDescriptor<HouseholdMember>())) ?? []
        let host = members.first(where: \.isOwner)
        // The RESOLVED name, not the typed one (§3.6). A member reading an
        // empty field falls back to their own Apple family name, so a host
        // who never typed one had every member's Home saying the reader's
        // surname over the host's household.
        root.name = HouseholdIdentity.familyName(
            typed: UserDefaults.standard.string(forKey: "householdName") ?? "",
            appleFamilyName: UserDefaults.standard.string(forKey: "userFamilyName") ?? "",
            ownerName: host?.name ?? cachedOwnerName
        )
        root.hostName = host?.name ?? cachedOwnerName
        root.hostPhoto = host?.photoData
        let profiles = (try? context.fetch(FetchDescriptor<HouseholdProfile>())) ?? []
        root.banner = profiles.sorted(by: { $0.createdAt < $1.createdAt }).first?.bannerPhotoData
        root.tableShareURL = cachedTableShareURL
        root.autoRotate = UserDefaults.standard.object(forKey: "autoRotateOpenNights") as? Bool ?? true
        root.publishedAt = cachedPublishedAt
        root.removedIDs = cachedRemovedIDs
        root.modifiedAt = .now
        return root
    }

    #if PLATED_CLOUDKIT
    private static var container: CKContainer { .default() }

    /// The database and zone this phone's household lives in: my own zone
    /// in the private database when I host, the owner's in the shared
    /// database when I am a member. Nil when there is no household to
    /// reach, or when the question could not be asked.
    static func householdZone() async -> (CKDatabase, CKRecordZone.ID)? {
        switch membership {
        case .member(let owner):
            let id = CKRecordZone.ID(zoneName: zoneName, ownerName: owner)
            do {
                _ = try await container.sharedCloudDatabase.recordZone(for: id)
                return (container.sharedCloudDatabase, id)
            } catch {
                print("PLATED HOUSEHOLD: could not reach \(owner)'s zone: \(error.localizedDescription)")
                return nil
            }
        case .hosting, .solo:
            let id = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
            do {
                _ = try await container.privateCloudDatabase.recordZone(for: id)
                return (container.privateCloudDatabase, id)
            } catch {
                return nil
            }
        }
    }

    // MARK: Membership from CloudKit

    /// Ask CloudKit which household this phone is in. The cache is
    /// overwritten only when the account is available and the listing
    /// succeeded: a failed listing says nothing, and reading it as "solo"
    /// is how a flaky network would make a member's phone forget its
    /// household.
    static func refreshMembership() async -> Membership {
        let cached = membership
        guard await TableSync.accountState() == .available else { return cached }
        let mine = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let privateDB = container.privateCloudDatabase
        var hosting = false
        do {
            _ = try await privateDB.recordZone(for: mine)
            let root = try await privateDB.record(for: CKRecord.ID(recordName: rootRecordName, zoneID: mine))
            hosting = root.share != nil
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            hosting = false
        } catch {
            print("PLATED HOUSEHOLD: membership check could not read the private zone: \(error.localizedDescription)")
            return cached
        }
        var joined: CKRecordZone.ID?
        do {
            let zones = try await container.sharedCloudDatabase.allRecordZones()
            joined = zones.first { $0.zoneID.zoneName == zoneName }?.zoneID
        } catch {
            print("PLATED HOUSEHOLD: membership check could not list the shared database: \(error.localizedDescription)")
            return cached
        }
        let found: Membership
        if let joined, cached.owner != nil || !hosting {
            // Both a shared household zone and a private root with a share
            // can exist at once: `abandonHosting` deletes the old zone best
            // effort, so a joiner's leftover would otherwise flip their
            // second device back to hosting. A cached member stays a member.
            found = .member(owner: joined.ownerName)
        } else if hosting {
            found = .hosting
        } else {
            found = .solo
        }
        // Promotion only (§8). Being removed is noticed on positive evidence:
        // a listing that succeeded but happens not to name the zone is not
        // that. `fetchChanges` sees the zone gone and `handleRemoved` does
        // the work; demoting here would skip every step of it, leaving the
        // outbox, the marks, the roster and the removed notice behind.
        if cached.owner != nil, found.owner == nil {
            print("PLATED HOUSEHOLD: no household zone listed, keeping the cached membership")
            return cached
        }
        if found != cached { setMembership(found) }
        return found
    }

    // MARK: The host's share

    /// The invitation link, minting the zone, the root and the share the
    /// first time. The Table share is minted first so its URL rides on the
    /// root and a joiner accepts both in one motion.
    static func invitationURL(hostName: String) async -> URL? {
        guard await TableSync.accountAvailable() else { return nil }
        if case .member = membership {
            print("PLATED HOUSEHOLD: a member does not mint a household link")
            return nil
        }
        let tableURL = await TableShare.invitationURL(hostName: hostName)
        do {
            let db = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
            _ = try? await db.save(CKRecordZone(zoneID: zoneID))

            let rootID = CKRecord.ID(recordName: rootRecordName, zoneID: zoneID)
            let root: CKRecord
            if let existing = try? await db.record(for: rootID) {
                root = existing
            } else {
                root = CKRecord(recordType: rootType, recordID: rootID)
                Wire.set(root, "name", HouseholdIdentity.familyName(
                    typed: UserDefaults.standard.string(forKey: "householdName") ?? "",
                    appleFamilyName: UserDefaults.standard.string(forKey: "userFamilyName") ?? "",
                    ownerName: hostName
                ))
                Wire.set(root, "autoRotateOpenNights", 1)
                Wire.set(root, "modifiedAt", Date.now)
            }
            Wire.set(root, "hostName", hostName)
            if let tableURL {
                Wire.set(root, "tableShareURL", tableURL.absoluteString)
                groupDefaults.set(tableURL.absoluteString, forKey: Keys.tableShareURL)
            }
            let title: String = hostName.isEmpty ? "Our household on Plated" : "\(hostName)'s household on Plated"

            // An existing share is reused: minting a second one would
            // silently invalidate the link already in somebody's messages.
            if let ref = root.share,
               let existing = try? await db.record(for: ref.recordID) as? CKShare,
               let url = existing.url {
                _ = try? await db.modifyRecords(saving: [root], deleting: [])
                setMembership(.hosting)
                print("PLATED HOUSEHOLD: reused the household share")
                return url
            }

            let share = CKShare(rootRecord: root)
            share[CKShare.SystemFieldKey.title] = title as CKRecordValue
            if let icon = TableShare.shareThumbnail() {
                share[CKShare.SystemFieldKey.thumbnailImageData] = icon as CKRecordValue
            }
            // The link is the credential (§1). No participant is ever added
            // to this share: a lookup by phone finds almost nobody, and
            // `addParticipant` on a public share raises an exception that
            // `try?` cannot catch.
            share.publicPermission = .readWrite

            // The URL is server-assigned and exists only on the record that
            // comes back.
            let saved = try await db.modifyRecords(saving: [root, share], deleting: [])
            for (_, result) in saved.saveResults {
                if case .success(let record) = result, let share = record as? CKShare, let url = share.url {
                    setMembership(.hosting)
                    print("PLATED HOUSEHOLD: minted the household share")
                    return url
                }
            }
            print("PLATED HOUSEHOLD: share saved but no URL came back")
            return nil
        } catch {
            print("PLATED HOUSEHOLD: could not mint the household share: \(error)")
            return nil
        }
    }

    /// The household's share: off my private root when I host, off the
    /// owner's root in the shared database when I am a member.
    private static func currentShare() async -> (CKDatabase, CKShare)? {
        guard let (db, zoneID) = await householdZone() else { return nil }
        guard let root = try? await db.record(for: CKRecord.ID(recordName: rootRecordName, zoneID: zoneID)),
              let ref = root.share,
              let share = try? await db.record(for: ref.recordID) as? CKShare else { return nil }
        return (db, share)
    }

    /// Everyone on the household share. Link joiners are public
    /// participants with no phone or email; identity is the only key.
    static func standings() async -> [TableShare.Standing] {
        guard await TableSync.accountAvailable() else { return [] }
        guard let (_, share) = await currentShare() else { return [] }
        return share.participants.compactMap { p in
            guard p.role != .owner else { return nil }
            let name = [p.userIdentity.nameComponents?.givenName,
                        p.userIdentity.nameComponents?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            return TableShare.Standing(
                phone: p.userIdentity.lookupInfo?.phoneNumber,
                email: p.userIdentity.lookupInfo?.emailAddress,
                name: name,
                accepted: p.acceptanceStatus == .accepted,
                participantID: p.userIdentity.userRecordID?.recordName
            )
        }
    }

    /// Take one person off the household share, matched by identity. False
    /// on any refusal, and the caller says so. `publicPermission` is never
    /// written: setting it to `.none` on a share with participants evicts
    /// everyone.
    ///
    /// A participant who is not on a share this call could read is answered
    /// true: they deleted the app or dropped the zone before their `left`
    /// push arrived, so what was asked for already holds. Answering false
    /// there put "Couldn't remove Riley. Check your connection and try
    /// again." on a screen where the connection was fine and the row could
    /// never be removed at all.
    static func removeParticipant(userRecordName: String) async -> Bool {
        guard !userRecordName.isEmpty, await TableSync.accountAvailable() else { return false }
        guard case .hosting = membership else { return false }
        guard let (db, share) = await currentShare() else {
            print("PLATED HOUSEHOLD: could not read the household share to remove \(userRecordName)")
            return false
        }
        guard let victim = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == userRecordName
        }) else {
            print("PLATED HOUSEHOLD: \(userRecordName) is not on the household share, nothing to remove")
            return true
        }
        guard victim.role != .owner else {
            print("PLATED HOUSEHOLD: the owner is not removed from their own household share")
            return false
        }
        share.removeParticipant(victim)
        do {
            _ = try await db.modifyRecords(saving: [share], deleting: [])
            print("PLATED HOUSEHOLD: removed participant \(userRecordName)")
            return true
        } catch {
            print("PLATED HOUSEHOLD: could not remove participant: \(error)")
            return false
        }
    }

    /// A member leaves: their copy of the zone goes from the shared
    /// database, and only that zone's token is forgotten.
    static func leave() async -> Bool {
        guard case .member(let owner) = membership else { return false }
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: owner)
        do {
            _ = try await container.sharedCloudDatabase.deleteRecordZone(withID: zoneID)
            TableShare.forgetToken(for: zoneID)
            print("PLATED HOUSEHOLD: left \(owner)'s household zone")
            return true
        } catch let error as CKError where error.code == .zoneNotFound {
            TableShare.forgetToken(for: zoneID)
            print("PLATED HOUSEHOLD: \(owner)'s household zone was already gone")
            return true
        } catch {
            print("PLATED HOUSEHOLD: could not leave: \(error)")
            return false
        }
    }

    static func accept(_ metadata: CKShare.Metadata) async -> Bool {
        do {
            _ = try await container.accept(metadata)
            print("PLATED HOUSEHOLD: accepted the household share")
            return true
        } catch {
            print("PLATED HOUSEHOLD: could not accept the household share: \(error)")
            return false
        }
    }

    // MARK: Pull

    /// What the household zones said since we last asked: my own zone when
    /// it exists, the owner's when I am a member. Zone changes, paged until
    /// the server says there is no more, with the token stored per zone.
    static func fetchChanges() async -> Changes {
        guard await TableSync.accountAvailable() else {
            var refused = Changes()
            refused.failed = true
            return refused
        }
        var all = Changes()
        // A member does not read a private household zone. The one this
        // phone might still own is the leftover of a household it left or
        // abandoned, and merging it is how a Leave whose zone delete failed
        // resurrects the household on the next pull. `refreshMembership`
        // runs before this on every pass, so the cache no longer lags a
        // join and nothing needs the old catch-all.
        if membership.owner == nil {
            let mine = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
            if (try? await container.privateCloudDatabase.recordZone(for: mine)) != nil {
                var part = await zoneChanges(in: container.privateCloudDatabase, zoneID: mine, isShared: false)
                part.stampPlan(owner: TableShare.canonicalOwner(mine, isPrivate: true))
                all.absorb(part)
            }
        }
        if case .member(let owner) = membership {
            let theirs = CKRecordZone.ID(zoneName: zoneName, ownerName: owner)
            if await sharedDatabaseReportsDeleted(theirs) {
                all.zoneGone = true
                print("PLATED HOUSEHOLD: the shared database reports \(owner)'s zone deleted")
            } else {
                var part = await zoneChanges(in: container.sharedCloudDatabase, zoneID: theirs, isShared: true)
                part.stampPlan(owner: TableShare.canonicalOwner(theirs, isPrivate: false))
                all.absorb(part)
            }
        }
        return all
    }

    private static func zoneChanges(in db: CKDatabase, zoneID: CKRecordZone.ID, isShared: Bool) async -> Changes {
        var found = Changes()
        do {
            var cursor = TableShare.token(for: zoneID)
            if cursor == nil { found.replayed = true }
            var more = true
            while more {
                let changes = try await db.recordZoneChanges(inZoneWith: zoneID, since: cursor)
                for (_, result) in changes.modificationResultsByID {
                    guard let record = try? result.get().record else { continue }
                    found.add(record)
                }
                for deleted in changes.deletions {
                    found.deleted.insert(deleted.recordID.recordName)
                }
                cursor = changes.changeToken
                more = changes.moreComing
            }
            TableShare.store(cursor, for: zoneID)
            print("PLATED HOUSEHOLD: read \(isShared ? zoneID.ownerName + "'s" : "my") zone: \(found.seats.count) seats, \(found.meals.count) meals, \(found.recipes.count) recipes, \(found.gatherings.count) gatherings, \(found.lines.count) lines, \(found.marks.count) marks, \(found.deleted.count) deleted\(found.root != nil ? ", root" : "")\(found.replayed ? ", replayed" : "")")
        } catch let error as CKError where error.code == .zoneNotFound {
            // Positive evidence only (§8): the account must be available and
            // a direct look at the zone must also say it is not there.
            guard isShared, await TableSync.accountState() == .available else {
                print("PLATED HOUSEHOLD: zone not found, but could not confirm")
                found.failed = true
                return found
            }
            do {
                _ = try await db.recordZone(for: zoneID)
                print("PLATED HOUSEHOLD: zone changes said not found but the zone is there; nothing changed")
            } catch let again as CKError where again.code == .zoneNotFound {
                found.zoneGone = true
                TableShare.forgetToken(for: zoneID)
                print("PLATED HOUSEHOLD: \(zoneID.ownerName)'s zone is gone from the shared database")
            } catch {
                print("PLATED HOUSEHOLD: zone not found, but the second look failed: \(error.localizedDescription)")
                found.failed = true
            }
        } catch let error as CKError where error.code == .changeTokenExpired {
            // The one error that means the cursor itself is bad. Forget this
            // zone's and the next pull re-reads it whole; every other token
            // survives.
            TableShare.forgetToken(for: zoneID)
            print("PLATED HOUSEHOLD: change token expired, the next pull re-reads the zone")
        } catch {
            // Everything else keeps the token. A network blip on a later page
            // of a zone that carries every photograph would otherwise
            // re-download the whole household, and the replay it forces makes
            // `TableNews.digest` return nothing, so a night somebody planned
            // while you were offline lands silently and never rings the bell.
            // What was read before the failure is returned and merged; the
            // cursor is not stored, so the next pull picks up where the last
            // stored one left off.
            print("PLATED HOUSEHOLD: zone read failed, token kept: \(error.localizedDescription)")
            found.failed = true
        }
        return found
    }

    /// The other road to "removed": a database-changes fetch on the shared
    /// database that lists our zone among the deleted or purged. With no
    /// stored token the server reports nothing deleted, so the first run
    /// only stores a token.
    private static func sharedDatabaseReportsDeleted(_ zoneID: CKRecordZone.ID) async -> Bool {
        let db = container.sharedCloudDatabase
        let previous = groupDefaults.data(forKey: Keys.sharedDatabaseToken).flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
        guard previous != nil else {
            // Nothing to compare against yet; take a token and answer next time.
            _ = await fetchSharedDatabaseChanges(db, since: nil)
            return false
        }
        return await fetchSharedDatabaseChanges(db, since: previous).contains(zoneID)
    }

    private static func fetchSharedDatabaseChanges(_ db: CKDatabase, since token: CKServerChangeToken?) async -> Set<CKRecordZone.ID> {
        await withCheckedContinuation { continuation in
            let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: token)
            operation.fetchAllChanges = true
            var gone: Set<CKRecordZone.ID> = []
            operation.recordZoneWithIDWasDeletedBlock = { gone.insert($0) }
            operation.recordZoneWithIDWasPurgedBlock = { gone.insert($0) }
            operation.fetchDatabaseChangesResultBlock = { result in
                switch result {
                case .success(let (token, _)):
                    if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                        groupDefaults.set(data, forKey: Keys.sharedDatabaseToken)
                    }
                    continuation.resume(returning: gone)
                case .failure(let error):
                    if let ck = error as? CKError, ck.code == .changeTokenExpired {
                        groupDefaults.removeObject(forKey: Keys.sharedDatabaseToken)
                    }
                    print("PLATED HOUSEHOLD: shared database changes failed: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                }
            }
            db.add(operation)
        }
    }

    // MARK: Push

    /// One row on its way to the zone, with what the push needs to know
    /// about it and what to do with the answer.
    private struct Candidate {
        var entry: HouseholdOutbox.Entry
        var shareModifiedAt: Date?
        /// A mark has no row: its own `at` is the version it carries.
        var markAt: Date?
        /// A recipe's local photo hash; nil for every other kind.
        var photoHash: String?
        var write: @MainActor (CKRecord, _ includingPhotos: Bool) -> Void
        var saved: @MainActor (Date) -> Void
        var gone: @MainActor () -> Void
        var applyRemote: @MainActor (CKRecord) -> Void
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let ck = error as? CKError else {
            return (error as NSError).domain == NSURLErrorDomain
        }
        if ck.retryAfterSeconds != nil { return true }
        switch ck.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return true
        case .limitExceeded:
            // The request was too big, not wrong (§6). The next attempt sends
            // it in smaller batches; counting it as a refusal would spend a
            // try and drop the record after twenty of them, which is how a
            // whole cookbook would stop publishing with nothing on screen
            // saying so.
            return true
        default:
            return false
        }
    }

    /// When CloudKit last said "not before this". §6: the drain honours
    /// `CKError.retryAfterSeconds`, and a push that keeps sending inside that
    /// window is what earns the next one. In the app group rather than in
    /// memory so a relaunch inside the window does not forget it.
    private static var rateLimitedUntil: Date? {
        get { groupDefaults.object(forKey: "plated.household.rateLimitedUntil") as? Date }
        set {
            if let newValue { groupDefaults.set(newValue, forKey: "plated.household.rateLimitedUntil") }
            else { groupDefaults.removeObject(forKey: "plated.household.rateLimitedUntil") }
        }
    }

    /// Whether a push would be refused on sight right now. The drain asks
    /// before it starts so it can stop rather than walk every kind to be
    /// told `.retry` seven times over (§6).
    static var isRateLimited: Bool {
        guard let until = rateLimitedUntil else { return false }
        return until > .now
    }

    private static func noteRateLimit(_ error: Error) {
        guard let ck = error as? CKError, let seconds = ck.retryAfterSeconds, seconds > 0 else { return }
        // Capped: an unreasonable answer, or a clock that moved, must not be
        // able to wedge the queue shut for the life of the install.
        let until = Date.now.addingTimeInterval(min(seconds, 600))
        guard (rateLimitedUntil ?? .distantPast) < until else { return }
        rateLimitedUntil = until
        print("PLATED HOUSEHOLD: rate limited, nothing goes out for \(Int(seconds))s")
    }

    /// Non-asset bytes on a record, for the 2 MB batch ceiling.
    private static func payloadBytes(_ record: CKRecord) -> Int {
        var bytes = 0
        for key in record.allKeys() {
            switch record[key] {
            case let s as String: bytes += s.utf8.count
            case let list as [String]: bytes += list.reduce(0) { $0 + $1.utf8.count }
            case let d as Data: bytes += d.count
            case is CKAsset, is [CKAsset]: break
            default: bytes += 16
            }
        }
        return bytes
    }

    private static let batchCeiling = 200
    private static let byteCeiling = 2_000_000

    private static func modify(
        saving: [CKRecord], deleting: [CKRecord.ID], in db: CKDatabase,
        policy: CKModifyRecordsOperation.RecordSavePolicy = .ifServerRecordUnchanged
    ) async -> (saved: [CKRecord.ID: Result<CKRecord, Error>],
                deleted: [CKRecord.ID: Result<Void, Error>], failure: Error?) {
        await withCheckedContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: saving, recordIDsToDelete: deleting)
            operation.savePolicy = policy
            operation.isAtomic = false
            var saved: [CKRecord.ID: Result<CKRecord, Error>] = [:]
            var deleted: [CKRecord.ID: Result<Void, Error>] = [:]
            operation.perRecordSaveBlock = { id, result in saved[id] = result }
            operation.perRecordDeleteBlock = { id, result in deleted[id] = result }
            operation.modifyRecordsResultBlock = { result in
                if case .failure(let error) = result {
                    continuation.resume(returning: (saved, deleted, error))
                } else {
                    continuation.resume(returning: (saved, deleted, nil))
                }
            }
            db.add(operation)
        }
    }

    /// Save in batches of at most 200 records and under 2 MB of non-asset
    /// payload, halving on `.limitExceeded`. Answers per record.
    private static func saveBatched(_ records: [CKRecord], in db: CKDatabase) async -> [CKRecord.ID: Result<CKRecord, Error>] {
        var results: [CKRecord.ID: Result<CKRecord, Error>] = [:]
        var queue = records
        var ceiling = batchCeiling
        while !queue.isEmpty {
            var batch: [CKRecord] = []
            var bytes = 0
            while let next = queue.first, batch.count < ceiling {
                let size = payloadBytes(next)
                if !batch.isEmpty, bytes + size > byteCeiling { break }
                batch.append(next)
                bytes += size
                queue.removeFirst()
            }
            let answer = await modify(saving: batch, deleting: [], in: db)
            if let failure = answer.failure as? CKError, failure.code == .limitExceeded, batch.count > 1 {
                ceiling = max(1, batch.count / 2)
                queue.insert(contentsOf: batch, at: 0)
                print("PLATED HOUSEHOLD: batch too large, halving to \(ceiling)")
                continue
            }
            for record in batch {
                if let result = answer.saved[record.recordID] {
                    results[record.recordID] = result
                } else if let failure = answer.failure {
                    results[record.recordID] = .failure(failure)
                } else {
                    results[record.recordID] = .failure(CKError(.internalError))
                }
            }
        }
        return results
    }

    /// Push every entry, fetch-compare-save per record (§2). Deletes and the
    /// root are routed to their own paths so the outbox can hand everything
    /// it holds for a kind through one door.
    @MainActor
    static func push(entries: [HouseholdOutbox.Entry], context: ModelContext) async -> [String: PushOutcome] {
        var outcomes: [String: PushOutcome] = [:]
        guard !entries.isEmpty else { return outcomes }
        if let until = rateLimitedUntil, until > .now {
            // Kept, never failed: a rate limit is not a refusal of the write.
            for entry in entries { outcomes[entry.id] = .retry }
            print("PLATED HOUSEHOLD: rate limited, \(entries.count) entries wait until \(until)")
            return outcomes
        }
        guard await TableSync.accountAvailable(), let (db, zoneID) = await householdZone() else {
            for entry in entries { outcomes[entry.id] = .retry }
            print("PLATED HOUSEHOLD: no household zone reachable, \(entries.count) entries kept")
            return outcomes
        }

        let deletes = entries.filter(\.isDelete)
        if !deletes.isEmpty {
            let ok = await delete(recordNames: deletes.map(\.id))
            for entry in deletes { outcomes[entry.id] = ok ? .saved(modifiedAt: entry.at) : .retry }
        }
        for kind in [HouseholdOutbox.Kind.seat, .recipe, .gathering, .meal, .line, .mark] {
            let batch = entries.filter { !$0.isDelete && $0.kind == kind }
            guard !batch.isEmpty else { continue }
            let candidates = candidates(for: kind, entries: batch, context: context)
            for entry in batch where candidates[entry.id] == nil {
                // The row is gone locally before it ever went out. Nothing
                // to send, and nothing to keep.
                outcomes[entry.id] = .gone
            }
            let part = await push(Array(candidates.values), db: db, zoneID: zoneID, context: context)
            outcomes.merge(part) { $1 }
        }
        // The root goes last, whatever order the caller handed things in:
        // `publishedAt` on it means everything else already landed, so a
        // mixed call that sent it first would say so before it was true.
        for entry in entries where !entry.isDelete && entry.kind == .root {
            let ok = await pushRoot(localRoot(in: context))
            outcomes[entry.id] = ok ? .saved(modifiedAt: entry.at) : .retry
        }
        return outcomes
    }

    @MainActor
    private static func candidates(
        for kind: HouseholdOutbox.Kind, entries: [HouseholdOutbox.Entry], context: ModelContext
    ) -> [String: Candidate] {
        let names = entries.map(\.id)
        var found: [String: Candidate] = [:]
        let me = TableIdentity.cached
        let isMember: Bool = { if case .member = membership { return true }; return false }()
        let claimed = mySeat

        func bookkeeping(_ body: () -> Void) {
            HouseholdSync.suppressed = true
            defer { HouseholdSync.suppressed = false }
            body()
            Persist.save(context, "household push")
        }

        switch kind {
        case .seat:
            let rows = (try? context.fetch(FetchDescriptor<HouseholdMember>(
                predicate: #Predicate { names.contains($0.shareRecordName) }
            ))) ?? []
            for entry in entries {
                guard let row = rows.first(where: { $0.shareRecordName == entry.id }) else { continue }
                // A member's own seat is never head and never owner on the
                // wire: the zone has exactly one head and it is the host's.
                if isMember, row.isMe || row.shareRecordName == claimed {
                    if row.role == "owner" { row.role = "partner" }
                    if row.seat == .head { row.seat = .joined }
                }
                if row.authorID.isEmpty { row.authorID = me }
                found[entry.id] = Candidate(
                    entry: entry, shareModifiedAt: row.shareModifiedAt, markAt: nil, photoHash: nil,
                    write: { record, _ in
                        var s = remote(from: row)
                        s.modifiedBy = me
                        s.modifiedAt = entry.at
                        write(s, onto: record)
                    },
                    saved: { at in bookkeeping {
                        row.shareModifiedAt = at
                        row.shareFingerprint = HouseholdSync.fingerprint(of: row) ?? ""
                    } },
                    gone: { bookkeeping { context.delete(row) } },
                    applyRemote: { record in
                        // §7: two people can be handed the same named seat,
                        // and the loser finds out here, when their own push
                        // comes back carrying somebody else's identity. The
                        // record is theirs; this device stops arguing for it
                        // and takes a fresh seat, with its nights.
                        let theirID = (record["userRecordName"] as? String) ?? ""
                        let taken = entry.id == claimed && !theirID.isEmpty && theirID != me
                        // §3.1: the seat's field rules apply on push-conflict
                        // as well as on pull. Role and cookWeekdays belong to
                        // the household and are last writer wins, so their
                        // version is merged and then the change this phone
                        // made is re-asserted, rather than reverting on the
                        // host's own screen with nobody told. Name, bio and
                        // photo belong to the person the seat is, and
                        // `applySeat` already protects those.
                        let role = row.role
                        let roleLine = row.roleLine
                        let weekdays = row.cookWeekdays
                        let primary = row.isPrimaryCook
                        var changes = Changes()
                        changes.add(record)
                        merge(changes, into: context, ignoringPending: [entry.id])
                        if taken {
                            HouseholdSync.claimFreshSeat(replacing: row, in: context)
                            return
                        }
                        bookkeeping {
                            row.role = role
                            row.roleLine = roleLine
                            row.cookWeekdays = weekdays
                            row.isPrimaryCook = primary
                        }
                    }
                )
            }
        case .recipe:
            let rows = (try? context.fetch(FetchDescriptor<Recipe>(
                predicate: #Predicate { names.contains($0.shareRecordName) }
            ))) ?? []
            for entry in entries {
                guard let row = rows.first(where: { $0.shareRecordName == entry.id }) else { continue }
                if row.authorID.isEmpty { row.authorID = me }
                let localHash = Wire.photoHash(
                    hero: row.photoData, extras: row.sortedExtraPhotos.compactMap(\.photoData)
                )
                found[entry.id] = Candidate(
                    entry: entry, shareModifiedAt: row.shareModifiedAt, markAt: nil, photoHash: localHash,
                    write: { record, photos in
                        var r = remote(from: row)
                        r.modifiedBy = me
                        r.modifiedAt = entry.at
                        write(r, onto: record, includingPhotos: photos)
                    },
                    saved: { at in bookkeeping {
                        row.shareModifiedAt = at
                        row.sharePhotoHash = localHash
                        row.shareFingerprint = HouseholdSync.fingerprint(of: row) ?? ""
                    } },
                    gone: { bookkeeping { context.delete(row) } },
                    applyRemote: { record in
                        var changes = Changes()
                        changes.add(record)
                        merge(changes, into: context, ignoringPending: [entry.id])
                    }
                )
            }
        case .gathering:
            let rows = (try? context.fetch(FetchDescriptor<Gathering>(
                predicate: #Predicate { names.contains($0.shareRecordName) }
            ))) ?? []
            for entry in entries {
                guard let row = rows.first(where: { $0.shareRecordName == entry.id }) else { continue }
                if row.authorID.isEmpty { row.authorID = me }
                found[entry.id] = Candidate(
                    entry: entry, shareModifiedAt: row.shareModifiedAt, markAt: nil, photoHash: nil,
                    write: { record, _ in
                        var g = remote(from: row)
                        g.modifiedBy = me
                        g.modifiedAt = entry.at
                        write(g, onto: record)
                    },
                    saved: { at in bookkeeping {
                        row.shareModifiedAt = at
                        row.shareFingerprint = HouseholdSync.fingerprint(of: row) ?? ""
                    } },
                    gone: { bookkeeping { context.delete(row) } },
                    applyRemote: { record in
                        var changes = Changes()
                        changes.add(record)
                        merge(changes, into: context, ignoringPending: [entry.id])
                    }
                )
            }
        case .meal:
            let rows = (try? context.fetch(FetchDescriptor<PlannedMeal>(
                predicate: #Predicate { names.contains($0.shareRecordName) }
            ))) ?? []
            for entry in entries {
                guard let row = rows.first(where: { $0.shareRecordName == entry.id }) else { continue }
                if row.authorID.isEmpty { row.authorID = me }
                found[entry.id] = Candidate(
                    entry: entry, shareModifiedAt: row.shareModifiedAt, markAt: nil, photoHash: nil,
                    write: { record, _ in
                        var m = remote(from: row)
                        m.modifiedBy = me
                        m.modifiedAt = entry.at
                        write(m, onto: record)
                    },
                    saved: { at in bookkeeping {
                        row.shareModifiedAt = at
                        row.shareFingerprint = HouseholdSync.fingerprint(of: row) ?? ""
                    } },
                    gone: { bookkeeping { context.delete(row) } },
                    applyRemote: { record in
                        var changes = Changes()
                        changes.add(record)
                        merge(changes, into: context, ignoringPending: [entry.id])
                    }
                )
            }
        case .line:
            let rows = (try? context.fetch(FetchDescriptor<GroceryItem>(
                predicate: #Predicate { names.contains($0.shareRecordName) }
            ))) ?? []
            for entry in entries {
                guard let row = rows.first(where: { $0.shareRecordName == entry.id }) else { continue }
                if row.authorID.isEmpty { row.authorID = me }
                found[entry.id] = Candidate(
                    entry: entry, shareModifiedAt: row.shareModifiedAt, markAt: nil, photoHash: nil,
                    write: { record, _ in
                        var l = remote(from: row)
                        l.modifiedBy = me
                        l.modifiedAt = entry.at
                        write(l, onto: record)
                    },
                    saved: { at in bookkeeping {
                        row.shareModifiedAt = at
                        row.shareFingerprint = HouseholdSync.fingerprint(of: row) ?? ""
                    } },
                    gone: { bookkeeping { context.delete(row) } },
                    applyRemote: { record in
                        var changes = Changes()
                        changes.add(record)
                        merge(changes, into: context, ignoringPending: [entry.id])
                    }
                )
            }
        case .mark:
            // A mark has no row and no version: it is a timestamped value,
            // and the server's copy wins only when it is newer.
            for entry in entries {
                guard let mark = GroceryMarks.shared.all.first(where: {
                    GroceryMarks.recordName(for: $0.lineKey) == entry.id
                }) else { continue }
                found[entry.id] = Candidate(
                    entry: entry, shareModifiedAt: nil, markAt: mark.at, photoHash: nil,
                    write: { record, _ in write(remote(from: mark), onto: record) },
                    saved: { _ in },
                    gone: {},
                    applyRemote: { record in
                        GroceryMarks.shared.fold(
                            {
                                let r = remoteMark(from: record)
                                return GroceryMarks.Mark(lineKey: r.lineKey, purchases: r.purchases,
                                                         dismissedUntil: r.dismissedUntil, at: r.at, by: r.by)
                            }(),
                            into: context
                        )
                        Persist.save(context, "household push")
                    }
                )
            }
        case .root:
            break
        }
        return found
    }

    /// The server version that won, decoded the way a pull decodes it, so
    /// the outbox can hand it to the bell without knowing about records.
    private static func theirs(_ record: CKRecord) -> Changes {
        var changes = Changes()
        changes.add(record)
        return changes
    }

    /// What a lost push means for the queue. §2 drops the local edit and
    /// says so, but a seat has field rules on top (§3.1): its `applyRemote`
    /// has already merged their version and kept this phone's household
    /// fields, so the entry stays and the next drain carries them to the
    /// zone. The row's `shareModifiedAt` is the server's by then, so that
    /// push matches on the fetch and lands rather than conflicting again.
    private static func conflictOutcome(for candidate: Candidate, record: CKRecord) -> PushOutcome {
        guard candidate.entry.kind == .seat else { return .remoteNewer(theirs: theirs(record)) }
        // The seat this device was pushing came back holding somebody
        // else's identity (§7). `applyRemote` moves this person to a fresh
        // seat; the entry for the taken one has nowhere to go, and keeping
        // it queued would push this phone's name onto a stranger's row on
        // every drain from here on.
        let theirID = (record["userRecordName"] as? String) ?? ""
        if candidate.entry.id == mySeat, !theirID.isEmpty, theirID != TableIdentity.cached {
            return .gone
        }
        return .retry
    }

    /// Somebody else wrote since this device last looked?
    private static func serverIsNewer(_ record: CKRecord, than candidate: Candidate) -> Bool {
        let serverModified = record["modifiedAt"] as? Date
        if let markAt = candidate.markAt {
            guard let serverModified else { return false }
            return serverModified > markAt
        }
        return serverModified != candidate.shareModifiedAt
    }

    @MainActor
    private static func push(
        _ candidates: [Candidate], db: CKDatabase, zoneID: CKRecordZone.ID, context: ModelContext
    ) async -> [String: PushOutcome] {
        var outcomes: [String: PushOutcome] = [:]
        guard !candidates.isEmpty else { return outcomes }
        let byName = Dictionary(uniqueKeysWithValues: candidates.map { ($0.entry.id, $0) })
        let ids = candidates.map { CKRecord.ID(recordName: $0.entry.id, zoneID: zoneID) }
        let rootID = CKRecord.ID(recordName: rootRecordName, zoneID: zoneID)

        // The server record first, so the write lands on the instance that
        // carries the change tag. Batched for the same reason the save is:
        // `publishAll` enqueues every recipe and every meal a household has,
        // and one request carrying all of them comes back `.limitExceeded`,
        // which used to mark the whole kind failed.
        var fetched: [CKRecord.ID: Result<CKRecord, Error>] = [:]
        var unread: Set<String> = []
        var queue = ids
        var ceiling = batchCeiling
        while !queue.isEmpty {
            let slice = Array(queue.prefix(ceiling))
            do {
                fetched.merge(try await db.records(for: slice)) { $1 }
                queue.removeFirst(slice.count)
            } catch let error as CKError where error.code == .limitExceeded && slice.count > 1 {
                ceiling = max(1, slice.count / 2)
                print("PLATED HOUSEHOLD: fetch before push too large, halving to \(ceiling)")
            } catch {
                // Only this slice waits. The rest of the kind still goes out,
                // and a fetch that could not be asked is never an answer that
                // the write is wrong.
                noteRateLimit(error)
                queue.removeFirst(slice.count)
                for id in slice { unread.insert(id.recordName) }
                print("PLATED HOUSEHOLD: fetch before push failed for \(slice.count) record(s): \(error.localizedDescription)")
            }
        }
        for name in unread { outcomes[name] = .retry }

        func typeName(_ kind: HouseholdOutbox.Kind) -> String {
            switch kind {
            case .seat: return seatType
            case .meal: return mealType
            case .recipe: return recipeType
            case .gathering: return gatheringType
            case .line: return lineType
            case .mark: return markType
            case .root: return rootType
            }
        }

        /// Write the candidate's fields onto a record, fetched or fresh.
        func prepare(_ candidate: Candidate, onto record: CKRecord) {
            let photos = candidate.photoHash == nil
                || candidate.photoHash != (record["photoHash"] as? String)
            candidate.write(record, photos)
        }

        var toSave: [CKRecord] = []
        for candidate in candidates {
            let name = candidate.entry.id
            guard !unread.contains(name) else { continue }
            let id = CKRecord.ID(recordName: name, zoneID: zoneID)
            switch fetched[id] {
            case .success(let record):
                if serverIsNewer(record, than: candidate) {
                    // Read before the apply: a seat conflict can move this
                    // device onto a fresh seat, and `mySeat` is what tells
                    // the two apart.
                    let outcome = conflictOutcome(for: candidate, record: record)
                    candidate.applyRemote(record)
                    outcomes[name] = outcome
                    print("PLATED HOUSEHOLD: \(name) is newer on the server, theirs is showing")
                } else {
                    prepare(candidate, onto: record)
                    toSave.append(record)
                }
            case .failure(let error):
                if let ck = error as? CKError, ck.code == .unknownItem {
                    if candidate.shareModifiedAt != nil {
                        // Synced once and gone now: a member deleted it.
                        candidate.gone()
                        outcomes[name] = .gone
                        print("PLATED HOUSEHOLD: \(name) is gone from the zone, deleted locally")
                    } else {
                        let record = CKRecord(recordType: typeName(candidate.entry.kind), recordID: id)
                        record.setParent(rootID)
                        Wire.set(record, "parent", CKRecord.Reference(recordID: rootID, action: .deleteSelf))
                        prepare(candidate, onto: record)
                        toSave.append(record)
                    }
                } else {
                    outcomes[name] = isRetryable(error) ? .retry : .failed
                }
            case .none:
                // No answer for this id at all. Treated as unknown, which
                // creates a never-synced row and leaves a synced one alone.
                if candidate.shareModifiedAt == nil {
                    let record = CKRecord(recordType: typeName(candidate.entry.kind), recordID: id)
                    record.setParent(rootID)
                    Wire.set(record, "parent", CKRecord.Reference(recordID: rootID, action: .deleteSelf))
                    prepare(candidate, onto: record)
                    toSave.append(record)
                } else {
                    outcomes[name] = .retry
                }
            }
        }

        var attempt = 0
        while !toSave.isEmpty, attempt < 3 {
            attempt += 1
            let results = await saveBatched(toSave, in: db)
            Wire.removeTemporaryAssets(on: toSave)
            var again: [CKRecord] = []
            for record in toSave {
                let name = record.recordID.recordName
                guard let candidate = byName[name] else { continue }
                switch results[record.recordID] {
                case .success(let saved):
                    let at = saved["modifiedAt"] as? Date ?? candidate.entry.at
                    candidate.saved(at)
                    outcomes[name] = .saved(modifiedAt: at)
                case .failure(let error):
                    if let ck = error as? CKError, ck.code == .serverRecordChanged,
                       let server = ck.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                        // Somebody wrote between the fetch and the save. The
                        // comparison runs again on the record they left.
                        if serverIsNewer(server, than: candidate) {
                            let outcome = conflictOutcome(for: candidate, record: server)
                            candidate.applyRemote(server)
                            outcomes[name] = outcome
                        } else {
                            prepare(candidate, onto: server)
                            again.append(server)
                        }
                    } else {
                        noteRateLimit(error)
                        outcomes[name] = isRetryable(error) ? .retry : .failed
                        print("PLATED HOUSEHOLD: save of \(name) refused: \(error.localizedDescription)")
                    }
                case .none:
                    outcomes[name] = .retry
                }
            }
            toSave = again
        }
        // Every `prepare` on a `.serverRecordChanged` answer wrote fresh
        // share-*.jpg files for the record's photographs, and the leftovers
        // of the third attempt never reached a `saveBatched` call to have
        // them swept.
        Wire.removeTemporaryAssets(on: toSave)
        for record in toSave { outcomes[record.recordID.recordName] = .retry }
        print("PLATED HOUSEHOLD: pushed \(candidates.count): \(outcomes.values.filter { if case .saved = $0 { return true }; return false }.count) saved")
        return outcomes
    }

    /// The root, with the fetched-instance discipline and no version check:
    /// the host owns its fields and the last write wins.
    static func pushRoot(_ root: RemoteRoot) async -> Bool {
        guard await TableSync.accountAvailable(), let (db, zoneID) = await householdZone() else { return false }
        let rootID = CKRecord.ID(recordName: rootRecordName, zoneID: zoneID)
        var record: CKRecord
        do {
            record = try await db.record(for: rootID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: rootType, recordID: rootID)
        } catch {
            print("PLATED HOUSEHOLD: could not fetch the root: \(error.localizedDescription)")
            return false
        }
        for attempt in 1...3 {
            write(root, onto: record)
            let answer = await modify(saving: [record], deleting: [], in: db)
            Wire.removeTemporaryAssets(on: [record])
            switch answer.saved[rootID] {
            case .success:
                groupDefaults.set(root.name, forKey: Keys.lastSyncedName)
                groupDefaults.set(root.name, forKey: Keys.name)
                print("PLATED HOUSEHOLD: root pushed")
                return true
            case .failure(let error):
                if let ck = error as? CKError, ck.code == .serverRecordChanged,
                   let server = ck.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord, attempt < 3 {
                    record = server
                    continue
                }
                print("PLATED HOUSEHOLD: root push refused: \(error.localizedDescription)")
                return false
            case .none:
                print("PLATED HOUSEHOLD: root push got no answer: \(answer.failure.map { "\($0)" } ?? "")")
                return false
            }
        }
        return false
    }

    /// Delete records through one operation per batch. `.unknownItem` is
    /// success: the thing is gone, which is what was asked.
    static func delete(recordNames: [String]) async -> Bool {
        guard !recordNames.isEmpty else { return true }
        guard await TableSync.accountAvailable(), let (db, zoneID) = await householdZone() else { return false }
        var ok = true
        var queue = recordNames.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
        while !queue.isEmpty {
            let batch = Array(queue.prefix(batchCeiling))
            queue.removeFirst(batch.count)
            let answer = await modify(saving: [], deleting: batch, in: db)
            for id in batch {
                switch answer.deleted[id] {
                case .success: continue
                case .failure(let error):
                    if let ck = error as? CKError, ck.code == .unknownItem { continue }
                    ok = false
                case .none:
                    if let failure = answer.failure as? CKError, failure.code == .unknownItem { continue }
                    ok = false
                }
            }
        }
        print("PLATED HOUSEHOLD: deleted \(recordNames.count) record(s): \(ok ? "ok" : "some refused")")
        return ok
    }

    #else
    static var isRateLimited: Bool { false }
    static func refreshMembership() async -> Membership { membership }
    static func invitationURL(hostName: String) async -> URL? { nil }
    static func standings() async -> [TableShare.Standing] { [] }
    static func removeParticipant(userRecordName: String) async -> Bool { false }
    static func leave() async -> Bool { false }
    static func accept(_ metadata: CKShare.Metadata) async -> Bool { false }
    static func fetchChanges() async -> Changes { Changes() }
    @MainActor
    static func push(entries: [HouseholdOutbox.Entry], context: ModelContext) async -> [String: PushOutcome] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.id, PushOutcome.retry) })
    }
    static func pushRoot(_ root: RemoteRoot) async -> Bool { false }
    static func delete(recordNames: [String]) async -> Bool { false }
    #endif
}
