<p align="center">
  <img src="assets/vocatrack-logo.png" alt="vocatrack" width="128" />
</p>

# vocatrack

英語・日本語・韓国語対応のローカルファースト語彙トラッカー。TestYourVocabスタイルのレベル推定機能付き。

> English: [README.md](./README.md) | 한국어: [README.ko.md](./README.ko.md)

## インストール

```text
/plugin marketplace add https://github.com/flame91/vocatrack
/plugin install voca@flame91-voca-marketplace
```

## クイックスタート

インストール後、セットアップウィザードを実行してください：

```text
/voca setup
```

言語選択、主言語、スキャンモデル、レベルテストを案内します。セットアップ完了前は他の`/voca`コマンドは使用できません。

## 機能

| コマンド | 説明 |
|---|---|
| `/voca setup` | 初回セットアップウィザード（言語、スキャンモデル、レベルテスト） |
| `/voca add <単語>` | 意味、例文、コンテキスト、タグとともに記録 |
| `/voca list` | 最近の語彙エントリをテーブル表示 |
| `/voca search <q>` | 単語/意味/例文/コンテキストの大文字小文字無視検索 |
| `/voca stats` | ダッシュボード（レベル、ライフサイクル、活動、hookの精度） |
| `/voca review` | 未評価のアクティブ単語の対話型レビュー |
| `/voca rate <単語>` | 単語を評価：memorized、learning、unsure |
| `/voca archive <単語>` | 単語をアーカイブ |
| `/voca master <単語>` | 単語をmasteredに昇格 |
| `/voca restore <単語>` | アーカイブ/mastered単語をactiveに復元 |
| `/voca level test [en\|ja\|ko]` | 3段階適応型語彙量推定 |
| `/voca scan` | セッション会話から候補単語を抽出（非同期） |
| `/voca queue` | 自動抽出された候補単語のpicker UI |
| `/voca config` | 対話型設定 |
| `/voca domain` | ドメインタグレジストリ管理（一覧 / 追加 / 削除） |
| `/voca source` | ソースタグレジストリ管理（一覧 / 追加 / 削除） |
| `/voca reclassify` | 既存単語を現在のコンベンションで再タグ付け |

**Stop hook**がセッション終了時にバックグラウンドでHaikuを呼び出し、候補単語を自動抽出して既存の単語リストと重複排除します。

## レベル評価

`/voca level test`は3段階の適応型テストで語彙量を推定し、CEFRバンド（L2学習者向け）またはネイティブスピーカー参照バンドにマッピングします。

### CEFRバンド（全言語共通）

| バンド | 語彙量 | 説明 |
|---|---|---|
| A1 | < 1,500 | 入門 |
| A2 | < 2,500 | 初級 |
| B1 | < 5,000 | 中級 |
| B2 | < 8,000 | 中上級 |
| C1 | < 12,000 | 上級 |
| C2 | < 17,000 | 最上級 |

### ネイティブバンド

| バンド | EN | JA | KO |
|---|---|---|---|
| 教養ある成人 | < 25,000 | < 25,000 | < 22,000 |
| 上級 | < 35,000 | < 35,000 | < 30,000 |
| トップ層 | < 45,000 | < 45,000 | < 40,000 |
| 多読家 | < 55,000 | — | — |
| 上位1% | ≥ 55,000 | ≥ 45,000 | ≥ 40,000 |

**出典**: EN — [testyourvocab.com](http://testyourvocab.com/) 2013（200万人以上） · JA — NTT語彙数推定テスト補正版、阪本（1955） · KO — 김광해（2003）、국립국어원 빈도調査（2002）

## プライバシー

Stop hookはローカルの`claude` CLIを介してAnthropicのHaiku APIを呼び出します。自身のAnthropicクレデンシャルのみを使用し、第三者には一切送信されません。

## 環境変数

| 変数 | デフォルト | 用途 |
|---|---|---|
| `VOCA_LOCALE` | システムlocale（`ko`/`en`/`ja`、フォールバック`en`） | shellスクリプトのメッセージ言語 |
| `VOCA_STATE_DIR` | `${CLAUDE_PLUGIN_DATA}`または`~/.claude/state` | voca.tsv、profile、configの保存場所 |
| `VOCA_CONFIG_PATH` | `${VOCA_STATE_DIR}/voca-config.json` | 設定ファイルのパス |

## レガシーインストールからの移行

移行スクリプトが旧`vocab*`ファイルを新しい`voca*`名にマッピングします：

```sh
bash ${CLAUDE_PLUGIN_ROOT}/scripts/migrate-from-legacy.sh --dry-run
bash ${CLAUDE_PLUGIN_ROOT}/scripts/migrate-from-legacy.sh
```

## 依存関係

- `bash` 4+、`jq`、`awk`、`sed`、`column`、`python3`（hookのタイムスタンプ用）
- macOS / Linux / WSL

## 制限事項 (v0.1.8)

- shellスクリプトの出力は`VOCA_LOCALE`でko/en/jaにローカライズされます。
- SKILL.md UIの文字列（AskUserQuestion）は主言語設定によるlocale対応レンダリングをサポートします。
- 語彙プールの更新には`tools/_curate.py`が必要です（別途Python venv）。

## ライセンス

CC BY-SA 4.0 -- [LICENSE](./LICENSE)および[NOTICE](./NOTICE)を参照。
