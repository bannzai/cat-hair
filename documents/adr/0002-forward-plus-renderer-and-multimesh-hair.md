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
   - GPU の無い CI ランナーでも Mesa lavapipe (`mesa-vulkan-drivers` + `/usr/share/vulkan/icd.d/lvp_icd.json`) で WARNING / ERROR 0 件で起動し、100 万本まで描画でき、1 フレームの描画時間も GL Compatibility と同等以上であることを実測した
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
