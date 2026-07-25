import 'dart:convert';
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
  static const _localPrivateKeyPrefix = 'sp_local_private_key_';

  static final _privateKeyRe = RegExp(r'^0x[0-9a-fA-F]{64}$');

  final _secure = const FlutterSecureStorage();
  final _cloud = CloudMediaClient();

  UserAccount? _currentUser;
  bool _ready = false;
  String? _cloudToken;
  String? _cloudUserId;
  String? _pendingPrivateKey;

  UserAccount? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isReady => _ready;
  String? get cloudToken => _cloudToken;
  String? get cloudUserId => _cloudUserId;
  bool get hasCloudToken => _cloudToken != null && _cloudToken!.isNotEmpty;

  /// One-time private key returned by a local-mode registration.
  /// Read via [consumePendingPrivateKey]; cleared after read or logout.
  String? get pendingPrivateKey => _pendingPrivateKey;

  String? consumePendingPrivateKey() {
    final pk = _pendingPrivateKey;
    _pendingPrivateKey = null;
    return pk;
  }

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
    bool storePrivateKey = false,
  }) async {
    final email = account.trim().toLowerCase();
    _validateEmail(email);
    _validatePassword(password);

    final EmailRegistered registered;
    final UserTokenIssued session;
    try {
      registered = await _cloud.register(
        email: email,
        password: password,
        storePrivateKey: storePrivateKey,
      );
      // Backend register does not return a token; log in to obtain one.
      session = await _cloud.login(email: email, password: password);
    } on CloudMediaException catch (e) {
      throw _mapCloudError(e, isRegister: true);
    } catch (e) {
      throw _connectionError(e);
    }

    final user = UserAccount(
      userId: registered.userId,
      account: email,
      nickname: _defaultNickname(email),
      walletAddress: registered.walletAddress,
      agreedAt: DateTime.now(),
    );
    await _persistSession(user, token: session.token, cloudUserId: session.userId);

    // Local mode: backend does not custody the key. Auto-save to device and
    // stash it transiently so the backup screen can display it once.
    _pendingPrivateKey = null;
    if (!storePrivateKey) {
      final pk = registered.privateKey;
      if (pk != null && _privateKeyRe.hasMatch(pk)) {
        await _writeLocalPrivateKey(user.userId, pk);
        _pendingPrivateKey = pk;
      }
    }

    notifyListeners();
    return user;
  }

  Future<UserAccount> login({
    required String account,
    required String password,
  }) async {
    final email = account.trim().toLowerCase();
    if (email.isEmpty || password.isEmpty) {
      throw AuthException('请输入邮箱和密码');
    }

    final UserTokenIssued session;
    UserProfile? profile;
    try {
      session = await _cloud.login(email: email, password: password);
      profile = await _cloud.getMe(session.token);
    } on CloudMediaException catch (e) {
      throw _mapCloudError(e, isRegister: false);
    } catch (e) {
      throw _connectionError(e);
    }

    final user = UserAccount(
      userId: profile.userId,
      account: profile.email ?? email,
      nickname: _defaultNickname(profile.email ?? email),
      walletAddress: profile.walletAddress ?? '',
      agreedAt: DateTime.now(),
    );
    await _persistSession(user, token: session.token, cloudUserId: session.userId);
    notifyListeners();
    return user;
  }

  Future<void> logout() async {
    await _secure.delete(key: _sessionKey);
    _currentUser = null;
    _cloudToken = null;
    _cloudUserId = null;
    _pendingPrivateKey = null;
    notifyListeners();
  }

  /// Reads the locally stored private key for the active user, if any.
  Future<String?> readLocalPrivateKey() async {
    final uid = _currentUser?.userId;
    if (uid == null) return null;
    final pk = await _secure.read(key: '$_localPrivateKeyPrefix$uid');
    if (pk == null || pk.isEmpty) return null;
    return pk;
  }

  /// Saves/updates the local private key for the active user.
  /// Validates the `0x`-prefixed 64-hex format.
  Future<void> saveLocalPrivateKey(String privateKey) async {
    final uid = _currentUser?.userId;
    if (uid == null) {
      throw AuthException('请先登录');
    }
    final pk = privateKey.trim();
    if (!_privateKeyRe.hasMatch(pk)) {
      throw AuthException('私钥格式不正确（应为 0x 开头的 64 位十六进制）');
    }
    await _writeLocalPrivateKey(uid, pk);
    notifyListeners();
  }

  /// Removes the locally stored private key for the active user.
  Future<void> clearLocalPrivateKey() async {
    final uid = _currentUser?.userId;
    if (uid == null) return;
    await _secure.delete(key: '$_localPrivateKeyPrefix$uid');
    notifyListeners();
  }

  Future<void> _writeLocalPrivateKey(String userId, String privateKey) async {
    await _secure.write(key: '$_localPrivateKeyPrefix$userId', value: privateKey);
  }

  /// Returns the backend Bearer token for the active session.
  Future<String> requireCloudToken() async {
    if (_currentUser == null) {
      throw AuthException('请先登录');
    }
    final token = _cloudToken;
    if (token == null || token.isEmpty) {
      throw AuthException('登录已过期，请重新登录');
    }
    return token;
  }

  Future<void> _persistSession(
    UserAccount user, {
    required String token,
    required String cloudUserId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final users = _readUsers(prefs);
    users.removeWhere((u) => u['userId'] == user.userId);
    users.add(user.toJson());
    await prefs.setString(_usersKey, jsonEncode(users));
    await _secure.write(key: _sessionKey, value: user.userId);
    await _secure.write(key: '$_cloudTokenPrefix${user.userId}', value: token);
    await _secure.write(key: '$_cloudUserIdPrefix${user.userId}', value: cloudUserId);
    _currentUser = user;
    _cloudToken = token;
    _cloudUserId = cloudUserId;
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

  void _validateEmail(String email) {
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!re.hasMatch(email)) {
      throw AuthException('请输入有效的邮箱地址');
    }
  }

  void _validatePassword(String password) {
    if (password.length < 8) {
      throw AuthException('密码至少 8 位');
    }
  }

  AuthException _mapCloudError(CloudMediaException e, {required bool isRegister}) {
    switch (e.statusCode) {
      case 409:
        return AuthException('该邮箱已注册，请直接登录');
      case 401:
        return AuthException('邮箱或密码错误');
      case 400:
      case 422:
        return AuthException(e.message);
      default:
        return AuthException(e.message);
    }
  }

  AuthException _connectionError(Object e) {
    debugPrint('Auth connection error: $e');
    return AuthException('无法连接服务器，请在登录页右上角「服务器设置」确认地址');
  }

  String _defaultNickname(String account) {
    if (account.contains('@')) {
      return account.split('@').first;
    }
    return '收藏者';
  }
}
