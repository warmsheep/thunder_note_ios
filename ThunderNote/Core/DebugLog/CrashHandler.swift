import Foundation
import UIKit

/// D2-I6-14 崩溃捕获
///
/// 捕获 NSException 和 Unix Signal (SIGSEGV, SIGABRT 等)，将调用栈输出到 DebugLog。
/// 然后恢复默认行为以便系统能产生真正的崩溃报告。
public final class CrashHandler: Sendable {

    private static var isInstalled = false
    private static var previousExceptionHandler: NSUncaughtExceptionHandler?

    // Signal handlers need to be C-function pointers, so we store the old ones
    private static var previousSigabrt: sigaction?
    private static var previousSigill: sigaction?
    private static var previousSigsegv: sigaction?
    private static var previousSigfpe: sigaction?
    private static var previousSigbus: sigaction?
    private static var previousSigpipe: sigaction?

    public static func install() {
        guard !isInstalled else { return }
        isInstalled = true

        // 1. 捕获 NSException
        previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            CrashHandler.handleException(exception)
        }

        // 2. 捕获 Signal
        installSignalHandler(SIGABRT, oldAction: &previousSigabrt)
        installSignalHandler(SIGILL, oldAction: &previousSigill)
        installSignalHandler(SIGSEGV, oldAction: &previousSigsegv)
        installSignalHandler(SIGFPE, oldAction: &previousSigfpe)
        installSignalHandler(SIGBUS, oldAction: &previousSigbus)
        installSignalHandler(SIGPIPE, oldAction: &previousSigpipe)
        
        Task { @MainActor in
            DebugLog.info(tag: "CrashHandler", message: "Crash handler installed.")
        }
    }

    private static func installSignalHandler(_ signal: Int32, oldAction: UnsafeMutablePointer<sigaction?>) {
        var action = sigaction()
        action.sa_flags = SA_SIGINFO
        action.__sigaction_u.__sa_sigaction = { sig, info, context in
            CrashHandler.handleSignal(sig, info: info, context: context)
        }
        var old = sigaction()
        sigaction(signal, &action, &old)
        oldAction.pointee = old
    }

    private static func handleException(_ exception: NSException) {
        let stackString = exception.callStackSymbols.joined(separator: "\n")
        let message = "Uncaught Exception: \(exception.name.rawValue)\nReason: \(exception.reason ?? "nil")\nStack:\n\(stackString)"
        
        // 我们需要在奔溃前同步写入文件，这里不能用 Task/DispatchQueue.async
        writeCrashLogSynchronously(message: message)
        
        // 恢复并传递给上一个 handler
        if let prev = previousExceptionHandler {
            prev(exception)
        }
    }

    private static func handleSignal(_ signal: Int32, info: UnsafeMutablePointer<siginfo_t>?, context: UnsafeMutableRawPointer?) {
        let stack = Thread.callStackSymbols.joined(separator: "\n")
        let message = "Caught Signal: \(signal)\nStack:\n\(stack)"
        
        writeCrashLogSynchronously(message: message)
        
        // 恢复默认行为
        uninstallSignalHandlers()
        raise(signal)
    }
    
    private static func writeCrashLogSynchronously(message: String) {
        let line = "[CRASH] \(message)\n"
        print(line)
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        if let cacheURL = urls.first {
            let currentLogURL = cacheURL.appendingPathComponent("debug_log.txt")
            if let handle = try? FileHandle(forWritingTo: currentLogURL) {
                _ = try? handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try? handle.write(contentsOf: data)
                }
                try? handle.close()
            }
        }
    }

    private static func uninstallSignalHandlers() {
        if var old = previousSigabrt { sigaction(SIGABRT, &old, nil) }
        if var old = previousSigill { sigaction(SIGILL, &old, nil) }
        if var old = previousSigsegv { sigaction(SIGSEGV, &old, nil) }
        if var old = previousSigfpe { sigaction(SIGFPE, &old, nil) }
        if var old = previousSigbus { sigaction(SIGBUS, &old, nil) }
        if var old = previousSigpipe { sigaction(SIGPIPE, &old, nil) }
    }
}
