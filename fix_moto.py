with open('lib/main.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

content = content.replace(
    'selectedTransport == TransportType.car || selectedTransport == TransportType.moto',
    'selectedTransport == TransportType.car || selectedTransport == TransportType.other'
)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
