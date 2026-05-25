with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

old = """      final result = await Navigator.push(context,
          MaterialPageRoute(builder: (_) => AfterReportScreen(
            workerName: name,
            reportTime: timeStr,
          )));"""

new = """      final transportLabel = {
        'train': '\u96fb\u8eca', 'car': '\u8eca', 'bus': '\u30d0\u30b9',
        'bike': '\u81ea\u8ee2\u8eca', 'walk': '\u5f92\u6b69', 'moto': '\u30d0\u30a4\u30af',
      }[_transport.name] ?? _transport.name;
      final result = await Navigator.push(context,
          MaterialPageRoute(builder: (_) => AfterReportScreen(
            workerName:  name,
            reportTime:  timeStr,
            gpsAddress:  _gpsAddress,
            transport:   transportLabel,
            workContent: _workContentCtrl.text.trim(),
            reportType:  'daily',
          )));"""

if old in content:
    content = content.replace(old, new)
    print('置換成功')
else:
    print('見つからない')
    idx = content.find('AfterReportScreen(')
    print(repr(content[idx-50:idx+200]))

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
