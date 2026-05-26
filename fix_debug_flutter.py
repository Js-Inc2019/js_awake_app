with open('lib/services/routes_service.dart', 'r', encoding='utf-8-sig') as f:
    content = f.read()

old = "        body: jsonEncode({'origin': origin, 'destination': destination}),\n      ).timeout(const Duration(seconds: 20));"
new = """        body: jsonEncode({'origin': origin, 'destination': destination}),
      ).timeout(const Duration(seconds: 20));
      print('🚀 compareRoutesV2 origin=$origin dest=$destination status=${response.statusCode} body=${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');"""

content = content.replace(old, new)
with open('lib/services/routes_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
