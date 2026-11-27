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
    ;;
esac
