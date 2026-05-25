with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

old = """            gpsAddress:  savedGps,
            transport:   transportLabel,
            workContent: savedWork,
            reportType:  'daily',"""

new = """            gpsAddress:       savedGps,
            transport:        transportLabel,
            workContent:      savedWork,
            reportType:       'daily',
            parkingPhotoPath: _photoPath,
            workPhotoPath:    _workPhotoPath,"""

if old in content:
    content = content.replace(old, new)
    print('置換成功')
else:
    print('見つからない')

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
