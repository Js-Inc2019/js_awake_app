with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# transportLabelをリセット前に取得するように移動
old = """    if (mounted) {
      setState(() {
        _submitting    = false;
        _transport     = TransportType.train;
        _photoPath     = null;
        _workPhotoPath = null;
      });
      _feeCtrl.clear();
      _workContentCtrl.clear();
      showJsSnackbar(context, """

new = """    if (mounted) {
      // transportLabelをリセット前に取得
      final transportLabel = {
        'train': '\u96fb\u8eca', 'car': '\u8eca', 'bus': '\u30d0\u30b9',
        'bike': '\u81ea\u8ee2\u8eca', 'walk': '\u5f92\u6b69', 'moto': '\u30d0\u30a4\u30af',
      }[_transport.name] ?? _transport.name;
      final savedGps = _gpsAddress;
      final savedWork = _workContentCtrl.text.trim();
      setState(() {
        _submitting    = false;
        _transport     = TransportType.train;
        _photoPath     = null;
        _workPhotoPath = null;
      });
      _feeCtrl.clear();
      _workContentCtrl.clear();
      showJsSnackbar(context, """

content = content.replace(old, new)

# AfterReportScreenに渡す変数を更新
old2 = """            gpsAddress:  _gpsAddress,
            transport:   transportLabel,
            workContent: _workContentCtrl.text.trim(),"""

new2 = """            gpsAddress:  savedGps,
            transport:   transportLabel,
            workContent: savedWork,"""

content = content.replace(old2, new2)

# 重複したtransportLabel宣言を削除
old3 = """      final transportLabel = {
        'train': '\u96fb\u8eca', 'car': '\u8eca', 'bus': '\u30d0\u30b9',
        'bike': '\u81ea\u8ee2\u8eca', 'walk': '\u5f92\u6b69', 'moto': '\u30d0\u30a4\u30af',
      }[_transport.name] ?? _transport.name;
      final result = await Navigator.push(context,"""

new3 = "      final result = await Navigator.push(context,"

content = content.replace(old3, new3)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
