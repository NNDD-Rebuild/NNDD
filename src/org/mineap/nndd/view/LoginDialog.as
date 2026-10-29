/**
 * LoginDialog.as
 * 指定されたサイトへのログイン処理を行う。
 *
 * Copyright (c) 2008 MAP - MineApplicationProject. All Rights Reserved.
 *
 */

import flash.data.EncryptedLocalStore;
import flash.desktop.NativeProcess;
import flash.desktop.NativeProcessStartupInfo;
import flash.filesystem.File;
import flash.net.URLRequest;
import flash.net.navigateToURL;
import flash.events.ErrorEvent;
import flash.events.Event;
import flash.events.HTTPStatusEvent;
import flash.events.IOErrorEvent;
import flash.events.KeyboardEvent;
import flash.system.Capabilities;
import flash.net.URLLoader;
import flash.net.URLRequest;
import flash.net.URLRequestHeader;
import flash.ui.Keyboard;
import flash.utils.ByteArray;

import mx.controls.Alert;
import mx.controls.Button;
import mx.events.FlexEvent;

import org.mineap.nicovideo4as.Login;
import org.mineap.nndd.LogManager;
import org.mineap.nndd.Message;
import org.mineap.nndd.server.SessionLoginReceiver;
import org.mineap.nndd.util.FirefoxCookieReader;
import org.mineap.nndd.view.LoadingPicture;
import org.mineap.util.config.ConfigManager;

public static const ON_LOGIN_SUCCESS: String = "onFirestTimeLoginSuccess";
public static const LOGIN_FAIL: String = "LoginFail";
public static const NO_LOGIN: String = "noLogin";
public static const DEVICE_NAME: String = "NNDD (" + Capabilities.os + ")";

public static var TOP_PAGE_URL: String;
public static var LOGIN_URL: String;

public static var LABEL_CANCEL: String = "キャンセル";
public static var LABEL_LOGIN: String = "ログイン";
public static var LABEL_NO_LOGIN: String = "ログインしない";

private var isStoreName: Boolean = false;
private var isStorePass: Boolean = false;
private var isAutoLogin: Boolean = false;
private var isLogout: Boolean = false;
private var logManager: LogManager = null;

//ログイン用URLローダー
private var _login: Login = null;

private var loading: LoadingPicture = new LoadingPicture();

private var userName: String = null;
private var password: String = null;
private var otp: String = null;
private var userSession: String = null;
private var isStoreSession: Boolean = true;

// user_session の確認用ローダーと、そのレスポンスステータス
private var _sessionCheckLoader: URLLoader = null;
private var _sessionCheckStatus: int = 0;

// 実際の再生と同じ /api/watch/v3 で確認する。有効なセッションなら 200 と viewer が返り、無効なら 400 UNAUTHORIZED になる
// actionTrackId は「英数字10文字_ミリ秒時刻」の形式でないと INVALID_PARAMETER(400) になる
private static const SESSION_CHECK_URL: String = "https://www.nicovideo.jp/api/watch/v3/sm9?actionTrackId=";
private var _sessionCheckBody: String = "";

/** user_session でログインしたか。true のとき、メールアドレス・パスワードは使われない。 */
public var isSessionLogin: Boolean = false;


public function initLoginDialog(
    topURL: String,
    loginURL: String,
    logManager: LogManager,
    isLogout: Boolean = false
): void {
    TOP_PAGE_URL = topURL;
    LOGIN_URL = loginURL;
    loginButton.enabled = true;
    noLoginButton.enabled = true;

    this.logManager = logManager;
    this.isLogout = isLogout;

    textInput_session.setFocus();

    // ブラウザ拡張からの受け取りを開始(この画面を開いている間だけ有効)。
    // 起動時の初期化の途中で呼ばれるため、失敗してもここで握って、後続の初期化(待ち受けの開始など)を止めない
    try {
        openExtensionReceiver();
        addEventListener(Event.REMOVED_FROM_STAGE, extensionReceiverClose);
    } catch (error: Error) {
        logManager.addLog("ブラウザ拡張からの受け取りを開始できませんでした:" + error + ":" + error.getStackTrace());
    }
}

/**
 * ブラウザ拡張から user_session を受け取る受付を(再)開始し、ペアリングコードを表示する。
 */
private function openExtensionReceiver(): void {
    var code: String = SessionLoginReceiver.instance.open(extensionSessionReceived);
    if (label_pairingCode != null) {
        label_pairingCode.text = code;
    }
}

private function extensionReceiverClose(event: Event): void {
    SessionLoginReceiver.instance.close();
}

/**
 * ブラウザ拡張から user_session を受け取った。入力欄に反映して、そのままログインを試す。
 */
private function extensionSessionReceived(session: String): void {
    this.userSession = session;
    textInput_session.text = session;
    logManager.addLog("ブラウザ拡張から受け取った user_session でログインを試みます");
    // コードは使い切りなので、確認に失敗した場合に備えて新しいコードで受付を開き直す
    openExtensionReceiver();
    loginWithSession();
}

/**
 * Chrome でニコニコ動画を開く。ブラウザの拡張機能のポップアップは外部から開けないため、
 * ペアリングコードを URL に付けて開き、拡張(コンテンツスクリプト)に自動で送信させる。
 * (ブラウザでニコニコ動画にログインしていれば、そのまま NNDD に送られる)
 */
private function openChromeForExtension(): void {
    var url: String = "https://www.nicovideo.jp/";
    var code: String = label_pairingCode.text;
    if (code != null && /^\d{6}$/.test(code)) {
        url += "?nndd_login_code=" + code;
    }
    var opened: Boolean = false;

    if (NativeProcess.isSupported) {
        try {
            var os: String = Capabilities.os.toLowerCase();
            var info: NativeProcessStartupInfo = new NativeProcessStartupInfo();
            var args: Vector.<String> = new Vector.<String>();

            if (os.indexOf("win") == 0) {
                // "start" は App Paths に登録された chrome を探して起動する(最初の "" はウィンドウタイトル)
                info.executable = new File("C:\\Windows\\System32\\cmd.exe");
                args.push("/c", "start", "", "chrome", url);
            } else if (os.indexOf("mac") == 0) {
                info.executable = new File("/usr/bin/open");
                args.push("-a", "Google Chrome", url);
            } else {
                info.executable = new File("/usr/bin/env");
                args.push("google-chrome", url);
            }

            info.arguments = args;
            var process: NativeProcess = new NativeProcess();
            process.start(info);
            opened = true;
        } catch (error: Error) {
            logManager.addLog("Chrome を起動できませんでした:" + error);
        }
    }

    if (!opened) {
        // 起動できなければ、既定のブラウザで開く
        navigateToURL(new URLRequest(url));
    }

    text_extensionHint.text = "Chrome が開きます。ニコニコ動画にログイン済みなら、拡張機能から自動で送られてタブが閉じます。" +
                              "未ログインの場合はログインページが開くので、ログインすると自動で送られてタブが閉じます。" +
                              "(拡張機能「NNDD-RE」が Chrome に入っている必要があります)";
}

/**
 * Firefox のプロファイルから user_session を読み取って、ログインを試す。
 */
private function loadFromFirefox(): void {
    try {
        var session: String = FirefoxCookieReader.read();
        if (Login.normalizeUserSession(session) == null) {
            Alert.show("Firefox に、ニコニコ動画の user_session が見つかりませんでした。\nFirefox で www.nicovideo.jp にログインしてから、もう一度試してください。", Message.M_ERROR);
            logManager.addLog("Firefoxから user_session を取得できませんでした(見つからない)");
            return;
        }
        this.userSession = session;
        textInput_session.text = session;
        logManager.addLog("Firefoxから user_session を取得しました");
        loginWithSession();
    } catch (error: Error) {
        logManager.addLog("Firefoxから user_session の取得に失敗:" + error);
        Alert.show("Firefox から user_session を取得できませんでした。\n" + error.message +
                   "\n\nブラウザ拡張を使うか、値を手で貼り付けてください。", Message.M_ERROR);
    }
}

private function execAutoLogin(): void {
    if (isAutoLogin && !isLogout) {

        // パスワードでのログインは使えないため、保存済みの user_session があればそちらを優先する
        if (Login.normalizeUserSession(userSession) != null) {
            loginWithSession();
            return;
        }

        // メールアドレス・パスワードでの自動ログインは廃止(ログインAPIが使えないため)。user_session が無ければ何もしない
    }
}

private function enterHandler(event: FlexEvent): void {

    if (this.userName.length >= 1 && this.password.length >= 1) {
        login();
    }

}

// ログインボタン押下字の処理
private function login(): void {
    if (loginButton.label == LoginDialog.LABEL_LOGIN) {
        // パスワードでログインするときは、取り込み済みの user_session を使わない
        Login.manualUserSession = null;
        isSessionLogin = false;

        noLoginButton.enabled = false;
        loginButton.label = LoginDialog.LABEL_CANCEL;

        if (_login != null) {
            _login.close();
        }

        _login = new Login();
        _login.addEventListener(Login.LOGIN_SUCCESS, loginSuccess);
        _login.addEventListener(Login.NO_LOGIN, loginSuccess);
        _login.addEventListener(Login.LOGIN_FAIL, loginFail);
        _login.addEventListener(Login.MULTI_FACTOR_AUTHENTICATION_REQUIRED, multiFactorAuthenticationRequiredHandler);
        _login.login(this.userName, this.password, this.otp, DEVICE_NAME);

    } else if (loginButton.label == LoginDialog.LABEL_CANCEL) {
        noLoginButton.enabled = true;
        if (_login != null) {
            try {
                _login.close();
            } catch (error: Error) {
                trace(error.getStackTrace());
            }
        }
        loginButton.label = LoginDialog.LABEL_LOGIN;
    }
}

private function notLogin(): void {
    Login.manualUserSession = null;
    isSessionLogin = false;
    saveStore();

    loginButton.enabled = false;
    noLoginButton.enabled = false;
    loginButton.label = LoginDialog.LABEL_LOGIN;
    dispatchEvent(new HTTPStatusEvent(NO_LOGIN));
}

private function saveStore(): void {
    var bytes: ByteArray = new ByteArray();

    if (checkBox_storeUserName.selected) {

        ConfigManager.getInstance().removeItem("userName");
        ConfigManager.getInstance().setItem("userName", this.userName);

        ConfigManager.getInstance().removeItem("storeName");
        ConfigManager.getInstance().setItem("storeName", true);

    } else {

        ConfigManager.getInstance().removeItem("userName");
        ConfigManager.getInstance().setItem("userName", "");

        ConfigManager.getInstance().removeItem("storeName");
        ConfigManager.getInstance().setItem("storeName", false);

    }

    if (checkBox_storePassword.selected) {
        savePassword(this.password);

        ConfigManager.getInstance().removeItem("storePass");
        ConfigManager.getInstance().setItem("storePass", true);
    } else {
        removePass();

        ConfigManager.getInstance().removeItem("storePass");
        ConfigManager.getInstance().setItem("storePass", false);
    }


    ConfigManager.getInstance().removeItem("isAutoLogin");
    ConfigManager.getInstance().setItem("isAutoLogin", checkbox_autoLogin.selected);

    try {
        ConfigManager.getInstance().save();
    } catch (error: Error) {
        trace(error.getStackTrace());
        Alert.show(Message.M_CONF_FILE_CAN_NOT_SAVE + "\n\n" + error, Message.M_ERROR);
    }
}

private function loginFail(event: ErrorEvent): void {
    this._login.close();

    if (event.text != Login.LOGIN_FAIL_MESSAGE) {

        Alert.show("ログインに失敗しました。以下の原因が考えられます。\n" + "\t1.インターネットに接続されていない。\n" + "\t2.ニコニコ動画へのアクセスが制限されている。\n" +
                   "\t3.ニコニコ動画のログインサーバーが応答しない。\n" +
                   "\t4.パスワードでのログインは使えなくなっている。(下の「user_session でログイン」を試してください)\n\n" + event.text, Message.M_ERROR);
        logManager.addLog("ログイン失敗:ニコニコ動画にアクセスできない:" + event);

    } else {

        Alert.show("ログインできませんでした。\n" + "メールアドレス、もしくはパスワードが間違っています。\n" + event.text +
                   "\n\nパスワードでのログインは使えなくなっています。下の「user_session でログイン」を試してください。", Message.M_ERROR);
        logManager.addLog("ログイン失敗:メールアドレスもしくはパスワードの設定ミス:" + event);
    }

    loginButton.enabled = true;
    noLoginButton.enabled = true;
    loginButton.label = LoginDialog.LABEL_LOGIN;

    return;
}

private function removePass(): void {

    var temp: Error = null;
    try {
        EncryptedLocalStore.removeItem("password");
    } catch (error: Error) {
        trace(error.getStackTrace());
        temp = error;
    }

    if (temp != null) {
        var message: String = Message.M_PASSWORD_CAN_NOT_SAVE + "\n" + temp;
        logManager.addLog(message);
        Alert.show(message, Message.M_ERROR);
    }

    // reset() は保存済みの全項目を消すので、user_session は退避して書き戻す
    var keptSession: ByteArray = null;
    try {
        keptSession = EncryptedLocalStore.getItem("userSession");
    } catch (error: Error) {
        trace(error.getStackTrace());
    }

    EncryptedLocalStore.reset();

    if (keptSession != null) {
        try {
            EncryptedLocalStore.setItem("userSession", keptSession);
        } catch (error: Error) {
            trace(error.getStackTrace());
        }
    }

}

private function savePassword(pass: String): void {
    var bytes: ByteArray = new ByteArray();
    var temp: Error = null;
    try {
        EncryptedLocalStore.removeItem("password");
        bytes = new ByteArray();
        bytes.writeUTFBytes(pass);
        EncryptedLocalStore.setItem("password", bytes);
    } catch (error: Error) {
        trace(error.getStackTrace());
        temp = error;
    }

    if (temp != null) {
        var message: String = Message.M_PASSWORD_CAN_NOT_SAVE + "\n" + temp;
        logManager.addLog(message);
        Alert.show(message, Message.M_ERROR);
    }
}


private function loginSuccess(event: Event): void {
    this._login.close();

    trace(event);
    saveStore();
    logManager.addLog("ログイン成功:" + event);

    // イベントを送出
    dispatchEvent(new HTTPStatusEvent(ON_LOGIN_SUCCESS));
}

private function sessionEnterHandler(event: FlexEvent): void {
    loginWithSession();
}

/**
 * 貼り付けられた user_session でログインする。
 * ニコニコの API で有効なセッションか確認し、有効なら Login に保持して成功を通知する。
 */
private function loginWithSession(): void {
    if (sessionLoginButton.label == LoginDialog.LABEL_CANCEL) {
        closeSessionCheck();
        resetSessionLoginButtons();
        return;
    }

    var session: String = Login.normalizeUserSession(this.userSession);
    if (session == null) {
        Alert.show("user_session を入力してください。\nブラウザの Cookie「user_session」の値を貼り付けます。", Message.M_ERROR);
        return;
    }

    noLoginButton.enabled = false;
    loginButton.enabled = false;
    sessionLoginButton.label = LoginDialog.LABEL_CANCEL;

    closeSessionCheck();
    _sessionCheckStatus = 0;
    _sessionCheckBody = "";
    _sessionCheckLoader = new URLLoader();
    _sessionCheckLoader.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, function (e: HTTPStatusEvent): void {
        _sessionCheckStatus = e.status;
    });
    _sessionCheckLoader.addEventListener(Event.COMPLETE, function (e: Event): void {
        _sessionCheckBody = String(_sessionCheckLoader.data);
        sessionCheckFinished(session);
    });
    _sessionCheckLoader.addEventListener(IOErrorEvent.IO_ERROR, function (e: IOErrorEvent): void {
        sessionCheckFinished(session);
    });

    var request: URLRequest = new URLRequest(SESSION_CHECK_URL + "nnddCheck0_" + new Date().getTime().toString());
    // 入力された値を手動で Cookie に付けて確認する(manageCookies=false にしないと Cookie ヘッダは送られない)
    request.manageCookies = false;
    request.requestHeaders = [
        new URLRequestHeader("Cookie", "user_session=" + session),
        new URLRequestHeader("X-Frontend-Id", "6"),
        new URLRequestHeader("X-Frontend-Version", "0"),
        new URLRequestHeader("X-Niconico-Language", "ja-jp")
    ];
    _sessionCheckLoader.load(request);
}

private function sessionCheckFinished(session: String): void {
    closeSessionCheck();

    // 200 でも viewer が無ければ、セッションが効かずゲスト扱いになっている
    var isValid: Boolean = _sessionCheckStatus == 200 && _sessionCheckBody.indexOf("\"viewer\":{") != -1;
    // build=manualCookie は manageCookies=false で Cookie を手動付与する版の目印。長さは貼り付けミス(途中で切れた等)の確認用
    logManager.addLog("user_sessionの確認(build=manualCookie):status=" + _sessionCheckStatus + " viewer=" + (isValid ? "あり" : "なし") +
                      " length=" + session.length + " prefix=" + (session.indexOf("user_session_") == 0 ? "ok" : "ng"));

    if (isValid) {
        Login.manualUserSession = session;
        isSessionLogin = true;

        // saveStore() は removePass() 経由でローカルストアを作り直すため、user_session の保存は先にしてはいけない
        saveStore();
        saveSession(session);

        logManager.addLog("ログイン成功:user_session");
        resetSessionLoginButtons();
        dispatchEvent(new HTTPStatusEvent(ON_LOGIN_SUCCESS));
        return;
    }

    resetSessionLoginButtons();
    diagnoseCookieHeader();
    if (_sessionCheckStatus == 200 || _sessionCheckStatus == 400 || _sessionCheckStatus == 401 || _sessionCheckStatus == 403) {
        logManager.addLog("ログイン失敗:user_sessionが無効または期限切れ:status=" + _sessionCheckStatus);
        Alert.show("user_session が無効か、期限切れです。\nブラウザで再度ログインし、新しい値を貼り付けてください。", Message.M_ERROR);
    } else {
        logManager.addLog("ログイン失敗:user_sessionの確認に失敗:status=" + _sessionCheckStatus);
        Alert.show("user_session の確認に失敗しました。(status:" + _sessionCheckStatus + ")\nインターネットに接続されているか確認してください。", Message.M_ERROR);
    }
}

/**
 * 失敗時の切り分け用。manageCookies=false で付けた Cookie ヘッダが実際にサーバーへ届くかを、
 * ダミーの値で確認してログに残す。user_session の値は外部に送らない。
 */
private function diagnoseCookieHeader(): void {
    var loader: URLLoader = new URLLoader();
    loader.addEventListener(Event.COMPLETE, function (e: Event): void {
        var received: Boolean = String(loader.data).indexOf("nndd_diag=1") != -1;
        logManager.addLog("診断:手動Cookieヘッダの送信=" + (received ? "届いた" : "届いていない"));
    });
    loader.addEventListener(IOErrorEvent.IO_ERROR, function (e: IOErrorEvent): void {
        logManager.addLog("診断:手動Cookieヘッダの送信=不明(診断用リクエストに失敗)");
    });
    var request: URLRequest = new URLRequest("https://httpbin.org/headers");
    request.manageCookies = false;
    request.requestHeaders = [new URLRequestHeader("Cookie", "nndd_diag=1")];
    loader.load(request);
}

private function closeSessionCheck(): void {
    if (_sessionCheckLoader != null) {
        try {
            _sessionCheckLoader.close();
        } catch (error: Error) {
            trace(error.getStackTrace());
        }
        _sessionCheckLoader = null;
    }
}

private function resetSessionLoginButtons(): void {
    sessionLoginButton.label = "user_session でログイン";
    sessionLoginButton.enabled = true;
    loginButton.enabled = true;
    noLoginButton.enabled = true;
}

private function saveSession(session: String): void {
    isStoreSession = checkBox_storeSession.selected;

    ConfigManager.getInstance().removeItem("storeSession");
    ConfigManager.getInstance().setItem("storeSession", isStoreSession);
    try {
        ConfigManager.getInstance().save();
    } catch (error: Error) {
        trace(error.getStackTrace());
    }

    try {
        EncryptedLocalStore.removeItem("userSession");
        if (isStoreSession) {
            var bytes: ByteArray = new ByteArray();
            bytes.writeUTFBytes(session);
            EncryptedLocalStore.setItem("userSession", bytes);
        }
    } catch (error: Error) {
        trace(error.getStackTrace());
        var message: String = "user_session を保存できませんでした。\n" + error;
        logManager.addLog(message);
        Alert.show(message, Message.M_ERROR);
    }
}

private function buttonKeyUp(event: KeyboardEvent): void {
    if (event.keyCode == Keyboard.ENTER) {
        if ((event.target as Button).label == LoginDialog.LABEL_CANCEL) {
            this.login();
        } else if ((event.target as Button).label == LoginDialog.LABEL_LOGIN) {
            this.login();
        } else if ((event.target as Button).label == LoginDialog.LABEL_NO_LOGIN) {
            this.notLogin();
        }
    }
}

private function multiFactorAuthenticationRequiredHandler(event: Event): void {
    trace("MultiFactorAuthentication is required.");
    trace(event);
    Alert.show("2段階認証が要求されています。\n6桁の数字からなるワンタイムパッドを入力してください。");
    textInput_otp.enabled = true;
    textInput_userName.enabled = false;
    textInput_password.enabled = false;
    hGroup_otp.visible = true;
    loginButton.label = LoginDialog.LABEL_LOGIN;
    loginButton.enabled = true;
}