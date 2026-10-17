# ADR 0001: Pitch shifting on tvOS

Status: **proposed**. Fill in after running Spike 0 on the Apple TV.

## Context
AVPlayer can't change pitch at a fixed rate, and audio taps don't run on HLS. SPEC §4 proposes
Approach A (a composition of direct MP4s, with an `MTAudioProcessingTap` running NewTimePitch) and
Approach B (muted video plus AVAudioEngine, mastered to the audio clock).

## Stream source (Phase 1a, run 2026-10-16 on the tvOS 27 Simulator)
`StreamProbeLiveTests` on 10 videos from a live "karaoke songs" search. "Usable" means a direct
`avc1` + `mp4a` pick whose URLs each returned `206` with the full 128 KB range, fetched with the
issuing client's User-Agent.

| Client | Usable | Notes |
|---|---|---|
| visionOS | **10/10** | 1080p avc1 + AAC 130k; also returns HLS. Ranges in 14–200 ms |
| androidVR | 9/10 | 1080p avc1 + AAC; one "Sign in to confirm you're not a bot" |
| android | 10/10 | 360p muxed only (29 of 30 formats ciphered, no URL) |
| tvEmbedded | 0/10 | "This video is unavailable" for every video |

Every direct URL from visionOS and androidVR carries `rqh=1`. SmartTube treats these as stalling
in AVFoundation, but they served full ranges here, and AVFoundation played them (below). So
`rqh=1` isn't filtered. Resolve order: **visionOS → androidVR → android**.

Simulator smoke test of Approach A: "Bohemian Rhapsody karaoke" resolved via visionOS at 1080p.
The composition item was ready in 1.1–1.2 s and played with picture. The tap reported NewTimePitch
initialized and ran (286 buffers in ~26 s, 0.1% load). The HUD A/V offset read about −100 ms,
which includes tap and output latency. This proves the tap runs on remote progressive assets in a
composition. It doesn't prove audio quality, sync or real-time load on the A15.

## Spike 0 results (Approach A, Apple TV 4K 3rd gen, tvOS __)
| Check | Result | Measured |
|---|---|---|
| 5-min video plays at 1080p with picture and sound | | |
| Key −6…+6 audible, tempo unchanged, change < 200 ms | | |
| A/V sync ±40 ms: start→end, after ±10 s seeks, after pause/resume | | HUD offset drift: |
| No crackles or dropouts; tap load | | tap load %: |
| 403/410 mid-song recovered by re-resolve + resume | | |

## Decision
_A or B, and why._

## Known gaps
- `VideoFormat` has no itag, audio-track or original-language field, so the audio pick is "best
  AAC by bitrate". Multi-language uploads may pick a dub. Needs a small upstream addition.
- Client User-Agents are `package`-scoped in SmartTubeIOSCore and copied into `StreamClient`.
- Deployment target is tvOS 18 (not 17) for `Synchronization.Atomic` in the tap.
- SmartTubeIOS is a local package; pin a git commit once this ADR is accepted.
