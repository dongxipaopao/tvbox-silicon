# Sourced by 3-simulator-shots.yml for scenes that live in the repo (so they change through apply-change,
# not the web editor). Uses the workflow's own shot function. Offline fixtures only: no real network in CI.
case "${SCENES:-}" in
  rex)
    shot 25a-rex-row 25 -qaSection discover -qaRexFixture 1 -qaRexRow 1
    shot 25b-rex-module 30 -qaSection discover -qaRexFixture 1 -qaRexRow 1 -qaRexOpen 1
    shot 25c-rex-unsupported 30 -qaSection discover -qaRexFixture 1 -qaRexRow 1 -qaRexOpen fixture.html
    shot 25d-rex-row-zh 25 -qaSection discover -qaRexFixture 1 -qaRexRow 1 -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    shot 25e-rex-unsupported-zh 30 -qaSection discover -qaRexFixture 1 -qaRexRow 1 -qaRexOpen fixture.html -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    shot 25f-rex-module-zh 30 -qaSection discover -qaRexFixture 1 -qaRexRow 1 -qaRexOpen 1 -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    # Stream module (B72/B73). Lines are asked for by a state hook; none of these is a real tap.
    shot 26a-stream-lines 30 -qaSection discover -qaRexFixture 1 -qaRexRow 1 -qaRexOpen fixture.stream -qaRexLines 1 -qaRexItem fx-ok
    shot 26b-stream-lines-zh 30 -qaSection discover -qaRexFixture 1 -qaRexRow 1 -qaRexOpen fixture.stream -qaRexLines 1 -qaRexItem fx-ok -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    shot 26c-stream-none-zh 30 -qaSection discover -qaRexFixture 1 -qaRexRow 1 -qaRexOpen fixture.stream -qaRexLines 1 -qaRexItem fx-none -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    shot 26d-stream-fail-zh 30 -qaSection discover -qaRexFixture 1 -qaRexRow 1 -qaRexOpen fixture.stream -qaRexLines 1 -qaRexItem fx-fail -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    shot 26e-stream-shape-zh 30 -qaSection discover -qaRexFixture 1 -qaRexRow 1 -qaRexOpen fixture.stream -qaRexLines 1 -qaRexItem fx-shape -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    shot 26f-stream-episode-cleared-zh 40 -qaSection discover -qaRexFixture 1 -qaRexRow 1 -qaRexOpen fixture.stream -qaRexLines 1 -qaRexItem fx-ok -qaRexEpisodeAfter 2 -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    shot 26g-stream-tap-player 40 -qaSection discover -qaRexFixture 1 -qaRexRow 1 -qaRexOpen fixture.stream -qaRexLines 1 -qaRexItem fx-ok -qaRexTap 1
    # 26g showed Discover, not a player, at 40 s: earlier shots to see whether the player opened and closed (example.invalid line, so an error state is expected).
    shot 26h-stream-tap-player-early 14 -qaSection discover -qaRexFixture 1 -qaRexRow 1 -qaRexOpen fixture.stream -qaRexLines 1 -qaRexItem fx-ok -qaRexTap 1
    shot 26i-stream-tap-player-mid 22 -qaSection discover -qaRexFixture 1 -qaRexRow 1 -qaRexOpen fixture.stream -qaRexLines 1 -qaRexItem fx-ok -qaRexTap 1
    # The removal of Danmaku, Sharper Picture and Smooth Motion, and the three kept app icons (B76/B77).
    shot 27a-settings-root-zh 20 -qaSection settings -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    shot 27b-settings-playback-zh 20 -qaSection settings -qaPage playback -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    shot 27c-settings-app-icon-zh 20 -qaSection settings -qaPage app-icon -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    shot 27d-settings-cache-zh 20 -qaSection settings -qaPage cache -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    # Discover with no Rex module imported (no fixture, no pin): where the Rex row and its import button sit by themselves (B79).
    shot 27e-discover-no-rex-zh 35 -qaSection discover -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    # Settings opened by a launch argument at the Cloud Drive Accounts row (automatic scroll, not a touch); the Rex import row is the next one (B79).
    # Offline fixture imported through the real store path, no -qaRexRow pin; Discover is scrolled to the Rex row automatically (not a touch).
    shot 27g-discover-rex-after-import-zh 40 -qaSection discover -qaRexFixture 1 -qaScroll rex -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    shot 27f-settings-rex-import-zh 25 -qaSection settings -qaScrollTo 'settings.search cloudDrive' -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    ;;
esac
