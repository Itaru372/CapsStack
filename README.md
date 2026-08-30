# CapsStack

> **Step away. Come back caught up.**

CapsStackは、AIコーディングエージェントへ作業を任せて席を離れたあと、戻った瞬間に状況へ追いつくためのmacOSアプリです。Codex、Claude Code、OpenCode、Pi、GitHub Copilot、Kilo Code、Goose、Qwen Code、Continue、Gemini CLIのセッションを、進捗・判断・ブロッカー・次の一手が分かる「復帰ブリーフ」にまとめます。

AIを速くするのではなく、**人間がAIの作業状態へ戻るまでの時間を短くする**ためのツールです。

## 使い方

1. AIエージェントへ作業を任せ、離席するときにCaps LockをON
2. CodexやClaude Codeなどが作業している間、その場を離れる
3. 戻ってCaps LockをOFFにすると、離席中のセッションから復帰ブリーフを生成

```text
Caps Lock ON   →   Step away   →   Agents keep working
Caps Lock OFF  →   Return brief: progress / decisions / blockers / next steps
```

## こんな人向け

- MacでCodex CLIやClaude Codeへ数分〜数十分のタスクを任せる
- 複数のターミナル型コーディングエージェントを使い分ける
- 離席後、長い会話ログやGit diffを読む前に現在地を把握したい
- エージェントが「何をしたか」だけでなく「次に何をすべきか」を知りたい

CapsStackが直接収集するのはターミナル型エージェントのセッションです。ChatGPTデスクトップアプリやCursorなどのGUI作業は直接収集せず、退席前メモで復帰ブリーフへ補足できます。

## 特徴

- 収集元は10種類の対応エージェントから独立して複数選択
- Caps Lock ON区間の記録をプロジェクトごと、その中のセッションごとに整理
- 要約担当CLIは収集元と無関係に選択
- 要約担当ごとにモデルとReasoning（CLI固有のeffort / variant / thinking）を指定
- 主担当が失敗した場合は利用可能な別CLIへ自動フォールバック
- 退席前に任意メモを入力でき、CLIログがなくても要約を実行（GUI版エージェントの作業補足に対応）
- 誤操作を防ぐ最短退席時間しきい値を設定可能
- 履歴の要約をクリップボードへコピー、Markdownとして書き出し
- 元セッションをresumeせず、隔離した一時ディレクトリで要約のみ実行
- 成功時は生ログを削除し、失敗時だけ再要約用に保持
- 履歴ウィンドウ、macOS通知、`.pkg`生成に対応
- 匿名テレメトリは初回セットアップで明示的にオプトインした場合だけ送信（SDKの自動収集・Session Replayは無効）

## 必要環境

- macOS 14以降
- Xcode 26または対応するSwift toolchain
- 要約に使うCLIがインストール・認証済みであること

初回起動時の収集元と要約担当は、このMacで検出できたCLI（または読めるローカル履歴）から自動設定されます。CodexとClaude Codeのどちらか一方しか入っていない場合でも、未導入側を既定で呼び出しません。利用可能な設定値は自動設定後も保持され、未導入の要約CLIは実行せず、自動フォールバックが有効なら利用可能なCLIへ切り替えます。別のCLIを後から追加した場合は設定画面から収集元・要約担当を選べます。旧バージョンから移行する場合も、CLIも履歴も使えない収集元だけは一度だけ自動停止します。

## 対応CLIの実装境界

| CLI | セッション収集 | 要約起動 | モデル / Reasoning |
| --- | --- | --- | --- |
| Codex | `~/.codex/sessions` のJSONL | `codex exec --ephemeral --sandbox read-only --output-schema` | `--model` / `--config model_reasoning_effort=...` |
| Claude Code | `~/.claude/projects` のJSONL | `claude -p`（安全境界は常時、任意機能だけ `--help` で有効化） | `--model` / `--effort` |
| OpenCode | `opencode session list --format json` + `opencode export` | `opencode run --format json --variant` | `--model provider/model` / model固有のvariant |
| Pi | `~/.pi/agent/sessions` のJSONL | `pi --print --no-session --no-tools` | `--model` / `--thinking` |
| GitHub Copilot | `$COPILOT_HOME/session-state/*/events.jsonl`（既定 `~/.copilot`） | `copilot -p --available-tools= --disable-builtin-mcps` | `--model` / `--effort` |
| Kilo Code | `kilo session list --all --format json` + `kilo export` | `kilo run --agent ask --format json` | `--model` |
| Goose | `goose session list --format json` + `goose session export --format json` | `GOOSE_MODE=chat goose run --no-session --output-format json` | `--model` |
| Qwen Code | `$QWEN_RUNTIME_DIR` / `$QWEN_HOME` の `projects/`・`tmp/`（新旧JSONL配置を両対応） | `qwen -p --safe-mode --exclude-tools ... --max-tool-calls 0` | `--model` |
| Continue | `~/.continue/sessions` のJSON | —（収集専用） | — |
| Gemini CLI | `$GEMINI_CLI_HOME/.gemini/tmp`（既定 `~/.gemini/tmp`）のJSON/JSONL | —（収集専用） | — |

OpenCode、Kilo Code、GooseはDB-backed storageを直接解釈せず、公式CLIの一覧・export境界を使います。Gemini CLIとContinueは複数行JSON、Qwen Codeは新旧JSONLの保存配置を読み取ります。GitHub Copilotは `events.jsonl` だけを読み、同じセッションフォルダにあるcheckpointやworkspace artifactを本文として取り込みません。

要約時は全CLIで元の作業ディレクトリをcwdにせず、一時ディレクトリを使います。Copilotは利用可能ツールと組み込みMCPを空にし、KiloはAsk agent、Gooseは全ツール無効のChat mode、Qwenはsafe mode・tool deny・tool-call上限0を併用します。OpenCode要約のセッションDBも一時ディレクトリへ隔離します。

モデルIDとReasoningの有効値はCLIやモデルごとに変わるため、設定欄は自由入力です。空欄なら各CLIの既定値を使います。OpenCodeのvariantはモデルごとに有効値が異なります。ContinueとGemini CLIは安全な無人要約境界を保守的に評価し、現時点では収集専用です。

Cursor CLIは非対話モードが書込み権限を持ち、Aiderはプロジェクト横断の中央履歴/export契約がなく、Roo CodeはCLI境界が移行中のため、名前だけの対応にはしていません。安定した公式境界が確認できた時点で追加します。

## GUI版エージェントと退席前メモ

ChatGPTデスクトップアプリやCursorなど、JSONLログを読めないGUIエージェントの作業はCapsStackが直接収集できません。その代わり、メニューバーの「退席前メモ...」から専用ウィンドウへ入力しておくと、復帰時の要約資料に含まれます。

CLIセッションが一件も検出されず、退席前メモだけがある場合は、メモ単体を要約対象として扱います。これにより、GUI専用ワークフローや短い外出でも履歴が空になりません。

実装時の照合先： [Codex exec CLI](https://github.com/openai/codex/blob/main/codex-rs/exec/src/cli.rs)、[Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code/cli-usage)、[OpenCode CLI](https://dev.opencode.ai/docs/cli/)、[Pi usage](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/usage.md)、[GitHub Copilot CLI](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)、[Kilo CLI](https://kilo.ai/docs/code-with-ai/platforms/cli)、[Goose CLI](https://github.com/aaif-goose/goose/blob/main/documentation/docs/guides/goose-cli-commands.md)、[Qwen headless mode](https://github.com/QwenLM/qwen-code/blob/main/docs/users/features/headless.md)、[Continue headless mode](https://docs.continue.dev/cli/headless-mode)、[Gemini session management](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/session-management.md)。

設定画面のエージェント画像はネット上の公式素材を取得してローカル同梱しています。Gemini CLIは[公式Brand Kit](https://geminicli.com/brand-kit/)のアイコン、Kilo Code・Goose・Qwen Code・Continueは各公式GitHub組織の公開プロフィール画像を使用します。アプリ起動時に外部画像ホストへ通信しません。

## 開発

```sh
swift test
./script/build_and_run.sh --verify
```

CodexアプリのRunボタンも `./script/build_and_run.sh` を呼び出します。

## CapsStack CLI

CLIは履歴の参照、退席前メモの受け渡し、対応エージェントCLIの検出を行います。履歴やメモはmacOSアプリと同じローカル保存先を使い、生ログにはアクセスしません。

開発時は、macOSの大文字小文字非区別ファイルシステムでアプリ名と衝突しないSwiftPM product名を使います。

```sh
swift run capsstack-cli --help
swift run capsstack-cli status --json
swift run capsstack-cli history latest --markdown
printf '%s' '次は回帰テストを実行' | swift run capsstack-cli memo set --stdin --json
```

`.app` / `.pkg` には `CapsStack.app/Contents/Helpers/capsstack` として同梱されます。`Contents/MacOS/CapsStack` と同じディレクトリに小文字名を置くと、macOS標準の大文字小文字非区別ファイルシステムでアプリ本体と衝突するためです。

```sh
/Applications/CapsStack.app/Contents/Helpers/capsstack status
```

主なコマンド：

| コマンド | 用途 |
| --- | --- |
| `status [--json]` | 履歴、メモ、対応CLIの状態を確認 |
| `history list [--limit N] [--json]` | 新しい順に履歴を一覧表示 |
| `history latest [--json\|--markdown]` | 最新の復帰要約を表示 |
| `history show <UUID> [--json\|--markdown]` | 指定した履歴を表示 |
| `memo get [--json]` | 現在の退席前メモを表示 |
| `memo set <text> [--json]` | 退席前メモを保存 |
| `memo set --stdin [--json]` | stdinから退席前メモを安全に保存 |
| `memo clear [--json]` | 退席前メモを消去 |

## AIエージェント用プラグイン

検証済みのCodexプラグインは `plugins/capsstack` にあります。プラグインには次のSkillsを同梱しています。

- `capsstack-context`: 退席前の作業状況を短いメモとして保存し、連携状態を確認
- `capsstack-history`: 最新または指定した復帰要約をJSON / Markdownで安全に取得

Skillsは `CAPSSTACK_CLI`、リポジトリ内の開発ビルド、`PATH`、`/Applications/CapsStack.app/Contents/Helpers/capsstack` の順でCLIを解決します。プラグインの配布時は `plugins/capsstack` ディレクトリをCodex marketplaceのplugin sourceとして利用できます。

## GitHubへ初回push

GitHubで新しい空のリポジトリを作成します。初回の履歴をローカルで作るため、作成時にREADME、`.gitignore`、Licenseの自動生成は選択しません。

ローカルでコミット対象を確認してから、初回コミットを作成します。`.gitignore` によりビルド生成物、ローカルのCodex設定、環境ファイル、秘密鍵・署名ファイルは対象外になります。

```sh
cd /path/to/CapsStack
git status --short --ignored
git add .
git status --short
git diff --cached --check
git diff --cached
git commit -m "Initial commit"
git branch -M main
```

コミット内容を確認したら、GitHubリポジトリを `origin` として登録してpushします。`OWNER` と `REPOSITORY` は自分の値に置き換えてください。

SSHを使う場合：

```sh
git remote add origin git@github.com:OWNER/REPOSITORY.git
git push -u origin main
```

HTTPSを使う場合：

```sh
git remote add origin https://github.com/OWNER/REPOSITORY.git
git push -u origin main
```

すでに `origin` が登録済みなら `git remote set-url origin ...` を使います。GitHub CLIやSSH agentなどで認証し、アクセストークンをURLやソースに直接書かないでください。2回目以降は `git push` だけで更新できます。

## PKG

ローカル確認用のad-hoc署名パッケージ：

```sh
./script/build_pkg.sh
```

Developer ID署名：

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: ..." \
DEVELOPER_ID_INSTALLER="Developer ID Installer: ..." \
./script/build_pkg.sh
```

`outputs/CapsStack.pkg` はバージョンごとに1つだけ保持します。同じバージョンがすでにある場合は再生成せず、異なるバージョンの場合だけ新しいパッケージを作ってから置き換えます。生成中に別のパッケージ生成が走った場合も、重複生成せず終了します。

バージョンを更新する場合：

```sh
CAPSSTACK_VERSION="0.2.0" CAPSSTACK_BUILD="0.2.0" ./script/build_pkg.sh
```

notarytoolの認証情報をKeychainへ保存した後：

```sh
NOTARY_PROFILE="capsstack-notary" ./script/notarize.sh
```

## プライバシー

CapsStackはセッション本文、退席前メモ、作業ディレクトリ、ファイルパスを独自サーバーへ送信しません。ただし要約CLIは各サービスの設定に従って入力を処理します。要約成功後、生ログと一時資料は削除されます。

匿名テレメトリは、復帰ブリーフの成功率・失敗種別・利用操作などの集計イベントだけをPostHogへ送信します。初期状態はOFFで、初回セットアップで明示的にONにした場合だけ有効です。設定画面には常設のトグルを表示せず、「一般」からセットアップを開き直すと選択を変更できます。自動ライフサイクル収集、画面遷移の自動収集、Session Replay、LLMのプロンプト／出力収集は使用しません。PostHogプロジェクトが設定されていないビルドでは、イベントは送信されません。

PostHogを有効にした配布用ビルドは、公開プロジェクトトークンをビルド時に埋め込みます。トークンや送信先はソースへコミットせず、次の環境変数で指定します。

```sh
CAPSSTACK_POSTHOG_PROJECT_TOKEN="phc_..." \
CAPSSTACK_POSTHOG_HOST="https://us.i.posthog.com" \
./script/build_and_run.sh --verify
```

EU Cloudを使う場合は`CAPSSTACK_POSTHOG_HOST="https://eu.i.posthog.com"`を指定します。PostHogのプロジェクトトークンは公開識別子ですが、個人APIキーやシークレットキーは使用・保存しないでください。

## デザインについて

Caps Lockを物理スイッチとして扱う軽快な体験は[Capsomnia](https://github.com/fuji-mak/Capsomnia/)に着想を得ています。CapsStackはコード、アセット、文言、画面構成を流用せず、セッション収集と復帰要約のために独立実装しています。スリープ制御や特権ヘルパーも含みません。
