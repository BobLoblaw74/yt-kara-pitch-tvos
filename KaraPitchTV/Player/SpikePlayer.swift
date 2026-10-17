import AVFoundation
import Observation
import SmartTubeIOSCore
import os

/// What the spike's debug HUD shows, refreshed four times a second.
struct SpikeHUD: Sendable {
    var key = 0
    var position: Double = 0
    var duration: Double = 0
    /// Player time minus the source time last pulled through the tap. It includes the tap's and
    /// the output's latency, so watch how it *changes* across seeks and pauses, not its value.
    var avOffsetMillis: Int?
    var tapLoadPercent: Double = 0
    var tapStatus = "not prepared"
    var tapBuffers: Int64 = 0
    var lastHTTPError: Int?
    var streams = ""
}

/// Spike 0, Approach A: two remote MP4s in one composition, with the audio run through
/// `PitchTap`. Approach B (AVAudioEngine) only gets built if this fails on the device.
@MainActor @Observable
final class SpikePlayer {
    let player = AVPlayer()
    private(set) var status = "Idle"
    private(set) var hud = SpikeHUD()

    @ObservationIgnored private var tapContext = PitchTapContext()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private let api = InnerTubeAPI()

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshHUD() }
        }
    }

    /// Plays the first long-enough search hit for `query`.
    func start(query: String) async {
        do {
            status = "Searching “\(query)”…"
            let hits = try await api.search(query: query).videos.filter { !$0.isLive && ($0.duration ?? 0) > 60 }
            guard let video = hits.first else {
                status = "No results for “\(query)”"
                return
            }
            try await play(videoID: video.id, title: video.title)
        } catch {
            status = "Failed: \(error)"
            Logger.player.error("spike failed: \(String(describing: error), privacy: .public)")
        }
    }

    func play(videoID: String, title: String, startAt: Double = 0) async throws {
        status = "Resolving \(title)…"
        let streams = try await StreamResolver(api: api).resolve(videoID: videoID)
        status = "Loading \(streams.description) via \(streams.client.rawValue)…"
        let loadStart = ContinuousClock.now
        let item = try await makeItem(streams)
        Logger.player.notice("item ready in \(String(describing: ContinuousClock.now - loadStart), privacy: .public)")
        hud.streams = "\(streams.client.rawValue) · \(streams.description)"
        player.replaceCurrentItem(with: item)
        if startAt > 0 { await player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600)) }
        player.play()
        status = title
    }

    func adjustKey(_ delta: Int) {
        hud.key = Key.clamp(hud.key + delta)
        tapContext.semitones.store(Int32(hud.key), ordering: .relaxed)
    }

    func seek(by seconds: Double) {
        let target = max(0, player.currentTime().seconds + seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePause() {
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
    }

    private func makeItem(_ streams: Streams) async throws -> AVPlayerItem {
        let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": streams.userAgent]]
        let videoAsset = AVURLAsset(url: streams.videoURL, options: options)
        let audioAsset = streams.audioURL.map { AVURLAsset(url: $0, options: options) } ?? videoAsset

        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
            let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first
        else { throw SpikeError.missingTrack }
        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let trackDuration = try await videoTrack.load(.timeRange).duration
        Logger.player.notice(
            "durations: video asset \(videoDuration.seconds) s, video track \(trackDuration.seconds) s, audio asset \(audioDuration.seconds) s")
        let duration = min(videoDuration, audioDuration)
        let range = CMTimeRange(start: .zero, duration: duration)

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw SpikeError.missingTrack }
        try compVideo.insertTimeRange(range, of: videoTrack, at: .zero)
        compVideo.preferredTransform = try await videoTrack.load(.preferredTransform)
        try compAudio.insertTimeRange(range, of: audioTrack, at: .zero)

        // A fresh context per item: the old tap may still be finalizing on its own thread.
        tapContext = PitchTapContext()
        tapContext.semitones.store(Int32(hud.key), ordering: .relaxed)
        let item = AVPlayerItem(asset: composition)
        item.audioMix = PitchTap.makeAudioMix(for: compAudio, context: tapContext)
        hud.duration = duration.seconds
        return item
    }

    private func refreshHUD() {
        let position = player.currentTime().seconds
        hud.position = position.isFinite ? position : 0
        let source = tapContext.sourceTimeMicros.load(ordering: .relaxed)
        hud.avOffsetMillis = source >= 0 ? Int((hud.position - Double(source) / 1e6) * 1000) : nil
        hud.tapLoadPercent = Double(tapContext.loadPermille.load(ordering: .relaxed)) / 10
        hud.tapBuffers = tapContext.processCount.load(ordering: .relaxed)
        let prepare = tapContext.prepareStatus.load(ordering: .relaxed)
        hud.tapStatus = prepare == Int32.min ? "not prepared" : prepare == noErr ? "NewTimePitch live" : "AU error \(prepare)"
        if let code = player.currentItem?.errorLog()?.events.last?.errorStatusCode, code != 0 {
            hud.lastHTTPError = code
        }
        if player.currentItem?.status == .failed {
            status = "Item failed: \(player.currentItem?.error?.localizedDescription ?? "?")"
        }
    }
}

enum SpikeError: Error {
    case missingTrack
}
