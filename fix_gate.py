import re

content = open('lib/main.dart', 'r', encoding='utf-8').read()

# import追加
old_import = "import 'services/pdf_service.dart';"
new_import = """import 'services/pdf_service.dart';
import 'services/work_settings_service.dart';
import 'screens/after_report_screen.dart';
import 'screens/clock_in_screen.dart';
import 'screens/work_settings_screen.dart';"""
content = content.replace(old_import, new_import)

# GateScreenの_pushWorkerを修正（work_settings取得してから画面遷移）
old_gate = """  void _pushWorker(BuildContext context) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const SharedWorkerForm(
        screenTitle: '職人用 - 日報報告', isBossMode: false)));"""

new_gate = """  Future<void> _pushWorker(BuildContext context) async {
    final prefs    = await SharedPreferences.getInstance();
    final userName = prefs.getString('user_name') ?? '';
    final settings = await WorkSettingsService.instance.getMySettings();
    if (!context.mounted) return;
    if (settings.isDeemed) {
      // みなし勤務 → 直接報告画面
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => const SharedWorkerForm(
            screenTitle: '日報報告', isBossMode: false)));
    } else {
      // 実勤務 → 出勤ボタン画面
      final clocked = await Navigator.push<bool>(context,
          MaterialPageRoute(builder: (_) => ClockInScreen(userName: userName)));
      if (clocked == true && context.mounted) {
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => const SharedWorkerForm(
              screenTitle: '日報報告', isBossMode: false)));
      }
    }
  }"""

content = content.replace(old_gate, new_gate)

open('lib/main.dart', 'w', encoding='utf-8').write(content)
print('OK')
print('import追加:', 'work_settings_service' in content)
print('GateScreen修正:', 'ClockInScreen' in content)
