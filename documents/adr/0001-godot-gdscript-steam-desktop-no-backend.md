# 0001. Godot 4.7 + GDScript で Steam 向けデスクトップ版を作り、バックエンドを持たず、ビルドと動作確認を外部のマシンで行う

## Status

Accepted

## Context

屋敷の猫の毛を手で 1 本ずつ取るところから自動化まで進める、一人称 3D のインクリメンタルゲームを作る ( https://github.com/bannzai/IdeaMemo/issues/406 )。立ち上げ情報 (同 issue の new-app-config) でエンジンは Godot、配信先は Steam (PC)、リポジトリは public に決まっている。

- 1 人で遊ぶゲームとして先に作り込む。協力プレイは後で足す案で、通信の方式は決めていない (同 issue「協力プレイ」)
- 開発マシン (macOS) の負荷を避けるため、ビルド・Godot の起動・描画付きの撮影・ブラウザやシミュレーターでの動作確認は開発マシンで実行しない (ユーザーの指示 2026-11-25。`~/.claude/documents/rules/cloud-verification-keeps-agent-local.md`)
- 同じ技術スタックの bannzai/card-rationing (public・Steam 向け) で、GitHub Actions の Linux ランナー (Xvfb + Mesa llvmpipe) だけで headless の検証・デスクトップ向けエクスポート・描画付きの撮影と録画を行う運用が動いている
- 絵は写実寄りの一人称 3D で、屋敷の毛の総本数は「数百万本」と見せる。この本数を Godot で描けるか、どのレンダラが要るかは確かめていない (同 issue「制約・リスク」)
- Steam での販売は、購入者の契約相手が Valve になる (Steam 利用規約「お客様が、利用権に基づき Steam を介して行うあらゆる取引の相手方は Valve となります」 https://store.steampowered.com/subscriber_agreement/?l=japanese 。bannzai/card-rationing の ADR 0001 が 2026-10-05 に引用した文で、本 ADR では取得し直していない)

## Decision

- エンジンは Godot 4.7 系の stable、言語は GDScript にする。C# (.NET 版 Godot) は導入しない。.NET 版はエクスポートと CI の準備が増える
- レンダラは、雛形の時点では GL Compatibility にする。これは暫定で、理由は CI の Xvfb + llvmpipe で描画できることを bannzai/card-rationing と bannzai/goki-hunter で確かめてあるのがこのレンダラだけであること。写実寄りの絵と毛の本数に Forward+ / Mobile が要るか、それらが GPU の無いランナーのソフトウェア Vulkan で描画できるかは、毛の描画の試作 (ロードマップの最初の issue) で CI を実際に動かして確かめ、結果を別 ADR に書いて決め直す
- エクスポート先は Windows x86_64 / macOS universal / Linux x86_64 の 3 つ
- バックエンド (DB・ストレージ・認証・サーバー) を持たない。セーブデータはローカル (`user://`) に置く。ゲームに計測 SDK を入れない。公開後の判定に使う指標と計測元は `documents/DIRECTION.md`「判定基準」に書く。このため DB のルール・GCP の課金とエラーのアラート・Crashlytics のアラート転送・Firebase Analytics は対象外にする
- Steamworks SDK の連携 (GodotSteam 等による実績・クラウドセーブ・協力プレイの通信) は、Steamworks のパートナー登録とアプリ登録の後に別 ADR で決める
- 特定商取引法に基づく表記は用意しない。Steam での販売は購入者の契約相手が Valve のため。Steam 以外で直接販売する判断をした時に見直す
- 法務ドキュメント (プライバシーポリシー・利用規約) と紹介ページは GitHub Pages (`docs/`) に置く
- ビルド・Godot の起動 (headless を含む)・エクスポート・描画付きの撮影と録画は GitHub Actions の Linux ランナー (`.github/workflows/ci.yml`) で行う。public リポジトリのため、ブラウザでの確認は webtunnel skill、macOS / iOS の画面を操作する確認は macos-simtunnel skill / simtunnel (ios-simulator skill) を使う。private に変える場合は Devin のセッション (devin-macos-e2e skill) に切り替える。開発マシンで実行してよいのは `make lint` だけで、ユーザーが明示的に頼んだ時と、人が遊んで確かめる `make run` はこの限りでない
- 本番へ配布する CD (Steam へのアップロード) は、bannzai が公開に進むと指示するまで作らない。CI のエクスポートは artifact に残すだけにする

## Consequences

- 良い点: サーバーの運用費・障害対応が無い。検証は Linux ランナーで完結し、開発マシンで Godot を起動しなくてよい
- 悪い点: CI の 1 往復 (数分) を挟まないと動作を確かめられない。Godot が生成する `.uid` / `.import` も CI の artifact から取り出して commit する (手順は AGENTS.md「検証方法」)。CI のソフトウェア描画の fps は実機の性能を示さないため、毛の本数の上限のように性能で決まる値は、人が実機で `make run` して確かめるまで決まらない。クラッシュや不具合の報告はユーザーからの連絡 (Steam のコミュニティ・メール) に頼る
- エージェントへの制約: C# を導入しない。サーバー・計測 SDK を追加しない。Steamworks SDK の追加は別 ADR を書いてから行う。開発マシンで Godot を起動しない。レンダラを変える時は ADR を書く (根拠は本 ADR)
