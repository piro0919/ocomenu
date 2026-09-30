import Foundation

// 表示文字列。
//
// .lproj は使わず Swift の表に置く。ビルドを自前の shell で組んでいて、
// 文字列だけのために資源の仕組みを足すと build.sh が重くなるため。
// 言語は2つしかないので、この形のほうが追いやすい。

enum Language: String, CaseIterable, Sendable {
    case system, ja, en

    /// 実際に使う言語。既定は英語で、環境が日本語のときだけ日本語にする
    static var resolved: Language {
        switch Settings.language {
        case .ja: return .ja
        case .en: return .en
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("ja") ? .ja : .en
        }
    }

    var label: String {
        switch self {
        case .system: return L.t("システムに従う", "Follow system")
        case .ja: return "日本語"
        case .en: return "English"
        }
    }
}

enum L {
    static func t(_ ja: String, _ en: String) -> String {
        Language.resolved == .ja ? ja : en
    }

    // メニューバー
    static var enabled: String { t("有効", "Enabled") }
    static var needsAccessibility: String {
        t("アクセシビリティの許可が必要です…", "Needs Accessibility permission…")
    }
    static var settings: String { t("設定…", "Settings…") }
    static var quit: String { t("終了", "Quit") }

    // 設定画面
    static var settingsTitle: String { t("Ocomenu の設定", "Ocomenu Settings") }
    static var menuTab: String { t("メニュー", "Menu") }
    static var generalTab: String { t("一般", "General") }
    static var paletteHint: String {
        t("よく使う項目を右クリックメニューにドラッグしてください…", "Drag your favorite items into the right-click menu…")
    }
    static var previewTitle: String { t("右クリックメニュー", "Right-Click Menu") }
    static var separator: String { t("区切り線", "Separator") }
    static var newItem: String { t("新しい項目…", "New Item…") }
    static var done: String { t("完了", "Done") }
    static var remove: String { t("削除", "Remove") }
    static var edit: String { t("編集…", "Edit…") }
    static var resetToDefaults: String { t("初期状態に戻す", "Reset to Defaults") }
    static var launchAtLogin: String { t("ログイン時に起動する", "Launch at login") }
    static var showMenuBarIcon: String { t("メニューバーにアイコンを表示", "Show icon in menu bar") }
    static var menuBarIconHint: String {
        t("隠しても、Ocomenu をもう一度開くとこの画面が出ます。", "When hidden, open Ocomenu again to get back to this window.")
    }
    static var language: String { t("言語", "Language") }
    static var checkForUpdates: String { t("更新を確認", "Check for updates") }
    static func launchToggleFailed(_ reason: String) -> String {
        t("切り替えられませんでした: \(reason)", "Could not change it: \(reason)")
    }

    // 自分で足す項目
    static var kind: String { t("種類", "Type") }
    static var title: String { t("名前", "Title") }
    static var script: String { t("スクリプト", "Script") }
    static var scriptHint: String {
        t("選んだ項目のパスが \"$@\" で渡されます。/bin/zsh で実行します。", "Selected paths are passed as \"$@\". Runs with /bin/zsh.")
    }
    static var application: String { t("アプリ", "Application") }
    static var folder: String { t("フォルダ", "Folder") }
    static var choose: String { t("選ぶ…", "Choose…") }
    static var cancel: String { t("キャンセル", "Cancel") }
    static var save: String { t("保存", "Save") }

    static func kindLabel(_ kind: CustomAction.Kind) -> String {
        switch kind {
        case .script: return t("シェルスクリプトを実行", "Run Shell Script")
        case .openWith: return t("このアプリで開く", "Open With App")
        case .copyTo: return t("フォルダへコピー", "Copy to Folder")
        case .moveTo: return t("フォルダへ移動", "Move to Folder")
        }
    }

    // 実行時
    static func actionFailed(_ title: String) -> String {
        t("「\(title)」を実行できませんでした", "Could not run “\(title)”")
    }
}
