import AVFoundation
import GSRKit
import MediaPlayer
import SwiftUI

/// Something the player can play: an audio article or a podcast episode.
struct Playable: Hashable, Identifiable {
    var id: String { url.absoluteString }
    let url: URL
    let title: String
    /// "Dexter Dow’s voice", "Synthetic voice", "AI hosts": the page's own label.
    let voice: String
    /// The article, or the podcast page, to read along.
    let page: URL
    /// From the page, used until the file reports its own length.
    let listedDuration: TimeInterval?
}

/// Plays one recording at a time, keeps going with the screen locked, shows on the Lock
/// Screen with its controls, and remembers where each recording was left.
@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()

    @Published private(set) var current: Playable?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isBuffering = false
    @Published private(set) var failed: String?
    @Published var rate: Float = 1 {
        didSet {
            player.defaultRate = rate
            if isPlaying { player.rate = rate }
            updateNowPlaying()
        }
    }
    static let rates: [Float] = [1, 1.25, 1.5, 2]

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var lastSaved: TimeInterval = 0
    private let skip: TimeInterval = 15

    /// Where each recording was left, by URL. Kept in the app's own settings on this phone.
    private let positionsKey = "GSRListenPositions"

    private init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let status = p.timeControlStatus
            Task { @MainActor in
                self?.isPlaying = status != .paused
                self?.isBuffering = status == .waitingToPlayAtSpecifiedRate
                self?.updateNowPlaying()
            }
        }
        let center = NotificationCenter.default
        center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] n in
            let item = n.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self, item === self.player.currentItem, let c = self.current else { return }
                self.forget(c)
                self.position = 0
                self.player.seek(to: .zero)
                self.updateNowPlaying()
            }
        }
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let info = n.userInfo
            MainActor.assumeIsolated { self?.interrupted(info) }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            // Headphones pulled out: stop rather than play out loud.
            let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated {
                if reason == .oldDeviceUnavailable { self?.pause() }
            }
        }
        setUpRemoteCommands()
    }

    // MARK: Control

    func play(_ item: Playable) {
        failed = nil
        if current != item {
            saveProgress()
            current = item
            duration = item.listedDuration ?? 0
            let avItem = AVPlayerItem(url: item.url)
            itemObservation = avItem.observe(\.status, options: [.new]) { [weak self] i, _ in
                let status = i.status, d = i.duration.seconds
                Task { @MainActor in
                    guard let self, i === self.player.currentItem else { return }
                    if status == .failed {
                        self.failed = "This recording did not load. Check the connection, or open the page to play it there."
                    } else if status == .readyToPlay, d.isFinite, d > 0 {
                        self.duration = d
                        self.updateNowPlaying()
                    }
                }
            }
            player.replaceCurrentItem(with: avItem)
            let resume = savedPosition(item)
            position = resume
            if resume > 0 { player.seek(to: CMTime(seconds: resume, preferredTimescale: 600)) }
        }
        activateSession()
        player.defaultRate = rate
        player.playImmediately(atRate: rate)
        updateNowPlaying()
    }

    func toggle() {
        guard let c = current else { return }
        isPlaying ? pause() : play(c)
    }

    func pause() {
        player.pause()
        saveProgress()
        updateNowPlaying()
    }

    func seek(to seconds: TimeInterval) {
        let t = max(0, duration > 0 ? min(seconds, duration) : seconds)
        position = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600))
        saveProgress()
        updateNowPlaying()
    }

    func skip(by delta: TimeInterval) { seek(to: position + delta) }

    /// Stops and clears the player, Lock Screen included.
    func stop() {
        saveProgress()
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemObservation = nil
        current = nil
        position = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Where a recording was left, for the lists ("Resume at 3:12").
    func resumePoint(_ url: URL) -> TimeInterval? {
        let p = positions()[url.absoluteString] ?? 0
        return p > 0 ? p : nil
    }

    // MARK: Internals

    private func tick(_ t: TimeInterval) {
        guard t.isFinite else { return }
        position = t
        if abs(t - lastSaved) >= 5 { saveProgress() }
    }

    private func activateSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try? s.setActive(true)
    }

    private func interrupted(_ info: [AnyHashable: Any]?) {
        guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            saveProgress()
        } else if let o = info?[AVAudioSessionInterruptionOptionKey] as? UInt,
                  AVAudioSession.InterruptionOptions(rawValue: o).contains(.shouldResume), let c = current {
            play(c)
        }
    }

    private func positions() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: positionsKey) as? [String: Double] ?? [:]
    }

    private func savedPosition(_ item: Playable) -> TimeInterval {
        let p = positions()[item.id] ?? 0
        // Within the last ten seconds counts as finished: start again from the top.
        if let d = item.listedDuration, p > d - 10 { return 0 }
        return p
    }

    private func saveProgress() {
        guard let c = current else { return }
        lastSaved = position
        var all = positions()
        if position < 5 || (duration > 0 && position > duration - 10) {
            all[c.id] = nil
        } else {
            all[c.id] = position
        }
        UserDefaults.standard.set(all, forKey: positionsKey)
    }

    private func forget(_ item: Playable) {
        var all = positions()
        all[item.id] = nil
        UserDefaults.standard.set(all, forKey: positionsKey)
    }

    private func updateNowPlaying() {
        guard let c = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: c.title,
            MPMediaItemPropertyArtist: "Granite State Report",
            MPMediaItemPropertyAlbumTitle: c.voice,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setUpRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let cur = self.current else { return .noActionableNowPlayingItem }
                self.play(cur)
                return .success
            }
        }
        c.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.toggle() }
            return .success
        }
        c.skipForwardCommand.preferredIntervals = [NSNumber(value: skip)]
        c.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: 15) }
            return .success
        }
        c.skipBackwardCommand.preferredIntervals = [NSNumber(value: skip)]
        c.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: -15) }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            MainActor.assumeIsolated { self?.seek(to: t) }
            return .success
        }
        c.nextTrackCommand.isEnabled = false
        c.previousTrackCommand.isEnabled = false
    }
}
