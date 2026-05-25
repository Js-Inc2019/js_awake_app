content = open('lib/main.dart', 'r', encoding='utf-8').read()

# TransportTypeのenumを修正（その他→バイク）
old = """  bike('自転車',  Icons.pedal_bike),
  walk('徒歩',    Icons.directions_walk),
  other('その他', Icons.more_horiz);"""

new = """  bike('自転車',  Icons.pedal_bike),
  walk('徒歩',    Icons.directions_walk),
  moto('バイク',  Icons.two_wheeler);"""

content = content.replace(old, new)

# キーマップも更新
old2 = """                  const keyMap = {
                    'train': 'transit',
                    'car':   'driving',
                    'bus':   'transit',
                    'bike':  'bicycling',
                    'walk':  'walking',
                    'other': 'driving',
                  };"""

new2 = """                  const keyMap = {
                    'train': 'transit',
                    'car':   'driving',
                    'bus':   'transit',
                    'bike':  'bicycling',
                    'walk':  'walking',
                    'moto':  'driving',
                  };"""

content = content.replace(old2, new2)
open('lib/main.dart', 'w', encoding='utf-8').write(content)
print('OK')
