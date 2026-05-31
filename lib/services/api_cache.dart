// lib/services/api_cache.dart - インメモリ TTL キャッシュ
class _CacheEntry {
  _CacheEntry(this.data, this.expiry);
  final dynamic data;
  final DateTime expiry;
  bool get isValid => DateTime.now().isBefore(expiry);
}

class ApiCache {
  static final ApiCache _instance = ApiCache._();
  ApiCache._();
  static ApiCache get instance => _instance;

  final Map<String, _CacheEntry> _cache = {};

  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null || !entry.isValid) {
      _cache.remove(key);
      return null;
    }
    return entry.data as T?;
  }

  void set(String key, dynamic data, Duration ttl) {
    _cache[key] = _CacheEntry(data, DateTime.now().add(ttl));
  }

  void invalidate(String key) => _cache.remove(key);

  void invalidatePrefix(String prefix) {
    _cache.removeWhere((k, _) => k.startsWith(prefix));
  }

  void clear() => _cache.clear();
}
