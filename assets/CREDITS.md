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
