# 素材のクレジット

`assets/` に置く素材の出典とライセンス。記録の規約は `~/.claude/rules/coding-rules-general-assets-license.md`。

素材を追加・差し替えたら、同じ変更でここに記録する。各素材のファイルは `assets/` からの相対パスをバッククォートで囲んで書く。

## フォント

- ファイル: `fonts/NotoSansJP[wght].ttf` (ライセンス全文は `fonts/OFL.txt`)
- 素材名・作者: Noto Sans JP (Variable font。wght 軸を持つ) / Adobe ほか (著作権表記は `fonts/OFL.txt` の先頭: Copyright 2014-2021 Adobe, Reserved Font Name 'Source')
- 入手 URL: https://github.com/google/fonts/blob/main/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf (bannzai/goki-hunter が 2026-10-19 に取得したファイルを 2026-11-25 に写した。goki-hunter の取得時点で `ofl/notosansjp` を最後に変更したコミットは 66a36c8c94b1a5d992ee4e7f392fccfe4945767c)
- ライセンス: SIL Open Font License 1.1 (全文を同梱する)。クレジット表記は不要
- 改変: なし
- 用途: プロジェクト全体の既定フォント (`scripts/main.gd` の `FONT`。メインシーンの theme の `default_font` に設定する)。Godot の既定フォントは日本語の字形を持たず、CI の Linux ランナーには日本語のシステムフォントも無いため同梱する

## BGM

どの画面で鳴らすかは `scripts/audio/audio_catalog.gd` を正とする。

- ファイル: `audio/bgm_title.ogg`
- 素材名・作者: Prologue Theme / CleytonKauffman
- 入手 URL: https://opengameart.org/content/prologue-theme
- ライセンス: CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/)。クレジット表記は不要
- 改変: `Prologue Theme.zip` 内の `Prologue Theme.ogg` を取り出し、ファイル名を変更し、読み込み負荷とリポジトリ容量を抑えるため OGG Vorbis (`-q:a 4`) で再エンコード

- ファイル: `audio/bgm_mansion.ogg`
- 素材名・作者: Hot Spring Town (`hot_spring_town_1.ogg`) / Kistol
- 入手 URL: https://opengameart.org/content/hot-springs-town (2026-11-27 に取得)
- ライセンス: CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/)。クレジット表記は不要 (作者の任意記載: "No credits necessary, though you may credit me as Kistol if you would like.")
- 改変: ファイル名を変更し、読み込み負荷とリポジトリ容量を抑えるため OGG Vorbis (libvorbis `-q:a 4`) で再エンコード (配布元は `q0.8` の 4.4MB。再エンコード後 2.1MB)
- 経緯: 2026-11-27 まで使っていた Snowfall (Kistol, CC0) を、owner の「微妙に不気味」の感想を受けて差し替えた (issue #79)

## 効果音

どの出来事で鳴らすかは `scripts/audio/audio_catalog.gd` を正とする。

- ファイル: `audio/sfx_pluck_hair.ogg`
- 素材名・作者: Classic fanfare lick (`fanfare_3.ogg`) / fvcalderan
- 入手 URL: https://opengameart.org/content/classic-fanfare-lick
- ライセンス: CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/)。クレジット表記は不要
- 改変: ファイル名変更のみ

- ファイル: `audio/sfx_earn_money.ogg`
- 素材名・作者: Purchasing Sound Effect (`snd_purchase_0.wav`) / Spring Spring
- 入手 URL: https://opengameart.org/content/purchasing-sound-effect
- ライセンス: CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/)。クレジット表記は不要
- 改変: ファイル名変更、および読み込み負荷と容量を抑えるため 44.1kHz OGG Vorbis (`-q:a 5`) へ再エンコード

- ファイル: `audio/sfx_buy_tool.ogg`
- 素材名・作者: Interface Sounds (`Audio/confirmation_002.ogg`) / Kenney
- 入手 URL: https://opengameart.org/content/interface-sounds
- ライセンス: CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/)。クレジット表記は不要
- 改変: `kenney_interfaceSounds.zip` から取り出し、ファイル名変更のみ

- ファイル: `audio/sfx_button.ogg`
- 素材名・作者: Interface Sounds (`Audio/click_001.ogg`) / Kenney
- 入手 URL: https://opengameart.org/content/interface-sounds
- ライセンス: CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/)。クレジット表記は不要
- 改変: `kenney_interfaceSounds.zip` から取り出し、ファイル名変更のみ
