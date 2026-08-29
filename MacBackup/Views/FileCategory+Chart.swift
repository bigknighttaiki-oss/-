import AppKit
import SwiftUI

/// グラフ用の配色。
///
/// 種別（エンティティ）に色を固定して割り当てる。並び順や件数が変わっても
/// 同じ種別は同じ色のままにする。ライト／ダークはそれぞれの背景に合わせて
/// 別々に選んだ値で、色覚特性のシミュレーション込みで検証済み
/// （隣接ペアの最悪値: CVD ΔE 9.1 ライト / 8.4 ダーク、通常視 19.6 / 19.3）。
///
/// ライトモードでは音楽・書類・アーカイブの 3 色が背景とのコントラスト 3:1 を
/// 下回るため、色だけに意味を持たせない。グラフには必ず凡例と直接ラベルを付け、
/// 数値は表でも読めるようにしてある。
extension FileCategory {

    /// 円グラフ・棒グラフで使う色。
    var chartColor: Color {
        switch self {
        case .photo:       return Self.dynamic(light: 0x2A78D6, dark: 0x3987E5) // 青
        case .video:       return Self.dynamic(light: 0xEB6834, dark: 0xD95926) // オレンジ
        case .music:       return Self.dynamic(light: 0x1BAF7A, dark: 0x199E70) // アクア
        case .document:    return Self.dynamic(light: 0xEDA100, dark: 0xC98500) // 黄
        case .archive:     return Self.dynamic(light: 0xE87BA4, dark: 0xD55181) // マゼンタ
        case .cache:       return Self.dynamic(light: 0x008300, dark: 0x008300) // 緑
        case .application: return Self.dynamic(light: 0x4A3AA7, dark: 0x9085E9) // 紫
        // 「その他」は寄せ集めなので、独立した色相ではなくニュートラルにする。
        case .other:       return Self.dynamic(light: 0x77766F, dark: 0x8E8D85)
        }
    }

    /// 凡例やグラフでの表示順。容量順に並べ替えても色は動かさない。
    static var chartOrder: [FileCategory] {
        [.photo, .video, .music, .document, .archive, .cache, .application, .other]
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgbHex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    /// 0xRRGGBB から色を作る。
    convenience init(rgbHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
