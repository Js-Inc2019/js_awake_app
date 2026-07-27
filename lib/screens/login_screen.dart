// ============================================================
// lib/screens/login_screen.dart - 新設計ログイン画面
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'consent_screen.dart';
import 'pending_approval_screen.dart';
import 'register_screen.dart';
import 'recovery_screen.dart';
import 'membership_select_screen.dart';
import '../config/constants.dart';
import '../utils/device_id.dart';
import '../main.dart' show bossPinOk;
import '../core/theme/js_colors.dart';

const String _apiBase = kApiBaseUrl;

// 現行の利用規約バージョン（BE の CURRENT_CONSENT_VERSION と同値）。
// ※ login_screen は recovery_screen を import するため、公開名の衝突回避で
//   library-private 定数（先頭 _）にしている。
const String _kCurrentConsentVersion = '1.0';

// ─── 配色は lib/core/theme/js_colors.dart のトークンへ統一（画面ローカル定数は撤去）─────

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

  // PIN設定ステップ（Sign Up後 — 旧フロー互換）
  final int _step = 0;
  Map<String, dynamic>? _pendingData;
  final _pinCtrl     = TextEditingController();
  final _pinConfCtrl = TextEditingController();
  bool _obscurePin  = true;
  bool _obscureConf = true;

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
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.orange,
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
    _pinCtrl.dispose();
    _pinConfCtrl.dispose();
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

  Future<void> _warmUpServer() async {
    for (int i = 0; i < 3; i++) {
      try {
        final res = await http.get(Uri.parse(kHealthUrl))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) return;
      } catch (_) {}
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
      final deviceId = await _getDeviceId();
      try {
        // 単一の顔の掟: verify-token は body の device_id 必須（未送信は 400 DEVICE_ID_REQUIRED）
        final response = await http.post(
          Uri.parse('$_apiBase/auth/verify-token'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $cachedToken',
          },
          body: jsonEncode({'device_id': deviceId}),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          try {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            // サーバ真実（DBの role/worker_id/user_id）を毎回 prefs へ上書き保存してから /gate へ
            final user = data['user'];
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
          } catch (_) {}
          if (mounted) Navigator.of(context).pushReplacementNamed('/gate');
          return;
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          // 掟違反系（ANCHOR_MISMATCH / DEVICE_NOT_FOUND / MEMBERSHIP_INVALID /
          // LEGACY_TOKEN / TOKEN_EXPIRED / INVALID_TOKEN_SCOPE / COOPERATION_PENDING）
          // → トークン破棄し、必ずログイン手段のある画面へ導く（袋小路禁止）
          String? errCode;
          try {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            errCode = (data['code'] ?? data['error']) as String?;
          } catch (_) {}
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
        // 400 DEVICE_ID_REQUIRED / 503 AUTH_DB_ERROR / その他 →
        // 一時障害の可能性。auth_token は消さずPIN画面へフォールバック
        if (mounted) setState(() { _showPinLogin = true; _isLoading = false; });
        return;
      } catch (e) {
        // タイムアウト・通信例外 → auth_token は消さずPIN画面へフォールバック
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
        try {
          final deviceId = await _getDeviceId(); // 復元トライ（device_id.dart は変更せず流用）
          if (deviceId.isNotEmpty) {
            final res = await http.get(
              Uri.parse('$_apiBase/auth/verify-device?device_id=$deviceId'),
              headers: {'Content-Type': 'application/json'},
            ).timeout(const Duration(seconds: 8));
            if (res.statusCode == 200) {
              recoverData = jsonDecode(res.body) as Map<String, dynamic>;
            }
          }
        } catch (_) {
          recoverData = null; // タイムアウト・通信例外 → 従来の登録画面へ
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
      final response = await http.get(
        Uri.parse('$_apiBase/auth/verify-device?device_id=$deviceId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      serverResponded = true;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // 複数所属 → 選択フロー（従来経路は変更なし）
        if (data is Map && data['requires_selection'] == true) {
          await _handleMembershipSelection(Map<String, dynamic>.from(data));
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

  Future<void> _setupPin() async {
    final pin  = _pinCtrl.text;
    final conf = _pinConfCtrl.text;
    if (pin.length < 4 || pin.length > 6) {
      setState(() => _errorMessage = 'PINは4〜6桁で入力してください');
      return;
    }
    if (pin != conf) {
      setState(() => _errorMessage = 'PINが一致しません');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final token = _pendingData!['token'] as String;
      final response = await http.post(
        Uri.parse('$_apiBase/auth/setup-pin'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'new_pin': pin}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: JsColors.surface,
            title: const Row(children: [
              Icon(Icons.warning_amber, color: JsColors.accent),
              SizedBox(width: 8),
              Flexible(child: Text('PINコードを必ず記録してください',
                style: TextStyle(color: JsColors.textStrong, fontSize: 15))),
            ]),
            content: const Text(
              'PINコードを忘れた場合、\nログインできなくなります。\n\nメモ帳などに必ず控えてから\n次へ進んでください。',
              style: TextStyle(color: JsColors.textStrong, height: 1.7)),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _saveAndNavigate(_pendingData!);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: JsColors.accent,
                  foregroundColor: JsPalette.onAccent),
                child: const Text('記録しました。次へ進む',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      } else {
        final data = jsonDecode(response.body);
        setState(() { _isLoading = false; _errorMessage = data['error'] ?? 'PIN設定に失敗しました'; });
      }
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = 'ネットワークエラー: $e'; });
    }
  }

  Future<void> _doLoginWithPin() async {
    final pin = _loginPinCtrl.text.trim();
    if (pin.length < 4) {
      setState(() => _errorMessage = 'PINを入力してください（4〜6桁）');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final deviceId = await _getDeviceId();
      final response = await http.post(
        Uri.parse('$_apiBase/auth/verify-pin'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pin': pin,
          'device_id': deviceId,
          'device_name': Platform.isAndroid ? 'Android' : 'iPhone',
          'device_type': 'smartphone',
        }),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        // 複数所属 → 選択フロー（従来経路は変更なし）
        if (data is Map && data['requires_selection'] == true) {
          await _handleMembershipSelection(Map<String, dynamic>.from(data));
          return;
        }
        final role = data['role'] as String? ?? 'worker';
        if (role == 'boss') {
          bossPinOk = true;
        }
        await _saveAndNavigate(data);
      } else {
        setState(() { _isLoading = false; _errorMessage = data['error'] ?? 'PINが違います'; });
      }
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = 'ネットワークエラー: $e'; });
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
        backgroundColor: JsColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '仮登録として申請します',
          style: TextStyle(color: JsColors.accent, fontSize: 16),
        ),
        content: const Text(
          '職長・事務スタッフに通知されます\n承認後にフル機能が使えます\nよろしいですか？',
          style: TextStyle(color: JsColors.textStrong, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: JsColors.textMid)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: JsColors.accent,
              foregroundColor: JsPalette.onAccent,
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
      final res = await http.post(
        Uri.parse('$_apiBase/workers/self-register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name':                 name,
          'own_company_name':     ownCompany,
          'partner_company_name': partnerCompany.isNotEmpty ? partnerCompany : null,
          'company_code':         companyCode.isNotEmpty ? companyCode : null,
          'device_id':            deviceId,
          'device_name':          deviceName,
        }),
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 || res.statusCode == 201) {
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
        final errMsg = body['error'] as String? ?? '登録に失敗しました';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errMsg),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('通信エラー: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
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

    // memberships[] を FIELD 用にフィルタ: role が 'worker' または 'boss' のみ残す。
    final rawList = data['memberships'];
    final all = (rawList is List) ? rawList.whereType<Map>() : const <Map>[];
    final field = all
        .where((m) {
          final role = m['role'] as String?;
          return role == 'worker' || role == 'boss';
        })
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

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
      await _showOfficeOnlyDialog();
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
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/auth/select-membership'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pre_auth_token': token,
          'membership_id': membershipId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
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
      String msg = '所属の選択に失敗しました。もう一度お試しください';
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final serverMsg = body['error'] as String?;
        if (serverMsg != null && serverMsg.isNotEmpty) msg = serverMsg;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isLoading = false;
          _showPinLogin = false;
          _errorMessage = msg;
        });
      }
    } catch (e) {
      _preAuthToken = null;
      if (mounted) {
        setState(() {
          _isLoading = false;
          _showPinLogin = false;
          _errorMessage = 'ネットワークエラー: $e';
        });
      }
    }
  }

  // select-membership 成功応答（full-login）を保存し /gate へ。
  // 保存は既存 _saveAndNavigate を再利用（同意束の救済刻印・version 判定を重複実装しない）。
  Future<void> _finishMembershipLogin(Map<String, dynamic> data) async {
    _preAuthToken = null; // 用済み・メモリからも破棄
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
        backgroundColor: JsColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('時間切れです',
            style: TextStyle(color: JsColors.accent, fontSize: 16)),
        content: const Text('もう一度ログインしてください',
            style: TextStyle(color: JsColors.textStrong, height: 1.7)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: JsColors.accent,
              foregroundColor: JsPalette.onAccent,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // フィルタ後 0件（FIELD 用の役割なし）→ OFFICE アプリへ案内。閉じたらログイン画面に留まる。
  Future<void> _showOfficeOnlyDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: JsColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ご案内',
            style: TextStyle(color: JsColors.accent, fontSize: 16)),
        content: const Text('この端末の役割はOFFICEアプリをご利用ください',
            style: TextStyle(color: JsColors.textStrong, height: 1.7)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: JsColors.accent,
              foregroundColor: JsPalette.onAccent,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
      try {
        final cRes = await http.post(
          Uri.parse('$_apiBase/auth/consent'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $consentToken',
          },
          body: jsonEncode({'consent_version': _kCurrentConsentVersion}),
        ).timeout(const Duration(seconds: 8));
        if (cRes.statusCode == 200) {
          final cd = jsonDecode(cRes.body) as Map<String, dynamic>;
          final cAt  = cd['consent_agreed_at'] as String?;
          final cVer = cd['consent_version']   as String?;
          if (cAt  != null && cAt.isNotEmpty)  await prefs.setString('consent_agreed_at', cAt);
          if (cVer != null && cVer.isNotEmpty) await prefs.setString('consent_version', cVer);
        }
      } catch (_) { /* fail-open: 失敗は無視（次回ログインで再試行） */ }
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
        backgroundColor: JsColors.background,
        body: Center(child: CircularProgressIndicator(color: JsColors.accent)),
      );
    }
    if (_step == 1) return _buildPinSetupScreen();
    if (_showPinLogin) return _buildPinLoginScreen();
    if (_biometricFailed) {
      return Scaffold(
        backgroundColor: JsColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.fingerprint, color: JsColors.accent, size: 80),
              const SizedBox(height: 24),
              const Text('Login',
                  style: TextStyle(color: JsColors.textStrong, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_errorMessage ?? '',
                  style: const TextStyle(color: JsColors.textMid),
                  textAlign: TextAlign.center),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _biometricThenLogin,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Retry'),
                // 生成り抜き（画面内の主ボタン）
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: JsFormTokens.outlineButtonBorder,
                    side: const BorderSide(
                        color: JsFormTokens.outlineButtonBorder, width: 1.5),
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
                icon: const Icon(Icons.lock_outline, color: JsColors.accent),
                label: const Text('PIN入力',
                    style: TextStyle(color: JsColors.accent)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: JsColors.accent),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RecoveryScreen()),
                ),
                child: const Text('機種変更（新しいデバイスで再登録）',
                    style: TextStyle(color: JsColors.textMid, fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }

    // ─── 新設計ランディングページ ─────────────────────────────
    return Scaffold(
      backgroundColor: JsColors.background,
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
                  color: JsColors.accent,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                '勤務管理システム',
                style: TextStyle(color: JsColors.textMid, fontSize: 16),
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
                        foregroundColor: JsColors.accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: JsColors.border),
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
                        foregroundColor: JsColors.accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: JsColors.border),
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
                      style: TextStyle(color: JsColors.textMid, fontSize: 13)),
                ),
              ),
              const SizedBox(height: 40),

              // ── はじめての方 セクション ──────────────────
              const Row(children: [
                Expanded(child: Divider(color: JsColors.border)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text('はじめての方',
                      style: TextStyle(color: JsColors.textMid, fontSize: 13)),
                ),
                Expanded(child: Divider(color: JsColors.border)),
              ]),
              const SizedBox(height: 24),

              // ── 招待コード入力（6桁・大字中央）──────────
              TextField(
                controller: _landingInviteCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: JsColors.textStrong,
                  fontSize: 32,
                  letterSpacing: 14,
                  fontWeight: FontWeight.bold,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '● ● ● ●',
                  hintStyle: const TextStyle(
                      color: JsColors.hint, letterSpacing: 8, fontSize: 24),
                  filled: true,
                  fillColor: JsColors.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: JsColors.accent, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '管理者から受け取った6桁の番号を入れてください',
                style: TextStyle(color: JsColors.textMid, fontSize: 12),
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
                    foregroundColor: JsFormTokens.outlineButtonBorder,
                    side: const BorderSide(
                        color: JsFormTokens.outlineButtonBorder, width: 1.5),
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
                    foregroundColor: JsColors.textMid,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    '招待コードがない方（応急登録）',
                    style: TextStyle(
                      color: JsColors.textMid,
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
                      backgroundColor: JsColors.surface,
                      foregroundColor: JsColors.accent,
                      side: const BorderSide(color: JsColors.accent),
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
                    color: Colors.red.withValues(alpha: 0.1),
                    border: Border.all(color: Colors.red),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_errorMessage!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13)),
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
      style: const TextStyle(color: JsColors.textStrong),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: JsColors.textMid, fontSize: 13),
        prefixIcon: const Icon(Icons.edit_note, color: JsColors.textMid),
        suffixIcon: showMic
            ? const Icon(Icons.mic_none, color: JsColors.textMid)
            : null,
        filled: true,
        fillColor: JsColors.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: JsColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: JsColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: JsColors.accent, width: 2),
        ),
      ),
    );
  }

  // ─── PIN ログイン画面 ─────────────────────────────────────
  Widget _buildPinLoginScreen() {
    return Scaffold(
      backgroundColor: JsColors.background,
      appBar: _isUpdateRecovery
          ? null
          : AppBar(
              backgroundColor: JsColors.background,
              foregroundColor: JsColors.accent,
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
              const Icon(Icons.lock_outline, color: JsColors.accent, size: 64),
              const SizedBox(height: 24),
              const Text('PINでログイン',
                  style: TextStyle(
                      color: JsColors.textStrong,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_isUpdateRecovery) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: JsColors.surfaceAlt,
                    border:
                        Border.all(color: JsColors.accent, width: 1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'アプリのアップデートのため、\nPINコードでの再認証が必要です',
                    style: TextStyle(
                        color: JsColors.accent, fontSize: 13, height: 1.6),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
              ] else ...[
                const Text('登録済みのPINを入力してください',
                    style: TextStyle(
                        color: JsColors.textMid, fontSize: 13)),
                const SizedBox(height: 40),
              ],
              TextField(
                controller: _loginPinCtrl,
                obscureText: _obscureLoginPin,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(
                    color: JsColors.textStrong, fontSize: 24, letterSpacing: 8),
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '● ● ● ●',
                  hintStyle: const TextStyle(
                      color: JsColors.hint, letterSpacing: 8),
                  filled: true,
                  fillColor: JsColors.surfaceAlt,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: JsColors.accent, width: 2)),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscureLoginPin
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: JsColors.textMid),
                    onPressed: () =>
                        setState(() => _obscureLoginPin = !_obscureLoginPin),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 13),
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
                    foregroundColor: JsFormTokens.outlineButtonBorder,
                    disabledBackgroundColor: Colors.transparent,
                    disabledForegroundColor:
                        JsFormTokens.outlineButtonDisabled,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ).copyWith(
                    side: WidgetStateProperty.resolveWith((states) =>
                        BorderSide(
                          color: states.contains(WidgetState.disabled)
                              ? JsFormTokens.outlineButtonDisabled
                              : JsFormTokens.outlineButtonBorder,
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
                              color: JsFormTokens.outlineButtonDisabled))
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

  // ─── PIN 設定画面（旧フロー互換）────────────────────────────
  Widget _buildPinSetupScreen() {
    return Scaffold(
      backgroundColor: JsColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('株式会社J\'s',
                  style: TextStyle(
                      color: JsPalette.brand,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('勤務管理システム',
                  style: TextStyle(color: JsColors.textStrong, fontSize: 16)),
              const SizedBox(height: 40),
              const Text('PINを設定',
                  style: TextStyle(
                      color: JsPalette.accentDeep,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('ログイン時に使用するPIN（4〜6桁）を設定してください',
                  style: TextStyle(color: JsColors.textMid, fontSize: 13)),
              const SizedBox(height: 28),
              TextField(
                controller: _pinCtrl,
                obscureText: _obscurePin,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: JsColors.textStrong),
                decoration: InputDecoration(
                  labelText: 'PIN（4〜6桁）',
                  labelStyle: const TextStyle(color: JsColors.textMid),
                  prefixIcon:
                      const Icon(Icons.lock, color: JsColors.textMid),
                  counterText: '',
                  enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: JsColors.border),
                      borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: JsColors.accent),
                      borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscurePin
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: JsColors.textMid),
                    onPressed: () =>
                        setState(() => _obscurePin = !_obscurePin),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _pinConfCtrl,
                obscureText: _obscureConf,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: JsColors.textStrong),
                decoration: InputDecoration(
                  labelText: 'PIN確認',
                  labelStyle: const TextStyle(color: JsColors.textMid),
                  prefixIcon: const Icon(Icons.lock_outline,
                      color: JsColors.textMid),
                  counterText: '',
                  enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: JsColors.border),
                      borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: JsColors.accent),
                      borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscureConf
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: JsColors.textMid),
                    onPressed: () =>
                        setState(() => _obscureConf = !_obscureConf),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!,
                    style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _setupPin,
                  // 生成り抜き（画面内の主ボタン）
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: JsFormTokens.outlineButtonBorder,
                    disabledBackgroundColor: Colors.transparent,
                    disabledForegroundColor:
                        JsFormTokens.outlineButtonDisabled,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ).copyWith(
                    side: WidgetStateProperty.resolveWith((states) =>
                        BorderSide(
                          color: states.contains(WidgetState.disabled)
                              ? JsFormTokens.outlineButtonDisabled
                              : JsFormTokens.outlineButtonBorder,
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
                              color: JsFormTokens.outlineButtonDisabled))
                      : const Text('PINを設定してはじめる',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
