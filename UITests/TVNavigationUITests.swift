#if os(tvOS)
import XCTest

/// Apple TV navigation with the Siri Remote against Scripts/qa-server.py (Scripts/test-tv-ui.sh).
final class TVNavigationUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Back on a video page whose details are still loading returns to the source. With nothing
    /// focusable on the page, tvOS used to hand the press to the system, which left the app.
    func testBackWhileDetailsLoadReturnsToTheSource() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "sites", "-qaPage", "open-detail:qa-stall:1", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/stall-config.json",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        let open = app.buttons["qa.open-detail"]
        XCTAssertTrue(open.waitForExistence(timeout: 60), "The QA page did not appear")
        // Focus starts in the tab sidebar on the left; move right into the page until Select opens the video.
        // The page's skeleton: the placeholder where Play will be holds focus while the details load.
        let loading = app.descendants(matching: .any)["detail.loading"]
        for _ in 0..<4 where !loading.exists {
            remote.press(.right); sleep(1)
            remote.press(.select)
            _ = loading.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(loading.exists, "The video page did not open")
        sleep(3)
        remote.press(.menu)
        sleep(3)
        XCTAssertEqual(app.state, .runningForeground, "Back left the app")
        XCTAssertFalse(loading.exists, "Back did not leave the loading video page")
        XCTAssertTrue(open.waitForExistence(timeout: 10), "Back did not return to the previous page")
    }

    /// Back once a video page has given up returns to the source. When the details failed, the error card's buttons
    /// sat below the full-screen hero, and with no episodes there was no Play: nothing on the page took focus, and
    /// Back did nothing.
    func testBackAfterDetailsFailReturnsToTheSource() throws { try backAfterTheVideoPageGivesUp(source: "qa-broken", focused: "detail.retry") }
    func testBackFromAVideoWithoutEpisodesReturnsToTheSource() throws { try backAfterTheVideoPageGivesUp(source: "qa-no-episodes", focused: "detail.goBack") }

    private func backAfterTheVideoPageGivesUp(source: String, focused identifier: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "sites", "-qaPage", "open-detail:\(source):1", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/stall-config.json",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        let open = app.buttons["qa.open-detail"]
        XCTAssertTrue(open.waitForExistence(timeout: 60), "The QA page did not appear")
        let action = app.buttons[identifier]
        for _ in 0..<4 where !action.exists {
            remote.press(.right); sleep(1)
            remote.press(.select)
            _ = action.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(action.exists, "The video page did not offer \(identifier)")
        sleep(2)
        XCTAssertTrue(action.hasFocus, "\(identifier) did not take focus")
        remote.press(.menu)
        sleep(3)
        XCTAssertEqual(app.state, .runningForeground, "Back left the app")
        XCTAssertTrue(open.waitForExistence(timeout: 10), "Back did not return to the previous page")
    }

    /// Back while a live stream is still loading closes the player. AVKit's player kept the press to itself
    /// until the picture started, so a stream that never loaded could only be left by quitting the app (#22).
    func testBackWhileLiveLoadsClosesThePlayer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "live", "-qaPage", "player-stall", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/stall-config.json",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let waiting = app.descendants(matching: .any)["player.waiting"]
        XCTAssertTrue(waiting.waitForExistence(timeout: 60), "The player did not open")
        sleep(3)
        XCUIRemote.shared.press(.menu)
        sleep(3)
        XCTAssertEqual(app.state, .runningForeground, "Back left the app")
        XCTAssertFalse(waiting.exists, "Back did not close the loading player")
        XCTAssertFalse(app.staticTexts["Can't play this right now"].exists, "The stream failed before Back was pressed")
    }

    /// Back still closes a loading episode once the transport bar has taken focus: it shows the episode
    /// buttons, focus moves onto one, and AVKit then kept the press to itself until the picture started.
    func testBackWhileAnEpisodeLoadsClosesThePlayerFromTheTransportBar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "sites", "-qaPage", "play-source:qa-stream-stall", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/stall-config.json",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let waiting = app.descendants(matching: .any)["player.waiting"]
        XCTAssertTrue(waiting.waitForExistence(timeout: 60), "The player did not open")
        sleep(3)
        let remote = XCUIRemote.shared
        remote.press(.select)
        sleep(2)
        remote.press(.down)
        sleep(2)
        remote.press(.menu)
        sleep(3)
        XCTAssertEqual(app.state, .runningForeground, "Back left the app")
        XCTAssertFalse(waiting.exists, "Back did not close the loading player")
        XCTAssertFalse(app.staticTexts["Can't play this right now"].exists, "The stream failed before Back was pressed")
    }

    /// Subtitle Files lists files only; it says where the video's own subtitles are, which people looked for here (#1524).
    func testSubtitleFilesSaysWhereTheVideosOwnSubtitlesAre() throws {
        let app = XCUIApplication()
        // A stream with subtitle tracks of its own, served on port 8777 (an HLS stream from the remuxer, say); the plain QA
        // clip has none, and then there is no note.
        let stream = "http://127.0.0.1:8777/master.m3u8"
        guard (try? Data(contentsOf: URL(string: stream)!)) != nil else { throw XCTSkip("Serve a stream with subtitle tracks at \(stream)") }
        app.launchArguments = ["-qaSection", "home", "-qaPlayURL", stream, "-qaIsolatedData", "1",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        func focus() -> String { focused.exists ? focused.label : "none" }
        func snap(_ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
        let waiting = app.descendants(matching: .any)["player.waiting"]
        _ = waiting.waitForExistence(timeout: 15)
        for _ in 0..<30 where waiting.exists { sleep(1) }
        sleep(2)
        // The bar's buttons are above the timeline: Up reaches them, Right walks along them.
        remote.press(.up); sleep(2)
        var trail = [focus()]
        for _ in 0..<12 where !focus().hasPrefix("Subtitle Files") { remote.press(.right); sleep(1); trail.append(focus()) }
        snap("bar")
        XCTAssertTrue(focus().hasPrefix("Subtitle Files"), "Subtitle Files was not reached: \(trail)")
        remote.press(.select); sleep(2)
        snap("subtitle-files")
        let note = "The video's own subtitles are under the speech bubble button."
        XCTAssertTrue(app.descendants(matching: .any)[note].exists || app.staticTexts.containing(NSPredicate(format: "label == %@", note)).count > 0,
                      "The note is missing")
    }

    /// A source page searches from the remote: the search keyboard has no return key, so a Search
    /// button below it runs the query that was typed, and typing alone does not search.
    func testSourcePageSearchesWithTheSearchButton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "sites", "-qaPage", "site:qa-standard", "-qaSearchDraft", "hello", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/config.json",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        XCTAssertTrue(shown("测试影片 01", in: app).waitForExistence(timeout: 60), "The source page did not load")
        // `-qaSearchDraft` stands in for typing (UI tests cannot type into the tvOS search keyboard).
        let submit = app.buttons["site.search.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), "A typed query did not show the Search button")
        // Focus starts in the tab sidebar; right moves it into the search keyboard.
        enterContent(app)
        XCTAssertFalse(shown("hello 01", in: app).exists, "The search ran before it was submitted")
        XCTAssertEqual(app.keyboards.count, 0, "The source page showed the keyboard")
        // The Search button leads the content: Up from the first cover reaches it.
        for _ in 0..<4 where !submit.hasFocus { remote.press(.up); sleep(1) }
        XCTAssertTrue(submit.hasFocus, "The remote did not reach the Search button: \(focusInfo(app))")
        remote.press(.select)
        XCTAssertTrue(shown("hello 01", in: app).waitForExistence(timeout: 20), "Pressing Search did not show results")
        XCTAssertFalse(submit.exists, "The Search button stayed after its query ran")
    }
    /// A source's own page opens on its content with no keyboard (the first cover is the default focus, not the search),
    /// and the magnifier at the top right opens the search only when pressed.
    func testSourcePageOpensOnFirstCoverWithMagnifier() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "sites", "-qaPage", "site:qa-standard", "-qaSubscription", "http://127.0.0.1:8776/config.json"])
        XCTAssertTrue(shown("测试影片 01", in: app).waitForExistence(timeout: 60), "The source page did not load")
        let entry = app.buttons["search.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "The source page has no search magnifier")
        sleep(3)
        note("Source page initial focus (before any press): \(focusInfo(app)); keyboards=\(app.keyboards.count); magnifier=\(describe(entry))")
        snap(app, "source-page-initial")
        XCTAssertEqual(app.keyboards.count, 0, "The keyboard is up on opening a source page")
        XCTAssertFalse(entry.hasFocus, "The magnifier has the initial focus")
        enterContent(app)
        let focus = focusInfo(app)
        note("Source page focus after entering content: \(focus)")
        snap(app, "source-page-content-focus")
        XCTAssertTrue(focus.contains("site.firstPoster") || focus.contains("测试影片 01"), "Focus is not the first cover: \(focus)")
        XCTAssertEqual(app.keyboards.count, 0, "The keyboard is up after entering the content")
        let remote = XCUIRemote.shared
        for _ in 0..<6 where !entry.hasFocus { remote.press(.up); sleep(1) }
        snap(app, "source-page-magnifier-focused")
        XCTAssertTrue(entry.hasFocus, "Up from the first cover did not reach the magnifier: \(focusInfo(app))")
        XCTAssertEqual(app.keyboards.count, 0, "Focus on the magnifier opened the keyboard")
        remote.press(.select); sleep(3)
        snap(app, "source-page-search-open")
        XCTAssertTrue(app.keyboards.count > 0 || app.searchFields.count > 0, "Select on the magnifier did not open the search")
    }
    /// A video with several sources and one file each: the rail ends above Play, so Right from the
    /// Play row once found nothing and the source chips were unreachable with the remote.
    func testRemoteReachesTheSourceChips() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "sites", "-qaPage", "open-detail:qa-standard:drive", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/config.json",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        let open = app.buttons["qa.open-detail"]
        XCTAssertTrue(open.waitForExistence(timeout: 60), "The QA page did not appear")
        let chips = ["夸父原1", "夸父智1", "嘟嘟无限2"].map { app.buttons[$0] }
        let second = chips[1]
        for _ in 0..<4 where !second.exists {
            remote.press(.right); sleep(1); remote.press(.select)
            _ = second.waitForExistence(timeout: 8)
        }
        XCTAssertTrue(second.exists, "The video page did not open")
        sleep(2)
        // Play takes focus once the details load; Download is under it, as on the Bilibili page, and the episodes are
        // under the hero.
        XCTAssertTrue(app.buttons["Play"].hasFocus, "Play did not take focus when the details loaded")
        let file = app.buttons["[18.35GB] 玩-居-宗 01.mkv"]
        remote.press(.down); sleep(1)
        XCTAssertTrue(app.buttons["detail.download"].hasFocus || app.buttons["detail.favorite"].hasFocus, "Down from Play did not reach Download or Favorite")
        // The rows under the hero are lazy: the file's row exists only once it is on screen.
        func inRail() -> Bool { (file.exists && file.hasFocus) || chips.contains { $0.exists && $0.hasFocus } }
        for _ in 0..<4 where !inRail() { remote.press(.down); sleep(1) }
        XCTAssertTrue(inRail(), "Down from Download did not reach the episode rail")
        if file.exists && file.hasFocus { remote.press(.up); sleep(1) }
        XCTAssertTrue(chips.contains { $0.hasFocus }, "Up from the file did not reach the source chips")
        for _ in 0..<3 where !second.hasFocus {
            remote.press(chips[0].hasFocus ? .right : .left); sleep(1)
        }
        remote.press(.select); sleep(1)
        XCTAssertTrue(second.isSelected, "Select did not switch the source")
        // Left from the chips goes back to the left column.
        for _ in 0..<3 where chips.contains(where: { $0.hasFocus }) { remote.press(.left); sleep(1) }
        XCTAssertFalse(chips.contains { $0.hasFocus } || file.hasFocus, "Left did not leave the episode rail")
    }
    /// The Bilibili source's home rows are Discover's: Left from a row's first cover opens See All, which lists the row
    /// (the home's rows give way to it).
    func testBilibiliRowSeeAllOpensFromTheLeft() throws {
        let app = XCUIApplication()
        // A version no release is newer than: the What's New screen would cover the page.
        app.launchArguments = ["-qaSection", "sites", "-qaPage", "site:builtin.bilibili", "-qaIsolatedData", "1", "-qaVersion", "99",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        func snap(_ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
        // See All is a hidden sliver until Left reveals it: wait for the rows.
        let mores = app.buttons.matching(identifier: "watchnow.more")
        let popular = app.staticTexts["Popular"]
        XCTAssertTrue(popular.waitForExistence(timeout: 90), "The home has no Popular row")
        sleep(3)
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        // Focus starts in the tab sidebar: Right into the page, then Down past the search keyboard, the sign-in card and
        // the chips to a cover, taller than any control.
        remote.press(.right); sleep(2)
        for _ in 0..<8 where !(focused.exists && focused.frame.height > 150) { remote.press(.down); sleep(1) }
        XCTAssertTrue(focused.frame.height > 150, "Down did not reach a row of covers: \(focused.identifier) \(focused.frame)")
        snap("cover")
        let seeAll = mores.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<4 where !seeAll.exists { remote.press(.left); sleep(1) }
        snap("see all")
        XCTAssertTrue(seeAll.exists, "Left from the row's first cover did not reach See All")
        remote.press(.select); sleep(5)
        snap("listed")
        XCTAssertFalse(popular.exists, "See All did not open the row's list")
    }

    /// The address row on Add Subscription opens its alert and the app keeps answering the remote. On tvOS 27 any
    /// alert or sheet over a page pushed in a tab froze the app: `openRoute` was a new closure on every update, so
    /// the stack never settled (#272).
    func testAddSubscriptionAddressOpensWithoutFreezing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "settings", "-qaIsolatedData", "1",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        let add = app.buttons["Add Subscription"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 60), "Settings did not appear")
        sleep(3)
        // A notice about a newer version can cover the page at launch, with its OK in focus.
        if app.buttons["OK"].exists { remote.press(.select); sleep(2) }
        remote.press(.right); sleep(1)
        for _ in 0..<20 where !add.hasFocus { remote.press(.down); usleep(600_000) }
        XCTAssertTrue(add.hasFocus, "Add Subscription did not take focus")
        remote.press(.select)
        let address = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Subscription URL'")).firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 10), "Add Subscription did not open")
        sleep(2)
        for _ in 0..<4 where !address.hasFocus { remote.press(.up); usleep(600_000) }
        remote.press(.select)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10), "The address alert did not appear")
        remote.press(.menu); sleep(2)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Back did not close the address alert")
        XCTAssertTrue(address.exists, "Back from the alert left Add Subscription")
        remote.press(.menu); sleep(2)
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Back did not return to Settings")
        XCTAssertEqual(app.state, .runningForeground)
    }
    /// A typed address stays when the alert closes by anything but Cancel. tvOS 18 also shows the alert's text field
    /// as a button under it, the first one Down reaches; selecting it closed the alert and dropped the address (#291).
    func testAddSubscriptionKeepsTheTypedAddress() throws {
        let typed = "http://127.0.0.1:8776/config.json"
        let app = XCUIApplication()
        // On tvOS 18, XCTest's runtime-issue hook crashed the app on a UIKit log fault when the text field took focus.
        app.launchEnvironment = ["OS_ACTIVITY_MODE": "disable"]
        app.launchArguments = ["-qaSection", "settings", "-qaIsolatedData", "1",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        let add = app.buttons["Add Subscription"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 60), "Settings did not appear")
        sleep(3)
        if app.buttons["OK"].exists { remote.press(.select); sleep(2) }
        remote.press(.right); sleep(1)
        for _ in 0..<20 where !add.hasFocus { remote.press(.down); usleep(600_000) }
        remote.press(.select)
        let address = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Subscription URL'")).firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 10), "Add Subscription did not open")
        sleep(2)
        for _ in 0..<4 where !address.hasFocus { remote.press(.up); usleep(600_000) }
        remote.press(.select)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "The address alert did not appear")
        sleep(1)
        // Select opens the keyboard on the focused text field; Menu returns to the alert with the text kept.
        remote.press(.select); sleep(3)
        app.typeText(typed); sleep(1)
        remote.press(.menu); sleep(2)
        XCTAssertTrue(alert.exists, "Leaving the keyboard closed the alert")
        let fieldButton = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Subscription URL'")).firstMatch
        let close = fieldButton.exists ? fieldButton : alert.buttons["Done"].firstMatch
        for _ in 0..<3 where !close.hasFocus { remote.press(.down); usleep(700_000) }
        for _ in 0..<2 where !close.hasFocus { remote.press(.right); usleep(700_000) }
        XCTAssertTrue(close.hasFocus, "\(close.label) did not take focus")
        remote.press(.select); sleep(2)
        XCTAssertFalse(alert.exists, "\(close.label) did not close the alert")
        XCTAssertTrue(address.label.hasSuffix(typed), "The typed address was not kept: \(address.label)")
    }
    /// Back on a title's page opened with Up Next's Show Details returns to Watch Now.
    func testBackFromUpNextDetailsReturnsToWatchNow() throws {
        let app = launchWatchNowWithHistory()
        let remote = XCUIRemote.shared
        let details = app.buttons["home.upNext.details"]
        XCTAssertTrue(details.waitForExistence(timeout: 60), "Up Next did not appear")
        sleep(3)
        for _ in 0..<4 where !details.hasFocus { remote.press(.right); sleep(1) }
        XCTAssertTrue(details.hasFocus, "Show Details did not take focus")
        remote.press(.select)
        try backFromDetails(app, to: details)
    }

    /// Back on a title's page opened from a Continue Watching card's menu returns to Watch Now.
    func testBackFromContinueWatchingDetailsReturnsToWatchNow() throws {
        let app = launchWatchNowWithHistory()
        let remote = XCUIRemote.shared
        let card = app.buttons["history.resume.1"]
        XCTAssertTrue(card.waitForExistence(timeout: 60), "Continue Watching did not appear")
        sleep(3)
        // Focus starts in the tab sidebar: Right into Up Next, then Down to the row.
        let resume = app.buttons["home.upNext.resume"]
        for _ in 0..<4 where !resume.hasFocus { remote.press(.right); sleep(1) }
        for _ in 0..<4 where !card.hasFocus { remote.press(.down); sleep(1) }
        XCTAssertTrue(card.hasFocus, "The card did not take focus")
        remote.press(.select, forDuration: 1.5)
        let show = app.buttons["Show Details"]
        XCTAssertTrue(show.waitForExistence(timeout: 5), "The card's menu did not open")
        for _ in 0..<3 where !show.hasFocus { remote.press(.up); usleep(700_000) }
        remote.press(.select)
        try backFromDetails(app, to: card)
    }

    private func launchWatchNowWithHistory() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "home", "-qaIsolatedData", "1", "-qaResetHistory", "1", "-qaSeedHistory", "qa-standard:1",
                               "-qaSubscription", "http://127.0.0.1:8776/config.json",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func backFromDetails(_ app: XCUIApplication, to origin: XCUIElement) throws {
        let favorite = app.buttons["detail.favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 30), "The title's page did not open")
        sleep(3)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        XCUIRemote.shared.press(.menu)
        sleep(3)
        XCTAssertEqual(app.state, .runningForeground, "Back left the app")
        XCTAssertFalse(favorite.exists, "Back did not leave the title's page")
        XCTAssertTrue(origin.waitForExistence(timeout: 10) && origin.isHittable, "Back did not return to Watch Now")
    }

    /// Down from the download queue reaches the finished episodes under it while other episodes are still downloading.
    func testRemoteReachesDownloadedEpisodesWhileOthersDownload() throws {
        let app = XCUIApplication()
        // Episodes 1 and 2 arrive at once, 3 and 4 take minutes (Scripts/qa-server.py).
        app.launchArguments = ["-qaSection", "downloads", "-qaIsolatedData", "1", "-qaDownload", "qa-downloads:1:4", "-downloadsSimultaneous", "4",
                               "-qaSubscription", "http://127.0.0.1:8776/downloads-config.json",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        // What's New covers the page on a fresh install.
        if app.buttons["OK"].waitForExistence(timeout: 20) { remote.press(.select); sleep(2) }
        let episodes = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play 第'"))
        XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout: 60), "Nothing was downloading")
        // Episodes 1 and 2 finish in a moment. Below a queue as tall as the screen, a lazy list never built them.
        sleep(10)
        XCTAssertTrue(app.buttons["Pause"].firstMatch.exists, "Nothing was still downloading")
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        remote.press(.right); sleep(1)
        var trail: [String] = []
        for _ in 0..<14 where !episodes.allElementsBoundByIndex.contains(where: { $0.hasFocus }) {
            trail.append(focused.exists ? focused.label : "-")
            remote.press(.down); usleep(800_000)
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(episodes.allElementsBoundByIndex.contains(where: { $0.hasFocus }),
                      "Down never reached the downloaded episodes; focus went \(trail.joined(separator: " > "))")
    }

    /// Down from the storage card reaches a show when fewer are cached than fit in a row (#1324). It moved to the sort
    /// buttons at the right and stopped there, with no show under them; Up still goes back the same way.
    func testRemoteReachesASingleCachedShow() throws {
        let app = XCUIApplication()
        // Episode 1 arrives at once (Scripts/qa-server.py): one film, one card at the left.
        app.launchArguments = ["-qaSection", "downloads", "-qaIsolatedData", "1", "-qaDownload", "qa-downloads:1:1",
                               "-qaSubscription", "http://127.0.0.1:8776/downloads-config.json",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        if app.buttons["OK"].waitForExistence(timeout: 20) { remote.press(.select); sleep(2) }
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play '")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 60), "The episode was never cached")
        sleep(3)
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        remote.press(.right); sleep(1)
        var trail: [String] = []
        for _ in 0..<4 where !card.hasFocus {
            remote.press(.down); usleep(800_000)
            trail.append(focused.exists ? focused.label : "-")
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(card.hasFocus, "Down never reached the cached show; focus went \(trail.joined(separator: " > "))")
        // Up goes to the sort buttons above the shows, then to the storage card.
        let top = card.frame.minY
        remote.press(.up); sleep(1)
        XCTAssertTrue(!card.hasFocus && focused.frame.maxY <= top && !focused.label.hasPrefix("Storage"),
                      "Up from the show did not reach the sort buttons: \(focused.label)")
        remote.press(.up); sleep(1)
        XCTAssertTrue(focused.label.hasPrefix("Storage"), "Up from the sort buttons did not reach the storage card: \(focused.label)")
    }

    /// Up from anywhere in Global Search's results reaches the search field beside the sidebar button. The field was
    /// 560 points wide at the left, nothing sat above most of the results, and once a search had run the field could
    /// not be reached to search again.
    func testUpFromSearchResultsReachesTheSearchField() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "search", "-qaQuery", "hello", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/config.json",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        if app.buttons["OK"].waitForExistence(timeout: 20) { remote.press(.select); sleep(2) }
        let field = app.buttons["search.field"]
        let results = shown("hello 01", in: app).waitForExistence(timeout: 60)
        if !results { let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot) }
        XCTAssertTrue(results, "The search showed no results")
        sleep(3)
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        // Into the results, out to their right end and down a row: the posters furthest from the field.
        // Focus may start in the tab sidebar; right moves it into the page.
        remote.press(.right); sleep(1)
        var down: [String] = []
        for _ in 0..<6 where !focused.label.contains("hello") {
            down.append("\(focused.elementType.rawValue):\(focused.identifier):\(focused.label)")
            remote.press(.down); sleep(1)
        }
        let near = XCTAttachment(screenshot: app.screenshot()); near.lifetime = .keepAlways; add(near)
        XCTAssertTrue(focused.label.contains("hello"), "Focus did not reach the results; went \(down.joined(separator: " > ")) then \(focused.debugDescription.prefix(600))")
        for _ in 0..<8 { remote.press(.right); usleep(600_000) }
        remote.press(.down); sleep(1)
        if !focused.label.contains("hello") { remote.press(.up); sleep(1) }
        let far = XCTAttachment(screenshot: app.screenshot()); far.lifetime = .keepAlways; add(far)
        XCTAssertTrue(focused.label.contains("hello"), "Focus left the results; it is on \(focused.label)")
        var trail: [String] = []
        for _ in 0..<10 where !field.hasFocus {
            trail.append(focused.exists ? focused.label : "-")
            remote.press(.up); usleep(800_000)
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(field.hasFocus, "Up never reached the search field; focus went \(trail.joined(separator: " > "))")
        remote.press(.select)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10), "Selecting the field did not open the keyboard")
    }

    /// A search whose results fit in one row (#481): Down from the search field, and from the far end of the rows
    /// above the results, reaches them. Without Yingxia's own sources, which
    /// would add more results.
    func testDownReachesASingleRowOfSearchResults() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "search", "-qaQuery", "few", "-qaIsolatedData", "1", "-qaNoCloudSources", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/config.json",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        if app.buttons["OK"].waitForExistence(timeout: 20) { remote.press(.select); sleep(2) }
        let field = app.buttons["search.field"]
        let results = shown("few 01", in: app).waitForExistence(timeout: 60)
        let first = XCTAttachment(screenshot: app.screenshot()); first.lifetime = .keepAlways; add(first)
        XCTAssertTrue(results, "The search showed no results")
        XCTAssertFalse(shown("few 03", in: app).exists, "The fixture should give two results per source")
        // Wait for the slow source too, so the rows above the results stop changing.
        sleep(5)
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        remote.press(.right); sleep(1)
        for _ in 0..<8 where !field.hasFocus { remote.press(.up); usleep(800_000) }
        XCTAssertTrue(field.hasFocus, "Up never reached the search field")
        var trail: [String] = []
        for _ in 0..<8 where !focused.label.contains("few") {
            trail.append("\(focused.identifier):\(focused.label)")
            remote.press(.down); sleep(1)
        }
        let down = XCTAttachment(screenshot: app.screenshot()); down.lifetime = .keepAlways; add(down)
        XCTAssertTrue(focused.label.contains("few"), "Down from the field never reached the results; went \(trail.joined(separator: " > "))")
        // Now from the far right of each row above the results.
        for _ in 0..<8 where !field.hasFocus { remote.press(.up); usleep(800_000) }
        remote.press(.down); sleep(1)
        for _ in 0..<8 { remote.press(.right); usleep(600_000) }
        trail = []
        for _ in 0..<8 where !focused.label.contains("few") {
            trail.append("\(focused.identifier):\(focused.label)")
            remote.press(.down); sleep(1)
        }
        let far = XCTAttachment(screenshot: app.screenshot()); far.lifetime = .keepAlways; add(far)
        XCTAssertTrue(focused.label.contains("few"), "Down from the right end never reached the results; went \(trail.joined(separator: " > "))")
    }

    /// Back on the sidebar of any section other than Watch Now goes to Watch Now; only Back on Watch Now's sidebar
    /// leaves the app (#499). Back from a page still moves to the sidebar first (#404).
    func testBackOnTheSidebarGoesToWatchNowBeforeLeaving() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "sites", "-qaIsolatedData", "1", "-qaResetHistory", "1", "-qaSeedHistory", "qa-standard:1",
                               "-qaSubscription", "http://127.0.0.1:8776/config.json",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        if app.buttons["OK"].waitForExistence(timeout: 20) { remote.press(.select); sleep(2) }
        let sources = app.buttons["sources.order.toggle"], watchNow = app.buttons["home.upNext.resume"]
        XCTAssertTrue(sources.waitForExistence(timeout: 60), "Sources did not appear")
        sleep(3)
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        func focus() -> String { focused.exists ? "\(focused.elementType.rawValue):\(focused.identifier):\(focused.label)" : "none" }
        func snap(_ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
        // Focus starts in the page (the source filter); Back moves it to the sidebar and Sources stays.
        let inPage = focus()
        remote.press(.menu); sleep(2)
        snap("sidebar on Sources")
        XCTAssertEqual(app.state, .runningForeground, "Back from the page (focus was \(inPage)) left the app")
        XCTAssertTrue(sources.exists, "Back from the page (focus was \(inPage)) left Sources; focus is \(focus())")
        let onSidebar = focus()
        // Back on Sources' sidebar goes to Watch Now.
        remote.press(.menu)
        let landed = watchNow.waitForExistence(timeout: 10)
        sleep(2)
        snap("Watch Now")
        XCTAssertEqual(app.state, .runningForeground, "Back on Sources' sidebar (focus was \(onSidebar)) left the app")
        XCTAssertTrue(landed && !sources.exists, "Back on Sources' sidebar (focus was \(onSidebar)) did not go to Watch Now; focus is \(focus())")
        let onWatchNow = focus()
        // Back on Watch Now's sidebar leaves.
        var presses = 0, trail: [String] = []
        for _ in 0..<4 where app.state == .runningForeground {
            remote.press(.menu); presses += 1
            for _ in 0..<6 where app.state == .runningForeground { sleep(1) }
            if app.state == .runningForeground { trail.append(focus()); snap("after \(presses)") }
        }
        XCTAssertEqual(presses, 1, "Back on Watch Now's sidebar (focus was \(onWatchNow)) left after \(presses) presses: \(trail) state \(app.state.rawValue)")
    }

    /// 选集 in the player: the info panel (down from the transport bar) has an Episodes tab with the lines and the line's
    /// episodes, the one playing focused; choosing another episode plays it in the same player.
    func testPlayerEpisodesTabPlaysAnotherEpisode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "sites", "-qaPage", "play-source:qa-standard", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/config.json", "-autoPlayNextEpisode", "NO",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        func focus() -> String { focused.exists ? "\(focused.elementType.rawValue):\(focused.identifier):\(focused.label)" : "none" }
        func snap(_ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
        let waiting = app.descendants(matching: .any)["player.waiting"]
        // The fixture clip starts at once: the wait may be over before it is looked for.
        _ = waiting.waitForExistence(timeout: 15)
        for _ in 0..<30 where waiting.exists { sleep(1) }
        XCTAssertFalse(waiting.exists, "The picture did not start")
        sleep(2)
        remote.press(.select); sleep(2)
        snap("transport bar")
        let panel = app.descendants(matching: .any)["player.episodes.panel"]
        var trail: [String] = []
        for _ in 0..<4 where !panel.exists {
            remote.press(.down); sleep(2); trail.append(focus()); snap("down \(trail.count)")
            if !panel.exists, focused.label == "Episodes" { remote.press(.select); sleep(2); snap("selected Episodes") }
        }
        XCTAssertTrue(panel.exists, "No Episodes tab: \(trail)")
        sleep(1)
        let first = focus()
        snap("episodes tab")
        XCTAssertTrue(first.contains("1"), "Focus did not start on the episode playing: \(first)")
        remote.press(.right); sleep(1)
        let second = focus()
        XCTAssertTrue(second.contains("2"), "Right did not reach episode 2: \(second)")
        // Up reaches the lines; the other line's episodes show once it is chosen.
        remote.press(.up); sleep(1)
        remote.press(.right); sleep(1)
        let line = focus()
        remote.press(.select); sleep(2)
        snap("other line")
        XCTAssertTrue(line.contains("线路二"), "Up and Right did not reach the second line: \(line)")
        remote.press(.down); sleep(1)
        let alternate = focus()
        XCTAssertTrue(alternate.contains("备用"), "Down did not reach the other line's episode: \(alternate)")
        // Choosing it plays it: the player stays and the panel closes.
        remote.press(.select); sleep(6)
        snap("after choosing")
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(panel.exists, "The Episodes tab stayed open after choosing an episode")
    }

    /// Double-click on the remote while the full-screen player plays: Right goes to the video's next line (same episode),
    /// Down to the next episode. The server's reports name each stream asked for.
    func testRemoteDoubleClicks() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "sites", "-qaPage", "play-source:qa-rc", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/rc-config.json", "-autoPlayNextEpisode", "NO",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        func reports() -> [String] { serverReports() }
        func waitFor(_ text: String, _ seconds: Int = 25) -> Bool {
            for _ in 0..<seconds { if reports().contains(text) { return true }; sleep(1) }
            return reports().contains(text)
        }
        func fromLabel() -> String {
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'from 0:'")).firstMatch.label
        }
        let panel = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "线路乙")).firstMatch
        XCTAssertTrue(waitFor("play l1-1", 40), "The first episode never started: \(reports())")
        let started = Date()
        // Controls hidden: leave the remote alone until the transport bar has gone, then double-click Right.
        sleep(14)
        snap(app, "remote-hidden-before-right")
        let rightAt = Date().timeIntervalSince(started)
        remote.press(.right); remote.press(.right)
        let line = waitFor("play l2-1")
        let label = fromLabel()
        snap(app, "remote-hidden-after-right")
        let panelAfterRight = panel.exists
        // Controls shown: wake the bar with a click, then double-click Down.
        sleep(8)
        snap(app, "remote-shown-before-down")
        let downAt = Date().timeIntervalSince(started)
        remote.press(.down, forDuration: 3.5)
        let episode = waitFor("play l2-2")
        sleep(1)
        snap(app, "remote-shown-after-down")
        let panelAfterDown = panel.exists
        sleep(8)
        snap(app, "remote-shown-after-down-later")
        note("reports=\(reports()) nextLine=\(line) nextEpisode=\(episode) rightPressedAt=\(Int(rightAt))s from-label='\(label)' panelAfterRight=\(panelAfterRight) downPressedAt=\(Int(downAt))s panelAfterDown=\(panelAfterDown)")
        XCTAssertTrue(line, "Double Right did not go to the next line: \(reports())")
        XCTAssertTrue(episode, "Double Down did not go to the next episode (on the line playing): \(reports())")
        XCTAssertFalse(panelAfterRight, "The info panel opened on double Right")
        XCTAssertFalse(panelAfterDown, "The info panel opened on double Down")
        XCTAssertFalse(reports().contains("play l1-3") && reports().contains("play l2-3"), "More than one step was taken: \(reports())")
    }

    /// Holding Right for 3 s while the full-screen player plays goes to the video's next line once: no second step, no info
    /// panel; Down double-click still goes to the next episode afterwards.
    func testRemoteRightHoldSwitchesLineOnce() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "sites", "-qaPage", "play-source:qa-rc", "-qaVideoID", "rc3", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/rc-config.json", "-autoPlayNextEpisode", "NO",
                               "-qaPlayerReport", "http://127.0.0.1:8776",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        func waitFor(_ text: String, _ seconds: Int = 25) -> Bool {
            for _ in 0..<seconds { if serverReports().contains(text) { return true }; sleep(1) }
            return serverReports().contains(text)
        }
        // The app resolves the next episode of a short video ahead, so a request for it is not a gesture's doing: the
        // plays of a line are its current episode and the one ahead.
        func plays() -> [String] { serverReports().filter { $0.hasPrefix("play ") } }
        func jumps() -> [String] { serverReports().filter { $0.hasPrefix("seekjump") } }
        XCTAssertTrue(waitFor("play f1-1", 40), "The first episode never started: \(serverReports())")
        sleep(6)
        snap(app, "hold-before")
        // A short Right click first: it must not switch the line (the hold is the gesture).
        remote.press(.right); sleep(3)
        let playsAfterClick = plays()
        let jumpsAfterClick = jumps()
        remote.press(.right, forDuration: 3.5)
        let line = waitFor("play f2-1")
        sleep(6)
        snap(app, "hold-after")
        let playsAfterHold = plays()
        let jumpsAfterHold = jumps()
        let startsAfterHold = serverReports().filter { $0.hasPrefix("item start") }
        let switches = serverReports().filter { $0.hasPrefix("item switch") }
        let panelAfterHold = panel(app).exists
        let loading = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Getting it ready'")).firstMatch.exists
        // Down double-click is unchanged: the next episode of the new line, and no panel left open.
        remote.press(.down, forDuration: 3.5)
        let episode = waitFor("item ep f2-2")
        sleep(6)
        snap(app, "hold-after-down")
        let eps = serverReports().filter { $0.hasPrefix("item ep") && $0 != "item ep -" }
        let positions = serverReports().filter { $0.hasPrefix("pos") }
        note("afterClick=\(playsAfterClick) afterHold=\(playsAfterHold) all=\(plays()) starts=\(startsAfterHold) streams=\(serverReports().filter { $0.hasPrefix("item ep") }) switches=\(switches) jumpsAfterClick=\(jumpsAfterClick) jumpsAfterHold=\(jumpsAfterHold) positions=\(positions) line=\(line) episode=\(episode) panelAfterHold=\(panelAfterHold) stillLoading=\(loading)")
        XCTAssertFalse(playsAfterClick.contains { $0.hasPrefix("play f2") }, "A short Right click switched the line: \(playsAfterClick)")
        XCTAssertTrue(line, "Holding Right did not go to the next line: \(serverReports())")
        XCTAssertEqual(playsAfterHold.filter { $0 == "play f2-1" }.count, 1, "The hold switched more than once: \(playsAfterHold)")
        XCTAssertEqual(Set(playsAfterHold).subtracting(playsAfterClick), ["play f2-1", "play f2-2"], "Something else was asked for during the hold: \(playsAfterClick) then \(playsAfterHold)")
        // The line switch goes on from where the first line was (about 14 s or more here), not from the start.
        let resumedAt = startsAfterHold.last.flatMap { Int($0.replacingOccurrences(of: "item start ", with: "")) } ?? -1
        XCTAssertEqual(startsAfterHold.count, 2, "Expected the first episode and the switched line to start: \(startsAfterHold)")
        XCTAssertGreaterThanOrEqual(resumedAt, 10, "The new line did not go on from the old position: \(startsAfterHold)")
        // "item switch <old line's last position> -> <new line's first position>": the old line goes on playing while the
        // new one loads, so the new one starts a little before where the old one ended, never after it.
        let numbers = switches.first.map { $0.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) } } ?? []
        XCTAssertEqual(numbers.count, 2, "No item switch was reported: \(switches)")
        if numbers.count == 2 { XCTAssertTrue(numbers[0] - numbers[1] >= 0 && numbers[0] - numbers[1] <= 6, "The new line did not start near the old position: \(switches)") }
        XCTAssertFalse(positions.isEmpty, "The position watch reported nothing, so a missing seek proves nothing")
        XCTAssertEqual(jumpsAfterHold, jumpsAfterClick, "The playback position jumped (a seek) during the hold: \(jumpsAfterClick) then \(jumpsAfterHold)")
        XCTAssertFalse(panelAfterHold, "The info panel opened on the hold")
        XCTAssertFalse(loading, "The new line is still getting ready, no picture")
        // Identity of what actually played, in order: episode 1 of line 1, the same episode on line 2 (the hold), then episode 2 of line 2 (Down hold).
        XCTAssertEqual(eps, ["item ep f1-1", "item ep f2-1", "item ep f2-2"], "The streams that played were not the expected ones, in order: \(eps)")
        XCTAssertTrue(episode, "Holding Down did not go to the next episode: \(serverReports())")
    }
    private func panel(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "线路乙")).firstMatch
    }

    /// Full screen, controls hidden, nothing pressed before: holding Down for 3 s goes to the next episode once, no Up first.
    func testRemoteDoubleDownWithHiddenControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "sites", "-qaPage", "play-source:qa-rc", "-qaVideoID", "rc3", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/rc-config.json", "-autoPlayNextEpisode", "NO",
                               "-qaPlayerReport", "http://127.0.0.1:8776",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        func has(_ text: String) -> Bool { serverReports().contains(text) }
        for _ in 0..<40 where !has("play f1-1") { sleep(1) }
        XCTAssertTrue(has("play f1-1"), "The first episode never started: \(serverReports())")
        sleep(12)
        snap(app, "down2-before")
        let before = serverReports()
        remote.press(.down, forDuration: 3.5)
        for _ in 0..<15 where serverReports().filter({ $0.hasPrefix("item ep") }).count < 2 { sleep(1) }
        sleep(6)
        snap(app, "down2-after")
        let after = serverReports()
        let restarts = after.filter { $0.hasPrefix("item start") }.count
        note("before=\(before) after=\(after) positionRestarts=\(restarts)")
        XCTAssertGreaterThanOrEqual(restarts, 2, "The player did not start another episode: \(after)")
        // Which streams played after the gesture: exactly episode 2 of the same line, nothing skipped, nothing twice.
        // An item with no play id (`item ep -`) was seen in a run before this one, at the old position; it is listed in the
        // note with its asset (`item asset`) and left out of the identity check, which covers the streams that carry an id.
        let epsAfter = Array(after.filter { $0.hasPrefix("item ep") && $0 != "item ep -" }.dropFirst(before.filter { $0.hasPrefix("item ep") }.count))
        let unnamed = after.filter { $0 == "item ep -" }.count
        XCTAssertLessThanOrEqual(unnamed, 1, "More than one stream without an id after the hold: \(after)")
        XCTAssertEqual(epsAfter, ["item ep f1-2"], "The streams played after the hold were not exactly the next episode: \(epsAfter) in \(after)")
        XCTAssertFalse(after.contains { $0.hasPrefix("seekjump") && !before.contains($0) }, "A seek happened: \(after)")
    }

    /// One episode on one line: double Right and double Down must do nothing (no request, the picture stays).
    func testRemoteDoubleClicksOnSingleEpisodeDoNothing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "sites", "-qaPage", "play-source:qa-rc", "-qaVideoID", "rc2", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/rc-config.json", "-autoPlayNextEpisode", "NO",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let remote = XCUIRemote.shared
        for _ in 0..<40 where !serverReports().contains("play l1-1") { sleep(1) }
        XCTAssertTrue(serverReports().contains("play l1-1"), "The episode never started: \(serverReports())")
        sleep(10)
        remote.press(.right); remote.press(.right); sleep(3)
        remote.press(.down, forDuration: 3.5); sleep(6)
        snap(app, "remote-single-after")
        note("single: reports=\(serverReports())")
        XCTAssertEqual(serverReports(), ["play l1-1"], "A double-click on a single episode asked for another stream")
        XCTAssertEqual(app.state, .runningForeground)
    }
    /// A refresh that fails keeps the last good copy: the page says why and still shows the Sources it holds.
    func testSubscriptionRefreshFailureKeepsOldData() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "settings", "-qaPage", "subscription:0", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/refresh-once-config.json",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let refresh = app.descendants(matching: .any)["subscription.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 30), "Refresh is not on the subscription page")
        let holds = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Sources: 1"))
        XCTAssertTrue(holds.firstMatch.waitForExistence(timeout: 30), "The page does not show the Sources the subscription holds before the refresh")
        snap(app, "refresh-fail-before")
        let remote = XCUIRemote.shared
        let focusedRefresh = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true AND label CONTAINS %@", "Refresh")).firstMatch
        var presses = 0
        remote.press(.right); sleep(1)
        while !focusedRefresh.exists && presses < 15 { remote.press(.down); presses += 1; sleep(1) }
        XCTAssertTrue(focusedRefresh.exists, "Refresh never took focus")
        let before = serverCounts()["/refresh-once-config.json"] ?? 0
        remote.press(.select)
        var after = before
        for _ in 0..<20 where after <= before { sleep(1); after = serverCounts()["/refresh-once-config.json"] ?? 0 }
        let failed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "refresh")).firstMatch
        _ = failed.waitForExistence(timeout: 20)
        sleep(2)
        snap(app, "refresh-fail-after")
        let labels = app.staticTexts.allElementsBoundByIndex.map { $0.label }.filter { $0.contains("Sources:") || $0.contains("refresh") }
        note("requests before=\(before) after=\(after); page texts=\(labels); reports=\(serverReports())")
        XCTAssertGreaterThan(after, before, "Refresh did not ask the subscription's address again")
        XCTAssertTrue(labels.contains { $0.contains("Couldn't refresh") }, "The page did not say the refresh failed: \(labels)")
        XCTAssertTrue(labels.contains { $0.contains("Sources: 1") }, "The failed refresh dropped the Sources the subscription held: \(labels)")
    }


    /// The subscription page's Refresh fetches that subscription again: the server sees its address asked for once more.
    func testSubscriptionRefreshButtonFetchesAgain() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "settings", "-qaPage", "subscription:0", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/fo-config.json",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let refresh = app.descendants(matching: .any)["subscription.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 30), "Refresh is not on the subscription page")
        let remote = XCUIRemote.shared
        // Focus opens in the sidebar here: move into the page first, then down to Refresh.
        let focusedRefresh = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true AND label CONTAINS %@", "Refresh")).firstMatch
        var presses = 0
        remote.press(.right); sleep(1)
        while !focusedRefresh.exists && presses < 15 { remote.press(.down); presses += 1; sleep(1) }
        snap(app, "subscription-refresh-focused")
        XCTAssertTrue(focusedRefresh.exists, "Refresh never took focus")
        let before = serverCounts()["/fo-config.json"] ?? 0
        remote.press(.select)
        var after = before
        for _ in 0..<20 where after <= before { sleep(1); after = serverCounts()["/fo-config.json"] ?? 0 }
        sleep(2)
        snap(app, "subscription-refresh-after")
        note("focused=\(focusedRefresh.exists) after \(presses) down presses; subscription address requests before=\(before) after=\(after)")
        XCTAssertGreaterThan(after, before, "Refresh did not ask the subscription's address again")
    }

    /// A dead first line falls through to the second line of the same source on its own: the fixture's first line
    /// points at a 404, so the server must see that address asked for and then the working clip, and a picture must show.
    func testDeadFirstLineSwitchesToSecondLine() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "sites", "-qaPage", "play-source:qa-fo", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/fo-config.json", "-autoPlayNextEpisode", "NO",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let waiting = app.descendants(matching: .any)["player.waiting"]
        _ = waiting.waitForExistence(timeout: 15)
        var seconds = 0
        for _ in 0..<60 where waiting.exists || seconds == 0 { sleep(1); seconds += 1 }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "after dead line"; shot.lifetime = .keepAlways; add(shot)
        var counts: [String: Int] = [:]
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:8776/counts")!) { data, _, _ in
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Int] { counts = json }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 10)
        add(XCTAttachment(string: "waited \(seconds)s; counts missing=\(counts["/missing.mp4"] ?? 0) clip=\(counts["/clip.mp4"] ?? 0) fo-plays=\(counts["/fo"] ?? 0)"))
        XCTAssertGreaterThan(counts["/missing.mp4"] ?? 0, 0, "The dead first line was never tried: \(counts)")
        XCTAssertGreaterThan(counts["/clip.mp4"] ?? 0, 0, "The second line was never asked for: \(counts)")
        XCTAssertFalse(waiting.exists, "The wait screen is still up after \(seconds)s: no picture on the second line")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// When the other line has two entries that could be episode 1, nothing is switched to: the viewer sees the error and
    /// chooses. The server must never be asked for the other line's clip.
    func testAmbiguousSecondLineDoesNotSwitch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-qaSection", "sites", "-qaPage", "play-source:qa-fo2", "-qaIsolatedData", "1",
                               "-qaSubscription", "http://127.0.0.1:8776/fo2-config.json", "-autoPlayNextEpisode", "NO",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let retry = app.buttons["Try Again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 40), "The error screen never showed")
        sleep(15)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "ambiguous second line"; shot.lifetime = .keepAlways; add(shot)
        var counts: [String: Int] = [:]
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:8776/counts")!) { data, _, _ in
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Int] { counts = json }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 10)
        add(XCTAttachment(string: "counts missing=\(counts["/missing.mp4"] ?? 0) clip=\(counts["/clip.mp4"] ?? 0)"))
        XCTAssertGreaterThan(counts["/missing.mp4"] ?? 0, 0, "The dead first line was never tried: \(counts)")
        XCTAssertEqual(counts["/clip.mp4"] ?? 0, 0, "A line was switched to although the episode could not be told for sure: \(counts)")
        XCTAssertTrue(retry.exists, "The error screen went away")
    }

    private func serverCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:8776/counts")!) { data, _, _ in
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Int] { counts = json }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 10)
        return counts
    }

    private func serverReports() -> [String] {
        var reports: [String] = []
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:8776/reports")!) { data, _, _ in
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String] { reports = json }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 10)
        return reports
    }

    /// A music extension added from an address (its download, start and check) shows its chart shelf on the Music page.
    func testMusicExtensionShelfShowsOnMusicPage() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "music", "-qaMusicExtension", "http://127.0.0.1:8776/music-ext.js"])
        let remote = XCUIRemote.shared
        let shelf = shown("测试榜单", in: app)
        var presses = 0
        _ = shelf.waitForExistence(timeout: 45)
        // Focus opens in the sidebar: step into the page first, then move down until the shelf title sits fully on screen.
        remote.press(.right); sleep(1)
        let screen = app.frame
        func onScreen() -> Bool { shelf.exists && shelf.frame.minX >= 0 && shelf.frame.minY >= 0 && shelf.frame.maxY <= screen.maxY - 40 && shelf.frame.maxX <= screen.maxX }
        while !onScreen() && presses < 24 { remote.press(.down); presses += 1; sleep(1) }
        sleep(1)
        snap(app, "music-extension-shelf-visible")
        snap(app, "music-extension-shelf-after-down")
        let ups = 0
        snap(app, "music-extension-shelf-after-up")
        note("extension script requests=\(serverCounts()["/music-ext.js"] ?? 0) shelf exists=\(shelf.exists) onScreen=\(onScreen()) frame=\(shelf.frame) screen=\(screen) after \(presses) down and \(ups) up presses; app reports: \(serverReports())")
        XCTAssertTrue(onScreen(), "The extension's shelf title never came fully on screen")
        XCTAssertGreaterThan(serverCounts()["/music-ext.js"] ?? 0, 0, "The extension was never downloaded")
        XCTAssertTrue(shelf.exists, "The extension's shelf is not on the Music page")
    }

    /// Searching Music finds the extension's song and playing it asks for the stream the extension gave.
    func testMusicExtensionSearchPlaysItsSong() throws {
        continueAfterFailure = true
        // The extension's song carries exactly the query as its title, so it is the direct hit auto play opens
        // (the built-in catalogs list nothing titled "ext晴天"); only the extension's getSongInfo answers with the local clip.
        let app = launch(["-qaSection", "music", "-qaMusicExtension", "http://127.0.0.1:8776/music-ext.js",
                          "-qaQuery", "ext晴天", "-qaMusicKind", "songs", "-qaMusicPlay", "1"])
        let hit = shown("ext晴天", in: app)
        _ = hit.waitForExistence(timeout: 60)
        snap(app, "music-extension-hit-listed")
        var waited = 0
        while (serverCounts()["/tone.wav"] ?? 0) == 0 && waited < 60 { sleep(1); waited += 1 }
        sleep(3)
        snap(app, "music-extension-search-play")
        let counts = serverCounts()
        note("song title shown=\(hit.exists); clip requests=\(counts["/tone.wav"] ?? 0) after \(waited)s; reports=\(serverReports())")
        XCTAssertTrue(hit.exists, "The extension's song is not shown")
        XCTAssertGreaterThan(counts["/tone.wav"] ?? 0, 0, "The extension's stream was never asked for: \(counts)")
    }

    /// The same search, but the song is chosen with the remote like a listener would (no auto play, no renamed shortcut):
    /// focus lands on the row of the extension's song (identified by its artist "QA Singer"), Select plays it, and the
    /// player's clock moves between two shots a few seconds apart.
    func testMusicExtensionSearchRemoteSelectPlays() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "music", "-qaMusicExtension", "http://127.0.0.1:8776/music-ext.js",
                          "-qaQuery", "ext晴天", "-qaMusicKind", "songs"])
        let remote = XCUIRemote.shared
        let row = shown("QA Singer", in: app)
        _ = row.waitForExistence(timeout: 60)
        sleep(2)
        let focusedRow = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true AND label CONTAINS %@", "QA Singer")).firstMatch
        snap(app, "remote-search-before-moves")
        var moves = 0
        remote.press(.right); sleep(1)
        // Right from the sidebar lands on the search button at the far right, and Down from there found nothing in the
        // earlier run (30 presses, focus never left it): Left goes to the kind chips, and Down then walks to the rows.
        let focusedNow = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let afterRight = focusedNow.exists ? "id=\(focusedNow.identifier) label=\(focusedNow.label)" : "none"
        remote.press(.left); sleep(1)
        let afterLeft = focusedNow.exists ? "id=\(focusedNow.identifier) label=\(focusedNow.label)" : "none"
        var trail: [String] = []
        func where_() -> String { focusedNow.exists ? "\(focusedNow.identifier)|\(focusedNow.label)" : "none" }
        while !focusedRow.exists && moves < 30 {
            remote.press(.down); moves += 1; sleep(1)
            if moves <= 6 { trail.append(where_()) }
            // Stuck on the search button: try the other ways out a listener has (Up, then Down again; Right then Left).
            if moves == 6 && !focusedRow.exists {
                remote.press(.up); sleep(1); trail.append("up:" + where_())
                remote.press(.down); sleep(1); trail.append("down2:" + where_())
                remote.press(.right); sleep(1); trail.append("right:" + where_())
                remote.press(.down); sleep(1); trail.append("down3:" + where_())
            }
        }
        note("focus trail: \(trail)")
        let focusedLabel = focusedRow.exists ? focusedRow.label : "none"
        snap(app, "remote-search-row-focused")
        let before = serverCounts()["/tone.wav"] ?? 0
        remote.press(.select)
        var waited = 0
        while (serverCounts()["/tone.wav"] ?? 0) <= before && waited < 40 { sleep(1); waited += 1 }
        func clocks() -> [String] {
            app.staticTexts.allElementsBoundByIndex.map { $0.label }.filter { $0.range(of: "^[0-9]+:[0-9][0-9]$", options: .regularExpression) != nil }
        }
        func playingIdentity() -> Bool {
            // The results list stays in the tree behind the player, so its labels prove nothing; what a failed song shows is
            // a "Skipped" notice, and a different song moving on shows a different elapsed clock only the pixel can name.
            // The player's own labels come before the sidebar's ("Watch Now"): the song it shows must be the extension's.
            let labels = app.staticTexts.allElementsBoundByIndex.map { $0.label }
            let player = Array(labels.prefix { $0 != "Watch Now" })
            return !labels.contains { $0.contains("Skipped") } && player.contains("ext晴天") && player.contains("QA Singer")
                && labels.contains { $0.range(of: "^00:[0-5][0-9]$", options: .regularExpression) != nil }
        }
        sleep(3)
        let first = clocks(); let identity1 = playingIdentity(); snap(app, "remote-search-play-1")
        sleep(6)
        let second = clocks(); let identity2 = playingIdentity(); snap(app, "remote-search-play-2")
        note("focus after Right: \(afterRight); after Left: \(afterLeft); focused row=\(focusedLabel) after \(moves) down presses; clip requests before=\(before) after=\(serverCounts()["/tone.wav"] ?? 0) (\(waited)s); clocks first=\(first) second=\(second); playing-ok=\(identity1)/\(identity2) labels2=\(app.staticTexts.allElementsBoundByIndex.map { $0.label }); reports=\(serverReports())")
        // Focus is read before Select (the row is gone once the player opens), identity of the playing track is read twice.
        XCTAssertTrue(focusedLabel.contains("QA Singer"), "The extension's row never took focus: \(focusedLabel)")
        XCTAssertGreaterThan(serverCounts()["/tone.wav"] ?? 0, before, "Selecting the extension's song did not ask for its stream")
        XCTAssertTrue(identity1, "The song was skipped or has no elapsed clock at the first shot")
        XCTAssertTrue(identity2, "The song was skipped or has no elapsed clock at the second shot")
        XCTAssertNotEqual(first, second, "The player's clock did not move: \(first) then \(second)")
    }

    // MARK: Apple TV parity checks (T1 to T3). They record what is on screen and where focus is, as screenshots and
    // attachments, and report each mismatch without stopping at the first one.

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = extra + ["-qaIsolatedData", "1", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }
    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways
        add(shot)
    }
    private func focusInfo(_ app: XCUIApplication) -> String {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        guard focused.exists else { return "none" }
        return "id=\(focused.identifier) label=\(focused.label)"
    }
    /// Focus opens either in the sidebar (no id, no label) or already in the content, depending on how the page's default
    /// focus settles: go in with Right only from the sidebar, as a user does, so a page already on its first item is not moved.
    private func enterContent(_ app: XCUIApplication) {
        sleep(2)
        let before = focusInfo(app)
        if before == "none" || before == "id= label=" { XCUIRemote.shared.press(.right); sleep(2) }
        note("enterContent: before=\(before) after=\(focusInfo(app))")
    }
    private func focusFrame(_ app: XCUIApplication) -> CGRect {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return focused.exists ? focused.frame : .zero
    }
    private func describe(_ element: XCUIElement) -> String {
        guard element.exists else { return "missing" }
        let f = element.frame
        return "enabled=\(element.isEnabled) hittable=\(element.isHittable) hasFocus=\(element.hasFocus) frame=(\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height)))"
    }
    /// Presses each direction in turn and records where focus went, so a missing path is visible as a trace.
    private func trace(_ app: XCUIApplication, _ target: XCUIElement, _ label: String) {
        let remote = XCUIRemote.shared
        var lines = ["\(label) target: \(describe(target))", "start: \(focusInfo(app))"]
        for (name, key) in [("up", XCUIRemote.Button.up), ("up", .up), ("up", .up), ("up", .up), ("up", .up), ("up", .up), ("up", .up), ("up", .up)] {
            remote.press(key); sleep(1)
            lines.append("\(name): \(focusInfo(app)) | target focus=\(target.hasFocus)")
            if target.hasFocus { break }
        }
        note(lines.joined(separator: "\n"))
    }
    private func note(_ text: String) {
        let item = XCTAttachment(string: text)
        item.name = "note"; item.lifetime = .keepAlways
        add(item)
    }

    /// The Sources page opens on its content, with no keyboard, and a magnifier that opens the search only when pressed.
    func testSourcesOpenOnContentAndMagnifierOpensSearch() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "sites", "-qaSubscription", "http://127.0.0.1:8776/config.json"])
        let entry = app.buttons["search.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 60), "The Sources page has no search magnifier")
        sleep(3)
        note("Sources initial focus: \(focusInfo(app)); keyboards=\(app.keyboards.count)")
        snap(app, "sources-initial")
        XCTAssertEqual(app.keyboards.count, 0, "The keyboard is up on opening the Sources page")
        XCTAssertFalse(entry.hasFocus, "The magnifier, not the first source, has the initial focus")
        let remote = XCUIRemote.shared
        // Into the content from the sidebar, as a user does: the first press of Right must land on the first source.
        remote.press(.right); sleep(2)
        note("after Right from the sidebar: \(focusInfo(app))")
        snap(app, "sources-content-focus")
        let firstSource = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Discover")).firstMatch
        XCTAssertTrue(focusInfo(app).contains("Discover") || firstSource.hasFocus, "Right from the sidebar did not land on the first source: \(focusInfo(app))")
        note("magnifier: \(describe(entry))")
        trace(app, entry, "sources")
        note("after Up: \(focusInfo(app))")
        snap(app, "sources-magnifier-focused")
        XCTAssertTrue(entry.hasFocus, "Up from the sources did not reach the magnifier")
        XCTAssertEqual(app.keyboards.count, 0, "Focus on the magnifier opened the keyboard")
        remote.press(.select); sleep(3)
        snap(app, "sources-search-open")
        note("after Select: keyboards=\(app.keyboards.count) searchFields=\(app.searchFields.count) focus=\(focusInfo(app))")
        XCTAssertTrue(app.keyboards.count > 0 || app.searchFields.count > 0, "Select on the magnifier did not open the search")
        remote.press(.menu); sleep(2)
        snap(app, "sources-after-back")
        note("after Menu: \(focusInfo(app)); entryExists=\(entry.exists)")
        XCTAssertTrue(entry.exists, "Back from the search did not return to the Sources page")
        XCTAssertEqual(app.keyboards.count, 0, "The keyboard stayed after Back")
    }

    /// Opening the Sources list with NO remote press: focus must settle on the first source by itself (not stay in the
    /// sidebar or on the magnifier), and nothing opens the keyboard.
    func testSourcesListFocusesFirstSourceWithoutAnyPress() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "sites", "-qaSubscription", "http://127.0.0.1:8776/config.json"])
        let entry = app.buttons["search.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 60), "The Sources page has no search magnifier")
        var trail: [String] = []
        var settled = false
        for second in 1...15 {
            sleep(1)
            let info = focusInfo(app)
            trail.append("\(second)s: \(info) frame=\(focusFrame(app))")
            if info.contains("Discover") { settled = true; break }
        }
        note("Sources list focus with no press: settled=\(settled); keyboards=\(app.keyboards.count); trail=\(trail)")
        snap(app, "sources-no-press")
        XCTAssertTrue(settled, "Focus never reached the first source without a press: \(trail.last ?? "")")
        XCTAssertFalse(entry.hasFocus, "The magnifier has the focus")
        XCTAssertEqual(app.keyboards.count, 0, "The keyboard is up on opening the Sources page")
    }

    /// Music has the same magnifier and no keyboard on opening.
    func testMusicOpensWithoutKeyboardAndHasMagnifier() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "music"])
        let entry = app.buttons["search.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 60), "The Music page has no search magnifier")
        sleep(5)
        note("Music initial focus: \(focusInfo(app)); keyboards=\(app.keyboards.count)")
        snap(app, "music-initial")
        XCTAssertEqual(app.keyboards.count, 0, "The keyboard is up on opening the Music page")
        // Focus opens in the sidebar, as on every page: into the content as a user does, with Right.
        note("Music focus before Right: \(focusInfo(app)) frame=\(focusFrame(app))")
        enterContent(app)
        snap(app, "music-after-right")
        let focus = focusInfo(app)
        let frame = focusFrame(app)
        let settings = app.buttons["music.settings"]
        note("Music initial focus frame=\(frame) settings=\(describe(settings))")
        XCTAssertFalse(focus.contains("Music Settings"), "Music opened with focus on Music Settings, not the first playlist: \(focus)")
        XCTAssertFalse(focus.hasPrefix("none"), "Music opened with nothing focused")
        XCTAssertTrue(focus.contains("id=music.firstCover"), "Focus is not the first playlist cover (id music.firstCover): \(focus)")
        XCTAssertFalse(focus.contains("See All") || focus.contains("watchnow.more"), "Music opened on a shelf's See All, not its first playlist cover: \(focus)")
        // The magnifier is reachable from the content with Up, Select opens the search, Menu returns to the page.
        let remote = XCUIRemote.shared
        for _ in 0..<4 where !entry.hasFocus { remote.press(.up); sleep(1) }
        snap(app, "music-magnifier-focused")
        XCTAssertTrue(entry.hasFocus, "Up from the first playlist did not reach the magnifier: \(focusInfo(app))")
        remote.press(.select); sleep(3)
        snap(app, "music-search-open")
        XCTAssertTrue(app.keyboards.count > 0 || app.searchFields.count > 0, "Select on the Music magnifier did not open the search")
        remote.press(.menu); sleep(2)
        snap(app, "music-after-back")
        XCTAssertTrue(entry.exists && app.keyboards.count == 0, "Back from the Music search did not return to the page")
        XCTAssertTrue(app.buttons["music.firstCover"].exists, "The Music page is not showing after Back")
        // Down from the magnifier returns to the content, and Back from the keyboard leaves the focus on the page.
        remote.press(.down); sleep(1)
        note("Music after Down from the magnifier: \(focusInfo(app))")
        XCTAssertFalse(entry.hasFocus, "Down did not leave the magnifier")
    }

    /// Apple TV's stand-in for "Add from File": the TV serves a page while its screen is open; a phone posts the script;
    /// nothing is added until Add is pressed on the TV. Uses the real HTTP path (no debug injection).
    func testMusicExtensionAddFromPhoneUpload() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "music", "-qaMusicSettings", "1"])
        XCTAssertTrue(shown("Music Settings", in: app).waitForExistence(timeout: 60), "Music Settings did not open")
        let remote = XCUIRemote.shared
        sleep(2)
        let row = shown("Add from Phone", in: app)
        var presses = 0
        while !(row.exists && row.hasFocus) && presses < 14 { remote.press(.down); presses += 1; sleep(1) }
        snap(app, "phone-add-row")
        XCTAssertTrue(row.hasFocus, "Add from Phone row never took focus")
        XCTAssertFalse(shown("QA Fake FM", in: app).exists, "The fixture extension was already present")
        remote.press(.select); sleep(2)
        let addressLabel = app.descendants(matching: .any)["ext.receiver.address"]
        XCTAssertTrue(addressLabel.waitForExistence(timeout: 20), "The receiver screen showed no address")
        sleep(2)
        snap(app, "phone-add-screen")
        let text = addressLabel.label
        let parts = text.replacingOccurrences(of: "http://", with: "").split(separator: "/").map(String.init)
        let hostPort = parts.first?.split(separator: ":").map(String.init) ?? []
        XCTAssertEqual(hostPort.count, 2, "Address not host:port: \(text)")
        let port = hostPort.last ?? "0", token = parts.count > 1 ? parts[1] : ""
        XCTAssertGreaterThanOrEqual(token.count, 32, "Token too short")
        let base = "http://127.0.0.1:\(port)"
        func http(_ url: String, method: String = "GET", body: Data? = nil) -> (Int, String) {
            var request = URLRequest(url: URL(string: url)!); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 20
            var out = (-1, "")
            let done = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: request) { data, response, error in
                out = ((response as? HTTPURLResponse)?.statusCode ?? -1, data.flatMap { String(data: $0, encoding: .utf8) } ?? (error?.localizedDescription ?? "")); done.signal()
            }.resume()
            _ = done.wait(timeout: .now() + 25)
            return out
        }
        let page = http("\(base)/\(token)")
        note("page status=\(page.0) hasForm=\(page.1.contains("type=\"file\""))")
        XCTAssertEqual(page.0, 200); XCTAssertTrue(page.1.contains("type=\"file\""), "The page has no file picker")
        XCTAssertEqual(http("\(base)/wrong-token").0, 404, "A wrong token was not refused")
        XCTAssertEqual(http("\(base)/\(token)", method: "POST", body: Data(count: 5_100_000)).0, 413, "An oversized upload was not refused")
        let script = http("http://127.0.0.1:8776/music-ext.js")
        XCTAssertEqual(script.0, 200, "Fixture script not served")
        XCTAssertFalse(shown("QA Fake FM", in: app).exists, "Added before any confirmation")
        let sent = http("\(base)/\(token)", method: "POST", body: Data(script.1.utf8))
        XCTAssertEqual(sent.0, 200, "Upload refused: \(sent.1)")
        XCTAssertTrue(app.descendants(matching: .any)["ext.receiver.pending"].waitForExistence(timeout: 15), "The TV did not ask to confirm")
        XCTAssertTrue(app.descendants(matching: .any)["ext.receiver.pending"].label.contains("QA Fake FM"), "Pending name is not the uploaded script's")
        snap(app, "phone-add-pending")
        XCTAssertEqual(http("\(base)/\(token)", method: "POST", body: Data(script.1.utf8)).0, 409, "A second upload was accepted while waiting")
        let accept = app.descendants(matching: .any)["ext.receiver.accept"]
        XCTAssertTrue(accept.exists, "No Add button")
        var tries = 0
        while !accept.hasFocus && tries < 6 { sleep(1); tries += 1 }
        XCTAssertTrue(accept.hasFocus, "Add did not take focus when the upload arrived")
        remote.press(.select); sleep(4)
        snap(app, "phone-add-after-accept")
        XCTAssertTrue(shown("QA Fake FM", in: app).waitForExistence(timeout: 20), "The accepted extension is not listed in Music Extensions")
        let closed = http("\(base)/\(token)")
        note("after close status=\(closed.0) \(closed.1)")
        XCTAssertEqual(closed.0, -1, "The receiver still answers after its screen closed")
    }

    /// Music Settings lists Music Extensions, with the address row (Apple TV adds by address, there is no file picker).
    func testMusicSettingsHasMusicExtensions() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "music", "-qaMusicSettings", "1"])
        XCTAssertTrue(shown("Music Settings", in: app).waitForExistence(timeout: 60), "Music Settings did not open")
        let remote = XCUIRemote.shared
        sleep(2)
        snap(app, "music-settings-top")
        for index in 0..<8 where !shown("Add from Address", in: app).exists { remote.press(.down); sleep(1); if index == 3 { snap(app, "music-settings-mid") } }
        snap(app, "music-settings-extensions")
        XCTAssertTrue(shown("Music Extensions", in: app).exists, "No Music Extensions section")
        XCTAssertTrue(shown("Add from Address", in: app).exists, "No Add from Address row in Music Extensions")
    }

    /// A source's page has its name with a down arrow; Select opens the subscription chips and that subscription's sources;
    /// choosing another source switches the page.
    func testSourcePageSwitchesSourceFromItsName() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "sites", "-qaPage", "site:qa-standard", "-qaSubscription", "http://127.0.0.1:8776/config.json"])
        XCTAssertTrue(shown("测试影片 01", in: app).waitForExistence(timeout: 60), "The source page did not load")
        let switcher = app.buttons["site.switcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10), "The source page has no switcher")
        let remote = XCUIRemote.shared
        snap(app, "source-page")
        XCTAssertEqual(app.keyboards.count, 0, "The source page opened with the keyboard")
        // Into the content from the sidebar as a user does: Right must land on the first poster.
        let firstPoster = shown("测试影片 01", in: app)
        enterContent(app)
        note("source page after Right: \(focusInfo(app)) firstPoster=\(describe(firstPoster))")
        snap(app, "source-page-content-focus")
        XCTAssertTrue(focusInfo(app).contains("site.firstPoster") || firstPoster.hasFocus, "Right did not land on the first poster: \(focusInfo(app))")
        XCTAssertFalse(app.buttons["search.entry"].hasFocus, "The source page opened on the magnifier")
        trace(app, switcher, "source page")
        note("switcher focus attempt: \(focusInfo(app))")
        XCTAssertTrue(switcher.hasFocus, "The remote did not reach the source name button")
        let before = switcher.value as? String ?? ""
        remote.press(.select); sleep(2)
        snap(app, "switcher-open")
        let groups = app.descendants(matching: .any)["site.switch.groups"]
        XCTAssertTrue(groups.exists, "The switch list has no subscription chips")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'site.switch.row.'"))
        note("switch rows=\(rows.count); focus=\(focusInfo(app)); current=\(before)")
        XCTAssertGreaterThan(rows.count, 1, "The switch list shows fewer than two sources")
        XCTAssertTrue(rows.matching(NSPredicate(format: "hasFocus == true")).count == 1, "Focus did not start on a source row")
        // Move to a different row and choose it.
        remote.press(.down); sleep(1)
        let picked = focusInfo(app)
        remote.press(.select); sleep(4)
        snap(app, "after-switch")
        note("picked \(picked); switcher now \(app.buttons["site.switcher"].value as? String ?? "?")")
        XCTAssertFalse(groups.exists, "The switch list stayed open after choosing")
        XCTAssertNotEqual(app.buttons["site.switcher"].value as? String ?? "", before, "The page did not switch to the chosen source")
    }

    /// With two subscriptions, the switcher's chips choose the subscription; its sources list changes; picking one switches the page.
    func testSourceSwitcherSwitchesAcrossSubscriptions() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "sites", "-qaPage", "site:qa-standard", "-qaSubscription", "http://127.0.0.1:8776/config.json",
                          "-qaSubscriptionExtra", "http://127.0.0.1:8776/stall-config.json"])
        XCTAssertTrue(shown("测试影片 01", in: app).waitForExistence(timeout: 60), "The source page did not load")
        let switcher = app.buttons["site.switcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10), "The source page has no switcher")
        let remote = XCUIRemote.shared
        enterContent(app)
        trace(app, switcher, "source page")
        XCTAssertTrue(switcher.hasFocus, "The remote did not reach the source name button")
        let before = switcher.value as? String ?? ""
        remote.press(.select); sleep(2)
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'site.switch.group.'"))
        note("chips=\(chips.count) before=\(before)")
        snap(app, "cross-open")
        XCTAssertGreaterThanOrEqual(chips.count, 2, "The switcher shows fewer than two subscription chips")
        XCTAssertFalse(app.buttons["site.switch.row.qa-stall"].exists, "The second subscription's source is listed before choosing its chip")
        var ups = 0
        while chips.matching(NSPredicate(format: "hasFocus == true")).count == 0 && ups < 8 { remote.press(.up); ups += 1; sleep(1) }
        XCTAssertEqual(chips.matching(NSPredicate(format: "hasFocus == true")).count, 1, "Focus never reached the chips: \(focusInfo(app))")
        for _ in 0..<3 where !app.buttons["site.switch.row.qa-stall"].exists {
            remote.press(.right); sleep(1); remote.press(.select); sleep(2)
        }
        snap(app, "cross-second-subscription")
        XCTAssertTrue(app.buttons["site.switch.row.qa-stall"].exists, "Choosing the second chip did not list its sources")
        XCTAssertFalse(app.buttons["site.switch.row.qa-standard"].exists, "The first subscription's source is still listed")
        let target = app.buttons["site.switch.row.qa-stall"]
        var downs = 0
        while !target.hasFocus && downs < 8 { remote.press(.down); downs += 1; sleep(1) }
        XCTAssertTrue(target.hasFocus, "Focus did not reach the second subscription's source: \(focusInfo(app))")
        remote.press(.select); sleep(5)
        snap(app, "cross-after-switch")
        let after = switcher.value as? String ?? ""
        note("switcher now \(after)")
        XCTAssertTrue(after.contains("详情卡住"), "The page did not switch to the second subscription's source: \(after)")
    }

    private func focusRow(_ element: XCUIElement, _ remote: XCUIRemote, limit: Int = 16) {
        var presses = 0
        while !element.hasFocus && presses < limit { remote.press(.down); presses += 1; sleep(1) }
    }

    /// The extension's shelf opens its playlist, which lists the extension's song.
    func testMusicExtensionShelfOpensPlaylistDetail() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "music", "-qaMusicExtension", "http://127.0.0.1:8776/music-ext.js"])
        let remote = XCUIRemote.shared
        let card = shown("Chart One", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 60), "The extension's playlist card is not on the Music page")
        remote.press(.right); sleep(1)
        focusRow(card, remote, limit: 24)
        snap(app, "ext-shelf-card-focus")
        XCTAssertTrue(card.hasFocus, "The playlist card never took focus: \(focusInfo(app))")
        remote.press(.select); sleep(4)
        snap(app, "ext-playlist-detail")
        XCTAssertTrue(shown("Chart Song One", in: app).waitForExistence(timeout: 20), "The playlist detail does not list the extension's song")
    }

    /// Turning the extension off in Music Settings removes its shelf from the Music page without a restart.
    func testMusicExtensionToggleOffRemovesShelf() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "music", "-qaMusicExtension", "http://127.0.0.1:8776/music-ext.js", "-qaMusicSettings", "1"])
        XCTAssertTrue(shown("Music Settings", in: app).waitForExistence(timeout: 60), "Music Settings did not open")
        let remote = XCUIRemote.shared
        sleep(3)
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'QA Fake FM' AND NOT label BEGINSWITH 'Remove'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The extension is not listed in Music Settings")
        focusRow(row, remote)
        XCTAssertTrue(row.hasFocus, "The extension row never took focus: \(focusInfo(app))")
        snap(app, "toggle-before")
        remote.press(.select); sleep(2)
        snap(app, "toggle-after")
        note("row after toggle: label=\(row.label) value=\(String(describing: row.value))")
        remote.press(.menu); sleep(4)
        snap(app, "toggle-music-page")
        // A negative needs a loaded page: the built-in shelf below must be in the hierarchy, as the extension's shelf was in the positive test.
        XCTAssertTrue(shown("More Charts", in: app).waitForExistence(timeout: 20), "The Music page did not reload, so the missing shelf proves nothing")
        XCTAssertFalse(shown("测试榜单", in: app).exists, "The extension's shelf is still on the Music page after turning it off")
    }

    /// Control for the two negative checks: closing Music Settings without a change keeps the shelf, found by the same query.
    func testMusicExtensionShelfSurvivesClosingSettings() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "music", "-qaMusicExtension", "http://127.0.0.1:8776/music-ext.js", "-qaMusicSettings", "1"])
        XCTAssertTrue(shown("Music Settings", in: app).waitForExistence(timeout: 60), "Music Settings did not open")
        sleep(3)
        XCUIRemote.shared.press(.menu); sleep(4)
        snap(app, "control-music-page")
        XCTAssertTrue(shown("More Charts", in: app).waitForExistence(timeout: 20), "The Music page did not reload")
        XCTAssertTrue(shown("测试榜单", in: app).exists, "The query cannot see the extension's shelf from the top of the Music page")
    }

    /// Removing the extension in Music Settings takes it out of the list and off the Music page.
    func testMusicExtensionRemoveDropsShelf() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "music", "-qaMusicExtension", "http://127.0.0.1:8776/music-ext.js", "-qaMusicSettings", "1"])
        XCTAssertTrue(shown("Music Settings", in: app).waitForExistence(timeout: 60), "Music Settings did not open")
        let remote = XCUIRemote.shared
        sleep(3)
        let remove = shown("Remove “QA Fake FM”", in: app)
        XCTAssertTrue(remove.waitForExistence(timeout: 20), "No Remove row for the extension")
        focusRow(remove, remote)
        XCTAssertTrue(remove.hasFocus, "The Remove row never took focus: \(focusInfo(app))")
        remote.press(.select); sleep(2)
        snap(app, "remove-after")
        XCTAssertFalse(shown("QA Fake FM", in: app).exists, "The extension is still listed after Remove")
        remote.press(.menu); sleep(4)
        snap(app, "remove-music-page")
        XCTAssertTrue(shown("More Charts", in: app).waitForExistence(timeout: 20), "The Music page did not reload, so the missing shelf proves nothing")
        XCTAssertFalse(shown("测试榜单", in: app).exists, "The extension's shelf is still on the Music page after removing it")
    }

    /// The extension's album shelf opens an album and its artist shelf opens a playlist (an artist maps to the playlist kind in the
    /// shared catalog code, the same on iOS), each listing the extension's own song.
    func testMusicExtensionAlbumAndArtistShelvesOpenDetail() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "music", "-qaMusicExtension", "http://127.0.0.1:8776/music-ext.js"])
        let remote = XCUIRemote.shared
        let album = shown("QA Album One", in: app)
        XCTAssertTrue(album.waitForExistence(timeout: 60), "The extension's album card is not on the Music page")
        remote.press(.right); sleep(1)
        focusRow(album, remote, limit: 30)
        XCTAssertTrue(album.hasFocus, "The album card never took focus: \(focusInfo(app))")
        snap(app, "ext-album-card-focus")
        remote.press(.select); sleep(4)
        snap(app, "ext-album-detail")
        XCTAssertTrue(shown("Album Song One", in: app).waitForExistence(timeout: 20), "The album's page does not list the extension's song")
        remote.press(.menu); sleep(4)
        let artist = shown("QA Artist One", in: app)
        XCTAssertTrue(artist.waitForExistence(timeout: 20), "The artist card is gone after Back")
        focusRow(artist, remote, limit: 30)
        XCTAssertTrue(artist.hasFocus, "The artist card never took focus: \(focusInfo(app))")
        snap(app, "ext-artist-card-focus")
        remote.press(.select); sleep(4)
        snap(app, "ext-artist-detail")
        XCTAssertTrue(shown("Artist Song One", in: app).waitForExistence(timeout: 20), "The artist's page does not list the extension's song")
    }

    /// Search with the extension on (the control for the two checks after it): the extension's song for the query is listed beside the built-in channels' results.
    func testMusicExtensionSearchListsItsSongWhenEnabled() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "music", "-qaMusicExtension", "http://127.0.0.1:8776/music-ext.js", "-qaMusicSettings", "1", "-qaQueryAfterSettings", "晴天"])
        XCTAssertTrue(shown("Music Settings", in: app).waitForExistence(timeout: 60), "Music Settings did not open")
        sleep(3)
        XCUIRemote.shared.press(.menu); sleep(4)
        let builtIn = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '晴天' AND NOT label CONTAINS 'QA Singer'")).firstMatch
        XCTAssertTrue(builtIn.waitForExistence(timeout: 60), "The built-in channels listed nothing for the query")
        sleep(3)
        snap(app, "search-enabled")
        XCTAssertTrue(shown("QA Singer", in: app).exists, "The extension's song is not in the search results")
    }

    /// Turning the extension off, then searching: its song is not listed, while the built-in results are.
    func testMusicExtensionSearchWithoutItsSongAfterToggleOff() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "music", "-qaMusicExtension", "http://127.0.0.1:8776/music-ext.js", "-qaMusicSettings", "1", "-qaQueryAfterSettings", "晴天"])
        XCTAssertTrue(shown("Music Settings", in: app).waitForExistence(timeout: 60), "Music Settings did not open")
        let remote = XCUIRemote.shared
        sleep(3)
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'QA Fake FM' AND NOT label BEGINSWITH 'Remove'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The extension is not listed in Music Settings")
        focusRow(row, remote)
        XCTAssertTrue(row.hasFocus, "The extension row never took focus: \(focusInfo(app))")
        remote.press(.select); sleep(2)
        note("row after toggle: \(row.label)")
        remote.press(.menu); sleep(4)
        let builtIn = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '晴天' AND NOT label CONTAINS 'QA Singer'")).firstMatch
        XCTAssertTrue(builtIn.waitForExistence(timeout: 60), "The built-in channels listed nothing, so a missing extension song proves nothing")
        sleep(3)
        snap(app, "search-after-toggle-off")
        XCTAssertFalse(shown("QA Singer", in: app).exists, "The extension's song is still in the search results after turning it off")
    }

    /// Removing the extension, then searching: its song is not listed, while the built-in results are.
    func testMusicExtensionSearchWithoutItsSongAfterRemove() throws {
        continueAfterFailure = true
        let app = launch(["-qaSection", "music", "-qaMusicExtension", "http://127.0.0.1:8776/music-ext.js", "-qaMusicSettings", "1", "-qaQueryAfterSettings", "晴天"])
        XCTAssertTrue(shown("Music Settings", in: app).waitForExistence(timeout: 60), "Music Settings did not open")
        let remote = XCUIRemote.shared
        sleep(3)
        let remove = shown("Remove “QA Fake FM”", in: app)
        XCTAssertTrue(remove.waitForExistence(timeout: 20), "No Remove row for the extension")
        focusRow(remove, remote)
        XCTAssertTrue(remove.hasFocus, "The Remove row never took focus: \(focusInfo(app))")
        remote.press(.select); sleep(2)
        remote.press(.menu); sleep(4)
        let builtIn = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '晴天' AND NOT label CONTAINS 'QA Singer'")).firstMatch
        XCTAssertTrue(builtIn.waitForExistence(timeout: 60), "The built-in channels listed nothing, so a missing extension song proves nothing")
        sleep(3)
        snap(app, "search-after-remove")
        XCTAssertFalse(shown("QA Singer", in: app).exists, "The extension's song is still in the search results after removing it")
    }

    /// Poster titles are part of their card's label, so look for the text anywhere in a label.
    private func shown(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
#endif
