import Foundation

/// スキャン前でも分かるディスクの空き状況を読む。
///
/// 走査には時間がかかるので、開始前の画面ではまずこれを見せる。
enum DiskSpace {

    /// 指定したパスが載っているボリュームの容量。取れなければ nil。
    static func usage(at url: URL) -> VolumeUsage? {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]), let total = values.volumeTotalCapacity else { return nil }

        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return VolumeUsage(totalBytes: Int64(total), availableBytes: Int64(available))
    }

    /// 起動ボリューム（ホームフォルダのあるボリューム）の容量。
    static var startupVolume: VolumeUsage? {
        usage(at: FileManager.default.homeDirectoryForCurrentUser)
    }
}
