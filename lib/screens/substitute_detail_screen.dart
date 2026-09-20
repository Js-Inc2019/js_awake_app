// ============================================================
// lib/screens/substitute_detail_screen.dart - 振替休日（1件）
//
// 承認済みモック field_substitute_flow_mock_v4.html の C1・D1・D4・D5・D6・E1 の
// 【表示だけ】。一覧・通知・カレンダーの「振替休日を開く」から来る。
//
// ★この便は【見る側だけ】。同意する・休む日を変える・申し出を取り下げる・取り消す、の
//   操作は次の便で足す。この画面に操作のボタンは1つも置かない。
//   ★「近く使えます」の類の空約束も書かない（無い機能を予告しない）。
//
// ★出どころは GET /rest-days/:id ただ1本（rest_day と events）。
//   ★events の text は BE の文をそのまま出す。端末で書き換えない・言い換えない。
//     並びも BE が返した順（古い順）のまま。端末で並べ替えない・畳まない。
//
// 色は FieldTokens のみ（直書き禁止・新しい色を作らない）。
// ============================================================

import 'package:flutter/material.dart';

import '../core/theme/field_tokens.dart';
import '../services/api_result.dart';
import '../services/reports_service.dart';
import 'substitute_list_screen.dart' show jpMonthDay, jpMonthDayOfIso;

class SubstituteDetailScreen extends StatefulWidget {
  const SubstituteDetailScreen({
    super.key,
    required this.restDayId,
    this.service,
  });

  final String restDayId;

  /// 口の差し替え（検査だけが渡す）。既定は null＝今までどおり ReportsService()。
  ///   ★なぜ要るか【Q70】と形は substitute_list_screen.dart の同じ引数の★と同じ。
  ///   ★呼び出し側（notification_list_screen.dart / home_screen.dart）は
  ///     restDayId だけを渡しており、1文字も変わらない。
  final ReportsService? service;

  @override
  State<SubstituteDetailScreen> createState() => _SubstituteDetailScreenState();
}

class _SubstituteDetailScreenState extends State<SubstituteDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _restDay = const {};
  List<Map<String, dynamic>> _events = const [];

  /// 実際に叩く口。★本番は今までどおり ReportsService()。
  late final ReportsService _api = widget.service ?? ReportsService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final ApiResult<Map<String, dynamic>> res =
        await _api.getRestDay(widget.restDayId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!res.ok) {
        _error = res.errorMessage ?? 'この振替休日を開けませんでした';
        _restDay = const {};
        _events = const [];
        return;
      }
      final d = res.data ?? const <String, dynamic>{};
      _restDay = (d['rest_day'] is Map)
          ? Map<String, dynamic>.from(d['rest_day'] as Map)
          : const <String, dynamic>{};
      _events = ((d['events'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }

  /// 上に出す状態。★BE が返した印と列だけで決める（日付の比較はしない）。
  ///   ・同意待ち       … pending_agreement
  ///   ・成立できません … change_blocked（1件の口が返す真偽）
  ///   ・事務の確認待ち … 申し出の列が入っている（change_requested_rest_date）
  ///   ・変更済み       … 成立の列が入っている（change_settled_at）
  ///   ・成立           … 残り
  ///
  /// ★change_blocked を1件の口から読む形に直した（2026-09-20）。それまでは
  ///   一覧から【引数で持ち込む】形だったため、通知やカレンダーから直に開いた回は
  ///   印が渡らず「成立できません」が出なかった＝同じ1件が入口によって違って見えた。
  ///   BE が一覧の口と1件の口の両方で同じ式から同じ真偽を返すようになったので、
  ///   どちらの入口から来ても、この画面は自分で読んだ印だけで同じ状態を出す。
  /// ★change_blocked を返さない回（古いサーバー）はキーが無く null＝false になり、
  ///   「成立できません」を出さない。端末で期限と今日を比べて作り直さない。
  String get _stateLabel {
    if (_restDay['pending_agreement'] == true) return '同意待ち';
    if (_restDay['change_blocked'] == true) return '成立できません';
    if (_restDay['change_requested_rest_date'] != null) return '事務の確認待ち';
    if (_restDay['change_settled_at'] != null) return '変更済み';
    return '成立';
  }

  Color get _stateColor {
    if (_restDay['pending_agreement'] == true) return FieldTokens.statusWarning;
    if (_restDay['change_blocked'] == true) return FieldTokens.statusError;
    if (_restDay['change_requested_rest_date'] != null) {
      return FieldTokens.statusWarning;
    }
    return FieldTokens.statusSuccess;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FieldTokens.bgBase,
      appBar: AppBar(title: const Text('振替休日')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final err = _error;
    if (err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(err,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: FieldTokens.textSupport)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('もう一度')),
            ],
          ),
        ),
      );
    }

    final requested = _restDay['change_requested_rest_date'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 状態 ─────────────────────────────────────────────
        Text(_stateLabel,
            style: TextStyle(
                color: _stateColor,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        // ── はじめにご確認ください（同意待ちのときだけ）─────────────
        //   ★出すのは【同意待ちの状態のときだけ】。まだ頷いていない人に、
        //     何に頷くのかを先に言うための注意書きなので、成立した後や
        //     事務の確認待ちの回に出すと「もう決まった話」を蒸し返す形になる。
        //   ★文はモック B2 の原文をそのまま写した（1文字も変えていない）。
        //     端末で言い換えない＝同じ事実に2通りの言い方を作らない。
        if (_restDay['pending_agreement'] == true) ...[
          const _AgreementNotice(),
          const SizedBox(height: 20),
        ],

        // ── 日付 ─────────────────────────────────────────────
        //   ★申し出中は「いまの休む日」と「変えたい休む日」を上下に出す
        //     （どちらが効いているのかを取り違えないため）。
        _Line('出勤する日', jpMonthDay('${_restDay['paired_work_date'] ?? ''}')),
        if (requested == null)
          _Line('休む日', jpMonthDay('${_restDay['rest_date'] ?? ''}'))
        else ...[
          _Line('いまの休む日', jpMonthDay('${_restDay['rest_date'] ?? ''}')),
          _Line('変えたい休む日', jpMonthDay('$requested')),
          if (_restDay['change_deadline'] != null)
            _Line('確認の期限', jpMonthDay('${_restDay['change_deadline']}')),
        ],
        if (_restDay['change_from_date'] != null)
          _Line('変更前の休む日', jpMonthDay('${_restDay['change_from_date']}')),

        const SizedBox(height: 20),

        // ── 記録 ─────────────────────────────────────────────
        //   ★BE が並べた順のまま。text は BE の文をそのまま出す。
        const Text('記録',
            style: TextStyle(
                color: FieldTokens.textSupport,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_events.isEmpty)
          const Text('記録はありません',
              style: TextStyle(color: FieldTokens.textFaint, fontSize: 13)),
        for (final e in _events)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: Text(jpMonthDayOfIso('${e['at'] ?? ''}'),
                      style: const TextStyle(
                          color: FieldTokens.textFaint, fontSize: 12)),
                ),
                Expanded(
                  child: Text('${e['text'] ?? ''}',
                      style: const TextStyle(
                          color: FieldTokens.textBody, fontSize: 14)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 「はじめにご確認ください」の注意書き（モック B2）。
///   ★文はモックの原文をそのまま。端末で言い換えない・要約しない。
///   ★太字にするのは2つだけ:「前もって入れ替える」と「休日の割増賃金は発生しません」。
///     どちらも、読み違えるとその人の賃金の受け取り方が変わる語。
///   ★※の2行は【枠の外】に置く。枠の中は本文だけ＝「何のしくみか」と
///     「いま何が要るか・最終的に何が決めるか」を同じ重さで並べない。
class _AgreementNotice extends StatelessWidget {
  const _AgreementNotice();

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(
        color: FieldTokens.textBody, fontSize: 14, height: 1.6);
    const strong = TextStyle(
        color: FieldTokens.textBody,
        fontSize: 14,
        height: 1.6,
        fontWeight: FontWeight.bold);
    const note = TextStyle(
        color: FieldTokens.textSupport, fontSize: 12, height: 1.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 枠の中（見出し＋本文だけ）──────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: FieldTokens.surfaceRaised,
            borderRadius: BorderRadius.circular(8),
            border: const Border(
                left: BorderSide(color: FieldTokens.statusWarning, width: 3)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('はじめにご確認ください',
                  style: TextStyle(
                      color: FieldTokens.textBody,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '振替休日は、出勤する日と休む日を', style: body),
                  TextSpan(text: '前もって入れ替える', style: strong),
                  TextSpan(text: 'しくみです。入れ替えた出勤日は通常の労働日となり、', style: body),
                  TextSpan(text: '休日の割増賃金は発生しません', style: strong),
                  TextSpan(text: '。', style: body),
                ]),
              ),
            ],
          ),
        ),
        // ── 枠の外（※の2行）────────────────────────────────
        const SizedBox(height: 8),
        // ★文は原文のまま。頭の「※」だけが印で、本文には1文字も足していない。
        const Text('※同意するまで、この振替は成立しません。', style: note),
        const Text('※実際の取り扱いは、雇用契約書および就業規則の定めによります。',
            style: note),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(label,
                  style: const TextStyle(
                      color: FieldTokens.textSupport, fontSize: 12)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: FieldTokens.textBody, fontSize: 16)),
            ),
          ],
        ),
      );
}
