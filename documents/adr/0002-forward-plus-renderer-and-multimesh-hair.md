# 0002. レンダラを Forward+ に決め、表面ごとの MultiMesh + swap-remove で毛を描画する

## Status

Accepted

## Context

`documents/DIRECTION.md`「判定基準」の 1 行目は、屋敷の 1 部屋に毛を何本まで描けるか (継続のしきい値: CI で 10 万本を描画でき、録画・画面が真っ黒でない) を最大の実現性リスクとして挙げている。また [ADR 0001](0001-godot-gdscript-steam-desktop-no-backend.md) では、CI (GPU の無い ubuntu-24.04 ランナー) で動作確認済みだった GL Compatibility を暫定レンダラとし、毛の描画の試作で Forward+ / Mobile がソフトウェア Vulkan (Mesa lavapipe) で動くかを CI で実測して決め直すことにしていた。

試作シーン (`scenes/hair_prototype.tscn`、床とソファの 2 表面を持つ 1 部屋) とベンチマーク (`make hairbench`、`scripts/dev/hairbench.gd`) を作り、GitHub Actions (`ubuntu-24.04` + Xvfb + Mesa 25.2.8、Godot 4.7.2-stable) 上で 3 レンダラすべてを実測した (run: https://github.com/bannzai/cat-hair/actions/runs/45762690680 )。毛のメッシュは 1 本あたり 3 セグメント・7 頂点・5 三角形の曲がった先細り形状で、白・黒・三毛の色と向きをランダムにばらつかせた。

### CI 実測結果 (1 フレームの描画時間 avg ms / setup ms / 描画・1 本削除の成否)

| 毛の本数 | GL Compatibility (Mesa llvmpipe GL 4.5) | Forward Mobile (Mesa lavapipe Vulkan 1.4.318) | Forward+ (Mesa lavapipe Vulkan 1.4.318) |
| --- | --- | --- | --- |
| 1,000 | 62.15 ms (setup 1.05 ms) | 156.67 ms (min 69.04 ms / setup 1.65 ms) | 154.02 ms (min 58.78 ms / setup 1.64 ms) |
| 10,000 | 80.10 ms (setup 6.39 ms) | 79.29 ms (setup 6.40 ms) | 73.60 ms (setup 6.26 ms) |
| 100,000 | 191.78 ms (setup 65.91 ms) | 154.48 ms (setup 65.15 ms) | 187.42 ms (setup 65.28 ms) |
| 1,000,000 | 1,111.20 ms (setup 669.10 ms) | 681.09 ms (setup 665.66 ms) | 1,003.07 ms (setup 660.96 ms) |
| 全本数の描画・1 本削除 | 成功 (remove_ok=true) | 成功 (remove_ok=true) | 成功 (remove_ok=true) |
| ログの WARNING / ERROR | V-Sync WARNING 1 件 (`Could not set V-Sync mode`) | 0 件 | 0 件 |

### lavapipe (Vulkan) 起動時の要点

- Ubuntu 24.04 の `mesa-vulkan-drivers` パッケージの lavapipe ICD は `/usr/share/vulkan/icd.d/lvp_icd.json` (`lvp_icd.x86_64.json` ではない)。存在しない ICD パスを渡すと `ERROR: Required Vulkan instance extension VK_KHR_surface not found.` が出て OpenGL 3 にフォールバックする
- 正しい ICD パス (`/usr/share/vulkan/icd.d/lvp_icd.json`) を `VK_ICD_FILENAMES` / `VK_DRIVER_FILES` に設定すると、Forward Mobile (`Vulkan 1.4.318 - Forward Mobile - Using Device #0: Unknown - llvmpipe`) と Forward+ (`Vulkan 1.4.318 - Forward+ - Using Device #0: Unknown - llvmpipe`) の両方が WARNING / ERROR 0 件で起動・描画できた
- PNG の目視では、GL Compatibility は壁・床が白飛び気味で陰影が平板だったが、Forward+ は光と影の階調が自然で、10 万本でも手前の床・ソファ上の白・黒・三毛の毛が 1 本ずつ曲がった線として見分けられ、100 万本でも破綻なく描けた

## Decision

1. **レンダラは Forward+ (`forward_plus` / Vulkan) を採用する**
   - 写実寄りの一人称 3D に必要な SSR・ボリュメトリックフォグ・SDFGI・デカールがすべて使える唯一のレンダラである (出典: Godot 公式レンダラ比較表 https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html )
   - GPU の無い CI ランナーでも Mesa lavapipe (`mesa-vulkan-drivers` + `/usr/share/vulkan/icd.d/lvp_icd.json`) で WARNING / ERROR 0 件で起動し、100 万本まで描画でき、10,000 本以上では 1 フレームの描画時間も GL Compatibility と同等以上であることを実測した (1,000 本のみ初回シェーダコンパイルを含み平均 154.02 ms・最小 58.78 ms)
   - PC (Steam) 専用タイトルであり、Web / モバイル向け互換性 (GL Compatibility / Mobile) を優先する理由が無い
   - CI の `screenshot-and-movie` job と `Makefile` の既定描画オプションを `vulkan` + `forward_plus` に切り替え、`screenshot`・`movie`・`hairbench` のすべてを Forward+ で検証する
2. **毛の描画方式は「表面ごとの `MultiMeshInstance3D` (`MultiMesh`)」を採用する**
   - Godot の `MultiMesh` は 1 ドローコールで数百万オブジェクトを描画できる一方、インスタンス単位のフラスタムカリングを行わない (出典: Godot 公式 MultiMesh チュートリアル https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html )。そのため 1 表面につき 1 つの `MultiMeshInstance3D` を割り当てて表面単位のフラスタムカリングが効くようにし、`use_colors = true` で 1 本ごとに白・黒・三毛の色を与える (`cast_shadow = OFF`)
   - 手で 1 本抜く操作は、削除対象のインスタンスを同表面の末尾可視インスタンスと入れ替えて `visible_instance_count` を 1 減らす O(1) swap-remove と、`PackedInt32Array` による双方向インデックス (`hair_id` ↔ 表面・スロット) で実装する
   - 他の候補を採用しなかった理由:
     - `GPUParticles3D`: 任意の 1 本を選んで抜く操作や、残り本数・配置の正確なセーブ・復元と相性が悪い
     - シェーダー単体 / デカール: 1 本ずつ摘んで伸びて抜ける立体表現と個別削除が難しく、将来実機で性能が不足した際の遠距離 LOD (転換条件) の選択肢として残す
3. **1 部屋の毛の本数の上限 (CI 基準と実機確認の分担)**
   - CI (Mesa lavapipe) で描画と 1 本削除の成立を確認した上限は **1,000,000 本** (継続のしきい値 10 万本を 10 倍上回る)
   - 実機 GPU での快適な fps (60fps 維持) に基づく初期の部屋本数の調整は、開発者が調整できる「調整値」と実機での `make run` 確認 (ユーザー作業の一覧 #5) で詰める

## Consequences

- 良い点:
  - 写実寄りの表現 (SSR / SDFGI / デカール / ボリュメトリックフォグ) を制約なく使える
  - CI で本番と同じ Forward+ レンダラによる撮影・録画・毛ベンチマークが WARNING / ERROR 0 件で回る
  - 1 本削除が O(1) で完結するため、100 万本配置時でも「手で 1 本抜く」処理がフレーム落ちの原因にならない
- 悪い点・注意点:
  - CI の描画付き job に `libvulkan1` と `mesa-vulkan-drivers` のインストール、および `lvp_icd*.json` の設定が必須になる (ICD のパスが変わると OpenGL 3 へフォールバックしうるため、ログに `Forward+` が出ることと `has_rendering_device: true` を確認する)
  - 100 万本は lavapipe 上で約 1.0 秒/フレームかかるため、`hairbench` の計測フレーム数を抑えて CI 時間を管理する
  - 実機の fps はソフトウェア描画の計測値からは決まらないため、実機での `make run` 確認を継続して行う
- エージェントへの制約:
  - レンダラは Forward+ を維持する。変更する時は別 ADR を書き、CI の描画付き job が新しいレンダラで動くことを同じ PR で確かめる
  - 毛の描画は表面単位の `MultiMesh` を前提に設計し、1 本単位の追加・削除には `HairField` の O(1) swap-remove 経路を使う

## 追記 (2026-11-27、issue #56)

毛 1 本のメッシュを 3 セグメント・7 頂点・5 三角形から、2 セグメント・5 頂点・3 三角形に減らした。曲がった先細りの形と、表面単位の `MultiMesh` で描くことは変えない。既定の毛の本数を 12,000 本から 120,000 本に上げるにあたり、見た目を変えずに毛の描画の時間を減らす手段として選んだ (CI の lavapipe で、毛 24 万本の部屋に入った直後の 1 フレームが 411 ms から 353 ms に減り、撮影で見分けが付かなかった。run: https://github.com/bannzai/cat-hair/actions/runs/45932194198 )。上の「毛のメッシュは 1 本あたり 3 セグメント・7 頂点・5 三角形」の数字は、この ADR を書いた時点の計測の条件として残す。

## 追記 (2026-11-27、issue #65)

既定の毛の本数を 120,000 本から 9,999,999 本に上げた (owner の指示)。全部を 1 本ずつ描くと、CI の lavapipe で 100 万本でも 1 フレーム約 0.9 秒かかり (下の hairbench)、その約 10 倍になるため、`HairField` に 1 本ずつ描く本数の上限 (`draw_budget`。屋敷の既定は `DEFAULT_DRAW_BUDGET` = 240,000 本) を足した。

- 総本数が上限を超える時は、上限を表面の本数に比例して分けた本数だけを表面の `MultiMesh` で 1 本ずつ描き、残りは「埋もれた毛」として表面ごと・色の系統ごとの本数だけを持つ。1 本ずつの配列 (毛 ID の逆引き・Transform3D・色) も描く本数分だけ作る
- 残り本数・表面ごとの本数・系統ごとの本数は、描いている毛と埋もれた毛の合計で 1 本ずつ数える。保存データの面ごとの本数の形は変えない
- 描いている毛を消すと、その表面に埋もれた毛があれば 1 本をその表面のどこかに描き足し、描いている本数を保つ (手で 1 本抜くと残りは 1 減り、見た目の密度は埋もれた毛が尽きるまで変わらない)。部屋ごとにかける道具と掃除ロボットは、描いている毛で足りない分を埋もれた毛から取る
- 毛を数える処理と 1 本ずつの配列が描く本数で頭打ちになるため、屋敷の組み直しの時間も本数ではなく上限で決まる

比べた方法と選ばなかった理由:

- 近くの毛だけを 1 本ずつ描き、遠くは面の模様で見せる: 模様のテクスチャ・距離での切り替え・切り替えの境目の見え方を新しく作る必要があり、上限で十分に埋もれて見えたため今回は採らない
- 見えている部屋の毛だけを描く: 部屋の出入りで毛を作り直す時間が出る。上限を屋敷全体で配る今の方法で、隣の部屋の毛も同じ密度で見えている

上限の値の計測 (CI の lavapipe、既定の 9,999,999 本の屋敷の最初の部屋に入った直後の 1 フレーム。`make scenebench`。run: https://github.com/bannzai/cat-hair/actions/runs/45942145058 ):

| 描く本数の上限 | 1 フレーム (ms) | 組み直し (ms) | 描いた三角形 |
|---|---|---|---|
| 12,000 | 193.1 | 64.6 | 143,867 |
| 120,000 | 275.8 | 317.6 | 422,867 |
| 240,000 | 372.9 | 603.5 | 732,869 |
| 480,000 | 554.0 | 1,166.5 | 1,352,867 |
| 1,000,000 | 954.6 | 2,395.4 | 2,696,201 |

240,000 本を選んだ。120,000 本 (issue #65 の前の既定と同じ描く本数) より床・カーペット・家具の上の毛が目に見えて密になり (撮影 `scenebench-<上限>.png` の比較)、1 フレームの時間は 120,000 本の約 1.35 倍にとどまる。480,000 本は 120,000 本の約 2 倍の時間がかかる一方、密度の差は 240,000 本との間で小さかった。`hairbench` の 10,000,000 本は描く本数を上限の 240,000 本で頭打ちにして測る (run https://github.com/bannzai/cat-hair/actions/runs/45943119476 で setup 564.77 ms・1 フレーム 337.65 ms。同じ run の scenebench は上の表より全体に 1〜5 割遅く、ランナーごとのばらつきがある)。1,000,000 本以下は上限を外して全部を描き、この ADR の描画の可否の計測を続ける。実機の fps は `F3` の表示で人が確かめる。
