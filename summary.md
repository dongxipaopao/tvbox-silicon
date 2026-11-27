# Test summary (iOS run 45915699483, inspect run 45917868531)

retry runs passed: 13  failed: 4

## failed test lines (retry)
✘ Test builtInMusicShipsAndOnlyFillsInForSubscriptionsWithoutMusic() failed after 0.010 seconds with 1 issue.
✘ Test pluginFailuresExplainTheReasonAndKeepTheTrace() failed after 0.018 seconds with 1 issue.
✘ Test publishedFeedIsValidAndTranslated() failed after 0.013 seconds with 1 issue.
✘ Test recommendedSourcesRequireAnExplicitSubscription() failed after 0.021 seconds with 1 issue.

## issues (retry)
✘ Test builtInMusicShipsAndOnlyFillsInForSubscriptionsWithoutMusic() recorded an issue at MusicTests.swift:774:2: Caught error: .invalidConfiguration
✘ Test pluginFailuresExplainTheReasonAndKeepTheTrace() recorded an issue at LocalizationTests.swift:57:5: Expectation failed: PluginFailure.message(screen, language: "zh-Hans") == "此条目会打开来源自带的设置或登录界面（例如二维码），映匣无法显示。请改在“设置 → 网盘账号”中登录。"
✘ Test publishedFeedIsValidAndTranslated() recorded an issue at ReleaseFeedTests.swift:111:5: Expectation failed: builds.first == projectBuild
✘ Test recommendedSourcesRequireAnExplicitSubscription() recorded an issue at DashStreamsTests.swift:41:9: Expectation failed: CloudMusic.current == nil

## full run failing tests
✘ Test aFailedQQSongIsLookedUpOnNetEase() failed after 20.590 seconds with 1 issue.
✘ Test aJumpReadsTheChunkThereInPieces() failed after 23.220 seconds with 1 issue.
✘ Test abandonedRunningWorkTellsTheHostItsRequestID() failed after 22.207 seconds with 1 issue.
✘ Test blockedPrimaryFallsBackAndCoolsDown() failed after 20.612 seconds with 1 issue.
✘ Test builtInMusicShipsAndOnlyFillsInForSubscriptionsWithoutMusic() failed after 19.184 seconds with 1 issue.
✘ Test dandanplayIsAskedOnlyWhenTheOtherProvidersFindNothing() failed after 22.287 seconds with 1 issue.
✘ Test endsByTheDeadlineWhateverIsOut() failed after 19.990 seconds with 1 issue.
✘ Test expiredRunningWorkAsksTheHostToStopIt() failed after 20.071 seconds with 1 issue.
✘ Test lossyPreferencesAskChannelsForLossyAudioAndNeverCallItDegraded() failed after 22.552 seconds with 2 issues.
✘ Test pluginFailuresExplainTheReasonAndKeepTheTrace() failed after 0.543 seconds with 1 issue.
✘ Test previewsAndFalseQualityLabelsAreRejected() failed after 22.149 seconds with 1 issue.
✘ Test publishedFeedIsValidAndTranslated() failed after 2.942 seconds with 1 issue.
✘ Test recommendedSourcesRequireAnExplicitSubscription() failed after 19.072 seconds with 1 issue.
✘ Test run with 986 tests in 48 suites failed after 39.618 seconds with 18 issues.
✘ Test scriptRequestsRaceAStalledOrFailedConnection() failed after 22.131 seconds with 1 issue.
✘ Test searchTimeLimitComesFromTheSetting() failed after 19.990 seconds with 1 issue.
✘ Test supersededCatalogRequestCancelsItsFetch() failed after 20.718 seconds with 1 issue.
✘ Test theBudgetBoundsSlowChannels() failed after 22.320 seconds with 1 issue.

## full run verdict
✘ Test run with 986 tests in 48 suites failed after 39.618 seconds with 18 issues.
