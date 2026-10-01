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
        case .system: return L.t("システムの言語を使用", "Use System Language")
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
        t("“アクセシビリティ”設定を開く", "Open Accessibility Settings")
    }
    static var settings: String { t("設定…", "Settings…") }
    static var quit: String { t("Ocomenuを終了", "Quit Ocomenu") }

    // 設定画面
    static var settingsTitle: String { t("Ocomenu設定", "Ocomenu Settings") }
    static var menuTab: String { t("メニュー", "Menu") }
    static var generalTab: String { t("一般", "General") }
    static var paletteHint: String {
        t("よく使う項目をショートカットメニューにドラッグしてください…", "Drag your favorite items into the shortcut menu…")
    }
    static var previewTitle: String { t("ショートカットメニュー", "Shortcut Menu") }
    static var separator: String { t("区切り線", "Separator") }
    static var newItem: String { t("新しい項目…", "New Item…") }
    static var done: String { t("完了", "Done") }
    static var remove: String { t("削除", "Delete") }
    static var edit: String { t("編集…", "Edit…") }
    static var resetToDefaults: String { t("デフォルトに戻す", "Restore Defaults") }
    static var launchAtLogin: String { t("ログイン時に開く", "Open at Login") }
    static var showMenuBarIcon: String { t("メニューバーに表示", "Show in Menu Bar") }
    static var menuBarIconHint: String {
        t("オフにしても、Ocomenuをもう一度開くとこの設定が表示されます。", "When off, open Ocomenu again to show these settings.")
    }
    static var language: String { t("言語", "Language") }
    // 文言は macOS の似た画面に揃える。出どころは macOS の日本語・英語の文言表（*.loctable）。
    // 除外する場所は Spotlight の「検索のプライバシー」、並べ替えは Finder の「ツールバーをカスタマイズ」、
    // 自分で足す品の種類は Automator の動作名、ログイン・メニューバー・アップデートはシステム設定から
    static var excludedFolders: String { t("除外する場所", "Excluded Locations") }
    static var excludedFoldersHint: String {
        t(
            "Ocomenuのショートカットメニューから除外する場所。ここではFinderの元のメニューが表示されます。",
            "Prevent Ocomenu from replacing the shortcut menu in these locations."
        )
    }
    static var noExcludedFolders: String { t("場所が追加されていません", "No Locations Added") }
    static var addExcludedFolder: String { t("除外するフォルダまたはディスクを追加します", "Add a folder or disk to exclude") }
    static var delete: String { t("削除", "Delete") }
    static var checkForUpdates: String { t("アップデートを確認", "Check for Updates") }
    static func launchToggleFailed(_ reason: String) -> String {
        t("変更できませんでした: \(reason)", "Couldn’t change this setting: \(reason)")
    }

    // 自分で足す項目
    static var kind: String { t("種類", "Type") }
    static var title: String { t("名前", "Name") }
    static var script: String { t("スクリプト", "Script") }
    static var scriptHint: String {
        t("シェル: /bin/zsh　入力の引き渡し方法: 引数として（\"$@\"）", "Shell: /bin/zsh   Pass input: as arguments (\"$@\")")
    }
    static var application: String { t("アプリケーション", "Application") }
    static var folder: String { t("フォルダ", "Folder") }
    static var choose: String { t("選択…", "Choose…") }
    static var cancel: String { t("キャンセル", "Cancel") }
    static var save: String { t("保存", "Save") }

    static func kindLabel(_ kind: CustomAction.Kind) -> String {
        switch kind {
        case .script: return t("シェルスクリプトを実行", "Run Shell Script")
        case .openWith: return t("このアプリケーションで開く", "Open With")
        case .copyTo: return t("Finder項目をコピー", "Copy Finder Items")
        case .moveTo: return t("Finder項目を移動", "Move Finder Items")
        }
    }

    // 実行時
    static func actionFailed(_ title: String) -> String {
        t("“\(title)”を実行できませんでした", "Couldn’t run “\(title)”")
    }
    static func scriptExited(_ code: Int32) -> String {
        t("スクリプトが終了コード\(code)で終了しました。", "The script exited with code \(code).")
    }
    static func scriptSignaled(_ signal: Int32) -> String {
        t("スクリプトがシグナル\(signal)で停止しました。", "The script was stopped by signal \(signal).")
    }
}
