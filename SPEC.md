# Kara Pitch for Apple TV — Specification

A karaoke player for Apple TV. It's the tvOS counterpart of the Fire TV app in
`../yt-kara-pitch` (see its `SPEC.md`). It plays YouTube videos and can shift a song's key without
changing its speed. Singers add songs from their phones through a web page served by the Apple TV,
or with the Siri Remote through on-screen search.

Status: **not started**. This spec carries over the decisions made for the Android app and adds
what's specific to tvOS. Everything marked **⚠ verify** is an assumption that needs proving on a
real device before it's relied on. Section 4 (the pitch-shift spike) has to pass before any UI work
starts.

---

## 1. Decisions

| Topic | Decision |
|---|---|
| Base | A **new, lean tvOS app** that uses **`SmartTubeIOSCore`** (from `SmartTubeIOS/`, a Foundation-only library) as a Swift package for YouTube InnerTube calls (player info, search). No SmartTube UI or playback code is reused. |
| License | **GPL-3.0**, inherited from SmartTubeIOS. |
| Device | **Apple TV 4K (3rd gen, A15)**, tvOS 17+ (matching `SmartTubeIOSCore`'s minimum). |
| Install | Xcode with a **free Apple ID**. Provisioning lasts **7 days**, so re-run from Xcode weekly. Personal use and friends only; no App Store or TestFlight. |
| Feature scope | The same as the Android app: queue, phone web UI, HTTP API, ±6 semitone key, count-in, TV search, "Up next" ticker, "added to queue" banner. |
| API and web UI | **Identical to Android**: same routes, JSON shapes and port 8080. The `assets/web` files are copied unchanged, so phones, Apple Shortcuts and other frontends work with either TV. |
| Search during a song | The Siri Remote has no Menu key, so **a swipe down on the clickpad** opens a control overlay with a **Search** button (plus Skip and Restart). |
| Out of scope | The same as Android: no account or sign-in, no AirPlay or casting, no vocal removal, no queue saved across restarts, no key changes from the phone during a song, no Top Shelf extension. |

---

## 2. Target device

| Property | Apple TV 4K (3rd gen) | Consequence |
|---|---|---|
| SoC / RAM | A15 Bionic, 4 GB | Plenty of room for 1080p playback plus real-time pitch processing |
| OS | tvOS 17+ | SwiftUI with `@Observable`, Swift 6 strict concurrency |
| Video decoding | H.264 and HEVC in hardware. **AVFoundation can't play WebM, and the A15 has no AV1 decoder** | Use **MP4 only**: `avc1` video (HEVC is optional later) and `mp4a` (AAC) audio. Never VP9, WebM or AV1 |
| Web views | **WKWebView isn't available on tvOS** | SmartTube's BotGuard/PoToken pipeline (WKWebView) can't run. Use only InnerTube clients that don't need a PoToken (§5) ⚠ verify |
| Remote | Siri Remote (2nd/3rd gen clickpad, or 1st gen touch surface) | See §6.2 |
| Screensaver | The system idle timer | `UIApplication.shared.isIdleTimerDisabled = true` while the app is in front |

---

## 3. People and flow
The same as Android:
1. The Apple TV shows the idle screen with a QR code and URL.
2. Guests add songs from their phones, or the host searches on the TV.
3. Each song is counted in for 5 seconds, then plays at its preset key.
4. The Siri Remote adjusts the key, seeks, pauses or skips.
5. Songs advance on their own. With nothing ready, the idle screen shows.

---

## 4. Pitch shifting with AVFoundation (Spike 0, the main technical risk)

AVPlayer can't shift pitch at a fixed playback speed. Its `audioTimePitchAlgorithm` only keeps
pitch steady *when the rate changes*. On top of that, **audio processing taps don't run on HLS
streams**, and HLS is what SmartTube's tvOS path mostly plays. So the karaoke app must **avoid HLS**
and play the separate (non-HLS) MP4 streams instead.

### Approach A — AVPlayer + composition + audio tap (preferred)
1. From `PlayerInfo.formats`, take the best `avc1` video-only MP4 up to 1080p and the best AAC
   audio-only M4A. Both are direct URLs.
2. Build an `AVMutableComposition` from the two `AVURLAsset`s, putting the video track and the
   audio track in one item. SmartTube already uses this "DASH composition" technique.
3. Attach an `AVAudioMix` to the audio track whose `audioTapProcessor` is an
   **`MTAudioProcessingTap`**. Inside the tap, run Apple's **NewTimePitch AudioUnit**
   (`kAudioUnitSubType_NewTimePitch`) with `rate = 1` and `pitch = 100 × semitones` cents.
4. Key changes update the AudioUnit's pitch parameter live, without rebuilding the item.

⚠ verify:
- The tap actually runs for *remote* progressive assets inside a composition. It's believed to
  work for non-HLS assets.
- Seeking and buffering behave well with two remote assets in one composition.
- googlevideo accepts AVFoundation's range requests from the client the URL was issued for, or a
  resource-loader delegate is needed to set the User-Agent and `range=` the way the Android app
  does.

### Approach B — fallback: muted video + AVAudioEngine
- The video plays muted in AVPlayer.
- The M4A is downloaded first (a 5-minute song is ~5 MB at 128 kbps) and played by `AVAudioEngine`:
  `AVAudioPlayerNode` → `AVAudioUnitTimePitch` (pitch in cents) → output.
- Sync is mastered to the audio clock. The engine's sample time drives AVPlayer through
  `setRate(_:time:atHostTime:)`, with drift correction when they differ by more than 40 ms.
  Seek, pause and buffering have to be mirrored by hand.

### Spike 0 acceptance criteria (on the Apple TV, not the Simulator)
- [ ] A 5-minute karaoke video plays at 1080p with picture and sound.
- [ ] Key −6…+6 is clearly audible. Tempo and duration don't change, and a change takes effect
      within 200 ms.
- [ ] A/V sync stays within ±40 ms from start to end, after seeks ±10 s, and after pause and
      resume.
- [ ] No crackles or dropouts during normal playback, measured as the A15's CPU load for the tap
      or engine.
- [ ] A 403/410 response mid-song can be recovered by resolving the streams again and resuming at
      the same position and key.

The outcome picks A or B. Record the decision in `docs/adr/0001-pitch-shift.md`.

---

## 5. Getting streams from YouTube
- **Player info:** call the `InnerTubeAPI.fetchPlayerInfo*` variants from `SmartTubeIOSCore`
  directly, trying clients in a fixed order and moving to the next when one returns no usable MP4
  adaptive formats. The order is a starting point ⚠ verify which clients return direct (non-HLS,
  no PoToken) URLs without WKWebView: `AndroidVR` → `iOS` → `TVEmbedded` → `Android`.
- **Stream choice:** the best `avc1` video-only stream up to 1080p, plus the best `mp4a`
  audio-only stream on the original-language track. If no separate streams exist, fall back to
  the muxed itag-18 MP4 (360p). That fallback still allows pitch shifting under Approach A, since
  it isn't HLS.
- **Expiry:** streams are resolved fresh on every play, because the URLs expire.
- **Metadata:** title, channel, thumbnail and length come from the same player response, or from
  the search result when the song was added from search.
- **Search:** `InnerTubeAPI.search(...)`, keeping videos that aren't live and are between 1 s and
  15 min long, up to 20 results. "karaoke" is added to the query unless it's already there.
- **Accepted URLs:** the same normalization rules as Android (watch, youtu.be, shorts, live,
  embed, `/v/`, music; playlists and channels rejected). The code is a port of `YouTubeUrls.kt`,
  or reuses `SmartTubeIOSCore.URLVideoResolver` if it matches the same cases.
- **When YouTube breaks extraction:** pull the latest SmartTubeIOS (update the package
  dependency), rebuild and re-run from Xcode. Its maintainers track YouTube changes.

---

## 6. Functional requirements

### 6.1 Playback, key and song flow
These match the Android spec §4.1 and §4.3:
- **Key:** an integer from −6 to +6. Each song starts at its preset key; nothing is remembered
  between plays.
- **Next song:** the first **READY** entry. RESOLVING and ERROR entries are skipped over, not
  removed.
- **Count-in:** 5 s, following queue changes live. Select starts the song right away.
- **End of a song:** when it ends, is skipped or fails, it's taken off the queue and the next one
  is counted in.
- **Interrupted songs:** if the app goes to the background (`scenePhase` isn't `.active`, for
  example the TV button, Home or sleep), the player is torn down and the song goes back to the
  **front** of the queue.
- **Failures:** a song that fails is skipped with a notice. A 403/410 response gets one fresh
  resolve and a resume at the same position and key.

### 6.2 Siri Remote while a song plays

| Input | Action |
|---|---|
| Clickpad **click** up / down | Key +1 / −1, with a "Key +2" notice |
| Clickpad **click** left / right | Seek −10 s / +10 s |
| **Hold** click right (~1 s) | Skip the song |
| Select (center click) or Play/Pause button | Pause / resume |
| **Swipe down** | Open the control overlay: **Search**, **Skip**, **Restart song**, and a key stepper |
| Back (◀ / Menu), then Back again within 3 s | Stop this song (the first press shows "Press Back again to stop this song") |
| Back while the overlay or search is open | Close it |
| TV / Home button | Handled by the system; the app goes to the background (§6.1) |

Implementation notes (⚠ verify on hardware):
- Directional **clicks** are read as `UIPress` types (`.upArrow` and so on) in a
  `UIViewController` hosting the player, wrapped for SwiftUI. Press duration gives the hold-to-skip.
- **Swipes** are read with a `UISwipeGestureRecognizer` set to `.down` and the indirect touch type,
  so a swipe and a click down don't collide.
- The 1st-gen Siri Remote (touch surface) has no edge clicks. There, up/down/left/right come from
  `onMoveCommand`, and the overlay is the fallback way to change the key.
- **Remote keyboard:** text fields use the tvOS fullscreen keyboard. An iPhone nearby gets the
  Apple TV keyboard notification (Continuity) for typing on the phone.

### 6.3 TV screens
These carry over from Android with the same content and behavior. Layouts are designed for
1920×1080 points, with tvOS focus effects instead of hand-drawn focus borders.
- **Idle:** "Karaoke" heading, a **Search songs** button (focused by default), the phone URL
  `http://<tv-ip>:8080` with a QR code (made with `CIFilter.qrCodeGenerator`), and the next 5
  queued songs.
- **Up next card:** the singer's name, the title, a key chip, the countdown and a "Press Select to
  start now" hint.
- **Playing:** full-screen video (`AVPlayerLayer` with aspect fit and no system transport
  controls, so the remote stays in the app's hands). A loading card shows until the video starts.
- **Up next ticker:** a strip across the top during a song, scrolling the next 3 songs that
  haven't failed, in the form `1. Singer — Title (Key +2)`. A SwiftUI marquee built from a
  `TimelineView` offset loop.
- **Added to queue banner:** a 4 s card that slides up from the bottom whenever an entry becomes
  READY, on any screen. It shows the thumbnail (`AsyncImage`), "ADDED TO QUEUE · #n", the title,
  the singer and a key chip. Several adds in a row each get a banner, one after another.
- **Notices:** short messages for 2 s, shown below the ticker.
- **Control overlay:** opened with a swipe down (§6.2). A translucent panel at the bottom with
  Search, Skip, Restart and a key stepper. It closes itself after 8 s without input.

### 6.4 TV search
The same as Android §4.5:
- **Opening it:** **Search songs** on the idle screen, or **Search** in the control overlay. The
  song keeps playing behind it, and Back closes it.
- **Typing:** a `TextField` with `.submitLabel(.search)`, a "+ karaoke" toggle and a 4-column
  `LazyVGrid` of focusable result cards.
- **Quick-add sheet:** recent singer chips plus **No name**, a key stepper changed with left/right
  clicks, and **Add**. Songs added this way are READY right away, and search stays open.

### 6.5 Phone web UI and HTTP API
- **Web UI:** the same files as the Android app (`index.html`, `app.js`, `style.css`), bundled as
  app resources under `web/` and served from `/`.
- **HTTP API:** the **exact contract** of Android SPEC §4.7:
  - `GET /api/state` (with the `since`/`player` options and 304)
  - `GET /api/search`
  - `POST /api/queue` (with optional search metadata)
  - `PATCH /api/queue/{id}`
  - `POST /api/queue/{id}/move`
  - `DELETE /api/queue/{id}`

  The same status codes and JSON field names, CORS open to any origin, and no authentication.
- **Server:** a small HTTP/1.1 server written in the app on **Network.framework `NWListener`**
  (TCP, port 8080). It handles request parsing (request line, headers, `Content-Length` body),
  routing, JSON through `Codable`, static files and CORS preflight. Connections are short-lived,
  with no keep-alive needed.
- **Bonjour:** the server is advertised as `_http._tcp`, named "Kara Pitch".
- **Info.plist:** includes `NSLocalNetworkUsageDescription` and `NSBonjourServices`. ⚠ verify
  whether tvOS shows a local-network permission prompt and how incoming connections behave before
  it's granted.
- **Address:** the TV's address shown on screen comes from `getifaddrs` (the first non-loopback
  IPv4 on `en0`/`en1`) and is refreshed every 15 s.

---

## 7. Queue model
The same rules as Android §5, ported to Swift:
- **Storage:** an `actor QueueStore` holding the queue, `nowPlaying`, and a `version` that goes up
  on every change.
- **Limits:** at most 200 entries, singer names trimmed to 40 characters, preset keys clamped to
  ±6.
- **States:** RESOLVING → READY / ERROR. Entries added with metadata are READY straight away. An
  entry removed while resolving stays removed.
- **Events:** an `added: AsyncStream<QueueEntry>` fires once for each entry when it becomes READY.
- **Playing:** `startNext()`, `finishNowPlaying()`, `requeueNowPlaying()`.
- **Persistence:** none. The queue lives in memory only.

---

## 8. Architecture

```
KaraPitchTV (Xcode project, tvOS app target)
 ├─ App/            @main App, scenePhase handling, idle-timer
 ├─ Queue/          QueueStore (actor), QueueEntry, VideoMeta, YouTubeURL
 ├─ YouTube/        StreamResolver, SearchService   → SmartTubeIOSCore.InnerTubeAPI
 ├─ Player/         KaraPlayer (@MainActor @Observable), PitchTap (Approach A) | SyncedAudioEngine (B), Key
 ├─ Session/        KaraSession: idle → upNext → playing loop, notices, recentSingers
 ├─ Server/         HTTPServer (NWListener), Router, API handlers, static web/
 ├─ UI/             IdleView, UpNextCard, PlayerView (+ remote input), Ticker, AddedBanner,
 │                  ControlOverlay, SearchView, QuickAddSheet, Theme
 └─ Resources/web/  index.html, app.js, style.css  (copied from the Android app)
KaraPitchTVTests    Swift Testing unit tests
```

- **Language and concurrency:** Swift 6 with strict concurrency. View models are
  `@MainActor @Observable`; there's no Combine, `DispatchQueue` or completion handlers in new code
  (this follows the SmartTubeIOS conventions). The audio tap's render callback is the only
  real-time code; it shares state with the rest of the app through atomics and doesn't allocate.
- **Logging:** `os.Logger` with subsystem `dev.ytkara.tv`.
- **Dependencies:** only `SmartTubeIOSCore`, as a local path or a git dependency on the
  SmartTubeIOS package. Its Firebase dependency belongs to the UI target and isn't linked.

---

## 9. Build and install (free Apple ID)
1. Open the project in Xcode and sign in with your Apple ID (Settings → Accounts). Under Signing,
   pick your **Personal Team** and set a unique bundle ID, for example `dev.ytkara.tv.<you>`.
2. Pair the Apple TV with Xcode. On the Apple TV, open Settings → Remotes and Devices → Remote App
   and Devices. On the Mac, open Xcode → Devices and Simulators, and the Apple TV appears for
   pairing while both are on the same network.
3. Choose the Apple TV as the run destination and press **Run**.
4. **Every 7 days** the profile expires and the app won't launch: run it from Xcode again. A free
   Apple ID is also limited to a few apps installed at once per device.

---

## 10. Milestones
1. **Spike 0:** pitch shift on the device (§4). Decide between A and B.
2. **Playback and queue:** stream resolution, `KaraPlayer`, `QueueStore`, `KaraSession`, a plain
   idle screen and the Siri Remote controls.
3. **Server and web UI:** the `NWListener` HTTP server, the API with the same contract as Android,
   the bundled web UI, Bonjour, the QR code.
4. **TV polish:** the up-next card, ticker, added-to-queue banner, control overlay and notices.
5. **TV search:** the search view, quick-add sheet and `/api/search`.

---

## 11. Testing
- **Unit tests (Swift Testing, no network):**
  - Semitone→pitch math (+12 = 1200 cents for Approach A, or 2.0 as a ratio).
  - URL normalization, using the same cases as the Android `YouTubeUrlsTest`.
  - Search query building and the duration/live filter.
  - `QueueStore`: adding, resolving, errors, versions, move clamping, startNext/requeue/finish,
    removal while resolving, adding with metadata, and `added` events.
  - HTTP request parsing and routing against fake connections.
- **API compatibility:** the same curl checks as the Android app against
  `http://<apple-tv-ip>:8080`, and an Apple Shortcut made for the Fire TV that works unchanged
  apart from the IP.
- **On the device only:** everything in Spike 0, the remote mapping (clicks vs swipes,
  hold-to-skip), the local-network prompt, the screensaver staying off, and backgrounding
  requeueing the song. The Simulator can't confirm decoding or real-time audio performance.

---

## 12. Open questions and risks
- **Spike 0 may fail on both approaches.** The last resort is to download both streams fully
  before each song (~30–60 MB at 1080p) and play local files, which taps support reliably. That
  adds a delay before every song.
- **InnerTube clients without WKWebView:** if no PoToken-free client returns direct MP4 URLs, tvOS
  can't get pitch-shiftable streams.
- **The local-network permission behavior** on tvOS is unconfirmed.
- **The 7-day free provisioning** means the app stops launching until it's re-run from Xcode. Plan
  around party dates.
- **SmartTubeIOSCore churn:** its playback code is under active refactoring. Only the InnerTube API
  surface is used, and the dependency should be pinned to a known-good commit.
