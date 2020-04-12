# Work from home with Raspberry pi (wfh_pi)

Raspberry Piにオープンソース版のSoftEther VPN clientを導入してリモートワーク環境を構築した際のノウハウと支援ツールを公開します。

リモートワーク化を推し進める際、特に事務処理などの会社のPCを操作しないとどうしても出来ない業務について、社員の個人PCにVPNソフトを導入して作業してもらうのは、会社と社員の両方にとって非常に高リスクです。一方で、小規模な会社では高額なPCを新たに調達して社員一人々々に提供するのも難しく、なかなかリモートワークに踏み込めないという面もあるかと思います。

そうした悩みを軽減し、最小限の投資でなるべく安全なリモートワーク環境を構築し、社員も会社も安心して生活や活動を続けられる状況を作り上げるための一助となれば幸いです。

## 概要

ここではRaspberry Piを使った以下のようなリモートワーク環境を構築する方法について説明します。

* 自宅から、会社のVPN(SoftEther VPN)に自動接続する
* 接続に成功したら、社内のPCをWake on LANを使って起動する
* PCのリモートデスクトップに接続して操作する

動作検証はWindows 10とRaspberry Pi 4で行いました。

### SoftEther VPN serverの構築と設定

おそらくこの手順が最初にして最大の難関なのですが、筆者は固定グローバルIPアドレスを取得しているネットワーク上のFreeBSDというOSのサーバでVPN serverを構築したため、固定IPを持たない一般的なネットワークや、Windowsマシンでのサーバの構築ノウハウを逆に持ち合わせていません。

このため、申し訳ありませんがこの手順については公式ドキュメントの紹介だけになります。

接続したい社内LANと直接通信可能な固定グローバルIPがない場合、SoftEther VPNプロジェクトの[公式ドキュメント](https://ja.softether.org/4-docs/2-howto/1.VPN_for_On-premise/2.Remote_Access_VPN_to_LAN)を参考に、VPNサーバを構築します。

筆者は確認していませんが、Raspberry PiでVPN serverを構築するノウハウもいくつか公開されているようですので、もしVPN serverを導入するのに適切なマシンがない場合「raspberry pi softether vpn 構築」などのキーワードで検索してみてください。

この[公式ドキュメント](https://ja.softether.org/4-docs/2-howto/1.VPN_for_On-premise/2.Remote_Access_VPN_to_LAN)で説明されている手順の、ステップ1と2までを進めてください。ステップ3と4に相当する作業は、後述するRaspberry Piの構築時に実施するので不要です。その際に以下の情報が必要となるので、メモしておきます。
* 仮想Hubの名前
* 仮想サーバのホスト名

#### グローバルIP使用時のTips

参考までに、筆者がグローバルIPアドレス環境下で構築した際に気付いた点などを列挙します。

* 基本的にはマルチホーム（グローバルと社内LANに接続するNICを持つ）構成とした上でルーティングを「しない」構成にするのがよいと思います
* サーバの初回起動前にadminip.txtというファイルを作成して、[リモート管理へのアクセス](https://ja.softether.org/4-docs/1-manual/3._SoftEther_VPN_Server_マニュアル/3.3_VPN_Server_管理#3.3.18_IP_.E3.82.A2.E3.83.89.E3.83.AC.E3.82.B9.E3.81.AB.E3.82.88.E3.82.8B.E3.83.AA.E3.83.A2.E3.83.BC.E3.83.88.E7.AE.A1.E7.90.86.E6.8E.A5.E7.B6.9A.E5.85.83.E3.81.AE.E5.88.B6.E9.99.90)を最低限プライベートアドレス側だけに制限しましょう。
* ポート番号は、標準の443, 992, 5555番は全て止めて別の番号にしました（ポートスキャンからのサービス標的型の攻撃を避けられます）。
* VPN serverをVMware上の仮想サーバ上に構築する場合、社内LAN側に接続しているVMwareの仮想スイッチで、「無差別モード」を有効にする必要がありました。

### 社内PCの事前準備

リモートワークで使用する社内PCに対して以下の設定を行います
* 物理(MAC)アドレスを調べる（やり方は「Windows macアドレス 確認」で検索）
* Wake on LANを有効にする（やり方は「Windows wake on lan 設定」で検索）
* ping(ICMP echo)に応答するようにする（やり方は「windows ping 許可」で検索）
* 固定IPアドレスを割り当てる（やり方は「Windows ipアドレス 設定」で検索、もしくはDHCPサーバを設定）

### Raspberry Piのセットアップ

Raspberry Piの初期設定を行います。

まず、社内LAN等VPN serverおよびインターネットにアクセスできるネットワークに接続してRaspberry Piを起動します。

初回起動時には、
* ファイルシステムをSDカードの容量に拡張するため再起動
* 使用する国や言語、キーボードレイアウトの設定
* 'pi'アカウントのパスワード設定
* 画面サイズの設定
* Wi-Fiの設定
* インストールされているソフトウェアのアップデート
などが行われるので、しばらく待ちます。

再起動してデスクトップ画面が表示されたら、ターミナル（上部ツールバー左側の黒い四角）をクリックして起動し、以下のコマンドを実行します。

```
$ git clone https://github.com/tsnr/wfh_pi.git
$ cd wfh_pi
$ sudo bash ./setup.sh
```

'setup.sh'スクリプトは設定に必要な、

* 作成するユーザ名
* VPNサーバの情報
* 接続するPCの情報
* 時刻同期サーバの設定情報

などを訪ねてきたのち、以下の設定を自動的に行います。

* 利用者用アカウントの作成
* 自動ログインの無効化
* SoftEther VPN client, wakeonlan, Remminaの確認とインストール
* VPN接続の自動化スクリプト類のインストール
* SoftEther VPN clientとserverの設定
* 時刻同期(NTP)の設定

セットアップが完了すると、user_note.txtというファイルに、ユーザに渡すための情報が保存されます。

### 利用者への端末引き渡し

Raspberry Piのセットアップが完了したら、本体とuser_note.txtおよび以下のファイルを印刷してユーザに渡します。

セットアップ手順書：
  docs/UserManual-setup.docx
使い方：
  (VNCなし版) docs/UsersManual-usage.docx
  (VNCあり版) docs/UsersManual-usage_RealVNC.docx

## トラブルシュート

### 会社と自宅でIPのセグメントが重なった場合

不運にも会社と自宅の両方で192.168.0.0/24など利用していて、IPのセグメントが重なってしまった場合、たとえIPアドレスを重ならないようにしても、余程トリッキーな設定を両方でやらない限り通信は不可能です。

そうなってしまった場合に一番手っ取り早い解決策は、自宅のネットワークとRaspberry Piの間にルータを1台挟んで、Raspberry Piには別のセグメントのIPアドレスを割り当てるようにする方法です。

## 免責

本資料に記述されている内容やプログラム、Raspberry Pi用の設定ファイルについて、その動作を保証するものではありません。利用に関しては自己責任でお願いいたします。

## ライセンス

Copyright (c) 2020 Hideki Sakamoto
Released under the MIT license
https://opensource.org/licenses/mit-license.php
