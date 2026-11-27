# Sourced by 3-simulator-shots.yml for scenes that live in the repo (so they change through apply-change,
# not the web editor). Uses the workflow's own shot function. Offline fixtures only: no real network in CI.
case "${SCENES:-}" in
  rex)
    # The removal of Danmaku, Sharper Picture and Smooth Motion, and the three kept app icons (B76/B77).
    shot 27a-settings-root-zh 20 -qaSection settings -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    shot 27b-settings-playback-zh 20 -qaSection settings -qaPage playback -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    shot 27c-settings-app-icon-zh 20 -qaSection settings -qaPage app-icon -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    shot 27d-settings-cache-zh 20 -qaSection settings -qaPage cache -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    # Discover after the Rex removal (B78): no Rex row.
    shot 27e-discover-no-rex-zh 35 -qaSection discover -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    # Settings opened by a launch argument at the Cloud Drive Accounts row (automatic scroll, not a touch): the Rex import row that used to follow is gone (B78).
    shot 27f-settings-no-rex-import-zh 25 -qaSection settings -qaScrollTo 'settings.search cloudDrive' -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
    ;;
esac
