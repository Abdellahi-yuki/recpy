import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keyReceiverIp = 'receiver_ip';
  static const String _keyReceiverPort = 'receiver_port';
  static const String _keyListenPort = 'listen_port';
  static const String _keyDownloadPath = 'download_path';
  static const String _defaultDownloadPath = '/storage/emulated/0/Downloads';

  static Future<String> getReceiverIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyReceiverIp) ?? '127.0.0.1';
  }

  static Future<void> setReceiverIp(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyReceiverIp, value);
  }

  static Future<int> getReceiverPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyReceiverPort) ?? 12345;
  }

  static Future<void> setReceiverPort(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyReceiverPort, value);
  }

  static Future<int> getListenPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyListenPort) ?? 12345;
  }

  static Future<void> setListenPort(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyListenPort, value);
  }

  static Future<String> getDownloadPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDownloadPath) ?? _defaultDownloadPath;
  }

  static Future<void> setDownloadPath(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDownloadPath, value);
  }

  static String get defaultDownloadPath => _defaultDownloadPath;
}
