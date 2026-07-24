class UserAccount {
  const UserAccount({
    required this.userId,
    required this.account,
    required this.nickname,
    required this.walletAddress,
    this.agreedAt,
  });

  final String userId;
  final String account;
  final String nickname;
  final String walletAddress;
  final DateTime? agreedAt;

  String get initial {
    final raw = nickname.trim().isNotEmpty ? nickname.trim() : account.trim();
    if (raw.isEmpty) return '?';
    return String.fromCharCode(raw.runes.first).toUpperCase();
  }

  String get walletShort {
    final w = walletAddress;
    if (w.length <= 10) return w;
    return '${w.substring(0, 6)}…${w.substring(w.length - 4)}';
  }

  String get accountMasked {
    if (account.contains('@')) {
      final parts = account.split('@');
      final name = parts.first;
      final masked = name.length <= 2
          ? '*' * name.length
          : '${name.substring(0, 2)}***';
      return '$masked@${parts.last}';
    }
    if (account.length >= 7) {
      return '${account.substring(0, 3)}****${account.substring(account.length - 4)}';
    }
    return account;
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'account': account,
        'nickname': nickname,
        'walletAddress': walletAddress,
        'agreedAt': agreedAt?.toIso8601String(),
      };

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      userId: json['userId'] as String,
      account: json['account'] as String,
      nickname: json['nickname'] as String? ?? '收藏者',
      walletAddress: json['walletAddress'] as String,
      agreedAt: json['agreedAt'] != null
          ? DateTime.tryParse(json['agreedAt'] as String)
          : null,
    );
  }
}
