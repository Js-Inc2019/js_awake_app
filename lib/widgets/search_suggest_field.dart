// lib/widgets/search_suggest_field.dart
// 共通検索欄ウィジェット（FIELD）。OFFICE版と同仕様。
// レイアウト: 【候補チップ横スクロール1行(直上)】＋【検索TextField(直下=最下段)】。
//   ・チップ = 入力の部分一致候補（最大 maxSuggestions 件）。一致部分を JsColors.accent(=gold) で強調。
//   ・チップタップ = そのテキストを確定入力（controller へ反映）＋ onSelected 通知＋チップ行を閉じる。
//   ・入力の都度 onChanged 通知（既存のデバウンス+API呼び出しロジックは呼び出し側のまま）。
//   ・入力空 or 候補0件 or 確定直後 = チップ行を出さない（高さ0）。
//   ・candidates は外から差し替え可能（API結果を親 setState で逐次更新）。
//   ・色は FIELD の既存 JsColors 定数のみ（accent/gold=#A89868 等・新規hex追加なし）。タップ領域44pt以上。
import 'package:flutter/material.dart';
import '../core/theme/js_colors.dart';

class SearchSuggestField extends StatefulWidget {
  const SearchSuggestField({
    super.key,
    required this.controller,
    required this.candidates,
    required this.onChanged,
    this.onSelected,
    this.hintText = '検索',
    this.maxSuggestions = 6,
    this.autofocus = false,
    this.serverFiltered = false,
  });

  final TextEditingController controller;
  final List<String> candidates;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSelected;
  final String hintText;
  final int maxSuggestions;
  final bool autofocus;
  // true のとき candidates は既にサーバ側で絞り込み済みとみなし、
  // 入力生テキストによる literal 部分一致フィルタ(_matches)を行わない。
  // 既定 false＝従来動作（生テキスト部分一致で絞る）。
  final bool serverFiltered;

  @override
  State<SearchSuggestField> createState() => _SearchSuggestFieldState();
}

class _SearchSuggestFieldState extends State<SearchSuggestField> {
  bool _suppress = false;

  List<String> _matches(String q) {
    if (q.isEmpty || _suppress) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final c in widget.candidates) {
      final s = c.trim();
      if (s.isEmpty) continue;
      // serverFiltered 時は生テキスト部分一致で捨てない（サーバ絞り込みを尊重）。
      if (!widget.serverFiltered && !s.toLowerCase().contains(q)) continue;
      if (!seen.add(s)) continue;
      out.add(s);
      if (out.length >= widget.maxSuggestions) break;
    }
    return out;
  }

  void _handleChanged(String v) {
    if (_suppress) _suppress = false;
    widget.onChanged(v);
    setState(() {});
  }

  void _handleTapChip(String text) {
    widget.controller.text = text;
    widget.controller.selection = TextSelection.collapsed(offset: text.length);
    widget.onChanged(text);
    widget.onSelected?.call(text);
    setState(() => _suppress = true);
  }

  Widget _highlight(String text, String q) {
    final idx = q.isEmpty ? -1 : text.toLowerCase().indexOf(q);
    if (idx < 0) {
      return Text(text,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: JsColors.offWhite, fontSize: 13));
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(color: JsColors.offWhite, fontSize: 13),
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + q.length),
            style: const TextStyle(color: JsColors.accent, fontWeight: FontWeight.bold),
          ),
          TextSpan(text: text.substring(idx + q.length)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.controller.text.trim().toLowerCase();
    final matches = _matches(q);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (matches.isNotEmpty)
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            itemCount: matches.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final m = matches[i];
              return InkWell(
                onTap: () => _handleTapChip(m),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40, maxWidth: 220),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: JsColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: JsColors.accent.withValues(alpha: 0.6)),
                  ),
                  child: _highlight(m, q),
                ),
              );
            },
          ),
        ),
      TextField(
        controller: widget.controller,
        onChanged: _handleChanged,
        autofocus: widget.autofocus,
        // 入力中文字は offWhite ではっきり（背景に沈まない）。
        style: const TextStyle(color: JsColors.offWhite, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          // 背景から浮かせる薄塗り: surface系に一段明るい既存定数が無いため、
          // アクセント色(accent=#A89868)の 8% 薄塗りで代用（新規hexリテラルなし・案1準拠）。
          fillColor: JsColors.accent.withValues(alpha: 0.08),
          hintText: widget.hintText,
          // ヒントは textMid より明るく（offWhite の 60%）・fontSize 14。
          hintStyle: TextStyle(color: JsColors.offWhite.withValues(alpha: 0.6), fontSize: 14),
          // 検索アイコンはアクセント色・サイズ20（16以上）。
          prefixIcon: const Icon(Icons.search, color: JsColors.accent, size: 20),
          suffixIcon: widget.controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, color: JsColors.silver, size: 18),
                  onPressed: () {
                    widget.controller.clear();
                    widget.onChanged('');
                    setState(() => _suppress = false);
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          // 枠線は常時アクセント色の実線1.5px（暗い枠を廃止）／フォーカス時2px。
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: JsColors.accent, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: JsColors.accent, width: 2),
          ),
        ),
      ),
    ]);
  }
}
