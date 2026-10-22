// lib/widgets/business_day_dialog_guard.dart
// 今日を前に置く字の窓を、開いたまま業務日が替われば閉じる部品（便BN・見つけた事 (47)(g)・下調べの (D8)）。
//
// ★何か：窓の中身をこれで包む。開いた時の業務日（その時の勤務の種類で）を覚え、業務日の切り替わりの知らせ
//   （lib/utils/business_day_tick.dart の BusinessDayTick.changes）の時に業務日が替わっていて、その窓がまだ一番上
//   （ModalRoute.isCurrentOf）なら、「キャンセル」「戻る」「閉じる」を押した時と同じ値で閉じる（何も書かない・遷移しない）。
//   知らせの時に覆われていた窓（打刻のお知らせの窓が上に開いた時など）は、一番上に戻った時（isCurrent が替わった時の描き直し）にも
//   比べて閉じる（閉じるのは描いた後＝addPostFrameCallback・描く中では閉じない）。
// ★押した直後の出ていく間（一番上でない）は閉じない（下の画面を閉じない）。閉じた後は、下の画面が今の業務日の物を出す。
// ★使う窓（5つ）：2件目の窓・［今日はここまで］の「退勤して今日を締めますか？」・［追加の申告］の窓（lib/screens/home_screen.dart）、
//   本日休みの窓・休みの取り消しの窓「本日は休み登録済みです」（lib/screens/punch_screen.dart）。
//   締めの窓「今日の報告を締めますか？」は字に日付が在るので使わない。
import 'package:flutter/widgets.dart';

import '../utils/business_date.dart';
import '../utils/business_day_tick.dart';

/// 開いたまま業務日が替われば、窓を閉じる（[closeValue] で閉じる）。
class CloseOnBusinessDayChange extends StatefulWidget {
  const CloseOnBusinessDayChange({
    super.key,
    required this.shiftType,
    required this.child,
    this.closeValue,
  });

  /// 開いた時の勤務の種類（'day'|'night'・業務日を数える物差し）。
  final String shiftType;

  /// 閉じる時の値（「キャンセル」「戻る」「閉じる」を押した時と同じ値）。
  final Object? closeValue;

  /// 窓の中身（AlertDialog など）。
  final Widget child;

  @override
  State<CloseOnBusinessDayChange> createState() => _CloseOnBusinessDayChangeState();
}

class _CloseOnBusinessDayChangeState extends State<CloseOnBusinessDayChange> {
  late final String _openBizDate;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _openBizDate = businessDateForShift(widget.shiftType, businessNow());
    BusinessDayTick.changes.addListener(_check);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 一番上に戻った時（覆っていた物が閉じた時）にも比べる（描いた後に閉じる）。
    if (ModalRoute.isCurrentOf(context) == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  void _check() {
    if (!mounted || _closing) return;
    if (businessDateForShift(widget.shiftType, businessNow()) == _openBizDate) return;
    if (ModalRoute.isCurrentOf(context) != true) return;
    _closing = true;
    Navigator.of(context).pop(widget.closeValue);
  }

  @override
  void dispose() {
    BusinessDayTick.changes.removeListener(_check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
