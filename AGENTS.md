# CapsStack 開発ガイド

このファイルは、リポジトリの変更を行うエージェント向けの作業ルールです。プロジェクトの利用方法や機能の詳細は、まず [README.md](README.md) を参照してください。より深いディレクトリに別の `AGENTS.md` がある場合は、その指示を優先します。

## コミュニケーション

- 作業報告、確認結果、変更理由は原則として日本語で書きます。
- 依頼内容に危険な操作、仕様との不整合、検証不足がある場合は、実行前に具体的な影響を説明します。
- 変更したファイル、実行した検証、未検証の事項を最終報告で明示します。

## プロジェクト概要

CapsStack は macOS 14 以降で動作する SwiftUI / AppKit アプリです。Caps Lock の ON 区間を退席区間として扱い、Codex、Claude Code、OpenCode、Pi のローカルセッションを収集して、選択した CLI で復帰ブリーフを生成します。アプリ本体と、履歴・メモ・状態確認に使う `capsstack-cli` を同じ SwiftPM パッケージからビルドします。

## 前提環境

- macOS 14 以降
- Xcode 26 または対応する Swift toolchain
- Swift tools version 6.0、言語モードは Swift 5
- UI、コード署名、`.pkg`、`notarytool` の検証は macOS 上で行う

## リポジトリ構成

- `Sources/CapsStack/App`: アプリライフサイクル、シーン、`AppController`
- `Sources/CapsStack/Models`: 設定、履歴、収集結果、要約モデル
- `Sources/CapsStack/Services`: Caps Lock 監視、セッション収集、CLI 実行、要約、通知
- `Sources/CapsStack/Stores`: ローカル履歴と一時成果物の永続化
- `Sources/CapsStack/Views`: 履歴、設定、メニューバー、退席前メモの UI
- `Sources/CapsStack/Support`: デザイン、Markdown、フォーマットなどの共通処理
- `Sources/CapsStackCLI`: `capsstack-cli` の引数解析、履歴・メモ・状態コマンド
- `Tests/CapsStackTests`: アプリ本体のモデル、サービス、UI レンダリングのテスト
- `Tests/CapsStackCLITests`: CLI の引数、出力、履歴・メモ操作のテスト
- `Packaging`: `Info.plist`、entitlements、アイコン、`.pkg` 用アセット
- `script`: 開発用起動、パッケージ作成、 notarization 用スクリプト
- `plugins/capsstack`: エージェント連携用プラグインと CLI ラッパー
- `Design`、`design-qa.md`: ブランド素材と UI 検証記録

## よく使うコマンド

変更後は、影響範囲に応じたコマンドに加えて、可能なら `swift test` を実行します。

```sh
# 全テスト
swift test

# 個別 product のビルド
swift build --product CapsStack
swift build --product capsstack-cli

# 厳格なコンパイル検証
swift build --product CapsStack \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warnings-as-errors

# アプリをビルド、バンドル化、署名して起動
./script/build_and_run.sh

# 起動確認（UI のスモーク検証）
CAPSSTACK_DEMO_DATA=1 ./script/build_and_run.sh --verify

# デバッグ・ログ確認
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry

# ローカル用 PKG
./script/build_pkg.sh
```

CLI の開発確認には次を使います。

```sh
swift run capsstack-cli --help
swift run capsstack-cli status --json
swift run capsstack-cli history latest --markdown
printf '%s' '次に行う作業' | swift run capsstack-cli memo set --stdin --json
```

`build_and_run.sh` はアプリ本体を `dist/CapsStack.app` に、CLI を `Contents/Helpers/capsstack` に配置します。macOS の大文字小文字非区別ファイルシステムで `CapsStack` と衝突するため、CLI の product 名と同梱名は意図的に異なります。

## 実装時に守る境界

### セッション収集と要約

- 収集元 CLI と要約担当 CLI は独立した設定です。片方の設定変更で、もう片方を暗黙に変更しないでください。
- 元の CLI セッションを `resume` したり、元の作業ディレクトリでツール付き実行をしたりしないでください。要約は隔離した一時ディレクトリで行い、読み取り専用またはツール無効の実行にします。
- OpenCode は DB-backed storage を使うため、保存ファイルを JSONL として直接解釈せず、公式 CLI の `session list` / `export` 境界を使います。要約時の OpenCode 用 DB も一時ディレクトリへ隔離します。
- 要約成功後は生ログと一時資料を削除し、失敗時だけ再要約用の pending artifact を保持します。再試行経路を壊さないよう、保存・削除タイミングを変更する場合は関連テストも更新します。
- CLI ログがなく退席前メモだけがある場合も要約できるよう、メモを合成セッションとして扱う現在の挙動を維持します。
- CLI の実行にはタイムアウト、出力サイズ上限、キャンセル処理があります。`ProcessRunner` や `SummaryOrchestrator` の変更では、ハング、過大な UTF-8 切断、キャンセル後の遅延書き込みを回帰させないでください。

### 状態と並行処理

- `AppController` は `@MainActor` です。UI 状態の公開はメインアクター上で行い、バックグラウンド処理の完了後に古い workflow が状態や履歴を上書きしないようにします。
- 収集・要約 workflow は一度に一つだけ進め、設定変更、履歴削除、再要約時には stale なタスクをキャンセルします。
- Caps Lock の状態、退席開始時刻、設定変更の復元処理を変更する際は、起動時に Caps Lock が ON のケースと、アプリ再起動後に保存済み退席区間を復元するケースを確認します。

### UI とデザイン

- 既存のブランド色、ネイティブ macOS のウインドウ・メニュー構成、アクセシビリティラベルを尊重します。
- アプリは通常の macOS アプリとして動作し、履歴ウインドウ、設定、メニューバー extra、退席前メモウインドウを提供します。トップレベルメニューの順序や SwiftUI が所有する submenu を無理に並べ替えないでください。
- UI のサイズや見た目を変更した場合は、`CAPSSTACK_QA_OUTPUT` を使ったレンダリングテストや、必要に応じて `design-qa.md` の検証項目も更新します。
- デモデータは `--capsstack-demo-data` によるメモリ内データです。デモ表示・削除・クリアで実データの `HistoryStore` を変更しないでください。

### プライバシーとローカルデータ

- CapsStack 自身は収集資料を独自サーバーへ送信しません。ただし、選択した要約 CLI が各サービスへ入力を送る可能性があります。新しいログ出力や診断情報に、セッション本文・メモ・認証情報を含めないでください。
- API キー、トークン、秘密鍵、署名証明書、個人のセッションログをコミットしないでください。
- 履歴・メモの CLI はアプリと同じローカル保存先を使いますが、生ログにはアクセスしません。CLI の read-only コマンドに削除や変更処理を混ぜないでください。

## テスト方針

- ロジック変更では対応する XCTest を追加・更新します。特に `Tests/CapsStackTests` と `Tests/CapsStackCLITests` の両方に影響する変更を見落とさないでください。
- CLI の JSON 出力はスキーマとして扱われるため、フィールド名、終了コード、`completed` / `pending` / `empty` の状態意味を不用意に変更しないでください。
- 日付、ファイル名、パス、UTF-8 サイズ、壊れた履歴、CLI のタイムアウト、フォールバック、再要約、デモデータ分離には回帰テストを優先します。
- UI 変更では、少なくとも `swift test` と `swift build --product CapsStack -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` を通し、可能なら `CAPSSTACK_DEMO_DATA=1 ./script/build_and_run.sh --verify` で起動確認します。
- テストや起動確認で生成される `.build/`、`build/`、`dist/`、`outputs/` は追跡対象外です。差分に意図しない生成物が入っていないことを `git status --short` で確認します。

## パッケージングと署名

- `script/build_pkg.sh` は同じバージョンの `outputs/CapsStack.pkg` を再生成せず、異なるバージョンの場合だけ置き換えます。出力先や lock の扱いを壊さないでください。
- Developer ID 署名時は `DEVELOPER_ID_APPLICATION` と `DEVELOPER_ID_INSTALLER` を環境変数で渡します。値や notarytool の認証情報をソースやログに書き込まないでください。
- notarization は `NOTARY_PROFILE` を指定して `script/notarize.sh` を実行します。署名・公証は利用可能な証明書とネットワークが必要なため、コード変更の通常テストとは分けて扱います。

## 変更の進め方

1. `git status --short` と関連ファイルを確認し、既存のユーザー変更を上書きしない。
2. 変更対象に対応するモデル、サービス、UI、テストを一緒に確認する。
3. 小さく実装し、まず対象テスト、次に `swift test` を実行する。
4. macOS 固有の変更は必要に応じて `build_and_run.sh --verify`、ログ、UI QA で確認する。
5. `git diff --check` と `git status --short` で不要な生成物・秘密情報・改行エラーがないことを確認する。

不明な仕様を推測で広げず、README、既存テスト、CLI 契約、直近の実装に合わせて最小の変更を選びます。
