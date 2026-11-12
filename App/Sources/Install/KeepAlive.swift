import AVFoundation

/// Silent audio loop so the app keeps running in the background while a batch/install runs.
/// The WAV is generated in code (no audio asset files).
@MainActor
final class KeepAlive {
    static let shared = KeepAlive()
    private var player: AVAudioPlayer?

    func start() {
        guard player == nil else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(data: Self.silentWAV())
            p.numberOfLoops = -1
            p.volume = 0
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// One second of 8 kHz 16-bit mono silence.
    private static func silentWAV() -> Data {
        let sampleRate: UInt32 = 8000
        let dataSize = UInt32(sampleRate * 2)
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(Data("RIFF".utf8)); u32(36 + dataSize)
        d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8)); u32(16); u16(1); u16(1); u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        d.append(Data("data".utf8)); u32(dataSize)
        d.append(Data(count: Int(dataSize)))
        return d
    }
}
