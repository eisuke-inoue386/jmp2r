# jmp2r

JMPをインストールせずに、`.jmp`を直接Rへ読み込むパッケージです。
Python・Julia・コンパイラも不要です。R 4.1以上で利用できます。

**0.3.0は実験版です。すべてのJMPファイルや全メタデータの解釈には対応していません。**
取得できない情報は`diagnostics`に表示します。データの値を読み取れない場合は
欠測値でごまかさずエラーにします。

## インストールと基本操作

```r
# 配布されたソースパッケージを指定
install.packages("jmp2r_0.3.0.tar.gz", repos = NULL, type = "source")

# Windows版を使う場合はこちら
# install.packages("jmp2r_0.3.0.zip", repos = NULL, type = "win.binary")

library(jmp2r)
x <- read_jmp("data.jmp")
x$data           # データフレーム
x$columns[[1]]   # 第1列の情報
x$diagnostics    # 未取得情報・変換上の注意

saveRDS(x, "data-with-metadata.rds")
```

GitHubから導入する場合は次を実行します。

```r
install.packages("remotes")
remotes::install_github("eisuke-inoue386/jmp2r")
```

## インストールせずに使う

新しいRセッションで、GitHub上の単一ファイルを1行で読み込みます。

```r
source("https://raw.githubusercontent.com/eisuke-inoue386/jmp2r/main/jmp2r.R", encoding = "UTF-8")
x <- read_jmp_file(file.choose())
x$data
x$diagnostics
```

コードの取得時にはネットワーク接続が必要です。データファイルは手元で読み込み、
アップロードしません。Rを再起動したら、再度コードを読み込んでください。
同じ版を使い続けるには、URLの`main`を確認済みのコミットSHAに置き換えます。
この方法では`library(jmp2r)`は不要です。以下の`system.file(..., package = "jmp2r")`
による同梱サンプルの取得にはパッケージのインストールが必要です。

`jmp2r.R`には読み取り関数の本体を含み、追加のコードはダウンロードしません。
この1ファイルを手元に保存すれば、`source("jmp2r.R", encoding = "UTF-8")`
でオフラインでも使えます。開発用の`R/`からライセンス表記も含めて生成し、
自動テストで更新漏れを検出します。

通常の`source()`と同様、Rコードを実行し、作業環境に関数を定義します。
信頼できるコードを読み込んでください。同名の関数があれば上書きされます。
`main`は更新されるため、同じ版を使うにはコミットSHAの指定かローカル保存を使います。

## 引き継ぐ情報と現時点の限界

0.2.0からは、**JMPで「除外」とされた行を読み込み時に取り除きます**。
`exclude_rows = TRUE`が既定値です。「選択」「非表示」だけの行は取り除きません。
全行を読み込む場合は、明示的にオフにしてください。

```r
x <- read_jmp_file("data.jmp", exclude_rows = FALSE)
```

`x$rows$row_id`で元ファイルの行番号を確認できます。
`x$table$source_nrows`は元の行数、`x$table$returned_nrows`は読み込んだ行数、
`x$table$excluded_rows_removed`は取り除いた元の行番号です。
元ファイルは変更しません。既定で保存する`x$source$bytes`には除外行も含まれます。
除外状態を解釈できない形式は、既定ではエラーにします。全行が必要なら
`exclude_rows = FALSE`を指定してください。`metadata = "quiet"`だけでは回避できません。

`.jmp`からは、対応する数値・文字列・圧縮データ・日時・値ラベルなどを読みます。
列名、列順、保存型、表示形式のコード、取得できた未解釈の列プロパティも保存します。
日時変換前の元の数値も列情報に残します。空文字列は`""`のまま保持します。

対応形式では、**連続／名義／順序の尺度、リテラルで定義した欠測コード・カテゴリ順序、
行の除外・非表示・選択・ラベル状態**を取得します。

0.3.0から、**欠測コードは`NA`、名義尺度は`factor`、順序尺度は`ordered factor`に
読み込み時に変換します**。`missing_codes = TRUE`と`factors = TRUE`が既定値です。
欠測コードの変換を先に行い、欠測コードをカテゴリ水準として残さないようにします。
連続尺度の列は数値・日付などの型を保持します。

```r
x <- read_jmp_file("data.jmp")  # x$data は変換済み
raw <- read_jmp_file("data.jmp", missing_codes = FALSE, factors = FALSE)
```

JMPで明示したカテゴリ順を優先します。順序尺度で順序が未指定なら、既定の
`ordinal_order = "sort"`でRの標準順を使い、`ordinal_order_inferred`として診断情報に
記録します。数値は昇順、文字列の並びはRのロケールに依存します。
`ordinal_order = "error"`なら順序未指定時にエラー、`"appearance"`なら出現順にできます。
名義尺度で明示順がない場合は出現順です。

変換前の値は`x$columns[[i]]$stored_values`に、元の尺度・欠測コードの定義も列情報に
保持します。`r_levels`、`r_level_labels`、`r_level_order_source`でRの水準と決定方法を
確認できます。必要なメタデータが取得できない場合は、quietでも変換を止めます。
その変換をオフにすると元の値を読み込めます。

一方、**単位、計算式、テーブルスクリプト、複雑な列プロパティは完全には解釈できません**。
取得できたかは各列の`metadata_known`で区別します。元ファイルのバイト列は既定で
`x$source$bytes`に保存しますが、これは元情報の保管であり、Rで利用可能な形へ
完全変換できたことを意味しません。

`metadata = "quiet"`を指定しても診断情報は残ります。
`metadata = "error"`では診断項目があればエラーにします。
`keep_source = FALSE`では元ファイルのバイト列の保存を省略します。

## `.jrp`の扱い

```r
p <- system.file("extdata", "embedded-example.jrp", package = "jmp2r")
x <- read_jrp(p)
```

対応範囲は、値を直接記述した単一の`New Table(...)`です。
型、尺度、値ラベル、順序、単位、欠測コードなどのリテラル情報を保持します。
JSLは一切実行しません。

- 外部データ参照は`jrp_external_reference_error`で止まります。
- 変数から値を取得する処理、ループ、関数実行などはエラーで止まります。
- 計算式は保存値もある場合に限り文字列として保持し、計算しません。
- 複数テーブル、未対応の構文、分析・グラフ作成命令もエラーになります。

**通常のJMPで保存した`.jrp`は分析命令を含むことが多いため、
データが埋め込まれていてもこの初版では読み込めない場合があります。**
添付の`embedded-example.jrp`が対応する記述形式の例です。

## 分析に設定を適用する場合

```r
d <- as_analysis_data(x, exclude_rows = TRUE,
                      missing_codes = TRUE, factors = TRUE)
```

指定した処理に必要な情報が不明なら、推測せずエラーにします。
通常は読み込み時に除外・欠測コード・factor変換が適用されています。
`as_analysis_data()`は、読み込み時にオフにした変換を後から行う際に使えます。
再変換時も元のコードを使い、値ラベルを元の値として誤って再解釈しません。
元の`x$data`は変更しません。FALSE指定は、すでに行った変換を元に戻す操作ではありません。

通常のR関数はJMPの除外フラグや尺度を自動では認識しません。
`x$data`を分析する場合は、`x$diagnostics`も確認してください。

検証内容は[VALIDATION.md](VALIDATION.md)、公開手順は
[PUBLISHING.md](PUBLISHING.md)を参照してください。
MITライセンス。JMP/SASの公式製品ではありません。
