# jmp2r

JMPをインストールせずに、対応する`.jmp`や限定的な`.jrp`をRに読み込みます。
R 4.1以上が必要です。Python・Julia・追加のRパッケージは不要です。
**0.4.1は実験版です。すべてのJMPファイル・設定には対応していません。**

## インストールせずに使う

```r
source("https://raw.githubusercontent.com/eisuke-inoue386/jmp2r/main/jmp2r.R", encoding = "UTF-8")
result <- read_jmp_file("C:/任意のフォルダ/data.jmp")

head(result)
names(result)
str(result)
View(result)
```

**戻り値は通常のデータフレームです。`result$data`とする必要はありません。**
次の処理を読み込み時に適用します。

- JMPで「除外」した行を取り除く。選択・非表示だけの行は残す。
- 欠測コードを`NA`にする。
- 名義尺度を`factor`、順序尺度を`ordered factor`にする。
- 連続尺度の数値・日付などは対応する型を保持する。

元ファイルは変更しません。データファイルのアップロードも行いません。
Rを再起動したら再度`source()`してください。単一ファイルを保存すれば
`source("jmp2r.R", encoding = "UTF-8")`でオフラインでも使えます。
`main`は更新されるため、同じ版を使うにはコミットSHAの指定かローカル保存を使います。
通常の`source()`と同様、コードを実行し、同名の関数があれば上書きします。

## 変換をオフにする

```r
result <- read_jmp_file(
  "data.jmp",
  exclude_rows = FALSE,
  missing_codes = FALSE,
  factors = FALSE
)
```

すべて既定値はTRUEです。必要なものだけFALSEにできます。
変換に必要な情報が読めない場合は、推測せずエラーにします。
`metadata = "quiet"`は、このエラーを無視する指定ではありません。

順序尺度は、JMPで指定したカテゴリ順を優先します。未指定なら
`ordinal_order = "sort"`でRの標準順を使い、診断情報に記録します。
数値は昇順、文字列の順はRのロケールに依存します。
`ordinal_order = "error"`なら未指定時にエラー、`"appearance"`なら出現順にできます。
名義尺度で明示順がない場合は出現順です。値ラベルの重複で異なるコードが
統合されてしまう場合は、エラーにします。

## 読み込み時の注意点を確認する

```r
jmp_metadata(result)$diagnostics
```

通常の戻り値には、読み込み時の診断を記録する`jmp_diagnostics`属性だけを追加します。
元ファイルのバイト列や詳細な列情報・スクリプトは含めません。
単位・計算式・テーブルスクリプトなど、使用しない未対応項目の警告は出しません。
カテゴリ順の補完や日時のタイムゾーンなど、データの解釈に関係する注意点は残します。
診断は読み込み時の記録であり、その後の行の絞り込みや編集を反映するものではありません。

カテゴリ順をRで補ったという記録は残しますが、そのwarningは出しません。
その他の警告は引き続き表示します。明示的な`metadata = "error"`は従来どおりです。

`metadata = "quiet"`で警告表示を抑え、`"error"`で診断がある場合に停止できます。

## 従来の詳細形式を使う

```r
details <- read_jmp_file("data.jmp", output = "dataset")
details$data
details$columns
details$rows
details$table
details$diagnostics
```

`output = "dataset"`で、従来の7要素のリストを返します。
元の行番号、除外した行、変換前の値、尺度・欠測コード・水準の情報などを確認できます。
`jmp_metadata(details)`は詳細メタデータを返します。この形式では未対応属性の診断も残ります。

詳細形式では、既定で`details$source$bytes`に除外行も含む元ファイルのバイト列を保存します。
不要なら`keep_source = FALSE`を指定してください。通常のデータフレーム形式では保存しません。

読み込み時に変換をオフにした詳細形式には、`as_analysis_data(details, ...)`で後から
変換を適用できます。通常のデータフレームは、そのまま分析してください。
FALSE指定は、すでに行った変換を元に戻す操作ではありません。

## 対応範囲と制限

対応する数値・整数・UTF-8文字列・圧縮データ・日時・値ラベル、尺度、
リテラルの欠測コード・カテゴリ順序、対応形式の行属性を読み取ります。
空文字列は、欠測コードに指定されていなければ空文字列として保持します。
64ビット整数は丸めを避けるため正確な十進文字列です。日時のタイムゾーンは不明で、
UTCは表示上の規約です。未知のデータ形式は、欠測値で埋めずにエラーにします。

単位・計算式・保存された分析手順・複雑な列プロパティ・表示装飾などは完全には再現しません。
計算式列の保存済みの値は読み取れますが、式の再計算は行いません。

`.jrp`は、単一の`New Table(...)`に値を直接記述した限定的な形式に対応します。
JSLは一切実行しません。外部データ参照、動的処理、分析・グラフ命令、複数テーブル、
未対応構文はエラーになります。**通常のJMPで保存したJRPは、データが埋め込まれていても
未対応の分析命令を含む場合があります。** `inst/extdata/embedded-example.jrp`が対応例です。

## パッケージとしてインストールする

```r
install.packages("remotes")
remotes::install_github("eisuke-inoue386/jmp2r")
library(jmp2r)
result <- read_jmp_file("data.jmp")
```

ローカルのソースパッケージは`jmp2r_0.4.1.tar.gz`、Windowsバイナリは
`jmp2r_0.4.1.zip`です。`jmp2r-source.zip`はリポジトリ用ソース一式であり、
インストール用のWindowsバイナリではありません。

検証は[VALIDATION.md](VALIDATION.md)、保守・公開は[PUBLISHING.md](PUBLISHING.md)を参照。
公開可能なサンプルと人工データでテストし、利用者から提供されたファイルは公開しません。
MITライセンス。由来とライセンス表記は[英語README](README.md)と`inst/NOTICE`に記載しています。
JMP/SASの公式製品ではありません。
