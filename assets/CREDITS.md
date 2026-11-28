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

## 3D モデル

屋敷に置く物の種別とモデルの対応は `scripts/mansion/furniture_models.gd` を正とする。Poly Haven の素材の利用条件は https://polyhaven.com/license (CC0 1.0)。

- ファイル: `models/Sofa_01/` (`Sofa_01_1k.gltf`・`Sofa_01.bin`・`textures/`)
- 素材名・作者: Sofa 01 / Kirill Sannikov (Poly Haven)
- 入手 URL: https://polyhaven.com/a/Sofa_01 (glTF の 1k の版を `https://api.polyhaven.com/files/Sofa_01` の URL から取得)
- ライセンス: CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/)。クレジット表記は不要
- 改変: なし (ゲームが物の大きさに合わせて伸縮して置く)

- ファイル: `models/wooden_table_02/`
- 素材名・作者: Wooden Table 02 / Serhii Khromov (Poly Haven)
- 入手 URL: https://polyhaven.com/a/wooden_table_02 (glTF の 1k の版)
- ライセンス: CC0 1.0。クレジット表記は不要
- 改変: なし

- ファイル: `models/ClassicConsole_01/`
- 素材名・作者: Classic Console 01 / Kirill Sannikov (Poly Haven)
- 入手 URL: https://polyhaven.com/a/ClassicConsole_01 (glTF の 1k の版)
- ライセンス: CC0 1.0。クレジット表記は不要
- 改変: なし (サイドボードとして置く)

- ファイル: `models/GreenChair_01/`
- 素材名・作者: Green Chair 01 / Kirill Sannikov (Poly Haven)
- 入手 URL: https://polyhaven.com/a/GreenChair_01 (glTF の 1k の版)
- ライセンス: CC0 1.0。クレジット表記は不要
- 改変: なし (ニットを掛ける椅子として置く。ニットの掛け布はゲームが基本の形で足す)

- ファイル: `models/first_person_arms.glb`
- 素材名・作者: fps arms (rigged only) / para (OpenGameArt)。作者の記載では MakeHuman の出力を元にしている
- 入手 URL: https://opengameart.org/content/fps-arms-rigged-only (`fps arms.7z` の `FPS ARMS RIG 1.fbx` と `new_diff.png`)
- ライセンス: CC0 1.0 (配布ページの License(s) 欄)。クレジット表記は不要
- 改変: Blender で FBX を読み、肌のテクスチャを貼って glb に書き出した (`scripts/assets/convert_models.py`。`.github/workflows/convert-models.yml` が GitHub Actions で実行する)。ゲームは右腕だけを見せ、左腕の骨を縮めて隠す

- ファイル: `models/buyer.glb`
- 素材名・作者: NPC male Steve / supersteve (OpenGameArt)
- 入手 URL: https://opengameart.org/content/npc-male-steve (`steve_npc1.zip` の `steve_npc1.blend` と服・腕・靴のテクスチャ)
- ライセンス: CC0 1.0 (配布ページの License(s) 欄)。クレジット表記は不要
- 改変: 立って待つ動き (idol) の最初の形でメッシュを固めて骨を外し、顔・頭・耳・口・目の写真のテクスチャを単色に差し替えて glb に書き出した (`scripts/assets/convert_models.py`)。同梱の写真には実在の人の顔が写っているため、Steam で売る物に出さないよう差し替えた (issue #15)

## 布の素材 (テクスチャ)

どの物に貼るかは `scripts/look/look_prototype_room.gd` を正とする。

- ファイル: `textures/dirty_carpet/` (`dirty_carpet_diff_1k.jpg`・`dirty_carpet_nor_gl_1k.jpg`)
- 素材名・作者: Dirty Carpet / Rohit Seervi (Poly Haven)
- 入手 URL: https://polyhaven.com/a/dirty_carpet (色 (Diffuse) と OpenGL の向きの法線 (nor_gl) の 1k の jpg)
- ライセンス: CC0 1.0。クレジット表記は不要
- 改変: なし (ゲームが色を掛けて臙脂に寄せる)

- ファイル: `textures/knitted_fleece/`
- 素材名・作者: Knitted Fleece / colormass・Rico Cilliers (Poly Haven)
- 入手 URL: https://polyhaven.com/a/knitted_fleece (1k の jpg)
- ライセンス: CC0 1.0。クレジット表記は不要
- 改変: なし

- ファイル: `textures/poly_wool_herringbone/`
- 素材名・作者: Poly Wool Herringbone / colormass・Rico Cilliers (Poly Haven)
- 入手 URL: https://polyhaven.com/a/poly_wool_herringbone (1k の jpg)
- ライセンス: CC0 1.0。クレジット表記は不要
- 改変: なし
