# Kara Pitch for Apple TV — Development Plan

## Context
`SPEC.md` describes a tvOS port of the Fire TV karaoke app in `../yt-kara-pitch`. It plays YouTube
videos at ±6 semitones, holds a LAN queue that phones fill through a web UI and HTTP API on :8080,
and offers Siri Remote search. The repo is empty apart from `SPEC.md`, which is uncommitted. The
spec gates all UI work on Spike 0 (pitch shift on the device). Reading the dependency code shows
an even earlier gate: whether `SmartTubeIOSCore` can provide **direct, non-HLS MP4 URLs** at all.

### Findings that shape the plan
- **The Android app** (`../yt-kara-pitch/app/src/main/java/dev/ytkara/`) is small and maps
  one-to-one onto the spec's Swift modules: `queue/QueueRepository.kt` → `QueueStore`,
  `KaraSession.kt` → `KaraSession`, `player/KaraPlayer.kt` + `player/Key.kt` → `Player/`,
  `extract/StreamResolver.kt` / `SearchService.kt` / `YouTubeUrls.kt` → `YouTube/`,
  `server/KaraServer.kt` (Ktor) → `Server/`, `ui/*.kt` → `UI/`, `net/LocalAddress.kt` →
  `getifaddrs`. The tests in `app/src/test/.../{KeyTest, YouTubeUrlsTest, SearchServiceTest,
  QueueRepositoryTest}.kt` are the cases to port. Web assets: `app/src/main/assets/web/*`.
- **SmartTubeIOSCore** (`../SmartTubeIOS/SmartTubeIOS`, product `SmartTubeIOSCore`, tvOS 17,
  Swift 6):
  - `public actor InnerTubeAPI` (`InnerTubeAPI.swift:21`, `init(authToken:poTokenProvider:)`)
    has `fetchPlayerInfo{,Android,AndroidVR,VisionOS,TVEmbedded,...}` in
    `InnerTubeAPI+Player.swift` and `search(...)` in `InnerTubeAPI+Browse.swift:130`.
  - `PlayerInfo` (`InnerTubeModels.swift:89`) already has `bestAdaptiveVideoURL`,
    `bestAdaptiveAudioURL` and `bestMuxedDownloadURL`. They pick by bitrate only, though, so
    they don't filter for `avc1` or cap at 1080p. We need our own picker over `formats`.
  - **Gap:** `VideoFormat` (`VideoGroup.swift:188`) has no `itag`, no audio-track or
    original-language flag, and no content length. Picking the original-language audio and an
    itag-18 fallback by itag needs either a small upstream addition or a filter on
    mimeType/height (itag 18 = muxed `avc1+mp4a` at 360p, which the mimeType check covers).
  - **Risk:** per the source comments, several clients now return only HLS or SABR. Formats
    whose `signatureCipher` can't be decoded have `url == nil`. The n-param descrambler lives in
    the UI target and only runs in the Simulator. Clients that need neither (AndroidVR,
    VisionOS, Android) are the candidates.
  - The package declares a Firebase dependency at package level. SPM will **fetch** it even
    though only `SmartTubeIOSCore` gets linked. That's acceptable, but expect a slow first
    resolve.

## Phase 0 — Repo scaffolding (½ day)
- Commit `SPEC.md`. Add an Xcode-style `.gitignore` and a GPL-3.0 `LICENSE`.
- Create the `KaraPitchTV` Xcode project: tvOS 17 app, SwiftUI, Swift 6 language mode,
  strict concurrency complete, bundle ID `dev.ytkara.tv.<you>`, plus a `KaraPitchTVTests` target
  using Swift Testing.
- Add `SmartTubeIOSCore` as a **local package** (`../SmartTubeIOS/SmartTubeIOS`) for
  development. Switch to a git dependency pinned to a commit after Spike 0 (spec §12).
- Lay out the folder skeleton from spec §8. Add `os.Logger` with subsystem `dev.ytkara.tv`.

## Phase 1a — Stream probe (new step, before Spike 0, can run on the Mac)
Goal: prove that a no-PoToken client gives direct `avc1` and `mp4a` URLs, without hardware.
- Add `YouTube/StreamResolver.swift` with a client chain of AndroidVR → VisionOS → iOS →
  TVEmbedded → Android. For each client, call `fetchPlayerInfo*` and keep only formats with a
  `url`, that aren't HLS, with an `avc1` video-only stream ≤1080p and an `mp4a` audio-only
  stream. Fall back to muxed `avc1, mp4a`. Return `Streams(videoURL, audioURL?, client,
  description)`.
- Add a **debug probe screen** (or a test that only runs with an env flag) that runs the chain
  on ~10 karaoke video IDs and logs, for each client, the formats returned, whether the URLs
  respond to a ranged `GET` (bytes=0-1023 → 206), and the UA used.
- Exit criterion: at least one client returns usable direct URLs for most test videos. **If none
  does, stop and revisit**: options are the spec §12 last resort, or adding an n-descrambler on
  JavaScriptCore (which is available on tvOS) upstream.

## Phase 1b — Spike 0: pitch shift on the Apple TV (spec §4)
- `Player/Key.swift`: clamp ±6, `cents(s) = 100*s`, `ratio(s) = 2^(s/12)`, plus labels. Port
  `KeyTest.kt`.
- **Approach A** `Player/PitchTap.swift`: build an `AVMutableComposition` from two
  `AVURLAsset`s (video + audio) and attach an `AVMutableAudioMix` with an
  `MTAudioProcessingTap`. The tap's prepare callback instantiates
  `kAudioUnitSubType_NewTimePitch`, and the process callback pulls source audio through the AU
  render callback. Pitch comes from an atomic (`Synchronization.Atomic<Int32>`) and is applied
  without allocating. If the spike needs it, pass a custom UA through
  `AVURLAssetHTTPUserAgentKey` / `"AVURLAssetHTTPHeaderFieldsKey"`.
- A minimal `SpikeView`: plays a hard-coded video ID full-screen, uses up/down for the key and
  left/right for ±10 s, and shows a debug HUD with key, position, the A/V offset estimate and
  the CPU load.
- Run the five acceptance checks in spec §4 on the device. If A fails, build **Approach B**
  (`Player/SyncedAudioEngine.swift`: download the M4A, then `AVAudioPlayerNode` →
  `AVAudioUnitTimePitch`, with the audio clock driving `AVPlayer.setRate(_:time:atHostTime:)`).
- Write `docs/adr/0001-pitch-shift.md` recording the outcome, the working client and the
  measured numbers. Pin the SmartTubeIOS commit.

## Phase 2 — Playback and queue (milestone 2)
- `Queue/QueueEntry.swift`, `VideoMeta`, and `YouTubeURL.swift`, a port of `YouTubeUrls.kt`
  (check `URLVideoResolver` first and keep the port only if it differs). Port
  `YouTubeUrlsTest.kt`.
- `Queue/QueueStore.swift`: an actor that ports `QueueRepository.kt` rule for rule. It covers
  the 200-entry cap, the 40-character singer trim, key clamping, RESOLVING → READY/ERROR,
  removal during a resolve, `version`, `move` clamping, `startNext`/`finishNowPlaying`/
  `requeueNowPlaying`, and an `added: AsyncStream<QueueEntry>` (one per READY). Port
  `QueueRepositoryTest.kt`.
- `Player/KaraPlayer.swift` (`@MainActor @Observable`): `play(streams:startKey:startAt:) async ->
  Outcome` (ended, skipped, released, or error with HTTP code and position), plus `setKey`,
  `adjustKey`, `togglePause`, `seekBy`, `skip`, `release` and a `snapshot` for `/api/state`.
  Mirrors `KaraPlayer.kt`.
- `Session/KaraSession.swift`: the idle → upNext (5 s count-in that follows the queue live) →
  playing loop. It retries once on 403/410 and resumes at the same position and key, skips with
  a notice on failure, keeps `recentSingers`, and posts notices. A port of `KaraSession.kt`.
- `App/`: `scenePhase` ≠ `.active` → release the player and `requeueNowPlaying()`. Set
  `isIdleTimerDisabled` while the app is in front.
- `UI/PlayerView.swift`: a `UIViewController` that hosts `AVPlayerLayer` and handles
  `pressesBegan/Ended` (clicks, hold right ~1 s → skip, Select/PlayPause, double Back within
  3 s), a `UISwipeGestureRecognizer(.down)`, and `onMoveCommand` for the 1st-gen remote.
  Plus a plain `IdleView`.

## Phase 3 — Server and web UI (milestone 3)
- `Server/HTTPServer.swift`: `NWListener` on TCP 8080. Per connection: read until `\r\n\r\n`,
  parse the request line and headers, read `Content-Length` bytes, respond, close. Make the
  parser a pure function so it can be tested.
- `Server/Router.swift` + `API.swift`: `Codable` DTOs with the **same JSON names** as the Kotlin
  data classes in `KaraServer.kt` (`AddRequest`, `UpdateRequest`, `MoveRequest`,
  `StateResponse`, `UpNextDto`, `ErrorResponse`, `SearchResponse`). Covers every route and
  status code in Android SPEC §4.7, including `since` → 304, `player=1`, CORS preflight,
  `/api/search`, static `web/` with content types and 404s. Handle nil optionals carefully:
  match whether Kotlin omits fields or sends `null`.
- Copy `assets/web/{index.html,app.js,style.css}` unchanged into `Resources/web/`.
- Bonjour `_http._tcp` "Kara Pitch". Add `NSLocalNetworkUsageDescription` and
  `NSBonjourServices` to Info.plist. Get the IP from `getifaddrs`, refreshed every 15 s. Make
  the QR code with `CIFilter.qrCodeGenerator`.
- Tests: request parsing and routing against fake inputs.

## Phase 4 — TV polish (milestone 4)
`UpNextCard`, `Ticker` (a `TimelineView` marquee of the next 3 non-failed songs), `AddedBanner`
(4 s each, a sequential queue fed by `QueueStore.added`), notices (2 s), `ControlOverlay`
(Search / Skip / Restart / key stepper, closes itself after 8 s) and `Theme`. Base the
layouts on `ui/Screens.kt` at 1920×1080.

## Phase 5 — TV search (milestone 5)
`YouTube/SearchService.swift` (adds "karaoke", keeps non-live videos of 1 s–15 min, at most 20;
port `SearchServiceTest.kt`), `SearchView` (`TextField` with `.submitLabel(.search)`, a
"+ karaoke" toggle, a 4-column `LazyVGrid`) and `QuickAddSheet` (singer chips, No name, a key
stepper, Add → READY). Then wire up `/api/search`.

## Verification
- **Unit tests:** `xcodebuild test -scheme KaraPitchTV -destination 'platform=tvOS
  Simulator,name=Apple TV 4K (3rd generation)'`, covering Key, URLs, search filtering,
  QueueStore and the HTTP parser and router.
- **Stream probe (Phase 1a):** a log table showing for each client whether it returned direct
  URLs and whether those return 206 to a range request.
- **On the device:** the spec §4 checklist, recorded in the ADR. Remote mapping, the
  local-network prompt, the screensaver staying off, and backgrounding requeueing the song.
- **API compatibility:** run the Android curl checks against `http://<apple-tv-ip>:8080`. Open
  the phone web UI and add a song. Run an existing Fire TV Apple Shortcut with only the IP
  changed.

## Spec changes to propose
1. Add Phase 1a (the stream probe) ahead of Spike 0 in §10.
2. In §5, note the missing itag and audio-track fields in `VideoFormat`, and that `VisionOS`
   is a candidate client.
3. In §8, note that the Firebase package gets fetched (not linked) when the package resolves.
