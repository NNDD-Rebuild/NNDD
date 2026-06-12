package org.mineap.nndd {
    import flash.errors.IOError;
    import flash.events.ErrorEvent;
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.events.HTTPStatusEvent;
    import flash.events.IOErrorEvent;
    import flash.events.ProgressEvent;
    import flash.events.TimerEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.net.URLRequestHeader;
    import flash.net.URLStream;
    import flash.utils.ByteArray;
    import flash.utils.Timer;
    import flash.utils.getTimer;

    import mx.controls.Alert;
    import mx.events.CloseEvent;

    import org.mineap.nicovideo4as.CommentLoader;
    import org.mineap.nicovideo4as.Login;
    import org.mineap.nicovideo4as.VideoLoader;
    import org.mineap.nicovideo4as.WatchVideoPage;
    import org.mineap.nicovideo4as.analyzer.DmcInfoAnalyzer;
    import org.mineap.nicovideo4as.analyzer.DmcResultAnalyzer;
    import org.mineap.nicovideo4as.analyzer.GetFlvResultAnalyzer;
    import org.mineap.nicovideo4as.analyzer.GetWaybackkeyResultAnalyzer;
    import org.mineap.nicovideo4as.analyzer.WatchDataAnalyzer;
    import org.mineap.nicovideo4as.analyzer.WatchDataAnalyzerGetFlvAdapter;
    import org.mineap.nicovideo4as.api.ApiGetBgmAccess;
    import org.mineap.nicovideo4as.loader.ThumbImgLoader;
    import org.mineap.nicovideo4as.loader.ThumbInfoLoader;
    import org.mineap.nicovideo4as.analyzer.DmsResultAnalyzer;
    import org.mineap.nicovideo4as.loader.api.ApiDmcAccess;
    import org.mineap.nicovideo4as.loader.api.ApiDmsAccess;
    import org.mineap.nicovideo4as.video.DmsHlsDownloader;
    import org.mineap.nicovideo4as.loader.api.ApiGetFlvAccess;
    import org.mineap.nicovideo4as.loader.api.ApiGetWaybackkeyAccess;
    import org.mineap.nicovideo4as.model.NgUp;
    import org.mineap.nicovideo4as.model.VideoType;
    import org.mineap.nicovideo4as.stream.VideoStream;
    import org.mineap.nicovideo4as.util.HtmlUtil;
    import org.mineap.nndd.library.LibraryManagerBuilder;
    import org.mineap.nndd.model.NNDDVideo;
    import org.mineap.nndd.player.comment.Command;
    import org.mineap.nndd.server.RequestType;
    import org.mineap.nndd.util.PathMaker;
    import org.mineap.nndd.util.ThumbInfoAnalyzer;
    import org.mineap.util.config.ConfigManager;

    /**
     * ニコニコ動画にアクセスし、ダウンロードを行います。処理は以下の順に進行します。<br>
     * 1.ログイン<br>
     * 2.動画ページへアクセス<br>
     * 3.コメントのDL<br>
     * 4.投稿者コメントのDL<br>
     * 5.ユーザーニコ割のDL(存在する場合)<br>
     * 6.サムネイル情報をDL<br>
     * 7.サムネイル画像をDL<br>
     * 8.市場情報をDL<br>
     * 9.動画をDL<br>
     * 各ステップの完了ごとにイベントが発行されます。<br>
     * また、動画のDL時はプログレスイベントが発行されます。
     *
     * @author shiraminekeisuke
     *
     */
    public class NNDDDownloader extends EventDispatcher {
        private var _login: Login;
        private var _watchVideo: WatchVideoPage;
        private var _getflvAccess: ApiGetFlvAccess;
        private var _getWaybackkeyAccess: ApiGetWaybackkeyAccess;
        private var _commentLoader: CommentLoader;
        private var _ownerCommentLoader: CommentLoader;
        private var _nicowariLoader: VideoLoader;
        private var _getbgmAccess: ApiGetBgmAccess;
        private var _thumbInfoLoader: ThumbInfoLoader;
        private var _thumbImgLoader: ThumbImgLoader;
        private var _videoLoader: VideoLoader;
        private var _videoStream: VideoStream;

        public var _dmcAccess: ApiDmcAccess;
        public var _dmcInfoAnalyzer: DmcInfoAnalyzer;
        public var _dmcResultAnalyzer: DmcResultAnalyzer;

        public var _dmsAccess: ApiDmsAccess;
        public var _dmsResultAnalyzer: DmsResultAnalyzer;
        private var _dmsHlsDownloader: DmsHlsDownloader;
        private var _dmsDownloaded: Boolean = false;

        private var _dmcHeartBeatTimer: Timer = null;

        private var _otherNNDDInfoLoader: URLLoader;

        private var _flvResultAnalyzer: GetFlvResultAnalyzer;

        private var _videoId: String;
        private var _saveDir: File;
        private var _saveVideoName: String;
        private var _saveVideoFileName: String;
        private var _streamingUrl: String;
        private var _nicoVideoName: String;
        private var _savedVideoPath: String;
        private var _thumbPath: String;
        private var _threadId: String;
        private var _thumbInfoId: String;
        private var _when: Date;
        private var _waybackkey: String;
        private var _maxCommentCount: Number;
        private var _fmsToken: String;

        private var _retryCount: int;
        private var _downloadedSize: Number;

        private var _nicowariVideoUrl: String;
        private var _nicowariVideoId: String;
        private var _nicowariVideoUrls: Array;
        private var _nicowariVideoIds: Array;

        private var _isVideoNotDownload: Boolean = false;
        private var _isCommentOnlyDownload: Boolean = false;
        private var _watchVideoOnly: Boolean = false;
        private var _isAppendComment: Boolean = false;
        private var _useOldType: Boolean = false;
        private var _isRedirected: Boolean = false;

        public var _isEnableGetVideoFromOtherNNDDServer: Boolean = false;
        public var _otherNNDDServerAddress: String = null;
        public var _otherNNDDServerPort: int = -1;
        private var _isNNDDServerReady: Boolean = false;
        private var _nnddServerVideoUrl: String = null;

        /**
         * ログイン処理を開始したときに、typeプロパティがこの定数に設定されたEventが発行されます。
         */
        public static const LOGIN_START: String = "LoginStart";

        /**
         * ログインに失敗したとき、typeプロパティがこの定数に設定されたIOErrorEventが発行されます。
         */
        public static const LOGIN_FAIL: String = "LoginFail";

        /**
         * ログインに成功したとき、typeプロパティがこの定数に設定されたEventが発行されます。
         */
        public static const LOGIN_SUCCESS: String = "LoginSuccess";
        public static const LOGIN_SKIP: String = "LoginSkip";

        /**
         * 動画ページへのアクセスを開始したときに、typeプロパティがこの定数に設定されたEventが発行されます。
         */
        public static const WATCH_START: String = "WatchStart";

        /**
         * 動画ページへのアクセスに失敗したとき、typeプロパティがこの定数に設定されたIOErrorEventが発行されます。
         */
        public static const WATCH_FAIL: String = "WatchFail";

        /**
         * 動画ページへのアクセスに成功したとき、typeプロパティがこの定数に設定されたEventが発行されます。
         */
        public static const WATCH_SUCCESS: String = "WatchSuccess";

        /**
         *
         */
        public static const GETFLV_API_ACCESS_START: String = "GetFlvAccessStart";

        /**
         * ニコニコ動画のAPIであるgetflvへのアクセスに失敗したとき、typeプロパティがこの定数に設定されたIOErrorEventが発行されます。
         */
        public static const GETFLV_API_ACCESS_FAIL: String = "GetFlvAccessFail";

        /**
         * ニコニコ動画のAPIであるgetflvへのアクセスに成功したとき、typeプロパティがこの定数に設定されたEventが発行されます。
         */
        public static const GETFLV_API_ACCESS_SUCCESS: String = "GetFlvAccessSuccess";

        /**
         *
         */
        public static const GETWAYBACKKEY_API_ACCESS_START: String = "GetWaybackkeyAccessStart";

        /**
         * ニコニコ動画のAPIであるgetwaybackkeyへのアクセスに失敗した時、typeプロパティがこの定数に設定されたErrorEventが発行されます。
         */
        public static const GETWAYBACKKEY_API_ACCESS_FAIL: String = "GetWaybackkeyAccessFail";

        /**
         * ニコニコ動画のAPIであるgetwaybackkeyへのアクセスに失敗した時、typeプロパティがこの定数に設定されたEventが発行されます。
         */
        public static const GETWAYBACKKEY_API_ACCESS_SUCCESS: String = "GetWaybackkeyAccessSuccess";

        /**
         *
         */
        public static const COMMENT_GET_START: String = "CommentGetStart";

        /**
         * 通常コメントの取得に失敗したとき、typeプロパティがこの定数に設定されたIOErrorEventが発行されます。
         */
        public static const COMMENT_GET_FAIL: String = "CommentGetFail";

        /**
         * 通常コメントの取得に成功したとき、typeプロパティがこの定数に設定されたEventが発行されます。
         */
        public static const COMMENT_GET_SUCCESS: String = "CommentGetSuccess";

        /**
         *
         */
        public static const OWNER_COMMENT_GET_START: String = "OwnerCommentGetStart";

        /**
         * 投稿者コメントの取得に失敗したとき、typeプロパティがこの定数に設定されたIOErrorEventが発行されます。
         */
        public static const OWNER_COMMENT_GET_FAIL: String = "OwnerCommentGetFail";

        /**
         * 投稿者コメントの取得に成功したとき、typeプロパティがこの定数に設定されたEventが発行されます。
         */
        public static const OWNER_COMMENT_GET_SUCCESS: String = "OwnerCommentGetSuccess";

        /**
         *
         */
        public static const NICOWARI_GET_START: String = "NicowariGetStart";

        /**
         * ニコ割の取得に失敗したとき、typeプロパティがこの定数に設定されたIOErrorEventが発行されます。
         */
        public static const NICOWARI_GET_FAIL: String = "NicowariGetFail";

        /**
         * ニコ割の取得に成功したとき、typeプロパティがこの定数に設定されたEventが発行されます。
         */
        public static const NICOWARI_GET_SUCCESS: String = "NicowariGetSuccess";

        /**
         *
         */
        public static const THUMB_INFO_GET_START: String = "ThumbInfoGetStart";

        /**
         * サムネイル情報の取得に失敗したとき、typeプロパティがこの定数に設定されたIOErrorEventが発行されます。
         */
        public static const THUMB_INFO_GET_FAIL: String = "ThumbInfoGetFail";

        /**
         * サムネイル情報の取得に成功したとき、typeプロパティがこの定数に設定されたEventが発行されます。
         */
        public static const THUMB_INFO_GET_SUCCESS: String = "ThumbInfoGetSuccess";

        /**
         * NNDDServer上で同じ動画IDの動画が発見されました
         */
        public static const REMOTE_NNDD_SERVER_ACCESS_SUCCESS: String = "RemoteNnddServerAccessSuccess";

        /**
         *
         */
        public static const REMOTE_NNDD_SERVER_ACCESS_FAIL: String = "RemoteNnddServerAccessFail";

        /**
         *
         */
        public static const THUMB_IMG_GET_START: String = "ThumbImgGetStart";

        /**
         * サムネイル画像の取得に失敗したとき、typeプロパティがこの定数に設定されたIOErrorEventが発行されます。
         */
        public static const THUMB_IMG_GET_FAIL: String = "ThumbImgGetFail";

        /**
         * サムネイル画像の取得に成功したとき、typeプロパティがこの定数に設定されたEventが発行されます。
         */
        public static const THUMB_IMG_GET_SUCCESS: String = "ThumbImgGetSuccess";

        /**
         *
         */
        public static const VIDEO_GET_START: String = "VideoGetStart";

        /**
         * 動画の取得に失敗したとき、typeプロパティがこの定数に設定されたIOErrorEventが発行されます。
         */
        public static const VIDEO_GET_FAIL: String = "VideoGetFail";

        /**
         * 動画の取得に成功したとき、typeプロパティがこの定数に設定されたEventが発行されます。
         */
        public static const VIDEO_GET_SUCCESS: String = "VideoGetSuccess";

        /**
         * 動画の取得中に、typeプロパティがこの定数に設定されたProgressEventが発行されます。
         */
        public static const VIDEO_DOWNLOAD_PROGRESS: String = "VideoDownloadProgress";

        /**
         * ダウンロード処理が通常に終了したとき、typeプロパティがこの定数に設定されたEventが発行されます。
         */
        public static const DOWNLOAD_PROCESS_COMPLETE: String = "DownloadProcessComplete";

        /**
         * ダウンロード処理が中断された際に、typeプロパティがこの定数に設定されたEventが発行されます。
         */
        public static const DOWNLOAD_PROCESS_CANCELD: String = "DonwloadProcessCancel";

        /**
         * ダウンロード処理が以上終了した際に、typeプロパティがこの定数に設定されたEventが発行されます。
         */
        public static const DOWNLOAD_PROCESS_ERROR: String = "DownloadProccessError";

        public static const CREATE_DMC_SESSION_START: String = "CreateDmcSessionStart";
        public static const CREATE_DMC_SESSION_SUCCESS: String = "CreateDmcSessionSuccess";
        public static const CREATE_DMC_SESSION_FAIL: String = "CreateDmcSessionFail";
        public static const BEAT_DMC_SESSION: String = "BeatDmcSession";
        public static const DMC_SESSION_FAIL: String = "DmcSessionFail";

        public static const CREATE_DMS_SESSION_START: String = "CreateDmsSessionStart";
        public static const CREATE_DMS_SESSION_SUCCESS: String = "CreateDmsSessionSuccess";
        public static const CREATE_DMS_SESSION_FAIL: String = "CreateDmsSessionFail";

        public static const RETRY_COUNT_LIMIT: int = 10;

        /**
         * コンストラクタです。
         *
         */
        public function NNDDDownloader() {
            this._retryCount = 0;
            this._downloadedSize = 0;

            /* For DMC Servers */
            this._dmcInfoAnalyzer = new DmcInfoAnalyzer();
            this._dmcResultAnalyzer = new DmcResultAnalyzer();

            /* For DMS (new delivery system) */
            this._dmsResultAnalyzer = new DmsResultAnalyzer();

            this._nicowariVideoIds = new Array();
            this._nicowariVideoUrls = new Array();
        }

        /**
         * ニコニコ動画に対して、動画のダウンロードをリクエストします。
         *
         * @param user ニコニコ動画のアカウント名（メールアドレス）
         * @param password ニコニコ動画にログインするためのパスワード
         * @param videoId ダウンロードしたい動画ID
         * @param saveVideoName 保存するときの動画の名前。未指定の場合は動画ページのタイトルを使う。
         * @param saveDir 保存先ディレクトリ
         * @param isStart すぐにダウンロードを開始するかどうか。trueの場合は即時実行。
         * @param isAppendComment 古いコメントファイルに今回ダウンロードしたコメントを追記するかどうか
         * @param maxCommentCount 古いコメントファイルにコメントを追加する際、保存するコメントの最大数
         * @param useOldType 旧形式でコメントを取得するかどうかです。これは通常コメントの取得でのみ有効で、過去コメント、投稿者コメントでは無視されます。
         */
        public function requestDownload(user: String,
                                        password: String,
                                        videoId: String,
                                        saveVideoName: String,
                                        saveDir: File,
                                        isStart: Boolean,
                                        isAppendComment: Boolean,
                                        maxCommentCount: Number,
                                        useOldType: Boolean
        ): void {

            trace("start - requestDownload(" + user + ", ****, " + videoId + ", " + saveDir.nativePath + ")");

            this._videoId = videoId;
            this._thumbInfoId = videoId;
            this._saveDir = saveDir;
            this._isAppendComment = isAppendComment;
            this._maxCommentCount = maxCommentCount;
            this._useOldType = useOldType;

            //ストリーミング再生の時のファイル名は「nndd」。それ以外のときは「ファイル名+[動画ID]」
            if (saveVideoName != null && saveVideoName != "" && saveVideoName != "nndd") {
                this._saveVideoName = saveVideoName + " - [" + videoId + "]";
            } else if (saveVideoName == "nndd") {
                this._saveVideoName = "nndd";
            } else {
                this._saveVideoName = "";
            }

            this._login = new Login();
            this._login.addEventListener(Login.LOGIN_SUCCESS, loginSuccess);
            this._login.addEventListener(Login.NO_LOGIN, loginSkip);
            this._login.addEventListener(Login.LOGIN_FAIL, function (event: ErrorEvent): void {
//				(event.target as Login).close();
                LogManager.instance.addLog(LOGIN_FAIL + event.target + ":" + event.text);
//				trace(event + ":" + event.target +  ":" + event.text);
//				dispatchEvent(new IOErrorEvent(LOGIN_FAIL, false, false, event.text));
//				close(true, true, event);

                //強引に取りに行く
                loginSuccess(event);
            });
            this._login.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, function (event: HTTPStatusEvent): void {
                trace(event);
                LogManager.instance.addLog("\t\t" + HTTPStatusEvent.HTTP_RESPONSE_STATUS + ":" + event);
            });

            if (isStart) {
                trace(LOGIN_START + ":" + this._videoId);
                LogManager.instance.addLog(LOGIN_START + ":" + this._videoId);
                dispatchEvent(new Event(LOGIN_START));
                this._login.login(user, password);
            }
        }

        /**
         * ストリーミング再生用。
         *
         * @param user ニコニコ動画のアカウント名（メールアドレス）
         * @param password ニコニコ動画にログインするためのパスワード
         * @param videoId ダウンロードしたい動画ID
         * @param saveDir 保存先ディレクトリ
         * @param isAlwaysEconomy 常にエコノミーモードで再生するかどうか
         *
         */
        public function requestDownloadForStreaming(user: String,
                                                    password: String,
                                                    videoId: String,
                                                    saveDir: File,
                                                    useOldType: Boolean
        ): void {

            this._isCommentOnlyDownload = false;
            this._isVideoNotDownload = true;

            this.requestDownload(
                user,
                password,
                videoId,
                "nndd",
                saveDir,
                true,
                false,
                2000,
                useOldType
            );

        }

        /**
         * 動画以外をダウンロードします。
         *
         * @param user
         * @param pasword
         * @param videoId
         * @param videoName
         * @param saveDir
         * @param isAlwaysEconomy
         * @param isAppendComment
         * @param when
         */
        public function requestDownloadForOtherVideo(user: String,
                                                     password: String,
                                                     videoId: String,
                                                     videoName: String,
                                                     saveDir: File,
                                                     isAppendComment: Boolean,
                                                     when: Date,
                                                     maxCommentCount: Number,
                                                     useOldType: Boolean
        ): void {
            this._isCommentOnlyDownload = false;
            this._isVideoNotDownload = true;
            this._when = when;

            this.requestDownload(
                user,
                password,
                videoId,
                videoName,
                saveDir,
                true,
                isAppendComment,
                maxCommentCount,
                useOldType
            );
        }

        /**
         * コメントのみをダウンロードします。
         *
         * @param user
         * @param password
         * @param videoId
         * @param saveDir
         * @param isAlwaysEconomy
         * @param isAppendComment
         * @param when
         */
        public function requestDownloadForCommentOnly(user: String,
                                                      password: String,
                                                      videoId: String,
                                                      videoName: String,
                                                      saveDir: File,
                                                      isAppendComment: Boolean,
                                                      when: Date,
                                                      maxCommentCount: Number,
                                                      useOldType: Boolean
        ): void {

            this._isCommentOnlyDownload = true;
            this._isVideoNotDownload = true;
            this._when = when;

            this.requestDownload(
                user,
                password,
                videoId,
                videoName,
                saveDir,
                true,
                isAppendComment,
                maxCommentCount,
                useOldType
            );

        }

        /**
         * 動画ページへのアクセスのみを行います。
         *
         * @param user
         * @param password
         * @param videoId
         * @param videoName
         *
         */
        public function requestForWatchOnly(
            user: String,
            password: String,
            videoId: String,
            videoName: String,
            useOldType: Boolean
        ): void {

            this._isCommentOnlyDownload = true;
            this._isVideoNotDownload = true;
            this._watchVideoOnly = true;

            this.requestDownload(
                user,
                password,
                videoId,
                videoName,
                File.documentsDirectory,
                true,
                false,
                2000,
                useOldType
            );

        }


        /**
         *
         * @param user
         * @param password
         *
         */
        public function requestStart(user: String, password: String): void {

            trace(LOGIN_START + ":" + this._videoId);
            LogManager.instance.addLog(LOGIN_START + ":" + this._videoId);
            dispatchEvent(new Event(LOGIN_START));
            this._login.login(user, password);

        }

        /**
         *
         * @param event
         *
         */
        private function loginSuccess(event: Event): void {

            //ログイン成功通知
            trace(LOGIN_SUCCESS + ":" + event);
            LogManager.instance.addLog("\t" + LOGIN_SUCCESS + ":" + this._videoId + ":" + this._nicoVideoName);
            dispatchEvent(new Event(LOGIN_SUCCESS));

            // closeが呼ばれていないか？
            if (this._login == null) {
                return;
            }

            // 動画を見に行く
            watch(this._videoId, false);

        }

        /**
         *
         * @param event
         *
         */
        private function loginSkip(event: Event): void {

            //ログイン成功通知
            trace(LOGIN_SKIP + ":" + event);
            LogManager.instance.addLog("\t" + LOGIN_SKIP + ":" + this._videoId + ":" + this._nicoVideoName);
            dispatchEvent(new Event(LOGIN_SKIP));

            // closeが呼ばれていないか？
            if (this._login === null) {
                return;
            }

            // 動画を見に行く
            watch(this._videoId, false);

        }

        /**
         *
         * @param videoId
         * @param watchHarmful deprecated
         * @return
         *
         */
        private function watch(videoId: String, watchHarmful: Boolean = false): void {
            this._watchVideo = new WatchVideoPage();
            //リスナ追加
            this._watchVideo.addEventListener(WatchVideoPage.WATCH_SUCCESS, watchSuccess);
            this._watchVideo.addEventListener(WatchVideoPage.WATCH_FAIL, function (event: ErrorEvent): void {
                (event.target as WatchVideoPage).close();
                LogManager.instance.addLog(WATCH_FAIL + ":" + _videoId + ":" + event + ":" + event.target + ":" +
                                           event.text);
                trace(WATCH_FAIL + ":" + _videoId + ":" + event + ":" + event.target + ":" + event.text);
                dispatchEvent(new IOErrorEvent(WATCH_FAIL, false, false, event.text));
                close(true, true, event);
            });
            this._watchVideo.addEventListener(
                HTTPStatusEvent.HTTP_RESPONSE_STATUS,
                function (event: HTTPStatusEvent): void {
                    trace(event);
                    var threadId: String = PathMaker.getVideoID(event.responseURL);
                    // リダイレクトされた。
                    if (threadId != _videoId) {
                        LogManager.instance.addLog("リダイレクト: " + _videoId + " -> " + threadId);
                        _isRedirected = true;
                        _threadId = threadId;
                    }
                    LogManager.instance.addLog("\t\t" + HTTPStatusEvent.HTTP_RESPONSE_STATUS + ":" + event);
                }
            );

            //this._videoIdの動画のページを見に行く
            var videoId: String = this._videoId;

            // 動画IDとしてスレッドIDがわたってきたときは、threadIDとしても使用する
            var regexp: RegExp = new RegExp("\\d+");
            if (videoId.match(regexp).length > 0) {
                this._threadId = this._videoId;
            }

            trace(WATCH_START + ":" + this._videoId);
            LogManager.instance.addLog(WATCH_START + ":" + this._videoId);
            dispatchEvent(new Event(WATCH_START));

            this._watchVideo.watchVideo(videoId, false);
        }


        /**
         * 動画ページへのアクセスが完了したら呼ばれます。
         * コメントのダウンロードを開始します。
         *
         * @param event
         *
         */
        private function watchSuccess(event: Event): void {

            // closeが呼ばれていないか？
            if (this._watchVideo == null) {
                return;
            }

            // 有害判定があるかどうか
            if (this._watchVideo.checkHarmful()) {
                LogManager.instance.addLog("この動画は有害報告されています:" + this._videoId);
            }

            this._videoId = this._watchVideo.getVideoId();
            if (this._videoId != this._thumbInfoId) {
                this._thumbInfoId = this._videoId;
                LogManager.instance.addLog("サムネイル情報用ID:" + this._videoId);
            }

            this._nicoVideoName = (this._watchVideo.isHTML5 ? this._watchVideo.jsonData.video.title :
                                   this._watchVideo.jsonData.flashvars.videoTitle) + " - [" + this._videoId + "]";
            if (this._saveVideoName == null || this._saveVideoName == "") {
                this._saveVideoName = FileIO.getSafeFileName(this._nicoVideoName);
            }

            //動画ページアクセス完了通知(動画ページへのアクセスは閉じない)
            trace(WATCH_SUCCESS + ":" + event);
            LogManager.instance.addLog("\t" + WATCH_SUCCESS + ":" + this._videoId + ":" + this._nicoVideoName);
            dispatchEvent(new Event(WATCH_SUCCESS));

            //動画ページの閲覧のみ。
            if (this._watchVideoOnly) {
                close(false, false);
                return;
            }

            getThumbInfo(this._videoId);

        }

        /**
         * サムネイル情報を取得します。
         *
         * @param videoId
         *
         */
        private function getThumbInfo(videoId: String): void {
            // closeが呼ばれていないか？
            if (this._login == null) {
                return;
            }

            this._thumbInfoLoader = new ThumbInfoLoader();
            this._thumbInfoLoader.addEventListener(IOErrorEvent.IO_ERROR, function (event: IOErrorEvent): void {
                (event.currentTarget as URLLoader).close();
                trace(THUMB_INFO_GET_FAIL + ":" + event + ":" + event.target + ":" + event.text);
                LogManager.instance.addLog(THUMB_INFO_GET_FAIL + ":" + videoId + "(" + _videoId + "):" + event + ":" +
                                           event.target + ":" + event.text);
                dispatchEvent(new IOErrorEvent(THUMB_INFO_GET_FAIL, false, false, event.text));
                close(true, true, event);
            });
            this._thumbInfoLoader.addEventListener(
                HTTPStatusEvent.HTTP_RESPONSE_STATUS,
                function (event: HTTPStatusEvent): void {
                    trace(event);
                    LogManager.instance.addLog("\t\t" + HTTPStatusEvent.HTTP_RESPONSE_STATUS + ":" + event);
                }
            );
            this._thumbInfoLoader.addEventListener(Event.COMPLETE, thumbInfoGetSuccess);

            trace(THUMB_INFO_GET_START + ":" + this._videoId);
            LogManager.instance.addLog(THUMB_INFO_GET_START + ":" + this._videoId);
            dispatchEvent(new Event(THUMB_INFO_GET_START));

            this._thumbInfoLoader.getThumbInfo(videoId);

        }

        /**
         * サムネイル情報の取得が完了したら呼ばれます。<br>
         * サムネルの保存が完了したら、サムネイル画像の取得を行います。
         *
         * @param event
         *
         */
        private function thumbInfoGetSuccess(event: Event): void {

            // closeが呼ばれていないか？
            if (this._thumbInfoLoader == null) {
                return;
            }

            try {

                var xml: XML = new XML((event.currentTarget as ThumbInfoLoader).data);

                var analyzer: ThumbInfoAnalyzer = new ThumbInfoAnalyzer(xml);

                if (analyzer.status == ThumbInfoAnalyzer.STATUS_OK) {
                    this._videoId = analyzer.videoId;
                } else {

                    // サムネイル情報を取得したが動画は削除済み？とりあえず次に進む。

                    LogManager.instance.addLog(THUMB_INFO_GET_FAIL + ", ThumbInfoAnalyzeFailed:" + _videoId +
                                               ", title=" + analyzer.title + ", errorCode=" + analyzer.errorCode);
                    trace(THUMB_INFO_GET_FAIL + ", ThumbInfoAnalyzeFailed:" + _videoId + ", title=" + analyzer.title);
                    trace(this._saveVideoName);
                    trace(xml);
                }

            } catch (error: Error) {
                trace(error.getStackTrace());

                LogManager.instance.addLog(THUMB_INFO_GET_FAIL + ", ThumbInfoAnalyzeFailed:" + _videoId + ", title=" +
                                           analyzer.title + ", error=" + error);
                trace(THUMB_INFO_GET_FAIL + ", ThumbInfoAnalyzeFailed:" + _videoId + ", title=" + analyzer.title);
                dispatchEvent(new IOErrorEvent(
                    THUMB_INFO_GET_FAIL,
                    false,
                    false,
                    "ThumbInfoAnalyzeFailed(" + error + ")"
                ));
                close(
                    true,
                    true,
                    new IOErrorEvent(THUMB_INFO_GET_FAIL, false, false, "ThumbInfoAnalyzeFailed(" + error + ")")
                );

                trace(this._saveVideoName);
                trace(xml);

                return;
            }

            if (this._isCommentOnlyDownload) {
                //コメントのみ取得モード
                getFlvAccess();
            } else {
                //コメント以外も取得するモード
                var fileIO: FileIO = new FileIO();
                fileIO.addFileStreamEventListener(IOErrorEvent.IO_ERROR, function (event: IOErrorEvent): void {
                    trace(THUMB_INFO_GET_FAIL + ":" + event + ":" + event.target + ":" + event.text);
                    LogManager.instance.addLog(THUMB_INFO_GET_FAIL + ":" + _saveVideoName + "[ThumbInfo].xml" + ":" +
                                               event + ":" + event.target + ":" + event.text);
                    dispatchEvent(new IOErrorEvent(THUMB_INFO_GET_FAIL, false, false, event.text));
                    close(true, true, event);
                });
                var path: String = fileIO.saveComment(
                    new XML((event.currentTarget as ThumbInfoLoader).data),
                    this._saveVideoName + "[ThumbInfo].xml",
                    this._saveDir.url,
                    false,
                    0
                ).nativePath;

                //サムネイル情報取得完了通知
                this._thumbInfoLoader.close();
                trace(THUMB_INFO_GET_SUCCESS + ":" + event + "\n" + path);
                LogManager.instance.addLog("\t" + THUMB_INFO_GET_SUCCESS + ":" + path);
                dispatchEvent(new Event(THUMB_INFO_GET_SUCCESS));

                var thumbInfoAnalyzer: ThumbInfoAnalyzer = new ThumbInfoAnalyzer(new XML((event.currentTarget as
                                                                                          ThumbInfoLoader).data));

                var thumbUrl: String = thumbInfoAnalyzer.thumbnailUrl;

                getThumbImg(thumbUrl);

            }

        }

        private function getThumbImg(thumbUrl: String): void {
            this._thumbImgLoader = new ThumbImgLoader();
            this._thumbImgLoader.addEventListener(Event.COMPLETE, thumbImgGetSuccess);
            this._thumbImgLoader.addEventListener(IOErrorEvent.IO_ERROR, function (event: IOErrorEvent): void {
                //				(event.target as URLLoader).close();
                trace(THUMB_IMG_GET_FAIL + ":" + event + ":" + event.target + ":" + event.text);
                LogManager.instance.addLog(THUMB_IMG_GET_FAIL + ":" + _videoId + ":" + event + ":" + event.target +
                                           ":" + event.text);
                dispatchEvent(new IOErrorEvent(THUMB_IMG_GET_FAIL, false, false, event.text));
                getFlvAccess();
            });
            this._thumbImgLoader.addEventListener(
                HTTPStatusEvent.HTTP_RESPONSE_STATUS,
                function (event: HTTPStatusEvent): void {
                    trace(event);
                    LogManager.instance.addLog("\t\t" + HTTPStatusEvent.HTTP_RESPONSE_STATUS + ":" + event);
                }
            );
            try {

                trace(THUMB_IMG_GET_START + ":" + this._videoId);
                LogManager.instance.addLog(THUMB_IMG_GET_START + ":" + this._videoId);
                dispatchEvent(new Event(THUMB_IMG_GET_START));

                // サムネ情報からサムネ画像を取得
                if (thumbUrl != null && thumbUrl != "") {
                    this._thumbImgLoader.getThumbImgByUrl(thumbUrl);
                } else {

                    // サムネ情報から取得できなければ自分で作る
                    thumbUrl = PathMaker.getThumbImgUrl(this._thumbInfoId);
                    this._thumbImgLoader.getThumbImgByUrl(thumbUrl);

                }
            } catch (error: Error) {
                trace(error + ":" + error.getStackTrace());
                LogManager.instance.addLog(THUMB_INFO_GET_FAIL + ":" + _videoId + ":" + error.getStackTrace());
                dispatchEvent(new IOErrorEvent(THUMB_IMG_GET_FAIL, false, false, error.getStackTrace()));
                close(true, true, new IOErrorEvent(THUMB_IMG_GET_FAIL, false, false, error.getStackTrace()));
            }

        }

        /**
         * サムネイル画像のダウンロードが完了したら呼ばれます。<br>
         * サムネイル画像の保存が完了したら市場情報のダウンロードを行います。
         *
         * @param event
         *
         */
        private function thumbImgGetSuccess(event: Event): void {

            var fileIO: FileIO = new FileIO();
            fileIO.addFileStreamEventListener(IOErrorEvent.IO_ERROR, function (event: IOErrorEvent): void {
                trace(THUMB_IMG_GET_FAIL + ":" + event + ":" + event.target + ":" + event.text);
                LogManager.instance.addLog(THUMB_IMG_GET_FAIL + ":" + _videoId + ":" + event + ":" + event.target +
                                           ":" + event.text);
                dispatchEvent(new IOErrorEvent(THUMB_IMG_GET_FAIL, false, false, event.text));
                close(true, true, event);
            });
            this._thumbPath = fileIO.saveByteArray(this._saveVideoName + "[ThumbImg].jpeg",
                                                   this._saveDir.url,
                                                   (event.target as URLLoader).data
            ).url;

            //サムネイル画像取得完了通知
            (event.target as URLLoader).close();
            LogManager.instance.addLog("\t" + THUMB_IMG_GET_SUCCESS + ":" + (new File(this._thumbPath)).nativePath);
            trace(THUMB_IMG_GET_SUCCESS + ":" + event + "\n" + (new File(this._thumbPath)).nativePath);
            dispatchEvent(new Event(THUMB_IMG_GET_SUCCESS));

            getFlvAccess();
        }

        /**
         *
         *
         */
        private function getFlvAccess(): void {
            if (_watchVideo != null && _watchVideo.isDms) {
                // DMS (新配信): getFlv API は廃止。空の analyzer でコメント取得へ進む。
                _flvResultAnalyzer = new GetFlvResultAnalyzer();
                getWaybackkeyAccess();
                return;
            }

            this._getflvAccess = new ApiGetFlvAccess();
            //APIアクセス開始
            this._getflvAccess.addEventListener(IOErrorEvent.IO_ERROR, function (event: ErrorEvent): void {
                (event.target as URLLoader).close();
                LogManager.instance.addLog(GETFLV_API_ACCESS_FAIL + ":" + _videoId + ":" + event + ":" + event.target +
                                           ":" + event.text);
                trace(GETFLV_API_ACCESS_FAIL + ":" + event + ":" + event.target + ":" + event.text);
                dispatchEvent(new IOErrorEvent(GETFLV_API_ACCESS_FAIL, false, false, event.text));
                close(true, true, event);
            });
            this._getflvAccess.addEventListener(
                HTTPStatusEvent.HTTP_RESPONSE_STATUS,
                function (event: HTTPStatusEvent): void {
                    trace(event);
                    LogManager.instance.addLog("\t\t" + HTTPStatusEvent.HTTP_RESPONSE_STATUS + ":" + event);
                }
            );
            this._getflvAccess.addEventListener(Event.COMPLETE, getFlvAccessSuccess);

            trace(GETFLV_API_ACCESS_START + ":" + this._threadId + "(" + this._videoId + ")");
            LogManager.instance.addLog(GETFLV_API_ACCESS_START + ":" + this._threadId + "(" + this._videoId + ")");
            dispatchEvent(new Event(GETFLV_API_ACCESS_START));

            this._getflvAccess.getAPIResult(this._threadId);

        }

        /**
         * getflvへのアクセスに成功した場合に呼ばれます。
         *
         * @param event
         *
         */
        private function getFlvAccessSuccess(event: Event): void {

            //APIアクセス成功(アクセスは閉じない)
            this._flvResultAnalyzer = new GetFlvResultAnalyzer();

            if (this._watchVideo.isFlash) {
                this._flvResultAnalyzer.analyze(this._watchVideo.jsonData.flashvars.flvInfo || "");
            } else {
                this._flvResultAnalyzer.analyze(this._getflvAccess.data);
            }

            this._threadId = this._flvResultAnalyzer.threadId;
            this._fmsToken = this._flvResultAnalyzer.fmsToken;

            if (this._flvResultAnalyzer.url == null) {
                var watchDataAnalyzer = new WatchDataAnalyzer();
                var watchWrapper = new WatchDataAnalyzerGetFlvAdapter();

                watchDataAnalyzer.analyze(this._watchVideo);
                watchWrapper.wrap(watchDataAnalyzer);
                this._flvResultAnalyzer = watchWrapper;
            }

            trace(GETFLV_API_ACCESS_SUCCESS + ":" + event);
            LogManager.instance.addLog(
                "\t" + GETFLV_API_ACCESS_SUCCESS + ":" + this._videoId + ":" + this._nicoVideoName
            );
            dispatchEvent(new Event(GETFLV_API_ACCESS_SUCCESS));

            getWaybackkeyAccess();
        }

        /**
         * waybackkey取得APIにアクセスする.
         */
        private function getWaybackkeyAccess(): void {
            if (this._when == null) {
                //過去ログは取得しない
                getNormalComment();
            } else {
                //過去ログモード
                this._getWaybackkeyAccess = new ApiGetWaybackkeyAccess();

                this._getWaybackkeyAccess.addEventListener(Event.COMPLETE, getWaybackkeySuccess);
                this._getWaybackkeyAccess.addEventListener(IOErrorEvent.IO_ERROR, function (event: IOErrorEvent): void {
                    (event.target as ApiGetWaybackkeyAccess).close();
                    LogManager.instance.addLog(GETWAYBACKKEY_API_ACCESS_FAIL + ":" + _videoId + ":" + event + ":" +
                                               event.target + ":" + event.text);
                    trace(GETWAYBACKKEY_API_ACCESS_FAIL + ":" + event + ":" + event.target + ":" + event.text);
                    dispatchEvent(new IOErrorEvent(GETWAYBACKKEY_API_ACCESS_FAIL, false, false, event.text));
                    close(true, true, event);
                });
                this._getWaybackkeyAccess.addEventListener(
                    HTTPStatusEvent.HTTP_RESPONSE_STATUS,
                    function (event: HTTPStatusEvent): void {
                        trace(event);
                        LogManager.instance.addLog("\t\t" + HTTPStatusEvent.HTTP_RESPONSE_STATUS + ":" + event);
                    }
                );

                trace(GETWAYBACKKEY_API_ACCESS_START + ":" + this._videoId);
                LogManager.instance.addLog(GETWAYBACKKEY_API_ACCESS_START + ":" + this._videoId);
                dispatchEvent(new Event(GETWAYBACKKEY_API_ACCESS_START));

                this._getWaybackkeyAccess.getAPIResult(this._threadId);
            }
        }

        /**
         * waybackkey APIへのアクセスが完了したら呼ばれるイベントハンドラです。
         * @param event
         *
         */
        private function getWaybackkeySuccess(event: Event): void {

            var analyzer: GetWaybackkeyResultAnalyzer = new GetWaybackkeyResultAnalyzer();
            analyzer.analyzer(this._getWaybackkeyAccess.data);
            trace(this._getWaybackkeyAccess.data);

            if (analyzer.waybackkey != null && analyzer.waybackkey.length > 0) {
                // 取得続行
                trace(GETWAYBACKKEY_API_ACCESS_SUCCESS + ":" + event);
                dispatchEvent(new Event(GETWAYBACKKEY_API_ACCESS_SUCCESS, false, false));
                this._waybackkey = analyzer.waybackkey;
                getNormalComment();
            } else {
                // waybackkey取得失敗。中断。
                (event.target as ApiGetWaybackkeyAccess).close();
                LogManager.instance.addLog(GETWAYBACKKEY_API_ACCESS_FAIL + ":" + _videoId + ":" + event + ":" +
                                           event.target);
                trace(GETWAYBACKKEY_API_ACCESS_FAIL + ":" + event + ":" + event.target);
                dispatchEvent(new IOErrorEvent(GETWAYBACKKEY_API_ACCESS_FAIL, false, false));
                close(true, true, new IOErrorEvent(GETWAYBACKKEY_API_ACCESS_FAIL, false, false));
            }
        }

        /**
         * 通常コメントの取得を開始します。
         *
         */
        private function getNormalComment(): void {

            // closeが呼ばれていないか？
            if (this._login == null) {
                return;
            }

            this._commentLoader = new CommentLoader();
            //リスナ追加
            this._commentLoader.addEventListener(CommentLoader.COMMENT_GET_SUCCESS, commentGetSuccess);
            this._commentLoader.addEventListener(CommentLoader.COMMENT_GET_FAIL, function (event: ErrorEvent): void {
                (event.target as CommentLoader).close();
                LogManager.instance.addLog(COMMENT_GET_FAIL + ":" + _videoId + ":" + event + ":" + event.target + ":" +
                                           event.text);
                trace(COMMENT_GET_FAIL + ":" + event + ":" + event.target + ":" + event.text);
                dispatchEvent(new IOErrorEvent(COMMENT_GET_FAIL, false, false, event.text));
                close(true, true, event);
            });
            this._commentLoader.addEventListener(
                HTTPStatusEvent.HTTP_RESPONSE_STATUS,
                function (event: HTTPStatusEvent): void {
                    trace(event);
                    LogManager.instance.addLog("\t\t" + HTTPStatusEvent.HTTP_RESPONSE_STATUS + ":" + event);
                }
            );

            trace(COMMENT_GET_START + ":" + this._videoId);
            LogManager.instance.addLog(COMMENT_GET_START + ":" + this._videoId);
            dispatchEvent(new Event(COMMENT_GET_START));

            //nvcomment API でコメントを取得（新仕様）
            var nvParams: Object = this._watchVideo.nvCommentParams;
            this._commentLoader.getNvComment(
                this._watchVideo.nvCommentThreadKey,
                nvParams ? nvParams.targets : [],
                nvParams ? nvParams.language : "ja-jp",
                this._watchVideo.userKey,
                this._watchVideo.nvCommentServerUrl
            );
        }


//		/**
//		 * 動画ページのタイトルから動画のタイトルを取得します。
//		 * @param html
//		 * 
//		 */
//		private function getVideoName(html:String):String{
//			var pattern:RegExp = new RegExp("<title>(.*)</title>","ig"); 
//			
//			var array:Array = pattern.exec(html);
//			
//			var videoName:String = "不明";
//			
//			if(array != null && array.length > 1){
//				videoName = array[1];
//				var index:int = videoName.lastIndexOf("‐ ニコニコ動画(");
//				if(index != -1){
//					videoName = videoName.substr(0, index);
//				}
//				videoName = StringUtil.trim(videoName);
//			}
//			
//			var videoId:String = PathMaker.getVideoID(this._videoId);
//			
//			videoName = HtmlUtil.convertSpecialCharacterNotIncludedString(videoName) + " - [" + videoId + "]";
//			videoName = FileIO.getSafeFileName(videoName);
//			
//			return videoName;
//			
//		}

        /**
         * コメントのダウンロードが終わったら呼ばれます。
         * コメントの保存後、投稿者コメントのダウンロードを開始します。
         *
         * @param event
         *
         */
        private function commentGetSuccess(event: Event): void {
            ownerCommentGetStart(event.currentTarget as CommentLoader);
        }

        /**
         *
         * @param event
         *
         */
        private function ownerCommentGetStart(loader: CommentLoader): void {

            // closeが呼ばれていないか？
            if (this._login == null) {
                return;
            }

            // var fileIO: FileIO = new FileIO();
            // fileIO.addFileStreamEventListener(IOErrorEvent.IO_ERROR, function (event: IOErrorEvent): void {
            //     trace(COMMENT_GET_FAIL + ":" + event + ":" + event.target + ":" + event.text);
            //     LogManager.instance.addLog(COMMENT_GET_FAIL + ":" + _saveVideoName + ".xml" + ":" + event + ":" +
            //                                event.target + ":" + event.text);
            //     dispatchEvent(new IOErrorEvent(COMMENT_GET_FAIL, false, false, event.text));
            //     close(true, true, event);
            // });
            // var path: String = fileIO.saveComment(
            //     loader.xml,
            //     this._saveVideoName + ".xml",
            //     this._saveDir.url,
            //     this._isAppendComment,
            //     this._maxCommentCount
            // ).nativePath;
            var path: String = "";

            //通常コメントの取得完了を通知
            loader.close();
            this._commentLoader.close();
            LogManager.instance.addLog("\t" + COMMENT_GET_SUCCESS + ":" + path);
            trace(COMMENT_GET_SUCCESS + ":" + loader + "\n" + path);
            dispatchEvent(new Event(COMMENT_GET_SUCCESS));

            trace(OWNER_COMMENT_GET_START + ":" + this._videoId);
            LogManager.instance.addLog(OWNER_COMMENT_GET_START + ":" + this._videoId);
            dispatchEvent(new Event(OWNER_COMMENT_GET_START));

            // nvcomment API では投稿者コメント(fork=owner)は通常コメント取得時に含まれる。
            // 再取得は不要。_commentLoader の XML・threadId をそのまま利用して即時完了。
            this._ownerCommentLoader = this._commentLoader;
            this._threadId = this._commentLoader.threadId;

            // コメントXMLを保存（ダウンロード/ストリーミング共通）
            if (loader.xml != null) {
                try {
                    var commentFile: File = _saveDir.resolvePath(_saveVideoName + ".xml");
                    var commentStream: FileStream = new FileStream();
                    commentStream.open(commentFile, FileMode.WRITE);
                    commentStream.writeUTFBytes(loader.xml.toXMLString());
                    commentStream.close();
                    LogManager.instance.addLog("コメントXML保存:" + commentFile.nativePath);
                } catch (commentSaveError: Error) {
                    LogManager.instance.addLog("コメントXML保存失敗:" + commentSaveError.getStackTrace());
                }
            }

            var ownerPath: String = "";
            LogManager.instance.addLog("\t" + OWNER_COMMENT_GET_SUCCESS + ":" + ownerPath);
            trace(OWNER_COMMENT_GET_SUCCESS + ":(nvComment included in main fetch)");
            dispatchEvent(new Event(OWNER_COMMENT_GET_SUCCESS));

            if (this._isCommentOnlyDownload) {
                trace(DOWNLOAD_PROCESS_COMPLETE + ":(commentOnly)");
                dispatchEvent(new Event(DOWNLOAD_PROCESS_COMPLETE));
                close(false, false);
            } else {
                this._nicowariVideoIds = this.searchAtCMInstruction(this._commentLoader.xml);
                if (this._nicowariVideoIds.length == 0) {
                    switcher();
                } else {
                    this._getbgmAccess = new ApiGetBgmAccess();
                    this._getbgmAccess.addEventListener(ApiGetBgmAccess.SUCCESS, getNicowariUrlsSuccess);
                    this._getbgmAccess.addEventListener(ApiGetBgmAccess.FAIL, function (event: IOErrorEvent): void {
                        (event.currentTarget as ApiGetBgmAccess).close();
                        trace(NICOWARI_GET_FAIL + ":" + event + ":" + event.target + ":" + event.text);
                        LogManager.instance.addLog(NICOWARI_GET_FAIL + ":" + _videoId + ":" + event + ":" +
                                                   event.target + ":" + event.text);
                        dispatchEvent(new IOErrorEvent(NICOWARI_GET_FAIL, false, false, event.text));
                        close(true, true, event);
                    });
                    this._getbgmAccess.getAPIResult(this._threadId);
                }
            }

        }


        /**
         * 投稿者コメントのダウンロードが終わったら呼ばれます。
         * 投稿者コメントの保存後、ユーザーニコ割のダウンロードを開始します。
         *
         * @param event
         *
         */
        private function ownerCommentGetSuccess(event: Event): void {

            // closeが呼ばれていないか？
            if (this._ownerCommentLoader == null) {
                return;
            }

            // var fileIO: FileIO = new FileIO();
            // fileIO.addFileStreamEventListener(IOErrorEvent.IO_ERROR, function (event: IOErrorEvent): void {
            //     trace(OWNER_COMMENT_GET_FAIL + ":" + event + ":" + event.target + ":" + event.text);
            //     LogManager.instance.addLog(OWNER_COMMENT_GET_FAIL + ":" + _saveVideoName + "[Owner].xml" + ":" + event +
            //                                ":" + event.target + ":" + event.text);
            //     dispatchEvent(new IOErrorEvent(OWNER_COMMENT_GET_FAIL, false, false, event.text));
            //     close(true, true, event);
            // });

            var ownerComments: XML = (event.currentTarget as CommentLoader).xml;

            // var ngups: XML = new XML("<ngups/>");
            // //投稿者によってフィルタが設定されていればそれを投稿者コメントXMLファイルに追記
            // for each(var ngup: NgUp in this._ownerCommentLoader.ngWords) {
            //     var xml: XML = new XML("<ngup/>");
            //     xml.@ngword = encodeURIComponent(ngup.ngWord);
            //     xml.@changeValue = encodeURIComponent(ngup.changeValue);
            //     ngups.appendChild(xml);
            // }
            // ownerComments.appendChild(ngups);

            // var path: String = fileIO.saveComment(
            //     ownerComments,
            //     this._saveVideoName + "[Owner].xml",
            //     this._saveDir.url,
            //     this._isAppendComment,
            //     this._maxCommentCount
            // ).nativePath;
            var path: String = "";

            this._threadId = this._ownerCommentLoader.threadId;

            //投稿者コメントの取得完了を通知
            (event.currentTarget as CommentLoader).close();
            this._ownerCommentLoader.close();
            LogManager.instance.addLog("\t" + OWNER_COMMENT_GET_SUCCESS + ":" + path);
            trace(OWNER_COMMENT_GET_SUCCESS + ":" + event + "\n" + path);
            dispatchEvent(new Event(OWNER_COMMENT_GET_SUCCESS));

            if (this._isCommentOnlyDownload) {
                //コメントのみ取得。全行程終了
                trace(DOWNLOAD_PROCESS_COMPLETE + ":" + event);
                dispatchEvent(new Event(DOWNLOAD_PROCESS_COMPLETE));

                close(false, false);
            } else {

                //投稿者コメントを解析して@cm命令を探す
                this._nicowariVideoIds = this.searchAtCMInstruction(ownerComments);

                if (this._nicowariVideoIds.length == 0) {
                    //投コメにニコ割は指定されていない。getbgmを確認せずに市場情報を取得しにいく
//					getThumbInfo(this._thumbInfoId);
                    switcher();
                } else {
                    this._getbgmAccess = new ApiGetBgmAccess();
                    //投コメにニコ割が指定されている。getbgmを確認してニコ割をダウンロード
                    this._getbgmAccess.addEventListener(ApiGetBgmAccess.SUCCESS, getNicowariUrlsSuccess);
                    this._getbgmAccess.addEventListener(ApiGetBgmAccess.FAIL, function (event: IOErrorEvent): void {
                        (event.currentTarget as ApiGetBgmAccess).close();
                        trace(NICOWARI_GET_FAIL + ":" + event + ":" + event.target + ":" + event.text);
                        LogManager.instance.addLog(NICOWARI_GET_FAIL + ":" + _videoId + ":" + event + ":" +
                                                   event.target + ":" + event.text);
                        dispatchEvent(new IOErrorEvent(NICOWARI_GET_FAIL, false, false, event.text));
                        close(true, true, event);
                    });

                    this._getbgmAccess.getAPIResult(this._threadId);
                }
            }
        }

        /**
         * 投稿者コメントから@CM命令で指定されたユーザーニコ割の動画IDを探します。
         *
         * @param ownerComment 投稿者コメント
         * @return 動画IDの配列
         *
         */
        private function searchAtCMInstruction(ownerComment: XML): Array {
            // TODO: 強制
            return new Array();

            var xmlList: XMLList = ownerComment.chat;
            var nicowariVideoIDs: Array = new Array();

            var command: Command = new Command();
            for each(var com: String in xmlList) {
                var nicowariID: String = command.getNicowariVideoID(com)[0];
                if (nicowariID != null && nicowariID != "") {
                    nicowariVideoIDs.push(nicowariID);
                }
            }

            return nicowariVideoIDs;
        }

        /**
         * 投稿者コメントを解析して、ユーザーニコ割が存在するかどうか調べます。
         * 存在する場合、ニコ割のIDを配列に格納して返します。存在しない場合はカラの配列を返します。
         *
         * @param ownerComment 投稿者コメントXML
         * @return ニコ割の動画IDを格納する配列
         *
         */
        private function getNicowariUrlsSuccess(event: Event): void {

            var nicowariVideoUrlsByGetBgm: Array = this._getbgmAccess.getNicowariUrl();
            var nicowariVideoIdByGetBgm: Array = this._getbgmAccess.getNicowariVideoIds();

            //取得したURLから実際に@CM命令で再生を指示されている物を抽出
            for each(var id: String in this._nicowariVideoIds) {
                for (var i: int = 0; i < nicowariVideoIdByGetBgm.length; i++) {
                    if (id == nicowariVideoIdByGetBgm[i]) {
                        //実際に@CM命令で指定されているニコ割。

                        var exists: Boolean = false;
                        for each(var url: String in this._nicowariVideoUrls) {
                            if (url == nicowariVideoUrlsByGetBgm[i]) {
                                exists = true;
                                break;
                            }
                        }

                        //既に追加済みの場合はスキップ
                        if (!exists) {
                            this._nicowariVideoUrls.push(nicowariVideoUrlsByGetBgm[i]);
                        }
                        break;
                    }
                }
            }

            trace("getbgm:" + this._nicowariVideoIds + ":" + this._nicowariVideoUrls);
            this._getbgmAccess.close();

            if (this._isCommentOnlyDownload) {

                //コメントのみのダウンロードはココで終了
                dispatchEvent(new Event(NNDDDownloader.DOWNLOAD_PROCESS_COMPLETE));

            } else if (this._nicowariVideoUrls == null || this._nicowariVideoUrls.length <= 0) {
                //ニコ割無し
//				getThumbInfo(this._thumbInfoId);
                switcher();

            } else {

                {
                    // 重複するnicowariVideoIdを取り除く
                    var tempVideoIds: Array = new Array();
                    for each(var nicowariVideoId: String in this._nicowariVideoIds) {

                        var exists: Boolean = false;
                        for each(var tempId: String in tempVideoIds) {
                            if (nicowariVideoId == tempId) {
                                exists = true;
                                break;
                            }
                        }

                        if (!exists) {
                            tempVideoIds.push(nicowariVideoId);
                        }
                    }
                    this._nicowariVideoIds = tempVideoIds;
                }

                trace("getbgm:" + this._nicowariVideoIds);
                LogManager.instance.addLog("\tgetbgm:" + this._nicowariVideoIds);

                //ニコ割あり
                getNicowari();
            }
        }

        /**
         * ニコ割を取得します。
         */
        private function getNicowari(): void {

            this._nicowariVideoUrl = this._nicowariVideoUrls.shift();
            this._nicowariVideoId = this._nicowariVideoIds.shift();

            this._nicowariLoader = new VideoLoader();
            this._nicowariLoader.addVideoLoaderListener(IOErrorEvent.IO_ERROR, function (event: IOErrorEvent): void {
                (event.target as URLLoader).close();
                trace(NICOWARI_GET_FAIL + ":" + _nicowariVideoId + ":" + event + ":" + event.target + ":" + event.text);
                LogManager.instance.addLog(NICOWARI_GET_FAIL + ":" + _videoId + ":" + _nicowariVideoId + ":" + event +
                                           ":" + event.target + ":" + event.text);
                dispatchEvent(new IOErrorEvent(NICOWARI_GET_FAIL, false, false, event.text));
//				close(true, true, event);

                // ニコ割が取れていなくても次へ
                if (_nicowariVideoIds.length <= 0 || _nicowariVideoUrls.length <= 0) {
                    //サムネイル情報取得
//					getThumbInfo(_thumbInfoId);
                    switcher();
                } else {
                    //次のニコ割を取りにいく
                    getNicowari();
                }
            });
            this._nicowariLoader.addEventListener(
                HTTPStatusEvent.HTTP_RESPONSE_STATUS,
                function (event: HTTPStatusEvent): void {
                    trace(event);
                    LogManager.instance.addLog("\t\t" + HTTPStatusEvent.HTTP_RESPONSE_STATUS + ":" + event);
                }
            );
            this._nicowariLoader.addVideoLoaderListener(Event.COMPLETE, nicowariGetSuccess);
            this._nicowariLoader.getVideoForApiResult(this._nicowariVideoUrl);
        }

        /**
         * ニコ割のダウンロードが終わったら呼ばれます。
         * ニコ割の保存後、ダウンロードすべきニコ割がまだ残っていれば続けてニコ割をダウンロードし、
         * ダウンロードすべきニコ割が無ければサムネイル情報の取得を開始します。
         *
         * @param event
         *
         */
        private function nicowariGetSuccess(event: Event): void {

            var fileName: String = this._saveVideoName + "[Nicowari]" + "[" + this._nicowariVideoId + "].swf";

            var fileIO: FileIO = new FileIO();
            fileIO.addFileStreamEventListener(IOErrorEvent.IO_ERROR, function (event: IOErrorEvent): void {
                trace(NICOWARI_GET_FAIL + ":" + fileName + ":" + event + ":" + event.target + ":" + event.text);
                LogManager.instance.addLog(NICOWARI_GET_FAIL + ":" + fileName + ":" + event + ":" + event.target + ":" +
                                           event.text);
                dispatchEvent(new IOErrorEvent(NICOWARI_GET_FAIL, false, false, event.text));
                close(true, true, event);
            });
            var file: File = fileIO.saveVideoByURLLoader((event.target as URLLoader), fileName, this._saveDir.url);

            //ニコ割取得完了を通知
            (event.target as URLLoader).close();
            this._nicowariLoader.close();
            trace(event + "\n" + file.nativePath);
            LogManager.instance.addLog("\t" + NICOWARI_GET_SUCCESS + ":" + file.nativePath);
            dispatchEvent(new Event(NICOWARI_GET_SUCCESS));

            if (this._nicowariVideoIds.length <= 0 || this._nicowariVideoUrls.length <= 0) {
                //市場情報取得
//				getThumbInfo(this._thumbInfoId);
                switcher();

            } else {
                //次のニコ割を取りにいく
                getNicowari();
            }

        }

        private function createNNDDServerRequest(): URLRequest {
            var request: URLRequest = new URLRequest("http://" + this._otherNNDDServerAddress + ":" +
                                                     this._otherNNDDServerPort + "/NNDDServer");
            request.method = "POST";

            var reqXML: XML = <nnddRequest/>;
            reqXML.@type = RequestType.GET_VIDEO_BY_ID.typeStr;
            reqXML.video.@id = this._videoId;

            request.data = reqXML.toXMLString();

            return request;
        }

        private function createDmsSession(): void {
            var videos: Array = _watchVideo.domandVideos;
            var audios: Array = _watchVideo.domandAudios;

            LogManager.instance.addLog("DMS: 利用可能なビデオストリーム: " + JSON.stringify(videos));
            var bestVideo: Object = null;
            // VP9優先 (CEFがVP9 MSEをサポート)、なければH.264
            for each (var v: Object in videos) {
                var vid: String = String(v.id).toLowerCase();
                if (v.isAvailable && (vid.indexOf("vp9") >= 0 || vid.indexOf("h264") >= 0 || vid.indexOf("avc") >= 0)) {
                    if (bestVideo == null || int(v.qualityLevel) > int(bestVideo.qualityLevel)) {
                        bestVideo = v;
                    }
                }
            }
            // H.264が見つからなければ任意の利用可能なストリームにフォールバック
            if (bestVideo == null) {
                LogManager.instance.addLog("DMS: H.264ストリームが見つかりません。利用可能なストリーム: " + JSON.stringify(videos));
                for each (var vAny: Object in videos) {
                    if (vAny.isAvailable && (bestVideo == null || int(vAny.qualityLevel) > int(bestVideo.qualityLevel))) {
                        bestVideo = vAny;
                    }
                }
            }
            if (bestVideo != null) {
                LogManager.instance.addLog("DMS: 選択ビデオストリーム: " + String(bestVideo.id));
            }
            var bestAudio: Object = null;
            for each (var a: Object in audios) {
                if (a.isAvailable && (bestAudio == null || int(a.qualityLevel) > int(bestAudio.qualityLevel))) {
                    bestAudio = a;
                }
            }

            if (bestVideo == null || bestAudio == null) {
                LogManager.instance.addLog(CREATE_DMS_SESSION_FAIL + ":" + _videoId + ": 利用可能なストリームがありません");
                var noStreamErr: IOErrorEvent = new IOErrorEvent(CREATE_DMS_SESSION_FAIL, false, false, "利用可能なストリームがありません");
                dispatchEvent(noStreamErr);
                close(true, true, noStreamErr);
                return;
            }

            _dmsAccess = new ApiDmsAccess();
            _dmsAccess.addEventListener(Event.COMPLETE, createDmsSessionSuccess);
            _dmsAccess.addEventListener(IOErrorEvent.IO_ERROR, function(e: IOErrorEvent): void {
                LogManager.instance.addLog(CREATE_DMS_SESSION_FAIL + ":" + _videoId + ":" + e.text);
                dispatchEvent(new IOErrorEvent(CREATE_DMS_SESSION_FAIL, false, false, e.text));
                close(true, true, e);
            });
            _dmsAccess.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, function(e: HTTPStatusEvent): void {
                LogManager.instance.addLog("\t\t" + HTTPStatusEvent.HTTP_RESPONSE_STATUS + ":" + e);
            });

            trace(CREATE_DMS_SESSION_START + ":" + _videoId);
            LogManager.instance.addLog(CREATE_DMS_SESSION_START + ":" + _videoId);
            dispatchEvent(new Event(CREATE_DMS_SESSION_START));
            dispatchEvent(new Event(VIDEO_GET_START));

            _dmsAccess.createDmsSession(
                _videoId,
                _watchVideo.domandAccessRightKey,
                String(bestVideo.id),
                String(bestAudio.id)
            );
        }

        private function createDmsSessionSuccess(event: Event): void {
            _dmsAccess.removeEventListener(Event.COMPLETE, createDmsSessionSuccess);
            _dmsResultAnalyzer.analyze(_dmsAccess.data);

            if (!_dmsResultAnalyzer.isValid) {
                LogManager.instance.addLog(CREATE_DMS_SESSION_FAIL + ":" + _videoId + ": contentUrl が取得できません");
                var err: IOErrorEvent = new IOErrorEvent(CREATE_DMS_SESSION_FAIL, false, false, "contentUrl が取得できません");
                dispatchEvent(err);
                close(true, true, err);
                return;
            }

            trace(CREATE_DMS_SESSION_SUCCESS + ":" + _videoId);
            LogManager.instance.addLog(CREATE_DMS_SESSION_SUCCESS + ":" + _videoId);
            dispatchEvent(new Event(CREATE_DMS_SESSION_SUCCESS));

            var masterUrl: String = _dmsResultAnalyzer.contentUrl;
            LogManager.instance.addLog("DMS ストリーム URL: " + masterUrl);

            if (_isVideoNotDownload) {
                // ストリーミングモード: DMS URL を Flashls に直接渡す
                _streamingUrl = masterUrl;
                dispatchEvent(new Event(DOWNLOAD_PROCESS_COMPLETE));
                close(false, false);
            } else {
                // ダウンロードモード: 全セグメントDL → ffmpeg mux
                _dmsHlsDownloader = new DmsHlsDownloader();
                _dmsHlsDownloader.logCallback = function(msg: String): void {
                    LogManager.instance.addLog(msg);
                };
                _dmsHlsDownloader.addEventListener(DmsHlsDownloader.COMPLETE, onDmsHlsComplete);
                _dmsHlsDownloader.addEventListener(DmsHlsDownloader.PROGRESS, onDmsHlsProgress);
                _dmsHlsDownloader.addEventListener(DmsHlsDownloader.ERROR,    onDmsHlsError);
                LogManager.instance.addLog("DmsHlsDownloader.startDownload 呼び出し");
                _dmsHlsDownloader.startDownload(masterUrl, _saveDir,
                    HtmlUtil.convertSpecialCharacterNotIncludedString(_saveVideoName));
            }
        }

        private function onDmsHlsComplete(event: Event): void {
            _dmsHlsDownloader.removeEventListener(DmsHlsDownloader.COMPLETE, onDmsHlsComplete);
            _dmsHlsDownloader.removeEventListener(DmsHlsDownloader.PROGRESS, onDmsHlsProgress);
            _dmsHlsDownloader.removeEventListener(DmsHlsDownloader.ERROR,    onDmsHlsError);

            _dmsDownloaded = true;
            _streamingUrl  = _dmsHlsDownloader.outputPath;
            _savedVideoPath = decodeURIComponent(new File(_dmsHlsDownloader.outputPath).url);
            LogManager.instance.addLog("DMSダウンロード完了: " + _streamingUrl);

            dispatchEvent(new Event(DOWNLOAD_PROCESS_COMPLETE));
            close(false, false);
        }

        private function onDmsHlsProgress(event: flash.events.ProgressEvent): void {
            LogManager.instance.addLog("DMSダウンロード進捗: " +
                int(event.bytesLoaded) + "/" + int(event.bytesTotal) + " セグメント");
            var fakeMB: Number = 1024 * 1024;
            dispatchEvent(new flash.events.ProgressEvent(VIDEO_DOWNLOAD_PROGRESS, false, false,
                event.bytesLoaded * fakeMB, event.bytesTotal * fakeMB));
        }

        private function onDmsHlsError(event: ErrorEvent): void {
            _dmsHlsDownloader.removeEventListener(DmsHlsDownloader.COMPLETE, onDmsHlsComplete);
            _dmsHlsDownloader.removeEventListener(DmsHlsDownloader.PROGRESS, onDmsHlsProgress);
            _dmsHlsDownloader.removeEventListener(DmsHlsDownloader.ERROR,    onDmsHlsError);

            LogManager.instance.addLog(CREATE_DMS_SESSION_FAIL + ": " + event.text);
            var err: IOErrorEvent = new IOErrorEvent(CREATE_DMS_SESSION_FAIL, false, false, event.text);
            dispatchEvent(err);
            close(true, true, err);
        }

        private function createDmcSession(): void {
            this._dmcAccess = new ApiDmcAccess();
            // Register EventListeners
            this._dmcAccess.addEventListener(IOErrorEvent.IO_ERROR, function (event: ErrorEvent): void {
                (event.target as URLLoader).close();
                LogManager.instance.addLog(CREATE_DMC_SESSION_FAIL + ":" + _videoId + ":" + event + ":" + event.target +
                                           ":" + event.text);
                trace(CREATE_DMC_SESSION_FAIL + ":" + event + ":" + event.target + ":" + event.text);
                dispatchEvent(new IOErrorEvent(CREATE_DMC_SESSION_FAIL, false, false, event.text));
                close(true, true, event);
            });
            this._dmcAccess.addEventListener(
                HTTPStatusEvent.HTTP_RESPONSE_STATUS,
                function (event: HTTPStatusEvent): void {
                    trace(event);
                    LogManager.instance.addLog("\t\t" + HTTPStatusEvent.HTTP_RESPONSE_STATUS + ":" + event);
                }
            );
            this._dmcAccess.addEventListener(Event.COMPLETE, createDmcSessionSuccess);

            trace(CREATE_DMC_SESSION_START + ":" + this._threadId + "(" + this._videoId + ")");
            LogManager.instance.addLog(CREATE_DMC_SESSION_START + ":" + this._threadId + "(" + this._videoId + ")");
            dispatchEvent(new Event(CREATE_DMC_SESSION_START));

            if (!this._dmcInfoAnalyzer.isAvailable) {
                LogManager.instance.addLog(CREATE_DMC_SESSION_FAIL + ":" + _videoId + ": DMC Server is Unavailable");
                trace(CREATE_DMC_SESSION_FAIL + ": DMC Server is Unavailable");
                close(true, true);
                return;
            }

            this._dmcAccess.createDmcSession(
                this._videoId,
                this._dmcInfoAnalyzer.apiUrl,
                this._dmcInfoAnalyzer.getSession(this._isVideoNotDownload)
            );
        }

        private function createDmcSessionSuccess(event: Event): void {
            this._dmcAccess.removeEventListener(Event.COMPLETE, createDmcSessionSuccess);
            this._dmcResultAnalyzer.analyze(this._dmcAccess.data);

            if (this._dmcResultAnalyzer.sessionId == null || this._dmcResultAnalyzer.sessionId.length == 0 ||
                this._dmcResultAnalyzer.session == null) {
                trace(CREATE_DMC_SESSION_FAIL + ":" + event);
                LogManager.instance.addLog("\t" + CREATE_DMC_SESSION_FAIL + ":" + this._videoId + ":" +
                                           this._nicoVideoName);
                LogManager.instance.addLog("動画が存在しないか、アクセスできません。(" + this._videoId + ")");
                var errorEvent: ErrorEvent = new IOErrorEvent(
                    CREATE_DMC_SESSION_FAIL,
                    false,
                    false,
                    "動画が存在しないか、アクセスできません。(" + this._videoId + ")"
                );
                dispatchEvent(errorEvent);
                close(true, true, errorEvent);
                return;
            } else {
                trace(CREATE_DMC_SESSION_SUCCESS + ":" + event);
                LogManager.instance.addLog("\t" + CREATE_DMC_SESSION_SUCCESS + ":" + this._videoId + ":" +
                                           this._nicoVideoName);
                dispatchEvent(new Event(CREATE_DMC_SESSION_SUCCESS));
            }

            this.switcher();
        }

        private function switcher(): void {
            // DMS (新配信) 優先
            if (this._watchVideo.isDms && !this._dmsResultAnalyzer.isValid) {
                createDmsSession();
                return;
            }

            if (!this._watchVideo.isDmc) {
                this._dmcAccess = null;
            }

            if (!this._watchVideo.isDmc || this._dmcResultAnalyzer.isValid) {
                try {
                    getVideo();
                } catch (error: Error) {
                    trace(error.getStackTrace());
                    LogManager.instance.addLog("動画のダウンロードでエラーが発生:" + error);
                    var myEvent: IOErrorEvent = new IOErrorEvent(VIDEO_GET_FAIL, false, false, "DownloadFail");
                    dispatchEvent(myEvent);
                    close(true, true, myEvent);
                }
            } else {
                this._dmcInfoAnalyzer.analyze(this._watchVideo.dmcInfo);
                createDmcSession();
            }
        }

        private function getVideo(): void {

            // 他のNNDDからの取得が許可されているなら、他のNNDDが持っていないかチェックしにいく
            if (this._isEnableGetVideoFromOtherNNDDServer) {
                var timeout: int = 1000;

                var timeoutStr: String = ConfigManager.getInstance().getItem("connectToNnddServerTimeout");
                if (timeoutStr != null) {
                    timeout = int(timeoutStr);
                }

                var request: URLRequest = createNNDDServerRequest();
                request.idleTimeout = timeout;

                this._otherNNDDInfoLoader = new URLLoader();
                this._otherNNDDInfoLoader.addEventListener(
                    HTTPStatusEvent.HTTP_RESPONSE_STATUS,
                    function (event: HTTPStatusEvent): void {
                        trace(event);
                        LogManager.instance.addLog("\t\t" + HTTPStatusEvent.HTTP_RESPONSE_STATUS + ":" + event);
                    }
                );
                this._otherNNDDInfoLoader.addEventListener(Event.COMPLETE, function (event: Event): void {
                    _otherNNDDInfoLoader.close();

                    var resXML: XML = new XML(_otherNNDDInfoLoader.data);

                    trace(resXML);

                    if (resXML.video.@videoUrl != null && resXML.video.@videoUrl != undefined) {
                        // サーバが動画を持っている
                        _isNNDDServerReady = true;
                        _nnddServerVideoUrl = resXML.video.@videoUrl;
                    }

                    LogManager.instance.addLog("\t" + REMOTE_NNDD_SERVER_ACCESS_SUCCESS + ":" + request.url);
                    trace(REMOTE_NNDD_SERVER_ACCESS_SUCCESS + ":" + event + "\n" + request.url);

                    dispatchEvent(new Event(REMOTE_NNDD_SERVER_ACCESS_SUCCESS));

                    startInnner();

                });
                this._otherNNDDInfoLoader.addEventListener(IOErrorEvent.IO_ERROR, function (event: IOErrorEvent): void {
                    (event.target as URLLoader).close();
                    LogManager.instance.addLog("REMOTE_NNDD_SERVER_ACCESS_FAIL" + request.url);
                    trace("REMOTE_NNDD_SERVER_ACCESS_FAIL" + ":" + event + ":" + event.target + ":" + event.text);

                    startInnner();

                });

                this._otherNNDDInfoLoader.load(request);

            } else {
                startInnner();
            }

            function startInnner(): void {
                if (!_isVideoNotDownload) {
                    getVideoForDownload();
                } else {
                    getVideoForStreaming();
                }
            }

        }

        /**
         * DLする動画のサイズ(bytes)
         */
        private var contentLength: Number = 0;

        /**
         * 動画のダウンロードを開始します
         *
         */
        private function getVideoForDownload(): void {
            this._videoStream = new VideoStream();
            this._videoStream.addEventListener(IOErrorEvent.IO_ERROR, function (event: IOErrorEvent): void {
                (event.target as URLStream).close();
                trace(VIDEO_GET_FAIL + ":" + event + ":" + event.target + ":" + event.text);
                LogManager.instance.addLog(VIDEO_GET_FAIL + ":" + _videoId + ":" + event + ":" + event.target + ":" +
                                           event.text);
                dispatchEvent(new IOErrorEvent(VIDEO_GET_FAIL, false, false, event.text));
                close(true, true, event);
            });
            this._videoStream.addEventListener(
                HTTPStatusEvent.HTTP_RESPONSE_STATUS,
                function (event: HTTPStatusEvent): void {
                    trace(event);
                    if (_retryCount === 0) {
                        for each(var header: URLRequestHeader in event.responseHeaders) {
                            if (header.name == "Content-Length") {
                                contentLength = Number(header.value);
                                break;
                            }
                        }
                    }
                    LogManager.instance.addLog("\t\t" + HTTPStatusEvent.HTTP_RESPONSE_STATUS + ":" + event);
                    LogManager.instance.addLog("\t\t" + "Content-Length:" + contentLength);
                }
            );
            this._videoStream.addEventListener(ProgressEvent.PROGRESS, streamProgressHandler);
            this._videoStream.addEventListener(Event.COMPLETE, videoGetCompleteHandler);

            this._threadId = this._flvResultAnalyzer.threadId;

            // TODO: Refactor this condition.
            if (
                this._flvResultAnalyzer.url == null ||
                this._flvResultAnalyzer.url.length == 0 ||
                (
                    this._watchVideo.isDmc &&
                    (
                        !this._dmcResultAnalyzer.isValid ||
                        this._dmcResultAnalyzer.contentUri.length == 0
                    )
                )
            ) {
                trace(VIDEO_GET_FAIL + ":動画サーバーのURLが取得できません:" + this.videoUrl);
                LogManager.instance.addLog(VIDEO_GET_FAIL + ":動画サーバーのURLが取得できません。:" + this.videoUrl);
                var event: ErrorEvent = new IOErrorEvent(VIDEO_GET_FAIL, false, false, "動画サーバーのURLが取得できません。");
                dispatchEvent(event);
                close(true, true, event);
                return;
            }
            var videoType: VideoType = VideoStream.checkVideoType(this._flvResultAnalyzer.url);

            var extension: String = "";
            if (VideoType.VIDEO_TYPE_FLV == videoType) {
                extension = ".flv";
            } else if (VideoType.VIDEO_TYPE_MP4 == videoType || this._watchVideo.isDmc) {
                extension = ".mp4";
            } else if (VideoType.VIDEO_TYPE_SWF == videoType) {
                extension = ".swf";
            }

            LogManager.instance.addLog("拡張子を判定:videoType=" + videoType + ", 拡張子=" + extension);

            //HTML特殊文字置き換え済動画名
            this._saveVideoFileName =
                HtmlUtil.convertSpecialCharacterNotIncludedString(this._saveVideoName) + extension;
            this._nicoVideoName = this._nicoVideoName + extension;

            LogManager.instance.addLog("保存ファイル名:" + this._saveVideoFileName);
            LogManager.instance.addLog("ニコ動の動画タイトル:" + this._nicoVideoName);

            //保存済みのファイルがあり, かつリトライでないならゴミ箱へ移動
            var oldFile: File = new File(_saveDir.url).resolvePath(_saveVideoFileName);
            if (oldFile.exists && this._retryCount === 0) {
                oldFile.moveToTrash();
            }

            var videoUrl: String = this._dmcResultAnalyzer.contentUri;

            if (this._isNNDDServerReady) {
                videoUrl = _nnddServerVideoUrl;
            }

            LogManager.instance.addLog("動画のDLを開始:DL先=" + videoUrl);

            trace(VIDEO_GET_START + ":" + this._videoId);
            LogManager.instance.addLog(VIDEO_GET_START + ":" + this._videoId);
            dispatchEvent(new Event(VIDEO_GET_START));

            this._dmcHeartBeatTimer = createDmcBeatingTimer();
            if (this._dmcHeartBeatTimer !== null) {
                this._dmcHeartBeatTimer.start();
            }
            this._videoStream.getVideoStart(videoUrl, this._downloadedSize);
        }

        public function createDmcBeatingTimer(): Timer {
            if (!this._watchVideo.isDmc) {
                return null;
            }

            var timer: Timer = new Timer(this._dmcResultAnalyzer.session.session.keep_method.heartbeat.lifetime * 0.5);
            timer.addEventListener(TimerEvent.TIMER, function (event: TimerEvent): void {
                trace("DMCSessionBeating...");
                _dmcAccess.beatDmcSession(_dmcResultAnalyzer.sessionId, _dmcResultAnalyzer.session);
            });

            this._dmcAccess.addEventListener(IOErrorEvent.IO_ERROR, function (event: IOErrorEvent): void {
                (event.target as URLStream).close();
                trace(DMC_SESSION_FAIL + ":" + event + ":" + event.target + ":" + event.text);
                LogManager.instance.addLog(DMC_SESSION_FAIL + ":" + _videoId + ":" + event + ":" + event.target + ":" +
                                           event.text);
                dispatchEvent(new IOErrorEvent(DMC_SESSION_FAIL, false, false, event.text));
                close(true, true, event);
                timer.stop();
            });

            if (this._videoStream !== null) {
                this._videoStream.addEventListener(Event.COMPLETE, function (event: Event): void {
                    timer.stop();
                });
            }

            return timer;
        }

        public function get isDmc(): Boolean {
            return this._dmcInfoAnalyzer.isAvailable;
        }

        public function get isHLS(): Boolean {
            if (_dmsDownloaded) return false; // ローカル MP4 再生
            if (_watchVideo != null && _watchVideo.isDms && _isVideoNotDownload) return true;
            return this._dmcInfoAnalyzer.isHLSAvailable && this._isVideoNotDownload;
        }

        /**
         * ストリーミング再生の準備をします
         *
         */
        private function getVideoForStreaming(): void {
            this._videoLoader = new VideoLoader();
            this._videoLoader.addVideoLoaderListener(
                VideoLoader.VIDEO_URL_GET_FAIL,
                function (event: IOErrorEvent): void {
                    (event.target as URLLoader).close();
                    trace(VIDEO_GET_FAIL + ":" + event + ":" + event.target + ":" + event.text);
                    LogManager.instance.addLog(VIDEO_GET_FAIL + ":" + _videoId + ":" + event + ":" + event.target +
                                               ":" + event.text);
                    dispatchEvent(new IOErrorEvent(
                        VIDEO_GET_FAIL,
                        false,
                        false,
                        event.text
                    ));
                    close(true, true, event);
                }
            );
            this._videoLoader.addVideoLoaderListener(IOErrorEvent.IO_ERROR, function (event: IOErrorEvent): void {
                (event.target as URLLoader).close();
                trace(VIDEO_GET_FAIL + ":" + event + ":" + event.target + ":" + event.text);
                LogManager.instance.addLog(VIDEO_GET_FAIL + ":" + _videoId + ":" + event + ":" + event.target + ":" +
                                           event.text);
                dispatchEvent(new IOErrorEvent(VIDEO_GET_FAIL, false, false, event.text));
                close(true, true, event);
            });
            this._videoLoader.addVideoLoaderListener(
                HTTPStatusEvent.HTTP_RESPONSE_STATUS,
                function (event: HTTPStatusEvent): void {
                    trace(event);
                    LogManager.instance.addLog("\t\t" + HTTPStatusEvent.HTTP_RESPONSE_STATUS + ":" + event);
                }
            );

            //ストリーミング再生用
            this._videoLoader.addEventListener(VideoLoader.VIDEO_URL_GET_SUCCESS, function (event: Event): void {

                trace(VideoLoader.VIDEO_URL_GET_SUCCESS + ":" + event);
                _streamingUrl = (event.target as VideoLoader).videoUrl;

                if (_isNNDDServerReady) {
                    _streamingUrl = _nnddServerVideoUrl;
                }

                LogManager.instance.addLog("ストリーム再生用のURL:" + _streamingUrl);

                var extension: String = "";
                if ((event.target as VideoLoader).videoType == VideoType.VIDEO_TYPE_FLV) {
                    extension = ".flv";
                } else if ((event.target as VideoLoader).videoType == VideoType.VIDEO_TYPE_MP4) {
                    extension = ".mp4";
                } else if ((event.target as VideoLoader).videoType == VideoType.VIDEO_TYPE_SWF) {
                    extension = ".swf";
                } else {
//					dispatchEvent(new IOErrorEvent(DOWNLOAD_PROCESS_ERROR, false, false, _streamingUrl));
                    close(true, true, new IOErrorEvent(DOWNLOAD_PROCESS_ERROR, false, false, _streamingUrl));
                    return;
                }

                _nicoVideoName = _nicoVideoName + extension;

                dispatchEvent(new Event(DOWNLOAD_PROCESS_COMPLETE));
                close(false, false);
            });

            LogManager.instance.addLog("ストリーム再生用のURLを取得:" + this._nicoVideoName);

            this._videoLoader.getVideo(this._isVideoNotDownload, this._flvResultAnalyzer, this._dmcAccess, this._watchVideo);
        }

        /**
         *
         */
        private var beforeBytes: Number = 0;

        /**
         *
         */
        private var loadedBytes: ByteArray = new ByteArray();

        /**
         *
         */
        private var isWriting: Boolean = false;

        /**
         *
         * @param event
         *
         */
        private function streamProgressHandler(event: ProgressEvent): void {
            var downloadedSize: Number = event.bytesLoaded + this._downloadedSize;

            //イベントを乱発すると性能が落ちるので間引き
            if (downloadedSize - beforeBytes > 1000000 || beforeBytes == 0) {
                trace(VIDEO_DOWNLOAD_PROGRESS + ":" + downloadedSize + "/" + this.contentLength + " bytes");
                dispatchEvent(new ProgressEvent(
                    VIDEO_DOWNLOAD_PROGRESS,
                    false,
                    false,
                    downloadedSize,
                    this.contentLength
                ));
                beforeBytes = downloadedSize;
            }

            // 読み取り可能なバイト列があるかどうか
            var stream: URLStream = (event.currentTarget as URLStream);
            if (!(stream.bytesAvailable > 0)) {
                return;
            }

            // ファイル書き出し中なら次の機会に
            if (isWriting) {
                return;
            }

            //ストリームからバイトを読み込み
            stream.readBytes(loadedBytes, loadedBytes.length);

            // 1MBを越えたらファイルに書き出し
            if (loadedBytes.length > 1000000) {
                isWriting = true;

                trace("append:" + loadedBytes.length + " bytes");
                outputFile(_saveVideoFileName, _saveDir.url, loadedBytes);
                loadedBytes.clear();

                isWriting = false;

            }
        }

        /**
         * 指定されたバイト列をファイルに書き出します。ファイルへの書き出しは追記モードで行います。
         *
         * @param fileName
         * @param saveDirPath
         * @param bytes
         *
         */
        private function outputFile(fileName: String, saveDirPath: String, bytes: ByteArray): void {
            //バイト列をファイルに書き出し
            try {
                var fileIO: FileIO = new FileIO();
                var savedFile: File = fileIO.saveByteArray(fileName, saveDirPath, loadedBytes, true);

                this._savedVideoPath = decodeURIComponent(savedFile.url);
            } catch (error: Error) {
                trace(error.getStackTrace());
                LogManager.instance.addLog("動画の保存に失敗:" + error.toString() + "\n" + fileName + ":" + saveDirPath);

                var myEvent: IOErrorEvent = new IOErrorEvent(IOErrorEvent.IO_ERROR, false, false, error.toString());
                dispatchEvent(myEvent);
                close(true, true, myEvent);
            }
        }

        /**
         * 動画のダウンロードが完了したら呼ばれます。<br>
         * 動画の保存終了後、requestDownloadの全行程終了イベントを発行します。
         *
         * @param event
         *
         */
        private function videoGetCompleteHandler(event: Event): void {

            try {
                var start: int = getTimer();

                var min: int = 30;
                var minStr: String = ConfigManager.getInstance().getItem("videoOutputWaitSec");
                if (minStr == null) {
                    ConfigManager.getInstance().setItem("videoOutputWaitSec", 30);
                    ConfigManager.getInstance().save();
                } else {
                    var temp: int = int(minStr);
                    if (temp > 0) {
                        min = temp;
                    }
                }

                // 書き出してないバイト列をファイルに書き出し
                while (true) {
//					outputFile(_saveVideoName, _saveDir.url, loadedBytes);

                    // 一つ前の書き出しが終わるまで待つ
                    if (!isWriting) {
                        var fileIO: FileIO = new FileIO();
                        var savedFile: File = fileIO.saveByteArray(_saveVideoFileName, _saveDir.url, loadedBytes, true);
                        isWriting = false;
                        this.loadedBytes.clear();
                        this._savedVideoPath = decodeURIComponent(savedFile.url);
                        break;
                    }

                    if (getTimer() - start > 1000 * min) {
                        throw new IOError("ファイルの書き込みに失敗( " + min + " 秒待ちましたが、書き出し先のファイルのロックが解放されませんでした。)", 3013);
                    }
                }
            } catch (error: Error) {
                trace(error.getStackTrace());
                LogManager.instance.addLog("動画の保存に失敗:" + error.toString() + "\n" + _saveVideoName + ":" + _saveDir.url);

                var myEvent: IOErrorEvent = new IOErrorEvent(IOErrorEvent.IO_ERROR, false, false, error.toString());
                dispatchEvent(myEvent);
                close(true, true, myEvent);
                return;
            }

            var file: File = new File(this._savedVideoPath);

            //ファイルの大きさチェック（小さすぎたらそれは何らかの障害で取得できていない）
            trace(file.size + " bytes");
            if (file.size < 1000 || contentLength != file.size) {
                LogManager.instance.addLog("ダウンロードした動画のサイズが正しくない:実際のサイズ=" + file.size + ", 想定されたサイズ=" + contentLength);

                var isLimitOver: Boolean = this._retryCount > RETRY_COUNT_LIMIT;
                var isSizeOver: Boolean = contentLength < file.size;

                if (isLimitOver || isSizeOver || !this._watchVideo.isDmc) {
                    var myEvent: IOErrorEvent = new IOErrorEvent(VIDEO_GET_FAIL, false, false, "DownloadFail");
                    dispatchEvent(myEvent);
                    close(true, true, myEvent);
                    return;
                }

                this._retryCount++;
                this._downloadedSize = file.size;
                this._dmcResultAnalyzer.reset();
                LogManager.instance.addLog("レジューム開始: 開始位置=" + file.size + ", リトライ回数=" + this._retryCount);
                watch(this._videoId);
                return;
            }

            //動画取得成功
            (event.currentTarget as URLStream).close();
            LogManager.instance.addLog("\t" + VIDEO_GET_SUCCESS + ":" + file.nativePath);
            trace(VIDEO_GET_SUCCESS + ":" + event + "\n" + file.nativePath);
            dispatchEvent(new Event(VIDEO_GET_SUCCESS));

            //全行程終了
            trace(DOWNLOAD_PROCESS_COMPLETE + ":" + event);
            dispatchEvent(new Event(DOWNLOAD_PROCESS_COMPLETE));

            close(false, false);
        }

        /**
         * 保存済動画のパスを返します。
         * @return
         *
         */
        public function get savedVideoPath(): File {
            if (this._savedVideoPath != null && this._savedVideoPath != "") {
                return new File(this._savedVideoPath);
            } else {

                var file: File = null;
                try {
                    var path: String = this._saveDir.url;
                    if (path.charAt(path.length) != "/") {
                        path += "/";
                    }
                    file = new File(path + this._saveVideoName);
                } catch (error: Error) {

                }

                return file;
            }
        }

        /**
         * 保存済動画の名前を返します。
         * @return
         *
         */
        public function get saveVideoName(): String {
            return this._saveVideoName;
        }

        /**
         * エコノミーモードかどうかを返します。
         * @return
         *
         */
        public function get isEconomyMode(): Boolean {
            return false;
        }

        /**
         * ストリーミング再生の際にストリーミング先URLを返します。
         * @return
         *
         */
        public function get streamingUrl(): String {
            return this._streamingUrl;
        }

        /**
         * ダウンロード済動画を表すNNDDVideoオブジェクトを返します。
         * 動画のタイトル、URL、エコノミーモードか否かの情報を含みますが、タグ情報等は含みません。
         *
         * @return
         *
         */
        public function get downloadedVideo(): NNDDVideo {
            var video: NNDDVideo = new NNDDVideo(this.savedVideoPath.url, null, isEconomyMode);
            return video;
        }

        /**
         *
         * @return
         *
         */
        public function get localThumbUri(): String {
            return this._thumbPath;
        }

        /**
         *
         * @return
         *
         */
        public function get nicoVideoName(): String {
            return this._nicoVideoName;
        }

        /**
         *
         *
         */
        private function terminate(): void {
            this._login = null;
            this._watchVideo = null;
            this._getflvAccess = null;
            this._commentLoader = null;
            this._ownerCommentLoader = null;
            this._nicowariLoader = null;
            this._getbgmAccess = null;
            this._thumbInfoLoader = null;
            this._thumbImgLoader = null;
            this._videoLoader = null;
            this._retryCount = 0;
            this._downloadedSize = 0;
        }

        /**
         * Loaderをすべて閉じます。
         *
         * @param isCancel trueにするとDOWNLOAD_PROCESS_CANCELDを発行します
         * @param isError trueにするとDOWNLOAD_PROCESS_ERRORを発行します
         * @param event isCancel=true、isError=trueの時にErrorEventを設定すると、ErrorEvent.textのテキストを含むDOWNLOAD_PROCESS_ERRORを発行します。
         *
         */
        public function close(isCancel: Boolean, isError: Boolean, event: ErrorEvent = null): void {

            if (isCancel == false && isError == false) {
                var nnddVideo: NNDDVideo = LibraryManagerBuilder.instance.libraryManager.remove(this._threadId, true);
                var file: File = null;
                if (nnddVideo != null) {
                    file = nnddVideo.file;
                }

                try {
                    // 動画タイトルに動画IDとは異なるスレッドIDが含まれているか？
                    if (file != null && file.exists && nnddVideo != null && this._threadId != this._videoId &&
                        file.name.indexOf(this._threadId) != -1) {

                        LogManager.instance.addLog("動画タイトルのスレッドID(" + this._threadId + ")を動画ID(" + this._videoId +
                                                   ")に置き換え中...");
                        LogManager.instance.addLog("対象動画:" + file.nativePath);
                        var newVideoFile: File = changeThreadIdToVideoId(file, this._threadId, this._videoId);
                        LogManager.instance.addLog("置き換え完了");

                        if (nnddVideo != null) {
                            var thumbImgUrl: String = PathMaker.createThumbImgFilePath(newVideoFile.url);
                            var newVideo: NNDDVideo = new NNDDVideo(newVideoFile.url,
                                                                    null,
                                                                    nnddVideo.isEconomy,
                                                                    nnddVideo.tagStrings,
                                                                    nnddVideo.modificationDate,
                                                                    nnddVideo.creationDate,
                                                                    thumbImgUrl,
                                                                    nnddVideo.playCount,
                                                                    nnddVideo.time,
                                                                    nnddVideo.lastPlayDate,
                                                                    nnddVideo.pubDate
                            );
                            LibraryManagerBuilder.instance.libraryManager.add(newVideo, true);

                            this._savedVideoPath = newVideoFile.url;
                            this._thumbPath = newVideo.thumbUrl;
                            this._saveVideoFileName = newVideoFile.name;
                        }
                    }
                } catch (error: Error) {
                    trace(error.getStackTrace());
                    LogManager.instance.addLog("置き換えに失敗:" + error);
                }
            }

            //終了処理
            try {
                this._login.close();
                trace(this._login + " is closed.");
            } catch (error: Error) {
//				trace(error.getStackTrace());
            }
            try {
                this._watchVideo.close();
                trace(this._watchVideo + " is closed.");
            } catch (error: Error) {
//				trace(error.getStackTrace());
            }
            try {
                this._getflvAccess.close();
                trace(this._getflvAccess + " is closed.");
            } catch (error: Error) {
//				trace(error.getStackTrace());
            }
            try {
                this._commentLoader.close();
                trace(this._commentLoader + " is closed.");
            } catch (error: Error) {
//				trace(error.getStackTrace());
            }
            try {
                this._ownerCommentLoader.close();
                trace(this._ownerCommentLoader + " is closed.");
            } catch (error: Error) {
//				trace(error.getStackTrace());
            }
            try {
                this._getbgmAccess.close();
                trace(this._getbgmAccess + " is closed.");
            } catch (error: Error) {
//				trace(error.getStackTrace());
            }
            try {
                this._nicowariLoader.close();
                trace(this._nicowariLoader + " is closed.");
            } catch (error: Error) {
//				trace(error.getStackTrace());
            }
            try {
                this._thumbInfoLoader.close();
                trace(this._thumbInfoLoader + " is closed.");
            } catch (error: Error) {
//				trace(error.getStackTrace());
            }
            try {
                this._thumbImgLoader.close();
                trace(this._thumbImgLoader + " is closed.");
            } catch (error: Error) {
//				trace(error.getStackTrace());
            }
            try {
                this._videoLoader.close();
                trace(this._videoLoader + " is closed.");
            } catch (error: Error) {
//				trace(error.getStackTrace());
            }

            try {
                this._videoStream.close();
                trace(this._videoStream + " is closed.");
            } catch (error: Error) {

            }

//			try
//			{
//				if (downloadProgressWatcher != null)
//				{
//					downloadProgressWatcher.stop();
//					downloadProgressWatcher = null;
//				}
//			}
//			catch(error:Error)
//			{
//				trace(error.getStackTrace());
//			}

            terminate();

            var eventText: String = "";
            if (event != null) {
                eventText = event.text;
            }
            if (isCancel && !isError) {
                dispatchEvent(new Event(DOWNLOAD_PROCESS_CANCELD));
            } else if (isCancel && isError) {
                dispatchEvent(new IOErrorEvent(DOWNLOAD_PROCESS_ERROR, false, false, eventText));
            }
        }


        /**
         *
         * @return
         *
         */
        public function get messageServerURL(): String {
            if (this._commentLoader != null) {
                return this._commentLoader.messageServerUrl;
            }
            return null;
        }

        /**
         *
         * @return
         *
         */
        public function get videoUrl(): String {
            if (this._videoLoader != null) {
                return this._videoLoader.videoUrl;
            }
            return null;
        }

        /**
         *
         * @return
         *
         */
        public function get videoType(): VideoType {
            if (this._videoLoader != null) {
                return this._videoLoader.videoType;
            }
            return null;
        }

        /**
         * getFlv APIの取得結果が存在する場合は、それを返します。
         * @return
         *
         */
        public function get getFlvResultAnalyzer(): GetFlvResultAnalyzer {
            return this._flvResultAnalyzer;
        }

        /**
         * NNDDServer上の動画のURLを返します。この値はnullの場合があります。
         *
         * @return
         *
         */
        public function get nnddServerVideoUrl(): String {
            return new String(this._nnddServerVideoUrl);
        }

        /**
         *
         * @return
         *
         */
        public function get fmsToken(): String {
            return this._fmsToken;
        }

        /**
         * ファイル名にスレッドIDが使用されている動画について、スレッドIDを動画IDに置き換えます。
         * @param nowVideoFile
         * @param threadId
         * @param videoId
         *
         */
        public function changeThreadIdToVideoId(nowVideoFile: File, threadId: String, videoId: String): File {
            var newVideoFile: File = null;
            var file: File = new File(nowVideoFile.url);
            if (file != null) {
                var oldVideoPath: String = decodeURIComponent(file.url);

                // 動画ファイルを置き換え
                var newFile: File = file.parent.resolvePath(file.name.replace(threadId, videoId));
                if (newFile.exists) {
                    newFile.moveToTrash();
                }
                file.moveTo(newFile, false);

                newVideoFile = newFile;

                // コメントを置き換え
                var nowFile: File = new File(PathMaker.createNomalCommentPathByVideoPath(oldVideoPath));
                if (nowFile.exists) {
                    newFile = nowFile.parent.resolvePath(nowFile.name.replace(threadId, videoId));
                    if (newFile.exists) {
                        newFile.moveToTrash();
                    }
                    nowFile.moveTo(newFile, false);
                }

                // 投稿者コメントを置き換え
                nowFile = new File(PathMaker.createOwnerCommentPathByVideoPath(oldVideoPath));
                if (nowFile.exists) {
                    newFile = nowFile.parent.resolvePath(nowFile.name.replace(threadId, videoId));
                    if (newFile.exists) {
                        newFile.moveToTrash();
                    }
                    nowFile.moveTo(newFile, false);
                }

                // サムネイル情報を置き換え
                nowFile = new File(PathMaker.createThmbInfoPathByVideoPath(oldVideoPath));
                if (nowFile.exists) {
                    newFile = nowFile.parent.resolvePath(nowFile.name.replace(threadId, videoId));
                    if (newFile.exists) {
                        newFile.moveToTrash();
                    }
                    nowFile.moveTo(newFile, false);
                }

                // サムネイル画像を置き換え
                nowFile = new File(PathMaker.createThumbImgFilePath(oldVideoPath));
                if (nowFile.exists) {
                    newFile = nowFile.parent.resolvePath(nowFile.name.replace(threadId, videoId));
                    if (newFile.exists) {
                        newFile.moveToTrash();
                    }
                    nowFile.moveTo(newFile, false);
                }

                // ニコ割を置き換え
                var nicowariArray: Vector.<File> = PathMaker.seachNicowariPathByVideoPath(oldVideoPath);
                for each(var nicowari: File in nicowariArray) {
                    if (nicowari.exists) {
                        newFile = nicowari.parent.resolvePath(nicowari.name.replace(threadId, videoId));
                        if (newFile.exists) {
                            newFile.moveToTrash();
                        }
                        nicowari.moveTo(newFile, false);
                    }
                }
            }
            return newVideoFile;
        }
    }
}