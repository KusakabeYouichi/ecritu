// 変換の中核のうちアプリも使う部分(Packages/EcrituConversion の EcrituConversionBase)を、アプリの全ファイルから見えるようにする。
// 個々のファイルには import を書かない。アプリには変換本体(EcrituConversion)をリンクしない
@_exported import EcrituConversionBase
