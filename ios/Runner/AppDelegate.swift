import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging

// ============================================================
// iOS APNs 開通のためのネイティブ土台
//
// 【背景＝調査で確定した事実】
//  ・APNs登録を要求する箇所はアプリ全体で
//    FLTFirebaseMessagingPlugin.m:308 `[[UIApplication sharedApplication]
//    registerForRemoteNotifications]` の1箇所だけ
//    （ios/Runner 直呼び0件・他プラグイン0件を grep で確認済み）。
//  ・その :308 は `application_onDidFinishLaunchingNotification:`（同 :214）の
//    内部にあり、UIApplicationDidFinishLaunchingNotification の通知ハンドラである
//    （購読は同 :68,73）。
//  ・購読開始は `registerWithRegistrar:`（同 :80）＝ GeneratedPluginRegistrant が
//    走った瞬間。本アプリではそれが didInitializeImplicitFlutterEngine であり、
//    FlutterEngine.h:475-478 が「storyboard から FlutterViewController が
//    生成された時」と明記している＝ UIScene 接続後。
//  ⇒ 起動通知を取り逃すと registerForRemoteNotifications が一度も呼ばれず、
//    APNsトークンが永久に来ない（getAPNSToken() が null のまま →
//    getToken() が [firebase_messaging/apns-token-not-set]）。
//
// 【対策＝このファイルで2段構え】
//  (1) AppDelegate から直接 registerForRemoteNotifications を呼び、届いた
//      deviceToken を Messaging へ直接渡す。プラグインの初期化順に依存しない。
//  (2) プラグイン登録が起動通知を「取り逃していた場合だけ」その通知を再送し、
//      プラグイン本来の初期化（swizzler登録 / addApplicationDelegate /
//      コールド起動タップの回収）を設計どおり走らせる。
//
// ★このファイルは iOS ビルドにのみ含まれる。Android への影響はゼロ。
// ★秘匿: NSLog に token の生値は出さない（長さのみ）。
// ============================================================

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  /// 実物の UIApplicationDidFinishLaunchingNotification を観測したか。
  /// 観測済み＝プラグイン登録がそれより後＝取り逃している、という判定に使う。
  /// これを見ずに無条件 post すると、登録が通知より先だった場合に
  /// ハンドラが2回走り、swizzler登録と addApplicationDelegate が二重になる
  /// （＝通知の二重配信）ので、必ずこのガードを通す。
  private var didObserveRealLaunchNotification = false

  /// 再送時に userInfo を復元するための launchOptions。
  /// これが無いと再送した通知の userInfo が空になり、プラグインの
  /// `_initialNotification`（コールド起動タップ＝getInitialMessage）が拾えない。
  private var savedLaunchOptions: [UIApplication.LaunchOptionsKey: Any]?

  private var launchNotificationObserver: NSObjectProtocol?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    savedLaunchOptions = launchOptions

    // Dart 側 lib/main.dart:57 の Firebase.initializeApp より先にネイティブで確定させる。
    // 二重初期化にはならない（firebase_core 3.15.2 の実装で確認済み・レポート③）。
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }

    // 実物の起動通知を観測するだけの監視。プラグインより先に張る。
    launchNotificationObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didFinishLaunchingNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.didObserveRealLaunchNotification = true
    }

    // APNs 登録要求。プラグインの初期化順に依存せず必ず走らせる（対策1の要）。
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // registerForRemoteNotifications が成功したときに OS から呼ばれる。
  // FlutterAppDelegate が同メソッドを実装しているため override が成立し、
  // super 転送で FlutterPluginAppLifeCycleDelegate 経由の各プラグインにも届く。
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // ★秘匿: token の生値は出さない。長さのみ。
    NSLog("APNs token received len=%ld", deviceToken.count)
    // プラグインの初期化順に関わらず、ここで直接 Messaging に渡す。
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // registerForRemoteNotifications が失敗したときに OS から呼ばれる。
  // 旧構成ではこの経路が誰にも拾われず、失敗が完全に無音だった（沈黙障害）。
  // aps-environment entitlement 欠落・Push Notifications capability 未設定などは
  // すべてここに出る。
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("APNs register FAILED: %@", error.localizedDescription)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // ここまでに実物の起動通知が既に流れていた場合、firebase_messaging の観測者は
    // それを取り逃している（購読開始が直上の register の瞬間のため）。
    // 起動通知の観測者は firebase_messaging ただ1つであることを
    // Pods/ ・.symlinks/plugins/ ・ios/Runner/ の全数 grep で確認済み。
    // 取り逃している時だけ再送する。未発火なら実物が届くので再送しない＝二重実行しない。
    if didObserveRealLaunchNotification {
      var userInfo: [AnyHashable: Any] = [:]
      // キーは rawValue(String) で載せる。プラグイン側は NSString 定数
      // （UIApplicationLaunchOptionsRemoteNotificationKey）で引くため。
      savedLaunchOptions?.forEach { userInfo[$0.key.rawValue] = $0.value }
      NSLog("FCM: replaying didFinishLaunchingNotification for late-registered plugins")
      NotificationCenter.default.post(
        name: UIApplication.didFinishLaunchingNotification,
        object: UIApplication.shared,
        userInfo: userInfo.isEmpty ? nil : userInfo
      )
    } else {
      NSLog("FCM: plugins registered before didFinishLaunchingNotification — no replay needed")
    }

    if let observer = launchNotificationObserver {
      NotificationCenter.default.removeObserver(observer)
      launchNotificationObserver = nil
    }
    savedLaunchOptions = nil
  }
}
