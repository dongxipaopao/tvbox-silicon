# The playback library

Catalog videos now retain their last episode and playback position. Watch Now
offers a Continue Watching section, and Playback History supports search,
individual removal and bulk removal. Resume resolves the saved episode through
its source again before seeking, rather than persisting the resolved media URL.
Episode identity uses subscription origin, source, title ID, line and episode
name so reordering a source's episode list cannot silently resume another episode.

On iOS and macOS, Playback Options also offers episode selection, automatic next
episode playback and intro/outro settings. Times belong to one title across its
episodes; automatic skipping has a global enable switch. The outro is stored as
time remaining. Invalid durations, overly long segments and overlapping settings
are rejected, and each segment is skipped once per play-through. Loop playback
takes precedence over automatic next episode. tvOS keeps its native transport
menus; history resume and automatic next use the same session.

With automatic next on, the next episode is resolved 30 seconds before the
episode (or its skipped outro) ends and queued behind it in the player's
`AVQueuePlayer`, so it loads while this one finishes and plays straight on: no
waiting screen, no new player. The session then takes the queued episode over
(history and intro/outro times) and the store makes it the playing one.
The Next Episode button plays a queued episode the same way. Streams that pass
through a plugin's proxy and MKV originals are never queued, and a queued item
that fails is dropped; those episodes switch the old way when one ends. On iOS
and tvOS the player's cover keeps one identity across episodes; keyed by the
channel, it would be dismissed and presented again for every episode.

## Disposable cache

The on-disk cache is bounded to 256 MiB, with an 8 MiB limit per entry. Artwork
expires after 30 days and catalog detail after 6 hours. Successful title-to-track mappings expire after 30 days and are limited
to the latest 20 works. Negative results last 5 minutes; provider failures last
30 seconds. Explicit retry removes the episode's cached result.

History titles and their artwork take eviction priority over other content.
After the current track loads, only the next episode on the same line is
prefetched. Prefetching is cancelled when playback changes. Cache generation tickets prevent an in-flight response from restoring
content that was deleted in the meantime.

Deleting a history title removes its catalog detail, artwork
and intro/outro times. Shared recent work mappings remain bounded independently.
Settings → Local Cache reports usage and clears all disposable data while keeping
history, subscriptions, pins and skip settings. The cache contains metadata, not downloaded video. Cached source metadata can include source
episode addresses; resume refreshes direct-file APIs and re-resolves plugin/API
playback, retrying with fresh detail when a cached episode fails.

Sources can be pinned from a source page or its context menu. Multiple pinned
sources appear on Watch Now and lead source browsing. Pins are
scoped to the subscription, so switching subscriptions cannot pin an unrelated
source with the same key.

## Validation

Run `swift test` and `python3 Scripts/check-localizations.py` for core behavior
and four-language completeness. `Scripts/test-library-ui.sh <iPad simulator UUID>`
creates a separate simulator application and local deterministic HTTP fixture;
its JAR bridge deliberately returns unavailable and is never installed on a
physical device. UI cases cover automatic comments, silent absence/failure,
next-episode playback, per-series skip isolation, history deletion, cache
clearing and persistent home pins. They do not exercise public provider uptime,
Java plugins or Bilibili account/casting interactions.
