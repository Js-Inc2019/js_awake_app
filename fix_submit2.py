content = open('lib/main.dart', 'r', encoding='utf-8').read()

old = "showJsSnackbar(context, '\u2705 ${name}\u306e\u5831\u544a\u3092\u9001\u4fe1\u3057\u307e\u3057\u305f');\n    }\n  }\n\n  void _openNotifSettings()"

new = """showJsSnackbar(context, '\u2705 ${name}\u306e\u5831\u544a\u3092\u9001\u4fe1\u3057\u307e\u3057\u305f');
      // \u9001\u4fe1\u5f8c\u753b\u9762\u306b\u9077\u79fb
      final now = DateTime.now();
      final timeStr = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';
      final result = await Navigator.push(context,
          MaterialPageRoute(builder: (_) => AfterReportScreen(
            workerName: name,
            reportTime: timeStr,
          )));
      if (result != null && mounted) {
        final action = result['action'] as String?;
        if (action == 'move') {
          final newAddr = result['newAddress'] as String? ?? '';
          setState(() => _gpsAddress = newAddr);
        }
      }
    }
  }

  void _openNotifSettings()"""

content = content.replace(old, new)
open('lib/main.dart', 'w', encoding='utf-8').write(content)
print('OK:', 'AfterReportScreen' in content)
