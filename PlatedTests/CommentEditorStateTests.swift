import XCTest
@testable import Plated

final class CommentEditorStateTests: XCTestCase {
    private func caret(_ text: String, before suffix: String = "") -> NSRange {
        NSRange(location: text.utf16.count - suffix.utf16.count, length: 0)
    }

    func testMentionReplacesTypedQueryInsteadOfDuplicatingIt() throws {
        let text = "Fresh basil @Sa"
        let result = try XCTUnwrap(CommentMentionInsertion.inserting("Sam", into: text, selection: caret(text)))
        XCTAssertEqual(result.text, "Fresh basil @Sam ")
        XCTAssertEqual(result.caretUTF16, result.text.utf16.count)
    }

    func testMultiwordDisplayNameQueryDoesNotDuplicateOrConsumeFollowingProse() throws {
        let text = "Ask @Alessandra Sch"
        let result = try XCTUnwrap(CommentMentionInsertion.inserting("Alessandra Schembari", into: text, selection: caret(text)))
        XCTAssertEqual(result.text, "Ask @Alessandra Schembari ")
        let prose = "Ask @Sam and tomatoes"
        XCTAssertNil(CommentMentionInsertion.activeToken(in: prose, selection: caret(prose), names: ["Sam", "Riley"]))
        let next = try XCTUnwrap(CommentMentionInsertion.inserting("Riley", into: prose, selection: caret(prose)))
        XCTAssertEqual(next.text, "Ask @Sam and tomatoes @Riley ")
    }

    func testMentionReplacesWholeTokenAroundMiddleCaret() throws {
        let text = "Try @Samantha with basil"
        let result = try XCTUnwrap(CommentMentionInsertion.inserting("Sam", into: text, selection: caret(text, before: "mantha with basil")))
        XCTAssertEqual(result.text, "Try @Sam with basil")
        XCTAssertEqual(result.caretUTF16, "Try @Sam ".utf16.count)
    }

    func testMultiwordChoiceConsumesTheWholeTokenAtAMiddleCaret() throws {
        let text = "Try @Samantha with basil"
        let result = try XCTUnwrap(CommentMentionInsertion.inserting("Sam Meadows", into: text, selection: caret(text, before: "mantha with basil")))
        XCTAssertEqual(result.text, "Try @Sam Meadows with basil")
        XCTAssertEqual(result.caretUTF16, "Try @Sam Meadows ".utf16.count)
    }

    func testMultiwordExtensionConsumesTheFinalWordsSuffix() throws {
        let text = "Try @Sam Meadowsworth with basil"
        let result = try XCTUnwrap(CommentMentionInsertion.inserting("Sam Meadows", into: text, selection: caret(text, before: "m Meadowsworth with basil")))
        XCTAssertEqual(result.text, "Try @Sam Meadows with basil")
        XCTAssertEqual(result.caretUTF16, "Try @Sam Meadows ".utf16.count)
    }

    func testMultiwordContinuationPreservesUnrelatedProseAndCompletesOnlyNameTokens() throws {
        let selection = NSRange(location: "Try @Sa".utf16.count, length: 0)
        for (text, expected) in [
            ("Try @Sam with basil", "Try @Sam Meadows with basil"),
            ("Try @Sam maybe later", "Try @Sam Meadows maybe later"),
            ("Try @Sam Mea with basil", "Try @Sam Meadows with basil"),
            ("Try @Sam Meadows with basil", "Try @Sam Meadows with basil"),
            ("Try @Sam Meadowsworth with basil", "Try @Sam Meadows with basil"),
            ("Try @Samantha with basil", "Try @Sam Meadows with basil")
        ] {
            let result = try XCTUnwrap(CommentMentionInsertion.inserting("Sam Meadows", into: text, selection: selection))
            XCTAssertEqual(result.text, expected, text)
            XCTAssertEqual(result.caretUTF16, "Try @Sam Meadows ".utf16.count, text)
        }
    }

    func testCaretAfterNameSeparatorDoesNotConsumeUnrelatedFollowingWord() throws {
        let selection = NSRange(location: "Try @Sam ".utf16.count, length: 0)
        for (text, expected) in [
            ("Try @Sam with basil", "Try @Sam Meadows with basil"),
            ("Try @Sam maybe later", "Try @Sam Meadows maybe later"),
            ("Try @Sam Mea with basil", "Try @Sam Meadows with basil")
        ] {
            let result = try XCTUnwrap(CommentMentionInsertion.inserting("Sam Meadows", into: text, selection: selection))
            XCTAssertEqual(result.text, expected, text)
        }
    }

    func testAttachmentMentionInsertsAtCaretWithoutMovingTheSuffix() throws {
        let text = "Fresh basil and tomatoes"
        let result = try XCTUnwrap(CommentMentionInsertion.inserting("Riley", into: text, selection: caret(text, before: "and tomatoes")))
        XCTAssertEqual(result.text, "Fresh basil @Riley and tomatoes")
        XCTAssertEqual(result.caretUTF16, "Fresh basil @Riley ".utf16.count)
    }

    func testMentionReplacesSelectedText() throws {
        let text = "Ask someone tonight"
        let selected = try XCTUnwrap(text.range(of: "someone"))
        let result = try XCTUnwrap(CommentMentionInsertion.inserting("Sam", into: text, selection: NSRange(selected, in: text)))
        XCTAssertEqual(result.text, "Ask @Sam tonight")
    }

    func testUnicodeNamesAndEmojiKeepAValidInsertionPoint() throws {
        let text = "🍅 café @Él"
        let result = try XCTUnwrap(CommentMentionInsertion.inserting("Élodie", into: text, selection: caret(text)))
        XCTAssertEqual(result.text, "🍅 café @Élodie ")
        XCTAssertNotNil(Range(NSRange(location: result.caretUTF16, length: 0), in: result.text))
    }

    func testAtSignInAnEmailOrEscapedAtIsNotAMentionQuery() {
        for text in ["hello@example", "@@Sam", "price@", "Fresh basil"] {
            XCTAssertNil(CommentMentionInsertion.activeToken(in: text, selection: caret(text)), text)
        }
    }

    func testBareAtAndPunctuationBoundariesSupportMentions() throws {
        for text in ["@", "Ask @", "(@Sa"] {
            XCTAssertNotNil(CommentMentionInsertion.activeToken(in: text, selection: caret(text)), text)
        }
        let result = try XCTUnwrap(CommentMentionInsertion.inserting("Sam", into: "(@Sa", selection: caret("(@Sa")))
        XCTAssertEqual(result.text, "(@Sam ")
    }

    func testInvalidSelectionIsRejectedWithoutChangingTheDraft() {
        XCTAssertNil(CommentMentionInsertion.inserting("Sam", into: "🍅", selection: NSRange(location: 1, length: 0)))
        XCTAssertNil(CommentMentionInsertion.inserting("Sam", into: "e\u{301}", selection: NSRange(location: 1, length: 0)))
        XCTAssertNil(CommentMentionInsertion.inserting("Sam", into: "👩‍🍳", selection: NSRange(location: 2, length: 0)))
        XCTAssertNil(CommentMentionInsertion.inserting("Sam", into: "Hi", selection: NSRange(location: NSNotFound, length: 1)))
        XCTAssertNil(CommentMentionInsertion.inserting("Sam", into: "Hi", selection: NSRange(location: 1, length: Int.max)))
        XCTAssertNil(CommentMentionInsertion.inserting("Sam", into: "Hi", selection: NSRange(location: 99, length: 0)))
        XCTAssertNil(CommentMentionInsertion.inserting("  ", into: "Hi", selection: nil))
    }

    func testMentionRecipientsDoNotTagNamesInsideLongerNames() {
        XCTAssertEqual(CommentMentionInsertion.mentionedNames(in: "Ask @Samantha tonight", names: ["Sam", "Samantha"]), ["Samantha"])
        XCTAssertEqual(CommentMentionInsertion.mentionedNames(in: "Ask @Sammy tonight", names: ["Sam", "Samantha"]), [])
    }

    func testLongestCompleteMultiwordMentionWins() {
        XCTAssertEqual(CommentMentionInsertion.mentionedNames(in: "Ask @Sam Meadows, then @Sam.", names: ["Sam", "Sam Meadows"]), ["Sam Meadows", "Sam"])
        XCTAssertEqual(CommentMentionInsertion.mentionedNames(in: "@Alessandra Schembari!", names: ["Alessandra", "Alessandra Schembari"]), ["Alessandra Schembari"])
    }

    func testEmailAndEmbeddedAtSignsAreNotNotificationRecipients() {
        XCTAssertEqual(CommentMentionInsertion.mentionedNames(in: "Send mail to person@Sam.com or @@Samantha, not name@Sam.", names: ["Sam", "Samantha"]), [])
    }

    func testMentionPunctuationAndRepeatedNamesProduceExactUniqueRecipients() {
        XCTAssertEqual(CommentMentionInsertion.mentionedNames(in: "(@Sam), [@Samantha]! @Sam?", names: ["Sam", "Samantha"]), ["Sam", "Samantha"])
    }

    func testMentionRecipientBoundariesPreserveUnicodeAndHyphenatedNames() {
        XCTAssertEqual(CommentMentionInsertion.mentionedNames(in: "🍅 @Élodie; @Sam-Park!", names: ["Élodie", "Sam", "Sam-Park"]), ["Élodie", "Sam-Park"])
    }

    func testDraftScopeSeparatesAccountsZonesAndPosts() {
        let original = CommentReplyDraftStore.Scope(account: "A", zoneOwner: "owner", postID: "post")
        let otherAccount = CommentReplyDraftStore.Scope(account: "B", zoneOwner: "owner", postID: "post")
        let otherZone = CommentReplyDraftStore.Scope(account: "A", zoneOwner: "other-owner", postID: "post")
        let otherPost = CommentReplyDraftStore.Scope(account: "A", zoneOwner: "owner", postID: "other-post")
        XCTAssertEqual(Set([original.key, otherAccount.key, otherZone.key, otherPost.key]).count, 4)
        XCTAssertNotEqual(CommentReplyDraftStore.Scope(account: "A.B", zoneOwner: "C", postID: "D").key,
                          CommentReplyDraftStore.Scope(account: "A", zoneOwner: "B.C", postID: "D").key)
    }

    func testLegacyEmptyOwnZoneAndExplicitCurrentOwnerShareOneScope() {
        let empty = CommentReplyDraftStore.Scope(account: "A", zoneOwner: "", postID: "post")
        let own = CommentReplyDraftStore.Scope(account: "A", zoneOwner: "A", postID: "post")
        let foreign = CommentReplyDraftStore.Scope(account: "A", zoneOwner: "B", postID: "post")
        XCTAssertEqual(empty, own)
        XCTAssertEqual(empty.key, own.key)
        XCTAssertNotEqual(empty.key, foreign.key)
    }

    func testCompleteDraftRestoresOnlyToItsWritingAccount() throws {
        try withDefaults { defaults in
            let scope = CommentReplyDraftStore.Scope(account: "A", zoneOwner: "owner", postID: "post")
            let draft = CommentReplyDraftStore.Draft(text: "One.\nTwo.", link: "https://example.com/menu", replyTo: "Sam", parent: "reply", photo: Data([1, 2, 3]))
            XCTAssertTrue(CommentReplyDraftStore.save(draft, scope: scope, currentAccount: "A", defaults: defaults))
            let restored = try XCTUnwrap(CommentReplyDraftStore.load(scope: scope, defaults: defaults))
            XCTAssertEqual(restored, draft)
            XCTAssertTrue(restored.showsLink)
            XCTAssertTrue(restored.showsAttachments)
            XCTAssertNil(CommentReplyDraftStore.load(scope: .init(account: "B", zoneOwner: "owner", postID: "post"), defaults: defaults))
        }
    }

    func testAccountChangeCannotSaveOrEraseAnotherAccountsLoadedDraft() throws {
        try withDefaults { defaults in
            let scope = CommentReplyDraftStore.Scope(account: "A", zoneOwner: "owner", postID: "post")
            let draft = CommentReplyDraftStore.Draft(text: "A private draft")
            XCTAssertTrue(CommentReplyDraftStore.save(draft, scope: scope, currentAccount: "A", defaults: defaults))
            XCTAssertFalse(scope.belongs(to: "B"))
            XCTAssertFalse(CommentReplyDraftStore.save(.init(text: "B writing"), scope: scope, currentAccount: "B", defaults: defaults))
            XCTAssertFalse(CommentReplyDraftStore.save(.init(), scope: scope, currentAccount: "B", defaults: defaults))
            XCTAssertEqual(CommentReplyDraftStore.load(scope: scope, defaults: defaults), draft)
            XCTAssertNil(CommentReplyDraftStore.load(scope: .init(account: "B", zoneOwner: "owner", postID: "post"), defaults: defaults))
        }
    }

    func testUnownedLegacyDraftIsNeitherAdoptedNorDeleted() throws {
        try withDefaults { defaults in
            let legacyKey = "table.replyDraft.post"
            let legacy: [String: Any] = ["text": "Unknown author's writing", "photo": Data([7])]
            defaults.set(legacy, forKey: legacyKey)
            let scope = CommentReplyDraftStore.Scope(account: "A", zoneOwner: "owner", postID: "post")
            XCTAssertNil(CommentReplyDraftStore.load(scope: scope, defaults: defaults))
            XCTAssertTrue(CommentReplyDraftStore.save(.init(text: "A's new draft"), scope: scope, currentAccount: "A", defaults: defaults))
            CommentReplyDraftStore.remove(scope: scope, defaults: defaults)
            XCTAssertEqual(defaults.dictionary(forKey: legacyKey)?["text"] as? String, "Unknown author's writing")
            XCTAssertEqual(defaults.dictionary(forKey: legacyKey)?["photo"] as? Data, Data([7]))
        }
    }

    func testPlaceholderDraftIsNotSilentlyAdoptedByAConfirmedAccount() throws {
        try withDefaults { defaults in
            let placeholder = CommentReplyDraftStore.Scope(account: "local-exact", zoneOwner: "", postID: "post")
            let draft = CommentReplyDraftStore.Draft(text: "Offline writing")
            XCTAssertTrue(CommentReplyDraftStore.save(draft, scope: placeholder, currentAccount: "local-exact", defaults: defaults))
            let confirmed = CommentReplyDraftStore.Scope(account: "confirmed", zoneOwner: "", postID: "post")
            XCTAssertNil(CommentReplyDraftStore.load(scope: confirmed, defaults: defaults))
            XCTAssertEqual(CommentReplyDraftStore.load(scope: placeholder, defaults: defaults), draft)
        }
    }

    func testLinkOnlyDraftRestoresAVisibleAttachmentAndEmptyDraftClearsOnlyItsScope() throws {
        try withDefaults { defaults in
            let scope = CommentReplyDraftStore.Scope(account: "A", zoneOwner: "owner", postID: "post")
            XCTAssertTrue(CommentReplyDraftStore.save(.init(link: "https://example.com"), scope: scope, currentAccount: "A", defaults: defaults))
            let restored = try XCTUnwrap(CommentReplyDraftStore.load(scope: scope, defaults: defaults))
            XCTAssertTrue(restored.text.isEmpty)
            XCTAssertTrue(restored.showsLink)
            XCTAssertTrue(restored.showsAttachments)
            XCTAssertTrue(CommentReplyDraftStore.save(.init(), scope: scope, currentAccount: "A", defaults: defaults))
            XCTAssertNil(CommentReplyDraftStore.load(scope: scope, defaults: defaults))
        }
    }

    func testOnlyTheLatestPhotoSelectionCanComplete() {
        let scope = CommentReplyDraftStore.Scope(account: "A", zoneOwner: "owner", postID: "post")
        var loads = CommentPhotoLoadState()
        let first = loads.begin(scope: scope)
        let second = loads.begin(scope: scope)
        XCTAssertFalse(loads.accepts(first, scope: scope, currentAccount: "A", selectionMatches: true))
        XCTAssertTrue(loads.accepts(second, scope: scope, currentAccount: "A", selectionMatches: true))
        XCTAssertFalse(loads.accepts(second, scope: scope, currentAccount: "A", selectionMatches: false))
    }

    func testRemoveAndSendInvalidateAnUnfinishedPhotoSelection() {
        let scope = CommentReplyDraftStore.Scope(account: "A", zoneOwner: "owner", postID: "post")
        for reason in ["Remove photo", "Send saved comment"] {
            var loads = CommentPhotoLoadState()
            let unfinished = loads.begin(scope: scope)
            loads.invalidate()
            XCTAssertFalse(loads.accepts(unfinished, scope: scope, currentAccount: "A", selectionMatches: true), reason)
            let newDraftPick = loads.begin(scope: scope)
            XCTAssertFalse(loads.accepts(unfinished, scope: scope, currentAccount: "A", selectionMatches: true), reason)
            XCTAssertTrue(loads.accepts(newDraftPick, scope: scope, currentAccount: "A", selectionMatches: true), reason)
        }
    }

    func testPhotoCompletionRejectsAnotherAccountOrDestination() {
        let scope = CommentReplyDraftStore.Scope(account: "A", zoneOwner: "owner", postID: "post")
        var loads = CommentPhotoLoadState()
        let request = loads.begin(scope: scope)
        XCTAssertFalse(loads.accepts(request, scope: scope, currentAccount: "B", selectionMatches: true))
        XCTAssertFalse(loads.accepts(request, scope: .init(account: "A", zoneOwner: "other", postID: "post"), currentAccount: "A", selectionMatches: true))
        XCTAssertFalse(loads.accepts(request, scope: .init(account: "A", zoneOwner: "owner", postID: "other-post"), currentAccount: "A", selectionMatches: true))
    }

    func testAccountChangeAndNewDraftCannotReviveAnOldPhotoRequest() {
        let old = CommentReplyDraftStore.Scope(account: "A", zoneOwner: "owner", postID: "post")
        let new = CommentReplyDraftStore.Scope(account: "B", zoneOwner: "owner", postID: "post")
        var loads = CommentPhotoLoadState()
        let oldPick = loads.begin(scope: old)
        loads.invalidate()
        let newPick = loads.begin(scope: new)
        XCTAssertFalse(loads.accepts(oldPick, scope: new, currentAccount: "B", selectionMatches: true))
        XCTAssertTrue(loads.accepts(newPick, scope: new, currentAccount: "B", selectionMatches: true))
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "Plated.CommentEditorStateTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }
}
