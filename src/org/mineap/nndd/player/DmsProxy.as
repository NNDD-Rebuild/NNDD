package org.mineap.nndd.player {
    import flash.events.ServerSocketConnectEvent;
    import flash.net.ServerSocket;
    import org.mineap.nndd.LogManager;

    /**
     * Local HLS proxy for DMS streams.
     * Routes CEF/hls.js requests through AIR's cookie-bearing URLLoader
     * so that session cookies are included automatically.
     */
    public class DmsProxy {

        private static var _instance: DmsProxy;
        private var _server: ServerSocket;
        public var port: int = 0;

        /** Segment ID registry: numeric string -> CDN URL (avoids exposing CDN URL in proxy URL) */
        public static var _reg: Object = {};
        public static var _regN: int = 0;

        public static function regSeg(url: String): String {
            var id: String = String(_regN++);
            _reg[id] = url;
            return id;
        }

        public static function lookupSeg(id: String): String {
            return _reg[id];
        }

        public static function get instance(): DmsProxy {
            if (!_instance) _instance = new DmsProxy();
            return _instance;
        }

        public function start(): void {
            if (_server != null) return;
            DmsProxy._reg = {};
            DmsProxy._regN = 0;
            _server = new ServerSocket();
            _server.bind(0, "127.0.0.1");
            _server.listen();
            port = _server.localPort;
            _server.addEventListener(ServerSocketConnectEvent.CONNECT, onConnect);
            LogManager.instance.addLog("DmsProxy: started port=" + port);
        }

        public function stop(): void {
            if (_server) {
                try { _server.close(); } catch (e: Error) {}
                _server = null;
                port = 0;
            }
        }

        /** Wrap a CDN URL so that hls.js fetches it via this proxy. */
        public function proxyUrl(url: String): String {
            return "http://127.0.0.1:" + port + "/proxy?url=" + encodeURIComponent(url).replace(/\./g, "%2E");
        }

        private function onConnect(e: ServerSocketConnectEvent): void {
            new DmsProxyConn(e.socket, port);
        }
    }
}

// ── internal helper ──────────────────────────────────────────────────────────

import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.net.Socket;
import flash.net.URLLoader;
import flash.net.URLLoaderDataFormat;
import flash.net.URLRequest;
import flash.utils.ByteArray;
import org.mineap.nndd.LogManager;
import org.mineap.nndd.player.DmsProxy;

class DmsProxyConn {

    private var _sock: Socket;
    private var _proxyPort: int;
    private var _buf: String = "";
    private var _handled: Boolean = false;

    public function DmsProxyConn(sock: Socket, proxyPort: int) {
        _sock = sock;
        _proxyPort = proxyPort;
        sock.addEventListener(ProgressEvent.SOCKET_DATA, onData);
        sock.addEventListener(IOErrorEvent.IO_ERROR, onErr);
    }

    private function onData(e: ProgressEvent): void {
        if (_handled) return;
        _buf += _sock.readUTFBytes(_sock.bytesAvailable);
        if (_buf.indexOf("\r\n\r\n") < 0) return;
        _handled = true;
        handleRequest();
    }

    private function handleRequest(): void {
        var firstLine: String = _buf.substring(0, _buf.indexOf("\r\n"));
        var parts: Array = firstLine.split(" ");
        if (parts.length < 2) { closeWith(400, "Bad Request"); return; }
        var method: String = parts[0];
        var path: String = parts[1]; // e.g. /proxy?url=ENCODED&_HLS_...

        if (method == "OPTIONS") { writeCors(); return; }

        var targetUrl: String = null;
        var idIdx: int = path.indexOf("?id=");
        var urlIdx: int = path.indexOf("?url=");
        if (idIdx >= 0) {
            var segId: String = path.substring(idIdx + 4);
            var ai1: int = segId.indexOf("&");
            if (ai1 >= 0) segId = segId.substring(0, ai1);
            targetUrl = DmsProxy.lookupSeg(segId);
            if (targetUrl == null) { closeWith(404, "Not Found"); return; }
        } else if (urlIdx >= 0) {
            var encodedTarget: String = path.substring(urlIdx + 5);
            var ai2: int = encodedTarget.indexOf("&");
            if (ai2 >= 0) encodedTarget = encodedTarget.substring(0, ai2);
            targetUrl = decodeURIComponent(encodedTarget);
        } else {
            closeWith(404, "Not Found");
            return;
        }

        var loader: URLLoader = new URLLoader();
        loader.dataFormat = URLLoaderDataFormat.BINARY;

        var self: DmsProxyConn = this;
        var captured_targetUrl: String = targetUrl;

        loader.addEventListener(Event.COMPLETE, function(ev: Event): void {
            var data: ByteArray = loader.data as ByteArray;
            var url: String = captured_targetUrl;
            var noQuery: String = url.indexOf("?") >= 0 ? url.substring(0, url.indexOf("?")) : url;
            var isM3u8: Boolean = noQuery.indexOf(".m3u8") >= 0;
            var isCmfv: Boolean = noQuery.indexOf(".cmfv") >= 0;
            var isCmfa: Boolean = noQuery.indexOf(".cmfa") >= 0;
            var isKey:  Boolean = noQuery.indexOf(".key") >= 0;
            if (isM3u8) {
                data.position = 0;
                var text: String = data.readUTFBytes(data.length);
                LogManager.instance.addLog("DmsProxy m3u8 (" + url.substring(0, 80) + "):\n" + text.substring(0, 2000));
                var rewritten: String = self.rewriteM3u8(text, url);
                var out: ByteArray = new ByteArray();
                out.writeUTFBytes(rewritten);
                self.writeResponse(200, "application/x-mpegURL", out);
            } else if (isCmfv || isCmfa) {
                self.writeResponse(200, "video/mp4", data);
            } else if (isKey) {
                self.writeResponse(200, "application/octet-stream", data);
            } else {
                self.writeResponse(200, "application/octet-stream", data);
            }
        });
        loader.addEventListener(IOErrorEvent.IO_ERROR, function(ev: IOErrorEvent): void {
            self.closeWith(502, "Bad Gateway");
        });

        try {
            loader.load(new URLRequest(targetUrl));
        } catch (e: Error) {
            closeWith(500, "Internal Error");
        }
    }

    /** Rewrite all URL lines in an m3u8 to go through this proxy. */
    private static function isHevcStreamInf(line: String): Boolean {
        var lc: String = line.toLowerCase();
        return lc.indexOf("hvc1") >= 0 || lc.indexOf("hev1") >= 0 ||
               lc.indexOf("dvh1") >= 0 || lc.indexOf("dvhe") >= 0;
    }

    private function rewriteM3u8(text: String, baseUrl: String): String {
        var noQuery: String = baseUrl.indexOf("?") >= 0
            ? baseUrl.substring(0, baseUrl.indexOf("?"))
            : baseUrl;
        var baseDir: String = noQuery.substring(0, noQuery.lastIndexOf("/") + 1);

        var protocolEnd: int = baseUrl.indexOf("//") + 2;
        var pathStart: int = baseUrl.indexOf("/", protocolEnd);
        var origin: String = baseUrl.substring(0, pathStart);

        var lines: Array = text.split("\n");

        // masterプレイリストにH.264バリアントが1つでもあるか確認
        var hasNonHevc: Boolean = false;
        for each (var checkLine: String in lines) {
            var cl: String = checkLine.replace(/\r$/, "");
            if (cl.indexOf("#EXT-X-STREAM-INF:") == 0 && !isHevcStreamInf(cl)) {
                hasNonHevc = true;
                break;
            }
        }
        // H.264が1つもない場合はフィルタしない (HEVC ハードウェアデコードに期待)
        var filterHevc: Boolean = hasNonHevc;

        var result: Array = [];
        var skipNextUrl: Boolean = false;
        var proxyBase: String = "http://127.0.0.1:" + _proxyPort + "/proxy?url=";

        for each (var rawLine: String in lines) {
            var line: String = rawLine.replace(/\r$/, "");
            if (line.indexOf("#EXT-X-STREAM-INF:") == 0 && filterHevc) {
                if (isHevcStreamInf(line)) {
                    skipNextUrl = true;
                    continue;
                }
            }
            if (line.length > 0 && line.charAt(0) != '#') {
                if (skipNextUrl) {
                    skipNextUrl = false;
                    continue;
                }
                var absolute: String;
                if (line.indexOf("http://") == 0 || line.indexOf("https://") == 0) {
                    absolute = line;
                } else if (line.charAt(0) == '/') {
                    absolute = origin + line;
                } else {
                    absolute = resolveRelative(baseDir, line);
                }
                var noQLine: String = absolute.indexOf("?") >= 0 ? absolute.substring(0, absolute.indexOf("?")) : absolute;
                if (noQLine.toLowerCase().indexOf(".m3u8") >= 0) {
                    result.push(proxyBase + encodeURIComponent(absolute).replace(/\./g, "%2E"));
                } else {
                    result.push("http://127.0.0.1:" + _proxyPort + "/s.ts?id=" + DmsProxy.regSeg(absolute));
                }
            } else {
                // #タグ行内の URI="..." を全てプロキシ経由に書き換え
                var rewrittenLine: String = rewriteTagUris(line, origin, baseDir, proxyBase);
                result.push(rewrittenLine);
            }
        }
        return result.join("\n");
    }

    /** タグ行 (#EXT-X-KEY, #EXT-X-MAP, #EXT-X-MEDIA 等) 内の URI="..." をプロキシ経由に書き換え */
    private function rewriteTagUris(line: String, origin: String, baseDir: String, proxyBase: String): String {
        var uriStart: int = line.indexOf('URI="');
        if (uriStart < 0) return line;

        var result: String = "";
        var pos: int = 0;
        while (true) {
            uriStart = line.indexOf('URI="', pos);
            if (uriStart < 0) {
                result += line.substring(pos);
                break;
            }
            var valueStart: int = uriStart + 5; // after URI="
            var valueEnd: int = line.indexOf('"', valueStart);
            if (valueEnd < 0) {
                result += line.substring(pos);
                break;
            }
            var uri: String = line.substring(valueStart, valueEnd);
            var abs: String;
            if (uri.indexOf("http://127.0.0.1") == 0) {
                abs = uri; // already proxied
            } else if (uri.indexOf("http://") == 0 || uri.indexOf("https://") == 0) {
                abs = uri;
            } else if (uri.charAt(0) == '/') {
                abs = origin + uri;
            } else {
                abs = resolveRelative(baseDir, uri);
            }
            var tagUri: String;
            if (uri.indexOf("http://127.0.0.1") == 0) {
                tagUri = uri;
            } else {
                var noQTag: String = abs.indexOf("?") >= 0 ? abs.substring(0, abs.indexOf("?")) : abs;
                if (noQTag.toLowerCase().indexOf(".m3u8") >= 0) {
                    tagUri = proxyBase + encodeURIComponent(abs).replace(/\./g, "%2E");
                } else {
                    tagUri = "http://127.0.0.1:" + _proxyPort + "/s.ts?id=" + DmsProxy.regSeg(abs);
                }
            }
            result += line.substring(pos, uriStart) + 'URI="' + tagUri + '"';
            pos = valueEnd + 1;
        }
        return result;
    }

    private function resolveRelative(baseDir: String, relative: String): String {
        var parts: Array = baseDir.split("/");
        parts.pop(); // remove trailing empty string from trailing "/"
        var relParts: Array = relative.split("/");
        for each (var p: String in relParts) {
            if (p == "..") {
                if (parts.length > 3) parts.pop();
            } else if (p != ".") {
                parts.push(p);
            }
        }
        return parts.join("/");
    }

    private function writeResponse(status: int, contentType: String, body: ByteArray): void {
        if (!_sock.connected) return;
        try {
            var header: String =
                "HTTP/1.1 " + status + " OK\r\n" +
                "Content-Type: " + contentType + "\r\n" +
                "Content-Length: " + body.length + "\r\n" +
                "Access-Control-Allow-Origin: *\r\n" +
                "Connection: close\r\n\r\n";
            _sock.writeUTFBytes(header);
            _sock.writeBytes(body);
            _sock.flush();
            _sock.close();
        } catch (e: Error) {}
    }

    private function writeCors(): void {
        if (!_sock.connected) return;
        try {
            _sock.writeUTFBytes(
                "HTTP/1.1 200 OK\r\n" +
                "Access-Control-Allow-Origin: *\r\n" +
                "Access-Control-Allow-Methods: GET, OPTIONS\r\n" +
                "Access-Control-Allow-Headers: *\r\n" +
                "Content-Length: 0\r\n" +
                "Connection: close\r\n\r\n"
            );
            _sock.flush();
            _sock.close();
        } catch (e: Error) {}
    }

    private function closeWith(code: int, msg: String): void {
        if (!_sock.connected) return;
        try {
            _sock.writeUTFBytes("HTTP/1.1 " + code + " " + msg + "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
            _sock.flush();
            _sock.close();
        } catch (e: Error) {}
    }

    private function onErr(e: IOErrorEvent): void {
        try { _sock.close(); } catch (er: Error) {}
    }
}
