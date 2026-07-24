import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../cloud/cloud_media_client.dart';
import '../cloud/cloud_media_models.dart';
import '../data/user_account.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _usersKey = 'sp_users_v1';
  static const _sessionKey = 'sp_session_user_id';
  static const _rememberFlagKey = 'sp_remember_password';
  static const _rememberAccountKey = 'sp_remember_account';
  static const _rememberPasswordKey = 'sp_remember_password_value';
  static const _cloudTokenPrefix = 'sp_cloud_user_token_';
  static const _cloudUserIdPrefix = 'sp_cloud_user_id_';

  final _secure = const FlutterSecureStorage();
  final _rng = Random.secure();
  final _cloud = CloudMediaClient();

  UserAccount? _currentUser;
  bool _ready = false;
  String? _cloudToken;
  String? _cloudUserId;

  UserAccount? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isReady => _ready;
  String? get cloudToken => _cloudToken;
  String? get cloudUserId => _cloudUserId;
  bool get hasCloudToken => _cloudToken != null && _cloudToken!.isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = await _secure.read(key: _sessionKey);
    if (sessionId != null) {
      final users = _readUsers(prefs);
      final match = users.where((u) => u['userId'] == sessionId).toList();
      if (match.isNotEmpty) {
        _currentUser = UserAccount.fromJson(match.first);
        await _loadCloudCredentials(sessionId);
      } else {
        await _secure.delete(key: _sessionKey);
      }
    }
    _ready = true;
    notifyListeners();
  }

  Future<UserAccount> register({
    required String account,
    required String password,
  }) async {
    final normalized = account.trim().toLowerCase();
    _validateAccount(normalized);
    _validatePassword(password);

    final prefs = await SharedPreferences.getInstance();
    final users = _readUsers(prefs);
    if (users.any((u) => (u['account'] as String).toLowerCase() == normalized)) {
      throw AuthException('该账号已注册，请直接登录');
    }

    final user = UserAccount(
      userId: _newId(),
      account: normalized,
      nickname: _defaultNickname(normalized),
      walletAddress: _newWallet(),
      agreedAt: DateTime.now(),
    );

    users.add({
      ...user.toJson(),
      'passwordHash': _hash(password, user.userId),
    });
    await prefs.setString(_usersKey, jsonEncode(users));
    await _secure.write(key: _sessionKey, value: user.userId);
    _currentUser = user;
    await _ensureCloudToken();
    notifyListeners();
    return user;
  }

  Future<UserAccount> login({
    required String account,
    required String password,
  }) async {
    final normalized = account.trim().toLowerCase();
    if (normalized.isEmpty || password.isEmpty) {
      throw AuthException('请输入账号和密码');
    }

    final prefs = await SharedPreferences.getInstance();
    final users = _readUsers(prefs);
    final match = users
        .where((u) => (u['account'] as String).toLowerCase() == normalized)
        .toList();
    if (match.isEmpty) {
      throw AuthException('账号不存在，请先注册');
    }
    final row = match.first;
    final userId = row['userId'] as String;
    final expected = row['passwordHash'] as String;
    if (_hash(password, userId) != expected) {
      throw AuthException('密码不正确');
    }

    final user = UserAccount.fromJson(row);
    await _secure.write(key: _sessionKey, value: user.userId);
    _currentUser = user;
    await _loadCloudCredentials(user.userId);
    await _ensureCloudToken();
    notifyListeners();
    return user;
  }

  Future<void> logout() async {
    await _secure.delete(key: _sessionKey);
    _currentUser = null;
    _cloudToken = null;
    _cloudUserId = null;
    notifyListeners();
  }

  /// Returns a valid Cloud Media UserToken for the current local session.
  /// Issues a new opaque token once per local account when missing.
  Future<String> requireCloudToken() async {
    if (_currentUser == null) {
      throw AuthException('请先登录');
    }
    await _ensureCloudToken();
    final token = _cloudToken;
    if (token == null || token.isEmpty) {
      throw AuthException('云端身份不可用，请检查 Cloud Media 服务');
    }
    return token;
  }

  Future<void> _ensureCloudToken({bool forceIssue = false}) async {
    final user = _currentUser;
    if (user == null) return;
    if (!forceIssue && hasCloudToken) return;

    try {
      final issued = await _cloud.issueUserToken();
      await _secure.write(key: '$_cloudTokenPrefix${user.userId}', value: issued.token);
      await _secure.write(key: '$_cloudUserIdPrefix${user.userId}', value: issued.userId);
      _cloudToken = issued.token;
      _cloudUserId = issued.userId;
    } on CloudMediaException catch (e) {
      // Keep local login usable offline; Press/Collection will surface cloud errors.
      debugPrint('Cloud token issue failed: $e');
      if (forceIssue) rethrow;
    } catch (e) {
      debugPrint('Cloud token issue failed: $e');
      if (forceIssue) {
        throw AuthException('无法连接云媒体服务，请确认服务已启动');
      }
    }
  }

  Future<void> _loadCloudCredentials(String localUserId) async {
    _cloudToken = await _secure.read(key: '$_cloudTokenPrefix$localUserId');
    _cloudUserId = await _secure.read(key: '$_cloudUserIdPrefix$localUserId');
  }

  Future<({bool remember, String account, String password})>
      loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_rememberFlagKey) ?? false;
    if (!remember) {
      return (remember: false, account: '', password: '');
    }
    final account = prefs.getString(_rememberAccountKey) ?? '';
    final password = await _secure.read(key: _rememberPasswordKey) ?? '';
    return (remember: true, account: account, password: password);
  }

  Future<void> saveRememberedCredentials({
    required bool remember,
    required String account,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!remember) {
      await prefs.setBool(_rememberFlagKey, false);
      await prefs.remove(_rememberAccountKey);
      await _secure.delete(key: _rememberPasswordKey);
      return;
    }
    await prefs.setBool(_rememberFlagKey, true);
    await prefs.setString(_rememberAccountKey, account.trim());
    await _secure.write(key: _rememberPasswordKey, value: password);
  }

  List<Map<String, dynamic>> _readUsers(SharedPreferences prefs) {
    final raw = prefs.getString(_usersKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  void _validateAccount(String account) {
    final email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    final phone = RegExp(r'^1\d{10}$');
    if (!email.hasMatch(account) && !phone.hasMatch(account)) {
      throw AuthException('请输入有效的手机号或邮箱');
    }
  }

  void _validatePassword(String password) {
    if (password.length < 6) {
      throw AuthException('密码至少 6 位');
    }
  }

  String _hash(String password, String salt) {
    final bytes = utf8.encode('$salt::$password::soundpola');
    return sha256.convert(bytes).toString();
  }

  String _newId() =>
      'u_${DateTime.now().microsecondsSinceEpoch}_${_rng.nextInt(9999)}';

  String _newWallet() {
    final buf = StringBuffer('0x');
    for (var i = 0; i < 40; i++) {
      buf.write(_rng.nextInt(16).toRadixString(16));
    }
    return buf.toString();
  }

  String _defaultNickname(String account) {
    if (account.contains('@')) {
      return account.split('@').first;
    }
    if (account.length >= 4) {
      return '收藏者${account.substring(account.length - 4)}';
    }
    return '收藏者';
  }
}
