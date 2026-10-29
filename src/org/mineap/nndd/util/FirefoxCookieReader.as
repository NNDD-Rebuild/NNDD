package org.mineap.nndd.util {
    import flash.data.SQLConnection;
    import flash.data.SQLMode;
    import flash.data.SQLResult;
    import flash.data.SQLStatement;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.system.Capabilities;

    import org.mineap.nndd.LogManager;

    /**
     * Firefox のプロファイルから、ニコニコ動画の user_session を読み取る。
     *
     * Firefox の cookies.sqlite は暗号化されていない。起動中は Firefox が使っているため、
     * 一時フォルダにコピー(-wal / -shm も含む)してから読む。
     * (Chrome は Cookie が暗号化されていて AIR からは復号できないため、ブラウザ拡張で受け取る)
     */
    public class FirefoxCookieReader {

        public function FirefoxCookieReader() {
        }

        /**
         * user_session を取得する。
         *
         * @return user_session の値。見つからなければ null
         * @throws Error Firefox が見つからない、DB が読めないなど
         */
        public static function read(): String {
            var firefoxDir: File = getFirefoxDir();
            if (firefoxDir == null || !firefoxDir.exists) {
                throw new Error("Firefox のプロファイルフォルダが見つかりません。");
            }

            var profiles: Array = listProfiles(firefoxDir);
            if (profiles.length == 0) {
                throw new Error("Firefox のプロファイルが見つかりません。");
            }

            var lastError: Error = null;
            for each(var profile: File in profiles) {
                var cookieFile: File = profile.resolvePath("cookies.sqlite");
                if (!cookieFile.exists) {
                    continue;
                }
                try {
                    var value: String = readFromProfile(cookieFile);
                    if (value != null) {
                        return value;
                    }
                } catch (error: Error) {
                    lastError = error;
                    LogManager.instance.addLog("Firefoxの Cookie 読み取りに失敗:" + profile.name + ":" + error);
                }
            }

            if (lastError != null) {
                throw lastError;
            }
            return null;
        }

        private static function getFirefoxDir(): File {
            var os: String = Capabilities.os.toLowerCase();
            if (os.indexOf("win") == 0) {
                return File.userDirectory.resolvePath("AppData/Roaming/Mozilla/Firefox");
            } else if (os.indexOf("mac") == 0) {
                return File.userDirectory.resolvePath("Library/Application Support/Firefox");
            }
            return File.userDirectory.resolvePath(".mozilla/firefox");
        }

        /**
         * profiles.ini から、使われている可能性が高い順(インストールの既定 → 既定フラグ付き → その他)にプロファイルを返す。
         */
        private static function listProfiles(firefoxDir: File): Array {
            var iniFile: File = firefoxDir.resolvePath("profiles.ini");
            if (!iniFile.exists) {
                return [];
            }

            var stream: FileStream = new FileStream();
            stream.open(iniFile, FileMode.READ);
            var text: String = stream.readUTFBytes(stream.bytesAvailable);
            stream.close();

            var installDefaults: Array = [];
            var defaults: Array = [];
            var others: Array = [];

            var data: Object = {};
            var sections: Array = [];

            for each(var rawLine: String in text.split(/\r?\n/)) {
                var line: String = rawLine.replace(/^\s+|\s+$/g, "");
                if (line.length == 0 || line.charAt(0) == ";") {
                    continue;
                }
                if (line.charAt(0) == "[") {
                    data = {};
                    sections.push({name: line, data: data});
                    continue;
                }
                var eq: int = line.indexOf("=");
                if (eq > 0) {
                    data[line.substring(0, eq)] = line.substring(eq + 1);
                }
            }

            for each(var sec: Object in sections) {
                var d: Object = sec.data;
                if (String(sec.name).indexOf("[Install") == 0 && d.Default != null) {
                    installDefaults.push(resolveProfile(firefoxDir, String(d.Default), true));
                } else if (String(sec.name).indexOf("[Profile") == 0 && d.Path != null) {
                    var profileDir: File = resolveProfile(firefoxDir, String(d.Path), String(d.IsRelative) != "0");
                    if (String(d.Default) == "1") {
                        defaults.push(profileDir);
                    } else {
                        others.push(profileDir);
                    }
                }
            }

            var result: Array = [];
            for each(var f: File in installDefaults.concat(defaults, others)) {
                if (f != null && f.exists) {
                    var dup: Boolean = false;
                    for each(var g: File in result) {
                        if (g.nativePath == f.nativePath) {
                            dup = true;
                        }
                    }
                    if (!dup) {
                        result.push(f);
                    }
                }
            }
            return result;
        }

        private static function resolveProfile(firefoxDir: File, path: String, isRelative: Boolean): File {
            if (isRelative) {
                return firefoxDir.resolvePath(path);
            }
            var f: File = new File();
            f.nativePath = path;
            return f;
        }

        /**
         * cookies.sqlite(と -wal / -shm)を一時フォルダにコピーして、user_session を読む。
         */
        private static function readFromProfile(cookieFile: File): String {
            var tempDir: File = File.createTempDirectory();
            var conn: SQLConnection = null;
            try {
                var names: Array = ["cookies.sqlite", "cookies.sqlite-wal", "cookies.sqlite-shm"];
                for each(var name: String in names) {
                    var src: File = cookieFile.parent.resolvePath(name);
                    if (src.exists) {
                        src.copyTo(tempDir.resolvePath(name), true);
                    }
                }

                conn = new SQLConnection();
                conn.open(tempDir.resolvePath("cookies.sqlite"), SQLMode.READ);

                var stmt: SQLStatement = new SQLStatement();
                stmt.sqlConnection = conn;
                // 有効期限が最も遠い(=最後にログインした)ものを使う
                stmt.text = "SELECT value FROM moz_cookies " +
                            "WHERE name = 'user_session' AND (host = '.nicovideo.jp' OR host = 'nicovideo.jp' OR host LIKE '%.nicovideo.jp') " +
                            "ORDER BY expiry DESC LIMIT 1";
                stmt.execute();

                var result: SQLResult = stmt.getResult();
                if (result != null && result.data != null && result.data.length > 0) {
                    var value: Object = result.data[0].value;
                    if (value != null) {
                        return String(value);
                    }
                }
                return null;
            } finally {
                if (conn != null) {
                    try {
                        conn.close();
                    } catch (error: Error) {
                        trace(error.getStackTrace());
                    }
                }
                try {
                    tempDir.deleteDirectory(true);
                } catch (error: Error) {
                    trace(error.getStackTrace());
                }
            }
            return null;
        }
    }
}
