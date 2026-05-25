content = open('lib/main.dart', 'r', encoding='utf-8').read()

old = """      showJsSnackbar(context, '\u2705 \${name}\u306e\u5831\u544a\u3092\u9001\u4fe1\u3057\u307e\u3057\u305f');"""

new = """      showJsSnackbar(context, '\u2705 \${name}\u306e\u5831\u544a\u3092\u9001\u4fe1\u3057\u307e\u3057\u305f');
      // \u9001\u4fe1\u5f8c\u753b\u9762\u306b\u9077\u79fb
      final result = await Navigator.push(context,
          MaterialPageRoute(builder: (_) => AfterReportScreen(
            workerName: name,
            reportTime: '\${DateTime.now().hour.toString().padLeft(2,'0')}:\${DateTime.now().minute.toString().padLeft(2,'0')}',
          )));
      if (result != null && mounted) {
        final action = result['action'] as String?;
        if (action == 'move') {
          // \u73fe\u5834\u79fb\u52d5 \u2192 GPS\u518d\u53d6\u5f97
          final newAddr = result['newAddress'] as String? ?? '';
          setState(() => _gpsAddress = newAddr);
        }
        // night_shift\u306f\u305d\u306e\u307e\u307e\u7d99\u7d9a
      }"""

content = content.replace(old, new)
open('lib/main.dart', 'w', encoding='utf-8').write(content)
print('OK')
print('AfterReportScreen:', 'AfterReportScreen' in content)
