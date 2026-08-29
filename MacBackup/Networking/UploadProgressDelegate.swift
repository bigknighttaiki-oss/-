import Foundation

/// URLSession のアップロード進捗を、0.0〜1.0 の割合として呼び出し元に流すだけの委譲先。
final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {

    /// 送信済みバイト数と、送信予定の総バイト数を受け取る。
    private let onProgress: @Sendable (_ sent: Int64, _ total: Int64) -> Void

    init(onProgress: @escaping @Sendable (_ sent: Int64, _ total: Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        onProgress(totalBytesSent, totalBytesExpectedToSend)
    }
}
