package org.mineap.nndd.server {
    import flash.crypto.generateRandomBytes;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.ProgressEvent;
    import flash.events.ServerSocketConnectEvent;
    import flash.events.TimerEvent;
    import flash.net.ServerSocket;
    import flash.net.Socket;
    import flash.utils.ByteArray;
    import flash.utils.Timer;

    import org.mineap.nicovideo4as.Login;
    import org.mineap.nndd.LogManager;

    /**
     * ブラウザ拡張から送られてくる user_session を受け取る。
     *
     * 「他の NNDD からの通信待ち受け」(LAN 向けの機能)とは別に、ログイン画面を開いている間だけ
     * 同じPC(127.0.0.1)からの通信だけを受ける小さなサーバーを立てる。LAN にポートを開けることはない。
     *
     * さらに、他のウェブサイトが勝手にセッションを送り込めないよう、ログイン画面に表示するペアリングコードが
     * 一致したときに限って受け付ける。コードを一定回数間違えると、ログイン画面を開き直すまで受け付けない。
     *
     *   GET  /NNDDLogin : 受付中かを返す {"waiting":true|false}
     *   POST /NNDDLogin : {"code":"6桁のコード","userSession":"値"} を受け取る
     */
    public class SessionLoginReceiver {

        /** 拡張が接続する既定のポート(同じPC内のみ) */
        public static const PORT: int = 12301;

        /** 受け付けた (確認とログインはログイン画面が行う) */
        public static const ACCEPTED: int = 202;
        /** リクエストの内容が不正 */
        public static const BAD_REQUEST: int = 400;
        /** ペアリングコードが違う */
        public static const WRONG_CODE: int = 403;
        /** ログイン画面を開いていない (受付中ではない) */
        public static const NOT_WAITING: int = 409;
        /** コードの誤りが多すぎる */
        public static const TOO_MANY_FAILS: int = 429;

        private static const MAX_FAILS: int = 5;
        private static const MAX_REQUEST_BYTES: int = 16384;
        private static const REQUEST_TIMEOUT_MS: int = 5000;
        private static const PATH: String = "/NNDDLogin";

        private static const _instance: SessionLoginReceiver = new SessionLoginReceiver();

        private var _code: String = null;
        private var _failCount: int = 0;
        private var _onReceived: Function = null;
        private var _server: ServerSocket = null;

        public function SessionLoginReceiver() {
        }

        public static function get instance(): SessionLoginReceiver {
            return _instance;
        }

        /**
         * 受付を開始し、画面に表示するペアリングコード(6桁の数字)を返す。
         * 受付用のサーバーが立っていなければ、ここで立てる。
         *
         * @param onReceived function(userSession: String): void 。コードが一致したときに呼ばれる
         */
        public function open(onReceived: Function): String {
            var bytes: ByteArray = generateRandomBytes(4);
            var n: uint = bytes.readUnsignedInt() % 1000000;
            var code: String = String(n);
            while (code.length < 6) {
                code = "0" + code;
            }

            this._code = code;
            this._failCount = 0;
            this._onReceived = onReceived;
            startServer();
            return code;
        }

        /**
         * 受付を終了する(ログイン画面を閉じたとき)。サーバーも止める。
         */
        public function close(): void {
            this._code = null;
            this._onReceived = null;
            stopServer();
        }

        public function get isWaiting(): Boolean {
            return this._code != null && this._failCount < MAX_FAILS;
        }

        /** 受付用のサーバーが動いているか */
        public function get isListening(): Boolean {
            return this._server != null && this._server.listening;
        }

        private function startServer(): void {
            if (isListening) {
                return;
            }
            if (!ServerSocket.isSupported) {
                LogManager.instance.addLog("ブラウザ拡張からのログイン:この環境ではサーバーソケットが使えません");
                return;
            }
            try {
                this._server = new ServerSocket();
                this._server.bind(PORT, "127.0.0.1");
                this._server.addEventListener(ServerSocketConnectEvent.CONNECT, connectHandler);
                this._server.listen();
                LogManager.instance.addLog("ブラウザ拡張からのログインの受付を開始:127.0.0.1:" + PORT);
            } catch (error: Error) {
                LogManager.instance.addLog("ブラウザ拡張からのログインの受付を開始できませんでした(ポート " + PORT + " が使用中の可能性):" + error);
                this._server = null;
            }
        }

        private function stopServer(): void {
            if (this._server == null) {
                return;
            }
            try {
                this._server.removeEventListener(ServerSocketConnectEvent.CONNECT, connectHandler);
                if (this._server.listening) {
                    this._server.close();
                }
                LogManager.instance.addLog("ブラウザ拡張からのログインの受付を終了");
            } catch (error: Error) {
                trace(error.getStackTrace());
            }
            this._server = null;
        }

        private function connectHandler(event: ServerSocketConnectEvent): void {
            var socket: Socket = event.socket;

            // bind は 127.0.0.1 だが、念のため同じPC以外は即座に切る
            if (socket.remoteAddress != "127.0.0.1" && socket.remoteAddress != "::1") {
                LogManager.instance.addLog("ブラウザ拡張からのログイン:同じPC以外からの通信を拒否:remoteAddress=" + socket.remoteAddress);
                try {
                    socket.close();
                } catch (error: Error) {
                }
                return;
            }

            var buffer: ByteArray = new ByteArray();
            var finished: Boolean = false;

            var timer: Timer = new Timer(REQUEST_TIMEOUT_MS, 1);

            var finish: Function = function (): void {
                if (finished) {
                    return;
                }
                finished = true;
                timer.stop();
                try {
                    socket.flush();
                    socket.close();
                } catch (error: Error) {
                }
            };

            timer.addEventListener(TimerEvent.TIMER, function (e: TimerEvent): void {
                finish();
            });
            timer.start();

            socket.addEventListener(IOErrorEvent.IO_ERROR, function (e: IOErrorEvent): void {
                finish();
            });
            socket.addEventListener(Event.CLOSE, function (e: Event): void {
                finished = true;
                timer.stop();
            });
            socket.addEventListener(ProgressEvent.SOCKET_DATA, function (e: ProgressEvent): void {
                if (finished) {
                    return;
                }
                socket.readBytes(buffer, buffer.length, socket.bytesAvailable);

                if (buffer.length > MAX_REQUEST_BYTES) {
                    writeResponse(socket, 413, "{\"status\":413}");
                    finish();
                    return;
                }

                // リクエスト全体(ヘッダ + Content-Length 分の本文)が揃うまで待つ
                var headerEnd: int = indexOfHeaderEnd(buffer);
                if (headerEnd < 0) {
                    return;
                }
                buffer.position = 0;
                var header: String = buffer.readUTFBytes(headerEnd);
                var lengthMatch: Array = header.match(/content-length:\s*(\d+)/i);
                var contentLength: int = lengthMatch != null ? int(lengthMatch[1]) : 0;
                var bodyStart: int = headerEnd + 4;
                if (buffer.length < bodyStart + contentLength) {
                    return;
                }

                buffer.position = bodyStart;
                var body: String = buffer.readUTFBytes(contentLength);

                var requestLine: Array = header.split("\r\n")[0].split(" ");
                var result: Object = handleRequest(String(requestLine[0]), String(requestLine[1]), body);
                writeResponse(socket, result.status, result.body);
                finish();
            });
        }

        /** ヘッダの終わり(CRLF CRLF)の位置を返す。まだ受信しきれていなければ -1 */
        private function indexOfHeaderEnd(data: ByteArray): int {
            for (var i: int = 0; i + 3 < data.length; i++) {
                if (data[i] == 13 && data[i + 1] == 10 && data[i + 2] == 13 && data[i + 3] == 10) {
                    return i;
                }
            }
            return -1;
        }

        private function handleRequest(method: String, path: String, body: String): Object {
            // 本文やセッションの値はログに出さない
            LogManager.instance.addLog("ブラウザ拡張からの通信:" + method + " " + path);

            var query: int = path.indexOf("?");
            var purePath: String = query >= 0 ? path.substring(0, query) : path;
            if (purePath != PATH && purePath != PATH + "/") {
                return {status: 404, body: "{\"status\":404}"};
            }

            if (method == "POST") {
                var code: String = null;
                var userSession: String = null;
                try {
                    var json: Object = JSON.parse(body);
                    code = json.code != null ? String(json.code) : null;
                    userSession = json.userSession != null ? String(json.userSession) : null;
                } catch (error: Error) {
                    return {status: BAD_REQUEST, body: "{\"status\":" + BAD_REQUEST + "}"};
                }
                var status: int = receive(code, userSession);
                return {status: status, body: "{\"status\":" + status + "}"};
            }

            if (method == "GET") {
                return {status: 200, body: "{\"waiting\":" + (isWaiting ? "true" : "false") + "}"};
            }

            // OPTIONS など(CORS の許可ヘッダは付けない。拡張からの通信には不要で、ウェブサイトからの通信は通さない)
            return {status: 405, body: "{\"status\":405}"};
        }

        private function writeResponse(socket: Socket, status: int, body: String): void {
            var reasons: Object = {
                200: "OK", 202: "Accepted", 400: "Bad Request", 403: "Forbidden", 404: "Not Found",
                405: "Method Not Allowed", 409: "Conflict", 413: "Payload Too Large", 429: "Too Many Requests"
            };
            var bodyBytes: ByteArray = new ByteArray();
            bodyBytes.writeUTFBytes(body);
            try {
                socket.writeUTFBytes("HTTP/1.1 " + status + " " + (reasons[status] != null ? reasons[status] : "OK") + "\r\n" +
                                     "Content-Type: application/json; charset=utf-8\r\n" +
                                     "Content-Length: " + bodyBytes.length + "\r\n" +
                                     "Cache-Control: no-store\r\n" +
                                     "Connection: close\r\n\r\n");
                socket.writeBytes(bodyBytes);
                socket.flush();
            } catch (error: Error) {
                trace(error.getStackTrace());
            }
        }

        /**
         * 拡張から送られてきた値を処理する。
         *
         * @return HTTP ステータスコード
         */
        public function receive(code: String, userSession: String): int {
            if (this._code == null) {
                return NOT_WAITING;
            }
            if (this._failCount >= MAX_FAILS) {
                return TOO_MANY_FAILS;
            }
            if (code == null || code != this._code) {
                this._failCount++;
                LogManager.instance.addLog("ブラウザ拡張からのログイン:ペアリングコードが一致しません(" + this._failCount + "/" + MAX_FAILS + ")");
                return WRONG_CODE;
            }

            var session: String = Login.normalizeUserSession(userSession);
            if (session == null) {
                return BAD_REQUEST;
            }

            // 1回使ったコードは再利用させない。ログイン画面が確認に失敗したら、画面側で新しいコードで受付を開き直す
            var callback: Function = this._onReceived;
            this._code = null;
            this._onReceived = null;
            LogManager.instance.addLog("ブラウザ拡張から user_session を受信");
            if (callback != null) {
                callback(session);
            }
            return ACCEPTED;
        }
    }
}
