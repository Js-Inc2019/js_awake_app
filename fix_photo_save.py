with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# 写真パスをリセット前に保存
old = """      final transportLabel = {
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
      });"""

new = """      final transportLabel = {
        'train': '\u96fb\u8eca', 'car': '\u8eca', 'bus': '\u30d0\u30b9',
        'bike': '\u81ea\u8ee2\u8eca', 'walk': '\u5f92\u6b69', 'moto': '\u30d0\u30a4\u30af',
      }[_transport.name] ?? _transport.name;
      final savedGps         = _gpsAddress;
      final savedWork        = _workContentCtrl.text.trim();
      final savedParkingPhoto = _photoPath;
      final savedWorkPhoto    = _workPhotoPath;
      setState(() {
        _submitting    = false;
        _transport     = TransportType.train;
        _photoPath     = null;
        _workPhotoPath = null;
      });"""

content = content.replace(old, new)

# 写真パスを渡す
old2 = """            parkingPhotoPath: _photoPath,
            workPhotoPath:    _workPhotoPath,"""

new2 = """            parkingPhotoPath: savedParkingPhoto,
            workPhotoPath:    savedWorkPhoto,"""

content = content.replace(old2, new2)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
