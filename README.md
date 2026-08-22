# CapsStack

Caps LockをONにしている間を「退席」とみなし、Codex CLI / Claude Code CLI / OpenCode / Piのセッション記録を収集して、選択したCLIとモデルで復帰時に要約するmacOSメニューバーアプリです。

## 特徴

- 収集元はCodex / Claude Code / OpenCode / Piを独立して複数選択
- 要約担当CLIは収集元と無関係に選択
- 要約担当ごとにモデルとReasoning（CLI固有のeffort / variant / thinking）を指定
- 主担当が失敗した場合は利用可能な別CLIへ自動フォールバック
- 元セッションをresumeせず、隔離した一時ディレクトリで要約のみ実行
- 成功時は生ログを削除し、失敗時だけ再要約用に保持
- 履歴ウィンドウ、macOS通知、`.pkg`生成に対応

## 必要環境

- macOS 14以降
- Xcode 26または対応するSwift toolchain
- 要約に使うCLIがインストール・認証済みであること

## 対応CLIの実装境界

| CLI | セッション収集 | 要約起動 | モデル / Reasoning |
| --- | --- | --- | --- |
| Codex | `~/.codex/sessions` のJSONL | `codex exec --ephemeral --sandbox read-only --output-schema` | `--model` / `--config model_reasoning_effort=...` |
| Claude Code | `~/.claude/projects` のJSONL | `claude -p`（対応フラグだけ `--help` で有効化） | `--model` / `--effort` |
| OpenCode | `opencode session list --format json` + `opencode export` | `opencode run --format json --variant` | `--model provider/model` / model固有のvariant |
| Pi | `~/.pi/agent/sessions` のJSONL | `pi --print --no-session --no-tools` | `--model` / `--thinking` |

OpenCodeは現行版がDB-backed storageを使うため、保存ファイルを直接JSONLとして解釈せず、公式CLIの一覧・export境界を使います。要約時は全CLIで元の作業ディレクトリをcwdにせず、読み取り専用またはツール無効の実行にしています。OpenCode要約のセッションDBも一時ディレクトリへ隔離します。

モデルIDとReasoningの有効値はCLIやモデルごとに変わるため、設定欄は自由入力です。空欄なら各CLIの既定値を使います。OpenCodeのvariantはモデルごとに有効値が異なります。

実装時の照合先： [Codex exec CLI](https://github.com/openai/codex/blob/main/codex-rs/exec/src/cli.rs)、[Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code/cli-usage)、[OpenCode CLI](https://dev.opencode.ai/docs/cli/)、[OpenCode permissions](https://dev.opencode.ai/docs/permissions/)、[Pi usage](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/usage.md)。

## 開発

```sh
swift test
./script/build_and_run.sh --verify
```

CodexアプリのRunボタンも `./script/build_and_run.sh` を呼び出します。

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

CapsStack自身は収集資料を独自サーバーへ送信しません。ただし要約CLIは各サービスの設定に従って入力を処理します。要約成功後、生ログと一時資料は削除されます。

## デザインについて

Caps Lockを物理スイッチとして扱う軽快な体験は[Capsomnia](https://github.com/fuji-mak/Capsomnia/)に着想を得ています。CapsStackはコード、アセット、文言、画面構成を流用せず、セッション収集と復帰要約のために独立実装しています。スリープ制御や特権ヘルパーも含みません。
