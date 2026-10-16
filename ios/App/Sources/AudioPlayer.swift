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
    /// The sender pressed play and has not paused or stopped since. An interruption (a call,
    /// Siri) resumes playback only then.
    private var wantsToPlay = false
    /// Where a new item should start, applied once it is ready. Saves wait until then, so the
    /// item's first ticks at 0:00 never overwrite its saved place.
    private var pendingResume: TimeInterval?
    /// Where each recording was left, by URL. A small file in the app's own storage on this
    /// phone, left out of iCloud and computer backups like the drafts.
    private var positionsCache: [String: Double]?

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
                self.wantsToPlay = false
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
        // A new recording, or the same one whose file failed to load: start a fresh item, so
        // pressing play again after a dropped connection tries again.
        if current != item || player.currentItem == nil || player.currentItem?.status == .failed {
            let switching = current != item
            if switching { saveProgress() }
            // A new recording starts where it was left; a retry starts where this one stood.
            let resume = switching ? savedPosition(item) : (pendingResume ?? position)
            current = item
            duration = item.listedDuration ?? 0
            pendingResume = resume > 0 ? resume : nil
            position = resume
            lastSaved = resume
            let avItem = AVPlayerItem(url: item.url)
            itemObservation = avItem.observe(\.status, options: [.new]) { [weak self] i, _ in
                let status = i.status, d = i.duration.seconds
                Task { @MainActor in
                    guard let self, i === self.player.currentItem else { return }
                    if status == .failed {
                        self.failed = "This recording did not load. Check the connection and press play again, or open the page to play it there."
                    } else if status == .readyToPlay {
                        if d.isFinite, d > 0 { self.duration = d }
                        if let at = self.pendingResume {
                            self.pendingResume = nil
                            self.player.seek(to: CMTime(seconds: at, preferredTimescale: 600))
                        }
                        self.updateNowPlaying()
                    }
                }
            }
            player.replaceCurrentItem(with: avItem)
        }
        wantsToPlay = true
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
        wantsToPlay = false
        player.pause()
        saveProgress()
        updateNowPlaying()
    }

    func seek(to seconds: TimeInterval) {
        let t = max(0, duration > 0 ? min(seconds, duration) : seconds)
        pendingResume = nil
        position = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600))
        saveProgress()
        updateNowPlaying()
    }

    func skip(by delta: TimeInterval) { seek(to: position + delta) }

    /// Stops and clears the player, Lock Screen included.
    func stop() {
        wantsToPlay = false
        saveProgress()
        pendingResume = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemObservation = nil
        current = nil
        position = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Stops the player and forgets where every recording was left. For "Delete everything
    /// the app is holding".
    func eraseListening() {
        stop()
        positionsCache = [:]
        try? FileManager.default.removeItem(at: Self.positionsFile)
    }

    /// Where a recording was left, for the lists ("Resume at 3:12").
    func resumePoint(_ url: URL) -> TimeInterval? {
        let p = positions()[url.absoluteString] ?? 0
        return p > 0 ? p : nil
    }

    // MARK: Internals

    private func tick(_ t: TimeInterval) {
        guard t.isFinite, pendingResume == nil else { return }
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
        } else if wantsToPlay, let o = info?[AVAudioSessionInterruptionOptionKey] as? UInt,
                  AVAudioSession.InterruptionOptions(rawValue: o).contains(.shouldResume), let c = current {
            play(c)
        }
    }

    private static let positionsFile: URL = {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("listen-positions.json")
    }()

    private func positions() -> [String: Double] {
        if let positionsCache { return positionsCache }
        let read = (try? Data(contentsOf: Self.positionsFile)).flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) }
        positionsCache = read ?? [:]
        return positionsCache ?? [:]
    }

    private func writePositions(_ all: [String: Double]) {
        positionsCache = all
        var url = Self.positionsFile
        guard let data = try? JSONEncoder().encode(all), (try? data.write(to: url, options: .atomic)) != nil else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private func savedPosition(_ item: Playable) -> TimeInterval {
        let p = positions()[item.id] ?? 0
        // Within the last ten seconds counts as finished: start again from the top.
        if let d = item.listedDuration, p > d - 10 { return 0 }
        return p
    }

    private func saveProgress() {
        guard let c = current, pendingResume == nil else { return }
        lastSaved = position
        var all = positions()
        if position < 5 || (duration > 0 && position > duration - 10) {
            all[c.id] = nil
        } else {
            all[c.id] = position
        }
        writePositions(all)
    }

    private func forget(_ item: Playable) {
        var all = positions()
        all[item.id] = nil
        writePositions(all)
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
