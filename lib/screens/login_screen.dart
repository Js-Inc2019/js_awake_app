// ============================================================
// lib/screens/login_screen.dart - 新設計ログイン画面
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'consent_screen.dart';
import 'pending_approval_screen.dart';
import 'register_screen.dart';
import 'recovery_screen.dart';
import 'membership_select_screen.dart';
import '../services/auth_service.dart';
import '../services/worker_service.dart';
import '../utils/device_id.dart';
import '../utils/field_role_gate.dart';
import '../main.dart' show bossPinOk;
import '../core/theme/field_tokens.dart';

// 現行の利用規約バージョン（BE の CURRENT_CONSENT_VERSION と同値）。
// ※ login_screen は recovery_screen を import するため、公開名の衝突回避で
//   library-private 定数（先頭 _）にしている。
const String _kCurrentConsentVersion = '1.0';

// ─── 配色は lib/core/theme/field_tokens.dart のトークンへ統一（画面ローカル定数は撤去）─────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading    = true;
  String? _errorMessage;
  final _nameCtrl           = TextEditingController();
  final _companyCodeCtrl    = TextEditingController();
  final _partnerCompanyCtrl = TextEditingController();
  final _ownCompanyCtrl     = TextEditingController();

  bool _biometricFailed = false;
  bool _fromBiometricFail = false;
  final _landingInviteCtrl = TextEditingController();
  bool _showSelfReg = false;

  // ★旧フロー互換の「Sign Up後 PIN設定ステップ」は退役。BE 側の初回PIN設定API
  //   ごと廃止されたため、この画面に PIN を作る経路は無い。self-register は token を
  //   prefs に保存して PendingApprovalScreen へ進む。招待コード経路の PIN 設定は
  //   register_screen.dart（/workers/activate）が担当＝そちらは現役。

  // PINログインフォールバック
  bool _showPinLogin = false;
  bool _isUpdateRecovery = false;
  final _loginPinCtrl = TextEditingController();
  bool _biometricErrorShown = false;
  bool _obscureLoginPin = true;

  // requires_selection（複数所属）応答の pre_auth_token。
  // メモリ保持のみ（prefs に保存しない・BE 側 5分で失効するため）。
  String? _preAuthToken;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_biometricErrorShown) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map && args['biometricFailed'] == true) {
        _biometricErrorShown = true;
        _fromBiometricFail = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text(
                '生体認証に失敗しました。PINコードでログインしてください。',
                style: TextStyle(
                    color: FieldTokens.textBody,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              backgroundColor: FieldTokens.statusWarning,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 20),
              duration: const Duration(seconds: 3),
            ));
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _companyCodeCtrl.dispose();
    _partnerCompanyCtrl.dispose();
    _ownCompanyCtrl.dispose();
    _landingInviteCtrl.dispose();
    _loginPinCtrl.dispose();
    super.dispose();
  }

  Future<File> _getRegFlagFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/.js_reg');
  }

  Future<bool> _readPersistentRegistered() async {
    try {
      final f = await _getRegFlagFile();
      return f.existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<void> _writePersistentRegistered() async {
    try {
      final f = await _getRegFlagFile();
      await f.create(recursive: true);
    } catch (_) {}
  }

  Future<String> _getDeviceId() async {
    return getDeviceId();
  }

  Future<bool> _doBiometric() async {
    try {
      final auth = LocalAuthentication();
      final canCheck  = await auth.canCheckBiometrics;
      final supported = await auth.isDeviceSupported();
      if (!canCheck || !supported) {
        if (mounted) setState(() { _showPinLogin = true; _isLoading = false; });
        return false;
      }
      final result = await auth.authenticate(
        localizedReason: '本人確認を行ってください',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
      return result;
    } catch (e) {
      if (mounted) setState(() { _showPinLogin = true; _isLoading = false; });
      return false;
    }
  }

  // ★3回・失敗時2秒待ちの再試行ループはこの画面に残す。
  //   再試行は「1リクエスト＝1結果」の ApiResult には載らない呼び手の方針であり、
  //   AuthService.warmUp() 側へ入れると他の呼び手にも勝手に3回叩かせることになる。
  //   ここを service.warmUp() の1回呼びに置き換えると再試行そのものが消える。
  Future<void> _warmUpServer() async {
    for (int i = 0; i < 3; i++) {
      final res = await AuthService().warmUp();
      if (res.statusCode == 200) return;
      if (i < 2) await Future.delayed(const Duration(seconds: 2));
    }
    debugPrint('サーバーウォームアップ失敗（処理続行）');
  }

  Future<void> _init() async {
    await _warmUpServer();

    final prefs = await SharedPreferences.getInstance();

    final consentAgreed = prefs.getBool('consent_agreed') ?? false;
    // 【順序変更】サイレント復帰(F5)が走り得る状態（reinstall 等で prefs 空: auth_token無・
    // device_id無・is_registered=false）では、ここで同意ゲートを出さず F5 の結果に委ねる:
    //   復帰成功→サーバ同意証跡から consent_agreed を復元し ConsentScreen をスキップ、
    //   復帰失敗(新規/非200)→F5 フォールバックで初めて ConsentScreen を出す。
    // それ以外（token/device/registered が既に在る＝既存状態）では従来どおりここで判定する
    //   （既存ユーザーは consent_agreed=true のため通常この分岐でも表示されない）。
    final recoveryEligible =
        (prefs.getString('auth_token') ?? '').isEmpty
        && prefs.getString('device_id') == null
        && !(prefs.getBool('is_registered') ?? false);
    if (!consentAgreed && !recoveryEligible && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConsentScreen(
          onAgreed: () {
            // この時点は未認証のため API を呼べず、ローカルに now() を暫定記録する。
            // 登録完了後の初ログインで _saveAndNavigate の救済刻印(POST /auth/consent)により
            // サーバへ正式刻印され、以後はサーバ真実値で上書きされる。
            prefs.setBool('consent_agreed', true);
            prefs.setString('consent_version', '1.0');
            prefs.setString(
                'consent_agreed_at', DateTime.now().toIso8601String());
          },
        ),
      ));
      if (!mounted) return;
    }

    // 生体認証失敗から戻った場合はPINログインへ直行（/gate無限ループを断つ）
    if (_fromBiometricFail) {
      if (mounted) setState(() { _showPinLogin = true; _isLoading = false; });
      return;
    }

    final cachedToken = prefs.getString('auth_token') ?? '';
    if (cachedToken.isNotEmpty) {
      {
        // 単一の顔の掟: verify-token は body の device_id 必須（未送信は 400 DEVICE_ID_REQUIRED）
        // token / device_id は AuthService が prefs と device_id.dart から取る
        // （移設前もこの2つと同じ出所だった）。
        final response = await AuthService().verifyToken();

        if (response.statusCode == 200) {
          // ★role ガード（起動時のトークン復帰）の判定結果だけをここで受ける。
          //   この経路は「既にログイン済みの端末」が毎回通る道で、サーバ真実の role を
          //   prefs へ上書きしてから /gate へ入れていた。役職が後から
          //   worker/boss → admin_office/admin_exec へ変わった場合、FIELD に入れては
          //   いけない顔をそのまま通してしまう（他の経路と同じ穴）。
          //   ★案内と return は下の try の【外】で行う。この try は catch (_) {} で
          //     全例外を握り潰す構造なので、案内処理を中に置くと万一の例外で握り潰され、
          //     そのまま下の /gate へ進む＝弾いたつもりが通る形になる。
          //     判定は代入だけ（例外を投げ得ない）にして、行動は外に出す。
          bool resumeBlocked = false;
          try {
            final data = response.data;
            if (data == null) throw StateError('verify-token 応答が空');
            // サーバ真実（DBの role/worker_id/user_id）を毎回 prefs へ上書き保存してから /gate へ
            final user = data['user'];
            // ★fail-close（他の経路と同じ）。role が FIELD の名簿に無ければ弾く。
            //   欠落・空・未知の値も弾く＝isFieldRole が false を返す側に倒す。
            //   ★fail-close にできる根拠（BE 実測）:
            //     js-office-api routes/auth.js:445-455 が
            //       user = { ...user, role: row.role, ... };
            //       return res.status(200).json({ success: true, user });
            //     の形で【必ず】 user.role を載せる。row.role は同 :384 の
            //     `SELECT ... m.role ...` で引いた membership の値で、
            //     memberships.role は NOT NULL DEFAULT 'worker'
            //     （db/prod_schema_v72.sql:1114）。さらに同 :408 が
            //     `!row.membership_id` を 401 で先に弾くため、200 に到達した時点で
            //     membership 行は必ず存在する＝role が空になる経路が無い。
            //     よって正規の FIELD 利用者（worker/boss）がここで弾かれることはない。
            //   ★この穴が実際に踏まれる筋道（fail-open で残せない理由）:
            //     役職変更は force_reauth を立てる（js-office-api routes/workers.js:1285 /
            //     :1436）ので、通常は verify-token が 401 ROLE_CHANGED を返す（同 auth.js:398-402）。
            //     しかし force_reauth は PIN 照合成功で解除される（同 auth.js:109-115）。
            //     verify-pin は OFFICE アプリと共用なので、OFFICE で PIN ログインした時点で
            //     解除され、その後 FIELD を開くと 200＋role='admin_office' が返る。
            //     ＝BE の force_reauth だけでは塞がらない。
            final resumeRole = (user is Map) ? user['role'] as String? : null;
            resumeBlocked = !isFieldRole(resumeRole);
            // ★弾くと決めた回は prefs へ1つも書かない。書いてから弾くと、入れていないのに
            //   user_role だけが OFFICE 側の値に書き換わって残る。
            if (!resumeBlocked) {
              if (user is Map) {
                final serverRole = user['role'] as String?;
                if (serverRole != null && serverRole.isNotEmpty) {
                  await prefs.setString('user_role', serverRole);
                }
                final serverWorkerId = user['worker_id'] as String?;
                if (serverWorkerId != null && serverWorkerId.isNotEmpty) {
                  await prefs.setString('worker_id', serverWorkerId);
                }
                final serverUserId = user['user_id'] as String?;
                if (serverUserId != null && serverUserId.isNotEmpty) {
                  await prefs.setString('user_id', serverUserId);
                }
              }
              // 旧 'role' キーの残骸掃除（二重キー統一・ログイン成功時に1回）
              await prefs.remove('role');

              final serverConsentAt = data['consent_agreed_at'];
              if (serverConsentAt != null) {
                await prefs.setString('consent_agreed_at', serverConsentAt.toString());
              }
              final serverConsentVersion = data['consent_version'];
              if (serverConsentVersion != null) {
                await prefs.setString('consent_version', serverConsentVersion.toString());
              }
              // 承認待ちステータス確認
              final status = data['status'] as String?;
              if (status == 'pending') {
                if (mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const PendingApprovalScreen()),
                  );
                }
                return;
              }
            }
          } catch (_) {}
          // ★auth_token は消さない。サーバ側では有効な資格情報のままで、消す判断は
          //   サーバが無効と言ったとき（下の 401/403 の枝）の仕事。
          if (resumeBlocked) {
            await _rejectNonFieldRole();
            return;
          }
          if (mounted) Navigator.of(context).pushReplacementNamed('/gate');
          return;
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          // 掟違反系（ANCHOR_MISMATCH / DEVICE_NOT_FOUND / MEMBERSHIP_INVALID /
          // LEGACY_TOKEN / TOKEN_EXPIRED / INVALID_TOKEN_SCOPE / COOPERATION_PENDING）
          // → トークン破棄し、必ずログイン手段のある画面へ導く（袋小路禁止）
          // ★移設前は code を優先し、無ければ error 文字列を code として扱っていた。
          //   errorCode が BE の code、errorMessage が BE の error を運ぶ（同じ出所）。
          final errCode = response.errorCode ?? response.errorMessage;
          await prefs.remove('auth_token');
          // 協業承認待ちのみ承認待ち画面へ（既存導線を流用）
          if (errCode == 'COOPERATION_PENDING') {
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const PendingApprovalScreen()),
              );
            }
            return;
          }
          // それ以外は生体ログイン経路へ（生体不可端末は _doBiometric 内で PIN 画面へ）
          await _biometricThenLogin();
          return;
        }
        // 400 DEVICE_ID_REQUIRED / 503 AUTH_DB_ERROR / その他、および
        // タイムアウト・通信例外（statusCode:0）→ 一時障害の可能性。
        // auth_token は消さずPIN画面へフォールバック。
        // ★移設前も catch 側と「その他」側でまったく同じ処理をしていたため、
        //   ApiResult 化で分岐が1本に畳まれるだけで挙動は不変。
        if (mounted) setState(() { _showPinLogin = true; _isLoading = false; });
        return;
      }
    }

    final hasDevice  = prefs.getString('device_id') != null;
    final registered = prefs.getBool('is_registered') ?? false;
    // _isRegistered は内部チェック用（UI未使用）
    if (hasDevice) {
      final loggedOut = prefs.getBool('logged_out') ?? false;
      if (loggedOut) {
        if (mounted) setState(() { _showPinLogin = true; _isLoading = false; });
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) await prefs.remove('logged_out');
        });
        return;
      }
      await _biometricThenLogin();
    } else if (registered) {
      if (!mounted) return;
      setState(() { _isUpdateRecovery = true; _showPinLogin = true; _isLoading = false; });
    } else {
      final persistentReg = await _readPersistentRegistered();
      if (!mounted) return;
      if (persistentReg) {
        await prefs.setBool('is_registered', true);
        setState(() { _isUpdateRecovery = true; _showPinLogin = true; _isLoading = false; });
      } else {
        // ─── サイレント復帰トライ（B案: 照会先行） ───────────────────
        // 再インストール後 prefs 空でも device_id は決定論的に復元可能（device_id.dart）。
        // サーバに端末アンカー(devices.membership_id)が残っていれば verify-device で復帰する。
        // 失敗・非200・新規ユーザーは何もUIに出さず従来の登録/ランディング画面へ（摩擦ゼロ）。
        // セキュリティ順序: 照会200では一切保存せず、保存/遷移は生体成功後の _saveAndNavigate に一任。
        Map<String, dynamic>? recoverData;
        {
          final deviceId = await _getDeviceId(); // 復元トライ（device_id.dart は変更せず流用）
          if (deviceId.isNotEmpty) {
            // 既定8秒＝移設前と同じ（_autoLogin 側は10秒を明示して同じメソッドを使う）。
            final res = await AuthService().verifyDevice(deviceId);
            // 非200・タイムアウト・通信例外はすべて recoverData=null のまま
            // ＝従来の登録画面へ（移設前の if/catch と同じ結果）。
            if (res.statusCode == 200 && res.ok) {
              recoverData = res.data;
            }
          }
        }
        if (!mounted) return;
        if (recoverData != null) {
          // 【再インストール後の同意画面再表示を防ぐ】サーバが有効な同意証跡を返しているなら
          // consent_agreed を復元（consent_version が現行と一致する時のみ）。これは UI ゲート用
          // フラグの復元であり、token/role 等の機密は依然として生体成功後の _saveAndNavigate まで保存しない。
          final rcAt  = recoverData['consent_agreed_at'] as String?;
          final rcVer = recoverData['consent_version']   as String?;
          final serverConsentValid =
              rcAt != null && rcAt.isNotEmpty && rcVer == _kCurrentConsentVersion;
          if (serverConsentValid) {
            // サーバに現行versionの有効な同意証跡あり → UIゲートを復元し ConsentScreen は出さない。
            // ＝一度刻印されたら（サーバ値が非null＆現行version）二度と表示しない（毎回同意の復活防止）。
            await prefs.setBool('consent_agreed', true);
          } else {
            // 【旧時代ユーザー救済・角ケース】サーバ同意が null/空、または version 不一致のとき。
            // 再インストールで prefs 消失していると、上部の同意ゲートは recoveryEligible でスキップ済み、
            // かつ _saveAndNavigate の救済刻印条件（localAgreed==true）も満たせず、同意が永久未記録になる。
            // そこで生体認証の前に ConsentScreen を表示して同意を取得する。onAgreed で consent_agreed=true 等を
            // prefs 保存 → 以降の既存フロー（生体→_saveAndNavigate）内の救済刻印が localAgreed=true + サーバ null を
            // 検知し POST /auth/consent で正式刻印する（既存ロジック再利用・重複実装しない）。
            bool agreedNow = false;
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ConsentScreen(
                onAgreed: () {
                  agreedNow = true;
                  prefs.setBool('consent_agreed', true);
                  prefs.setString('consent_version', '1.0');
                  prefs.setString(
                      'consent_agreed_at', DateTime.now().toIso8601String());
                },
              ),
            ));
            if (!mounted) return;
            if (!agreedNow) {
              // 同意せず戻った → ログインへ進めない。従来のランディング画面へ（袋小路ではない）。
              setState(() => _isLoading = false);
              return;
            }
          }
          // 照会200: 生体認証を要求（既存 _doBiometric 流用）。成功時のみ保存/遷移する。
          final ok = await _doBiometric();
          if (!mounted) return;
          if (ok) {
            // 複数所属 → 選択フロー（従来経路は変更なし）
            if (recoverData['requires_selection'] == true) {
              await _handleMembershipSelection(recoverData);
              return;
            }
            // ★role ガード（単一所属＝full-login 応答）。
            //   BE は verify-device の full-login 応答に role を必ず載せる
            //   （js-office-api routes/auth.js:667 の res.json に role: chosen.role）。
            //   FIELD で扱えない役職なら保存も遷移もせず案内して留まる。
            if (!isFieldRole(recoverData['role'] as String?)) {
              await _rejectNonFieldRole();
              return;
            }
            // 保存・遷移は既存 _saveAndNavigate に一任（is_registered=true・.js_reg 再作成・
            // role 等サーバ真実の prefs 保存を含む）。
            await _saveAndNavigate(recoverData);
            return;
          }
          // 生体失敗/キャンセル → 既存の生体失敗画面（Retry＋PINフォールバック導線・袋小路なし）。
          // 生体不可端末は _doBiometric 内で _showPinLogin=true 済み → その場合は PIN 画面のまま。
          if (!_showPinLogin) {
            setState(() { _isLoading = false; _biometricFailed = true; _errorMessage = '認識に失敗しました。Retryしてください。'; });
          }
          return;
        }
        // 非200/timeout/例外 → 新規ユーザー/復帰失敗（＝サイレント復帰不成立）。
        // 上部ゲートは recoveryEligible でスキップ済みのため、ここで初めて同意ゲートを
        // 評価する（consent_agreed==false の時だけ ConsentScreen を表示）。
        if (!(prefs.getBool('consent_agreed') ?? false) && mounted) {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ConsentScreen(
              onAgreed: () {
                prefs.setBool('consent_agreed', true);
                prefs.setString('consent_version', '1.0');
                prefs.setString(
                    'consent_agreed_at', DateTime.now().toIso8601String());
              },
            ),
          ));
          if (!mounted) return;
        }
        // 従来通り登録/ランディング画面（device_id キャッシュは残置）
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _biometricThenLogin({bool resetPinState = false}) async {
    setState(() {
      _isLoading = true;
      _biometricFailed = false;
      if (resetPinState) _showPinLogin = false;
      _errorMessage = null;
    });
    final ok = await _doBiometric();
    if (!ok) {
      if (!_showPinLogin) {
        setState(() { _isLoading = false; _biometricFailed = true; _errorMessage = '認識に失敗しました。Retryしてください。'; });
      }
      return;
    }
    await _autoLogin();
  }

  Future<void> _autoLogin() async {
    bool serverResponded = false;
    try {
      final deviceId = await _getDeviceId();
      // 10秒を明示（サイレント復帰側の既定8秒とは別。丸めない）。
      final response = await AuthService()
          .verifyDevice(deviceId, timeout: const Duration(seconds: 10));
      // statusCode:0 だけが「サーバまで届かなかった」。非200はサーバが答えている
      // ＝移設前に `serverResponded = true` を置いていた位置と同じ意味。
      serverResponded = response.statusCode != 0;
      final data = response.data;
      if (response.statusCode == 200 && response.ok && data != null) {
        // 複数所属 → 選択フロー（従来経路は変更なし）
        if (data['requires_selection'] == true) {
          await _handleMembershipSelection(Map<String, dynamic>.from(data));
          return;
        }
        // ★role ガード（単一所属＝full-login 応答）。応答の role は
        //   js-office-api routes/auth.js:667（verify-device）が必ず載せる。
        if (!isFieldRole(data['role'] as String?)) {
          await _rejectNonFieldRole();
          return;
        }
        await _saveAndNavigate(data);
        return;
      }
    } catch (_) {}
    if (!serverResponded) {
      final prefs = await SharedPreferences.getInstance();
      final cachedToken = prefs.getString('auth_token') ?? '';
      if (cachedToken.isNotEmpty && mounted) {
        Navigator.of(context).pushReplacementNamed('/gate');
        return;
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _doLoginWithPin() async {
    final pin = _loginPinCtrl.text.trim();
    if (pin.length < 4) {
      setState(() => _errorMessage = 'PINを入力してください（4〜6桁）');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    {
      final deviceId = await _getDeviceId();
      final response = await AuthService().verifyPin(
        pin:        pin,
        deviceId:   deviceId,
        deviceName: Platform.isAndroid ? 'Android' : 'iPhone',
        deviceType: 'smartphone',
      );
      final data = response.data;
      if (response.statusCode == 200 && response.ok && data != null) {
        // 複数所属 → 選択フロー（従来経路は変更なし）
        if (data['requires_selection'] == true) {
          await _handleMembershipSelection(Map<String, dynamic>.from(data));
          return;
        }
        // ★role ガード（単一所属＝full-login 応答）。応答の role は
        //   js-office-api routes/auth.js:194（verify-pin）が必ず載せる。
        //   ★bossPinOk を立てるより【前】に置く。あちらはグローバル変数
        //     （main.dart:43）で prefs ではないが、弾いた回に副作用を1つも
        //     残さないため、判定の前に何も書かない順序にする。
        if (!isFieldRole(data['role'] as String?)) {
          await _rejectNonFieldRole();
          return;
        }
        final role = data['role'] as String? ?? 'worker';
        if (role == 'boss') {
          bossPinOk = true;
        }
        await _saveAndNavigate(data);
      } else if (response.statusCode == 0) {
        // 通信不成立。errorMessage は規約1の「サーバーに接続できません: $e」を
        // そのまま出す（画面側で prefix を重ねない＝理由を1回だけ言う）。
        setState(() { _isLoading = false; _errorMessage = response.errorMessage; });
      } else {
        setState(() { _isLoading = false; _errorMessage = response.errorMessage ?? 'PINが違います'; });
      }
    }
  }

  // ─── 自己登録（仮登録申請）────────────────────────────────
  Future<void> _selfRegister() async {
    final ownCompany     = _ownCompanyCtrl.text.trim();
    final name           = _nameCtrl.text.trim();
    final partnerCompany = _partnerCompanyCtrl.text.trim();
    final companyCode    = _companyCodeCtrl.text.trim().toUpperCase();

    if (ownCompany.isEmpty) {
      setState(() => _errorMessage = '自社の会社名を入力してください');
      return;
    }
    if (name.isEmpty) {
      setState(() => _errorMessage = '氏名を入力してください');
      return;
    }
    setState(() => _errorMessage = null);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '仮登録として申請します',
          style: TextStyle(color: FieldTokens.accent, fontSize: 16),
        ),
        content: const Text(
          '職長・事務スタッフに通知されます\n承認後にフル機能が使えます\nよろしいですか？',
          style: TextStyle(color: FieldTokens.textBody, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: FieldTokens.textSupport)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: FieldTokens.accent,
              foregroundColor: FieldTokens.onAccent,
            ),
            child: const Text('確認'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final deviceId   = await _getDeviceId();
      final deviceName = Platform.isAndroid ? 'Android' : 'iPhone';
      final res = await WorkerService().selfRegister(
        name:               name,
        ownCompanyName:     ownCompany,
        // 空文字は null で送る（BE にとって別の意味）＝移設前と同じ判定を画面に残す。
        partnerCompanyName: partnerCompany.isNotEmpty ? partnerCompany : null,
        companyCode:        companyCode.isNotEmpty ? companyCode : null,
        deviceId:           deviceId,
        deviceName:         deviceName,
      );

      if (!mounted) return;

      final body = res.data ?? const <String, dynamic>{};
      if (res.ok && (res.statusCode == 200 || res.statusCode == 201)) {
        final token = body['token'] as String?;
        if (token != null && token.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', token);
          await prefs.setString('user_name',  name);
          await prefs.setString('user_role',  'worker');
          await prefs.setString('device_id',  deviceId);
          await prefs.setBool('is_registered', true);
          // self-register（主経路）は token と共に worker_id を返す（BE workers.js:353）→ prefs へ保存
          final wid = body['worker_id'] as String?;
          if (wid != null && wid.isNotEmpty) {
            await prefs.setString('worker_id', wid);
          }
          await _writePersistentRegistered();
        }
        if (!mounted) return;
        // already_registered: true でも PendingApprovalScreen へ（ゲートUIはフェーズ2）
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PendingApprovalScreen()),
        );
      } else {
        // statusCode:0（通信不成立）は規約1の「サーバーに接続できません: $e」を
        // そのまま出す（画面側で prefix を重ねない＝理由を1回だけ言う）。
        // 非200 は BE の error 文字列（errorMessage が同じ出所で運ぶ）。
        final errMsg = res.errorMessage ?? '登録に失敗しました';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errMsg),
            backgroundColor: FieldTokens.statusError,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── requires_selection（複数所属）対応：A案＝アプリ側フィルタ＋自動昇格 ──
  //
  // verify-pin / verify-device が requires_selection:true を返したとき、3経路
  //（_autoLogin / _doLoginWithPin / F5サイレント復帰）から本関数へ委譲する。
  // pre_auth_token はメモリ（_preAuthToken）にのみ保持し prefs には保存しない。
  Future<void> _handleMembershipSelection(Map<String, dynamic> data) async {
    _preAuthToken = data['pre_auth_token'] as String?;

    // memberships[] を FIELD 用にフィルタ（絞り込みは field_role_gate.dart に1つだけ）。
    final field = filterFieldMemberships(data['memberships']);

    // pre_auth_token が無い異常応答 → 袋小路回避でログイン画面へ（prefs は触らない）。
    if (_preAuthToken == null || _preAuthToken!.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _showPinLogin = false;
          _biometricFailed = false;
          _errorMessage = 'ログインに失敗しました。もう一度お試しください';
        });
      }
      return;
    }

    // フィルタ後 0件 → OFFICE 案内ダイアログ → 閉じたらログイン画面に留まる（prefs 保存なし）。
    if (field.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _showPinLogin = false;
        _biometricFailed = false;
      });
      await showOfficeOnlyDialog(context);
      _preAuthToken = null;
      return;
    }

    // フィルタ後 1件 → 選択画面を出さず自動で select-membership（自動昇格）。
    if (field.length == 1) {
      final id = field.first['membership_id'] as String?;
      if (id == null || id.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _showPinLogin = false;
            _biometricFailed = false;
            _errorMessage = '所属情報が不正です。もう一度お試しください';
          });
        }
        _preAuthToken = null;
        return;
      }
      await _autoSelectMembership(id);
      return;
    }

    // フィルタ後 2件以上 → 選択画面へ遷移。
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _showPinLogin = false;
      _biometricFailed = false;
    });
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => MembershipSelectScreen(
          preAuthToken: _preAuthToken!,
          memberships: field,
        ),
      ),
    );
    // 選択画面が full-login 応答を返したら保存＆/gate。null（戻る/失効/失敗）ならログインに留まる。
    if (result != null) {
      await _finishMembershipLogin(result);
    } else {
      _preAuthToken = null;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 自動昇格（フィルタ後1件）専用の select-membership 呼び出し。選択画面は表示しない。
  Future<void> _autoSelectMembership(String membershipId) async {
    final token = _preAuthToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _showPinLogin = false;
          _errorMessage = 'ログインに失敗しました。もう一度お試しください';
        });
      }
      return;
    }
    if (mounted) setState(() { _isLoading = true; _errorMessage = null; });
    {
      final res = await AuthService().selectMembership(
        preAuthToken: token,
        membershipId: membershipId,
      );

      final data = res.data;
      if (res.statusCode == 200 && res.ok && data != null) {
        await _finishMembershipLogin(data);
        return;
      }

      _preAuthToken = null; // 失敗時は失効扱いで破棄
      if (res.statusCode == 401) {
        // pre_auth 失効（TOKEN_EXPIRED / BE auth.js:255）→ 時間切れ案内 → ログインへ戻す。
        if (!mounted) return;
        setState(() { _isLoading = false; _showPinLogin = false; });
        await _showMembershipTimeoutDialog();
        return;
      }
      // その他（400/403/500 等）→ エラー表示＋ログイン画面へ（袋小路なし）。
      // statusCode:0（通信不成立）も同じ枝に入る＝規約1の
      // 「サーバーに接続できません: $e」をそのまま出す（prefix を重ねない）。
      final serverMsg = res.errorMessage;
      final String msg;
      if (serverMsg != null && serverMsg.isNotEmpty) {
        msg = serverMsg;
      } else {
        msg = '所属の選択に失敗しました。もう一度お試しください';
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _showPinLogin = false;
          _errorMessage = msg;
        });
      }
    }
  }

  // select-membership 成功応答（full-login）を保存し /gate へ。
  // 保存は既存 _saveAndNavigate を再利用（同意束の救済刻印・version 判定を重複実装しない）。
  Future<void> _finishMembershipLogin(Map<String, dynamic> data) async {
    _preAuthToken = null; // 用済み・メモリからも破棄
    // ★保存前の再検査。ここへ来る membership_id は _handleMembershipSelection が
    //   worker/boss で絞った中から選ばれているが、絞ったのは【verify 応答に載っていた
    //   memberships[] のスナップショット】であって、select-membership が返す role が
    //   サーバの最終真実である（js-office-api routes/auth.js:318 が m.role を返す）。
    //   その2つがずれた場合（選択中に役職が変わった等）に備え、保存の直前でもう一度見る。
    //   OFFICE 側も同じ位置に同じ再検査を置いている
    //   （js_office_app .../login_screen.dart:520 の「門番A（保存前）」）。
    if (!isFieldRole(data['role'] as String?)) {
      await _rejectNonFieldRole();
      return;
    }
    // boss は _doLoginWithPin と同じく bossPinOk を立てる（ゲート整合）。
    final role = data['role'] as String? ?? 'worker';
    if (role == 'boss') {
      bossPinOk = true;
    }
    await _saveAndNavigate(data);
  }

  // pre_auth 失効時（自動昇格経路）の案内ダイアログ。閉じたらログイン画面に留まる。
  Future<void> _showMembershipTimeoutDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: FieldTokens.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('時間切れです',
            style: TextStyle(color: FieldTokens.accent, fontSize: 16)),
        content: const Text('もう一度ログインしてください',
            style: TextStyle(color: FieldTokens.textBody, height: 1.7)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: FieldTokens.accent,
              foregroundColor: FieldTokens.onAccent,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ─── FIELD で扱えない役職だったときの共通処理 ───────────────────────
  //
  // ★ダイアログ本体は lib/utils/field_role_gate.dart へ移設した（画面ごとに作らない）。
  //   文言・見た目・barrierDismissible:false は移設前と同一。
  //
  // ★呼んだら必ず即 return すること。この先で _saveAndNavigate を呼んではいけない。
  //   prefs / .js_reg / device_id へ書くのは _saveAndNavigate ただ一つなので、
  //   その手前で止めれば端末には何も残らない（下の「保存しない」の根拠）。
  //
  // ★状態の戻し方は複数所属経路の「フィルタ後0件」枝と同一にする
  //   （_isLoading / _showPinLogin / _biometricFailed を全て false）。
  //   3つとも false になると build() は最後まで落ちてランディング画面を返す＝
  //   PIN入力・招待コード登録・機種変更の導線が並ぶ画面に戻る。よって袋小路にならない。
  //   ★_errorMessage は触らない。0件枝も触っておらず、ここだけ挙動を変えないため。
  Future<void> _rejectNonFieldRole() async {
    if (!mounted) return;
    setState(() {
      _isLoading       = false;
      _showPinLogin    = false;
      _biometricFailed = false;
    });
    await showOfficeOnlyDialog(context);
    // pre_auth_token を持っている経路（選択フロー経由）でも確実に捨てる。
    _preAuthToken = null;
  }

  Future<void> _saveAndNavigate(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token',  data['token']      as String? ?? '');
    await prefs.setString('user_name',   data['name']       as String? ?? '');
    await prefs.setString('user_role',   data['role']       as String? ?? 'worker');
    await prefs.remove('role'); // 旧 'role' キーの残骸掃除（二重キー統一）
    await prefs.setString('company_id',  data['company_id'] as String? ?? '');
    await prefs.setString('company_name', data['company_name'] as String? ?? '');
    await prefs.setString('work_mode',   data['work_mode']  as String? ?? 'deemed');
    await prefs.setString('user_id',     data['user_id']    as String? ?? '');
    // 同意証跡はサーバ真実に一本化: サーバ値が非null/非空の時だけ保存（毎回 now() 上書きを廃止）。
    final serverConsentAt  = data['consent_agreed_at'] as String?;
    final serverConsentVer = data['consent_version']   as String?;
    if (serverConsentAt != null && serverConsentAt.isNotEmpty) {
      await prefs.setString('consent_agreed_at', serverConsentAt);
    }
    if (serverConsentVer != null && serverConsentVer.isNotEmpty) {
      await prefs.setString('consent_version', serverConsentVer);
    }
    // 規約バージョン不一致（サーバ値が非null かつ現行と不一致）の時だけ次回起動で再同意させる。
    // それ以外の理由で consent_agreed を false に戻さない（毎回同意の復活防止）。
    if (serverConsentVer != null && serverConsentVer.isNotEmpty
        && serverConsentVer != _kCurrentConsentVersion) {
      await prefs.setBool('consent_agreed', false);
    }
    await prefs.setBool('is_registered', true);
    // 既存ユーザー救済刻印: サーバが consent_agreed_at=null を返し、かつローカルで同意済みなら、
    // 受領した本token で POST /auth/consent を1回呼びサーバに正式刻印する（fail-open・8秒）。
    final localAgreed = prefs.getBool('consent_agreed') ?? false;
    final consentToken = data['token'] as String? ?? '';
    if ((serverConsentAt == null || serverConsentAt.isEmpty)
        && localAgreed && consentToken.isNotEmpty) {
      // fail-open: 結果を見るのは 200 のときだけ。失敗は無視（次回ログインで再試行）。
      final cRes = await AuthService().consent(
        consentToken:   consentToken,
        consentVersion: _kCurrentConsentVersion,
      );
      final cd = cRes.data;
      if (cRes.statusCode == 200 && cRes.ok && cd != null) {
        final cAt  = cd['consent_agreed_at'] as String?;
        final cVer = cd['consent_version']   as String?;
        if (cAt  != null && cAt.isNotEmpty)  await prefs.setString('consent_agreed_at', cAt);
        if (cVer != null && cVer.isNotEmpty) await prefs.setString('consent_version', cVer);
      }
    }
    // 呼び出し元により worker_id 有無が異なる: verify-pin(BE auth.js:184)/select-membership(:297)は返す、
    // verify-device(:592)は BE 未返却。含む経路のみ保存されるよう null/空はスキップする。
    final wid = data['worker_id'] as String?;
    if (wid != null && wid.isNotEmpty) {
      await prefs.setString('worker_id', wid);
    }
    String deviceId = prefs.getString('device_id') ?? '';
    if (deviceId.isEmpty) {
      deviceId = await _getDeviceId();
      await prefs.setString('device_id', deviceId);
    }
    await _writePersistentRegistered();
    // FCM token 取得・POST はホーム画面で権限取得後に行う
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/gate');
  }

  // ─── build ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: FieldTokens.bgBase,
        body: Center(child: CircularProgressIndicator(color: FieldTokens.accent)),
      );
    }
    if (_showPinLogin) return _buildPinLoginScreen();
    if (_biometricFailed) {
      return Scaffold(
        backgroundColor: FieldTokens.bgBase,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.fingerprint, color: FieldTokens.accent, size: 80),
              const SizedBox(height: 24),
              const Text('Login',
                  style: TextStyle(color: FieldTokens.textBody, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_errorMessage ?? '',
                  style: const TextStyle(color: FieldTokens.textSupport),
                  textAlign: TextAlign.center),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _biometricThenLogin,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Retry'),
                // 生成り抜き（画面内の主ボタン）
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: FieldTokens.textBody,
                    side: const BorderSide(
                        color: FieldTokens.textBody, width: 1.5),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _biometricFailed = false;
                  _showPinLogin = true;
                }),
                icon: const Icon(Icons.lock_outline, color: FieldTokens.accent),
                label: const Text('PIN入力',
                    style: TextStyle(color: FieldTokens.accent)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: FieldTokens.accent),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RecoveryScreen()),
                ),
                child: const Text('機種変更（新しいデバイスで再登録）',
                    style: TextStyle(color: FieldTokens.textSupport, fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }

    // ─── 新設計ランディングページ ─────────────────────────────
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── ヘッダー ─────────────────────────────────
              const Text(
                '株式会社J\'s',
                style: TextStyle(
                  color: FieldTokens.accent,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                '勤務管理システム',
                style: TextStyle(color: FieldTokens.textSupport, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // ── ログイン ─────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _biometricThenLogin(resetPinState: true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: FieldTokens.accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: FieldTokens.outline),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('生体認証',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        _showPinLogin = true;
                        _errorMessage = null;
                      }),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: FieldTokens.accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: FieldTokens.outline),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('PIN入力',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RecoveryScreen()),
                  ),
                  child: const Text('機種変更・再インストールの方はこちら',
                      style: TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
                ),
              ),
              const SizedBox(height: 40),

              // ── はじめての方 セクション ──────────────────
              const Row(children: [
                Expanded(child: Divider(color: FieldTokens.outline)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text('はじめての方',
                      style: TextStyle(color: FieldTokens.textSupport, fontSize: 13)),
                ),
                Expanded(child: Divider(color: FieldTokens.outline)),
              ]),
              const SizedBox(height: 24),

              // ── 招待コード入力（6桁・大字中央）──────────
              TextField(
                controller: _landingInviteCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: FieldTokens.textBody,
                  fontSize: 32,
                  letterSpacing: 14,
                  fontWeight: FontWeight.bold,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '● ● ● ●',
                  hintStyle: const TextStyle(
                      color: FieldTokens.textHint, letterSpacing: 8, fontSize: 24),
                  filled: true,
                  fillColor: FieldTokens.surfaceRaised,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: FieldTokens.accent, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '管理者から受け取った6桁の番号を入れてください',
                style: TextStyle(color: FieldTokens.textSupport, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    final code = _landingInviteCtrl.text.trim();
                    if (code.length < 6) {
                      setState(() => _errorMessage = '6桁の番号を入力してください');
                      return;
                    }
                    setState(() => _errorMessage = null);
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RegisterScreen(initialInviteCode: code),
                    ));
                  },
                  // 生成り抜き（画面内の主ボタン）
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: FieldTokens.textBody,
                    side: const BorderSide(
                        color: FieldTokens.textBody, width: 1.5),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('次へ（PIN設定）',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 32),

              // ── 応急登録リンク（薄いゴールド・最下部）────
              Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    _showSelfReg = !_showSelfReg;
                    _errorMessage = null;
                  }),
                  style: TextButton.styleFrom(
                    foregroundColor: FieldTokens.textSupport,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    '招待コードがない方（応急登録）',
                    style: TextStyle(
                      color: FieldTokens.textSupport,
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
              ),

              // ── 応急登録フォーム（展開式・リンクで開閉）──
              if (_showSelfReg) ...[
                const SizedBox(height: 16),
                _regField(
                  controller: _companyCodeCtrl,
                  label: '会社コード（わかる方のみ）',
                ),
                const SizedBox(height: 14),
                _regField(
                  controller: _partnerCompanyCtrl,
                  label: '協力先の業者名（自社で働く方は未記入でOK）',
                  showMic: true,
                ),
                const SizedBox(height: 14),
                _regField(
                  controller: _ownCompanyCtrl,
                  label: '自社の会社名',
                  showMic: true,
                ),
                const SizedBox(height: 14),
                _regField(
                  controller: _nameCtrl,
                  label: '氏名',
                  showMic: true,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _selfRegister,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FieldTokens.surfaceCard,
                      foregroundColor: FieldTokens.accent,
                      side: const BorderSide(color: FieldTokens.accent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('仮登録する',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: FieldTokens.statusError.withValues(alpha: 0.1),
                    border: Border.all(color: FieldTokens.statusError),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_errorMessage!,
                      style: const TextStyle(
                          color: FieldTokens.statusError, fontSize: 13)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _regField({
    required TextEditingController controller,
    required String label,
    bool showMic = false,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: FieldTokens.textBody),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: FieldTokens.textSupport, fontSize: 13),
        prefixIcon: const Icon(Icons.edit_note, color: FieldTokens.textSupport),
        suffixIcon: showMic
            ? const Icon(Icons.mic_none, color: FieldTokens.textSupport)
            : null,
        filled: true,
        fillColor: FieldTokens.surfaceRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: FieldTokens.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: FieldTokens.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: FieldTokens.accent, width: 2),
        ),
      ),
    );
  }

  // ─── PIN ログイン画面 ─────────────────────────────────────
  Widget _buildPinLoginScreen() {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: _isUpdateRecovery
          ? null
          : AppBar(
              backgroundColor: FieldTokens.bgBase,
              foregroundColor: FieldTokens.accent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _showPinLogin = false;
                  _errorMessage = null;
                  _loginPinCtrl.clear();
                }),
              ),
            ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, color: FieldTokens.accent, size: 64),
              const SizedBox(height: 24),
              const Text('PINでログイン',
                  style: TextStyle(
                      color: FieldTokens.textBody,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_isUpdateRecovery) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: FieldTokens.surfaceRaised,
                    border:
                        Border.all(color: FieldTokens.accent, width: 1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'アプリのアップデートのため、\nPINコードでの再認証が必要です',
                    style: TextStyle(
                        color: FieldTokens.accent, fontSize: 13, height: 1.6),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
              ] else ...[
                const Text('登録済みのPINを入力してください',
                    style: TextStyle(
                        color: FieldTokens.textSupport, fontSize: 13)),
                const SizedBox(height: 40),
              ],
              TextField(
                controller: _loginPinCtrl,
                obscureText: _obscureLoginPin,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(
                    color: FieldTokens.textBody, fontSize: 24, letterSpacing: 8),
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '● ● ● ●',
                  hintStyle: const TextStyle(
                      color: FieldTokens.textHint, letterSpacing: 8),
                  filled: true,
                  fillColor: FieldTokens.surfaceRaised,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: FieldTokens.accent, width: 2)),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscureLoginPin
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: FieldTokens.textSupport),
                    onPressed: () =>
                        setState(() => _obscureLoginPin = !_obscureLoginPin),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!,
                    style: const TextStyle(
                        color: FieldTokens.statusError, fontSize: 13),
                    textAlign: TextAlign.center),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _doLoginWithPin,
                  // 生成り抜き（画面内の主ボタン）
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: FieldTokens.textBody,
                    disabledBackgroundColor: Colors.transparent,
                    disabledForegroundColor:
                        FieldTokens.textFaint,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ).copyWith(
                    side: WidgetStateProperty.resolveWith((states) =>
                        BorderSide(
                          color: states.contains(WidgetState.disabled)
                              ? FieldTokens.textFaint
                              : FieldTokens.textBody,
                          width: 1.5,
                        )),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          // 面が透明になったのでスピナーも枠色（生成り）へ
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: FieldTokens.textFaint))
                      : const Text('ログイン',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
