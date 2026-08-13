// ============================================================
// lib/services/profile_service.dart - ユーザープロフィール管理
// 自宅住所・個人設定（prefs ラッパ）＋ /profile 系の HTTP
//
// ★段6で HTTP を追加。prefs ラッパは setHomeAddress / getHomeAddress の2本のみ維持する
//   （どちらも呼び手あり）。現場住所の setWorkAddress / getWorkAddress は
//   呼び手ゼロだったため撤去した（'work_address' キーを読み書きする箇所は他に無い）。
//
// ★HTTP メソッドの URL・body・timeout・成否判定の正は「移設元の画面コード」。
//   移設元は各メソッドのコメントに file:line で残してある（突合用）。
//
// ★このクラスは通信の運び屋であり、prefs キャッシュの更新も画面遷移もしない。
//   profile_screen が「サーバ真実を prefs へ書き戻す」項目（worker_id / user_role /
//   home_address 等）を選んでいるのは画面の方針なので、そこは画面に残す。
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_result.dart';
import 'auth_service.dart';
import '../config/constants.dart';

class ProfileService {
  static final ProfileService _instance = ProfileService._internal();

  factory ProfileService() {
    return _instance;
  }

  ProfileService._internal();

  final AuthService _auth = AuthService();

  // ============================================================
  // prefs ラッパ（既存・段6で変更なし）
  // ============================================================

  //  自宅住所を保存
  Future<void> setHomeAddress(String address) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('home_address', address);
  }

  // 自宅住所を取得
  Future<String?> getHomeAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('home_address');
  }

  // ============================================================
  // /profile（認証必須）
  // ============================================================

  /// プロフィール取得。
  /// 移設元: profile_screen.dart:206-212（GET /profile・8秒）
  ///
  /// ★8秒は移設元のまま（他の GET 系 15秒より短い）。この画面はローカル値で
  ///   先に描いてからサーバ値で上書きする作りで、待たせない方が正しいため。
  /// ★data は応答全体。name / role / company_name / home_address / phone /
  ///   blood_type / experience_years / health_check_date / worker_id /
  ///   postal_code / emergency_* / profile_image_url を含む。
  ///   どれを prefs へ書き戻すかは呼び手の判断（移設元 :236-251）。
  Future<ApiResult<Map<String, dynamic>>> getProfile() async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'ProfileService.getProfile',
      () => http.get(
        Uri.parse('$kApiBaseUrl/profile'),
        headers: headers,
      ).timeout(const Duration(seconds: 8)),
      apiJsonMap,
    );
  }

  /// プロフィール更新。
  /// 移設元: profile_screen.dart:1236-1243（PUT /profile・15秒）
  ///
  /// ★body は画面が組み立てたものをそのまま送る。条件付きキー
  ///   （experience_years / health_check_date / profile_image_base64）の
  ///   有無判定は画面側の入力状態そのものなので、ここでは組み替えない。
  /// ★移設元は成功を statusCode 200 または 204 に限っていた（:1262）。
  ///   201 等を成功に広げると「サーバ保存失敗」の警告が出なくなるため、
  ///   その判定は呼び手が statusCode で行う（ここでは丸めない）。
  Future<ApiResult<Map<String, dynamic>>> updateProfile(
      Map<String, dynamic> body) async {
    final headers = await _auth.getAuthHeaders();
    return runApiCall<Map<String, dynamic>>(
      'ProfileService.updateProfile',
      () => http.put(
        Uri.parse('$kApiBaseUrl/profile'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15)),
      apiJsonMap,
    );
  }

  // ============================================================
  // 郵便番号 → 住所（zipcloud・外部API・認証なし）
  // ============================================================

  /// 移設元: profile_screen.dart:1120-1122（GET zipcloud・8秒・ヘッダ無し）
  ///
  /// ★自社 BE ではない外部 API。kApiBaseUrl は使わず、認証ヘッダも付けない
  ///   （移設元も headers を渡していない）。
  /// ★応答 {"status":200,"results":[{address1,address2,address3}]|null}。
  ///   results が null（該当なし）でも HTTP は 200 で返る＝
  ///   「取れなかった」と「該当なし」は ok と data の空で区別できる形にする。
  /// ★住所文字列の連結（address1+2+3）は画面の表示都合なので呼び手に残す。
  Future<ApiResult<List<Map<String, dynamic>>>> lookupZipcode(String zipcode) {
    return runApiCall<List<Map<String, dynamic>>>(
      'ProfileService.lookupZipcode',
      () => http.get(
        Uri.parse('https://zipcloud.ibsnet.co.jp/api/search?zipcode=$zipcode'),
      ).timeout(const Duration(seconds: 8)),
      (body) => ((apiJsonMap(body)?['results'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
}
