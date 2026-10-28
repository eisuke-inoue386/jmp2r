# jmp2r

JMPをインストールせずに、`.jmp`を直接Rへ読み込むパッケージです。
Python・Julia・コンパイラも不要です。R 4.1以上で利用できます。

**0.1.0は実験版です。すべてのJMPファイルや全メタデータの解釈には対応していません。**
取得できない情報は`diagnostics`に表示します。データの値を読み取れない場合は
欠測値でごまかさずエラーにします。

## インストールと基本操作

```r
# 配布されたソースパッケージを指定
install.packages("jmp2r_0.1.0.tar.gz", repos = NULL, type = "source")

# Windows版を使う場合はこちら
# install.packages("jmp2r_0.1.0.zip", repos = NULL, type = "win.binary")

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

新しいRセッションで、GitHub上の3つのRファイルを読み込みます。

```r
base_url <- "https://raw.githubusercontent.com/eisuke-inoue386/jmp2r/main/R/"
for (f in c("binary.R", "jrp.R", "read.R")) {
  source(paste0(base_url, f), encoding = "UTF-8")
}
x <- read_jmp_file(file.choose())
x$data
x$diagnostics
```

コードの取得時にはネットワーク接続が必要です。データファイルは手元で読み込み、
アップロードしません。Rを再起動したら、再度コードを読み込んでください。
同じ版を使い続けるには、URLの`main`を確認済みのコミットSHAに置き換えます。
この方法では`library(jmp2r)`は不要です。以下の`system.file(..., package = "jmp2r")`
による同梱サンプルの取得にはパッケージのインストールが必要です。

## 引き継ぐ情報と現時点の限界

`.jmp`からは、対応する数値・文字列・圧縮データ・日時・値ラベルなどを読みます。
列名、列順、保存型、表示形式のコード、取得できた未解釈の列プロパティも保存します。
日時変換前の元の数値も列情報に残します。空文字列は`""`のまま保持します。

一方、バイナリ`.jmp`の**連続／名義／順序の尺度、単位、欠測コードの定義、
カテゴリ順序、計算式、テーブルスクリプト、行の除外・非表示状態は、
現時点では意味を解釈して取り出せません**。元ファイルのバイト列は既定で
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
そのため、現在のバイナリ`.jmp`では上記の3指定は基本的に使えません。
対応するリテラル`.jrp`では、既知の情報に基づいて変換できます。
順序尺度の変換には明示的な`Value Order`が必要です。

通常のR関数はJMPの除外フラグや尺度を自動では認識しません。
`x$data`を分析する場合は、`x$diagnostics`も確認してください。

検証内容は[VALIDATION.md](VALIDATION.md)、公開手順は
[PUBLISHING.md](PUBLISHING.md)を参照してください。
MITライセンス。JMP/SASの公式製品ではありません。
