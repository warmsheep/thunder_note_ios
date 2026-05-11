import Foundation
import AVFoundation

/// D2-I3-11 语音录制 helper：基于 `AVAudioRecorder`。
/// - 启动后实时按 100ms 采样 peak power（dBFS），通过 `levels` Stream 输出 0~1 的归一化值，
///   `VoiceWaveView` 订阅后自实现波形绘制。
/// - 与 Android `ChatRecordingHelper` 等价：支持 start/stopAndKeep/cancel；
///   超出 60s 自动停止；输出 m4a 文件 URL（AAC, 单声道, 22.05kHz）。
/// - 调用方需要先取得麦克风权限（`NSMicrophoneUsageDescription` 已在 project.yml 声明）。
@MainActor
public final class ChatRecordingHelper: NSObject, ObservableObject {
    public enum State: Equatable {
        case idle
        case recording(elapsed: TimeInterval)
        case finished(url: URL, duration: TimeInterval)
        case cancelled
        case failed(message: String)
    }

    public static let maxDuration: TimeInterval = 60

    @Published public private(set) var state: State = .idle
    @Published public private(set) var levels: [Float] = []
    @Published public private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var sampleTimer: Timer?
    private var startedAt: Date?
    private let session = AVAudioSession.sharedInstance()

    public override init() { super.init() }

    deinit {
        sampleTimer?.invalidate()
        recorder?.stop()
    }

    /// 启动录音；返回是否启动成功。
    public func start() async -> Bool {
        // 确保前置已配置 record category
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            state = .failed(message: "无法启用音频会话：\(error.localizedDescription)")
            return false
        }
        // 申请麦克风权限
        let granted = await requestMicrophonePermission()
        if !granted {
            state = .failed(message: "未授予麦克风权限")
            return false
        }

        let url = makeRecordURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                state = .failed(message: "录音启动失败")
                return false
            }
            self.recorder = recorder
            startedAt = Date()
            elapsed = 0
            levels = []
            state = .recording(elapsed: 0)
            startSampling()
            return true
        } catch {
            state = .failed(message: error.localizedDescription)
            return false
        }
    }

    /// 停止录音并保留文件，进入 `.finished`。
    public func stopAndKeep() {
        guard let recorder, recorder.isRecording else { return }
        sampleTimer?.invalidate()
        sampleTimer = nil
        recorder.stop()
        let duration = elapsed
        let url = recorder.url
        try? session.setActive(false)
        self.recorder = nil
        state = .finished(url: url, duration: duration)
    }

    /// 停止录音并丢弃文件（上滑取消区域）。
    public func cancel() {
        guard let recorder else {
            state = .cancelled
            return
        }
        sampleTimer?.invalidate()
        sampleTimer = nil
        if recorder.isRecording { recorder.stop() }
        let url = recorder.url
        try? FileManager.default.removeItem(at: url)
        try? session.setActive(false)
        self.recorder = nil
        state = .cancelled
    }

    /// 重置 state 到 idle，让 UI 隐藏录音浮层。
    public func reset() {
        sampleTimer?.invalidate()
        sampleTimer = nil
        recorder?.stop()
        recorder = nil
        elapsed = 0
        levels = []
        state = .idle
    }

    // MARK: - 私有

    private func startSampling() {
        // 闭包内 [weak self] 捕获到 var；直接 hop 到 Task 时严格并发会报
        // 「reference to captured var 'self' in concurrently-executing code」。
        // 通过 let 重新绑定为 immutable 后再传入 Task，避开 var 捕获判断。
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            let weakSelf = self
            Task { @MainActor in
                weakSelf?.tick()
            }
        }
        sampleTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let dbfs = recorder.averagePower(forChannel: 0)
        // 把 dB 转为 0~1：-60 dB 视为静音，0 dB 视为最大。
        let normalized = max(0, min(1, (dbfs + 60) / 60))
        if levels.count >= 60 { levels.removeFirst() }
        levels.append(normalized)
        if let startedAt {
            elapsed = Date().timeIntervalSince(startedAt)
            state = .recording(elapsed: elapsed)
            if elapsed >= Self.maxDuration {
                stopAndKeep()
            }
        }
    }

    private func makeRecordURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tn-voice-\(UUID().uuidString).m4a")
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            session.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

extension ChatRecordingHelper: AVAudioRecorderDelegate {
    public nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // 由 stopAndKeep / cancel 主动控制 state，这里只兜底失败场景。
        if !flag {
            Task { @MainActor in
                self.state = .failed(message: "录音异常结束")
            }
        }
    }
}
