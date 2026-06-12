# NNDD 5chメンテナンス版（NNDD-5ch）

本ソフトウェアは[MineAP][]さんが作成された[NNDD][] ver2.4.3からフォークした[NNDD+DMC][] ver4.0.1からフォークした[NNDD-5ch][] ver4.4.9からフォークしたソフトウェアです。

本プロジェクトでリリースしたNNDD-RE (version >= RE-5.0.0)を利用して発生した不具合等に関しては[このリポジトリのIssues][Issues]にご報告いただくようお願いします。
**オリジナルの作者様にお問い合わせをすることのないようにお願いします。**

## 現在分かっている不具合
 ＿人人人人人人人人人人人人人人人人人人＿  
＞　　コメントの投稿ができない！！　　＜  
￣Y^Y^Y^Y^Y^Y^Y^Y^Y^Y^Y^Y^Y^Y^Y￣

## このソフトウェアについて
NNDD-REは[ニコニコ動画](http://www.nicovideo.jp)にアップロードされた動画の視聴およびダウンロード/管理をするための自由ソフトウェアです。

動画の視聴, 保存に加え, ランキングの表示や動画の検索, マイリストの管理を行うことが出来ます。

## 対応環境
Windows用インストーラ(.exe)をリリースしています。
メンテナの環境はWindowsであるため, メインストリームはWindowsのみになります。


## ダウンロード
最新版のダウンロードは[**こちら (releases/latest)**][Release-Latest]から行ってください。

Windows用インストーラ(.exe)でインストールした場合には, 設定から「起動時にバージョンチェックをする」にチェックを入れている場合(デフォルト)には起動時に最新バージョンの確認及びインストールが可能です。

新機能追加や大幅な修正等の際には自動アップデートの対象にならないバージョン(Alpha版)のリリースを行います。
これらのバージョンをご利用の際には[Releases][]のページからご希望のバージョンをダウンロード/インストールしてご利用下さい。
不具合等ありましたら[Issues][]にご報告頂けると有り難いです。


## NNDD+DMCからの設定の引継ぎ
NNDD-5chでは, NNDD+DMCと異なる場所に設定ファイルが保存されます。
NNDD+DMCから設定を引き継ぎたい場合にはNNDD+DMC Wikiの[**NNDDからNNDD DMCへの設定の引継ぎについて**][Config]をご覧ください。
基本的な手順はNNDDからNNDD+DMCへの引継ぎと同じです。
NNDD-5chのディレクトリのパスは\[org.mineap.nndd-re\]です。

## ライセンス
本ソフトウェアは[MITライセンス][License]の下で公開, 頒布される自由ソフトウェアです。
ライセンスに示された利用条件に同意する限り, 本ソフトウェアは用途を問わず誰でも自由に利用することが出来ます。

MITライセンスに示されるとおり, 本ソフトウェアは**無保証**です。
作者及び著作権者は, 本ソフトウェアに起因し, または関わる事柄に関して一切の責任及び義務を負うことは無いものとします。

ライセンスの詳細は本リポジトリの[LICENSE][License]ファイルをご確認下さい。

## 謝辞
[NNDD][]作者の[MineAP][]氏, 並びに下記ライブラリの作者に対してこの場を借りて御礼申し上げます。

* [NNDD][] &copy; MineAP (MIT License ([LICENCE0][License-Orig]))
* [nicovideo4as][NNDD] &copy; MineAP (MIT License ([LICENSE0][License-Orig]))
* [AirHttpd][NNDD] &copy; MineAP (MIT License ([LICENSE0][License-Orig]))
* [NativeApplicationUpdater][] &copy; Piotr Walczyszyn ([Apache License 2.0])
* [Flashls][] &copy; [mangui][] ([Mozilla Public License 2.0][MPLv2])
* [WebViewANE][] &copy; [tuarua][]  ([Apache License 2.0])
* [FreSwift][] &copy; [tuarua][]  ([Apache License 2.0])
* [hls.js][] &copy; [video-dev][]  ([Apache License 2.0])


[MineAP]: https://twitter.com/mineap
[NNDD]: https://ja.osdn.net/projects/nndd/
[NNDD+DMC]: https://github.com/SSW-SCIENTIFIC/NNDD
[NNDD-5ch]: https://github.com/nndd-reboot/NNDD
[NNDD-RE]:https://github.com/NNDD-Rebuild/NNDD
[Issues]: https://github.com/NNDD-Rebuild/NNDD/issues
[License]: https://github.com/NNDD-Rebuild/NNDD/blob/master/LICENSE
[License-Orig]: https://github.com/NNDD-Rebuild/NNDD/blob/master/LICENSE0
[MPLv2]: https://github.com/NNDD-Rebuild/NNDD/blob/master/LICENSE_MPLv2
[NativeApplicationUpdater]: https://code.google.com/archive/p/nativeapplicationupdater/
[Flashls]: http://www.flashls.org/
[mangui]: https://github.com/mangui
[WebViewANE]: https://github.com/tuarua/WebViewANE
[FreSwift]: https://github.com/tuarua/Swift-IOS-ANE
[hls.js]: https://github.com/video-dev/hls.js
[tuarua]: https://github.com/tuarua
[video-dev]: https://github.com/video-dev
[Apache License 2.0]: https://www.apache.org/licenses/LICENSE-2.0
[Config]: https://github.com/SSW-SCIENTIFIC/NNDD/wiki/NNDD%E3%81%8B%E3%82%89NNDD-DMC%E3%81%B8%E3%81%AE%E8%A8%AD%E5%AE%9A%E3%81%AE%E5%BC%95%E7%B6%99%E3%81%8E%E3%81%AB%E3%81%A4%E3%81%84%E3%81%A6
[NNDD+DMC on Linux]: https://github.com/SSW-SCIENTIFIC/NNDD/wiki/(%E5%8F%82%E8%80%83)-Linux%E3%81%B8%E3%81%AE%E3%82%A4%E3%83%B3%E3%82%B9%E3%83%88%E3%83%BC%E3%83%AB
[Release-Latest]: https://github.com/NNDD-Rebuild/NNDD/releases/latest
[Releases]: https://github.com/NNDD-Rebuild/NNDD/releases
[5ch nndd]: https://egg.5ch.net/test/read.cgi/software/1701226145/l50
