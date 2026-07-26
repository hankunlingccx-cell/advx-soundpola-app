class CloudMediaException implements Exception {
  CloudMediaException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class UserTokenIssued {
  const UserTokenIssued({
    required this.userId,
    required this.token,
    this.tokenType = 'Bearer',
  });

  final String userId;
  final String token;
  final String tokenType;

  factory UserTokenIssued.fromJson(Map<String, dynamic> json) => UserTokenIssued(
        userId: json['user_id'] as String,
        token: json['token'] as String,
        tokenType: json['token_type'] as String? ?? 'Bearer',
      );
}

class EmailRegistered {
  const EmailRegistered({
    required this.userId,
    required this.email,
    required this.walletAddress,
    this.privateKey,
    this.privateKeyStored = false,
  });

  final String userId;
  final String email;
  final String walletAddress;
  final String? privateKey;
  final bool privateKeyStored;

  factory EmailRegistered.fromJson(Map<String, dynamic> json) => EmailRegistered(
        userId: json['user_id'] as String,
        email: json['email'] as String? ?? '',
        walletAddress: json['wallet_address'] as String? ?? '',
        privateKey: json['private_key'] as String?,
        privateKeyStored: json['private_key_stored'] as bool? ?? false,
      );
}

class UserProfile {
  const UserProfile({
    required this.userId,
    this.walletAddress,
    this.email,
  });

  final String userId;
  final String? walletAddress;
  final String? email;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        userId: json['user_id'] as String,
        walletAddress: json['wallet_address'] as String?,
        email: json['email'] as String?,
      );
}

enum CloudContentState {
  uploaded,
  processing,
  ready,
  failed,
  deleted,
  unknown;

  static CloudContentState parse(String? raw) {
    switch (raw) {
      case 'UPLOADED':
        return CloudContentState.uploaded;
      case 'PROCESSING':
        return CloudContentState.processing;
      case 'READY':
        return CloudContentState.ready;
      case 'FAILED':
        return CloudContentState.failed;
      case 'DELETED':
        return CloudContentState.deleted;
      default:
        return CloudContentState.unknown;
    }
  }

  String get wire {
    switch (this) {
      case CloudContentState.uploaded:
        return 'UPLOADED';
      case CloudContentState.processing:
        return 'PROCESSING';
      case CloudContentState.ready:
        return 'READY';
      case CloudContentState.failed:
        return 'FAILED';
      case CloudContentState.deleted:
        return 'DELETED';
      case CloudContentState.unknown:
        return 'UNKNOWN';
    }
  }
}

class ContentCreated {
  const ContentCreated({
    required this.contentId,
    required this.state,
    required this.displayLabel,
    required this.statusUrl,
  });

  final String contentId;
  final CloudContentState state;
  final String displayLabel;
  final String statusUrl;

  factory ContentCreated.fromJson(Map<String, dynamic> json) => ContentCreated(
        contentId: json['content_id'] as String,
        state: CloudContentState.parse(json['state'] as String?),
        displayLabel: json['display_label'] as String? ?? '',
        statusUrl: json['status_url'] as String? ?? '',
      );
}

/// Response of `POST /api/v1/contents/{id}/video`.
class ContentVideoUploaded {
  const ContentVideoUploaded({
    required this.contentId,
    required this.state,
    this.videoSha256,
  });

  final String contentId;
  final CloudContentState state;
  final String? videoSha256;

  factory ContentVideoUploaded.fromJson(Map<String, dynamic> json) =>
      ContentVideoUploaded(
        contentId: json['content_id'] as String? ?? '',
        state: CloudContentState.parse(json['state'] as String?),
        videoSha256: json['video_sha256'] as String?,
      );
}

class ContentSource {
  const ContentSource({
    required this.filename,
    required this.contentType,
    required this.byteLength,
    required this.sha256,
  });

  final String filename;
  final String contentType;
  final int byteLength;
  final String sha256;

  factory ContentSource.fromJson(Map<String, dynamic> json) => ContentSource(
        filename: json['filename'] as String? ?? '',
        contentType: json['content_type'] as String? ?? '',
        byteLength: (json['byte_length'] as num?)?.toInt() ?? 0,
        sha256: json['sha256'] as String? ?? '',
      );
}

class ContentSummary {
  const ContentSummary({
    required this.contentId,
    required this.state,
    required this.displayLabel,
    required this.createdAt,
    required this.updatedAt,
    required this.statusUrl,
    required this.source,
    this.processingStage,
    this.errorCode,
    this.errorMessage,
    this.durationMs,
    this.readyAt,
    this.deletedAt,
    this.nfcUrl,
    this.visualUrl,
  });

  final String contentId;
  final CloudContentState state;
  final String displayLabel;
  final String createdAt;
  final String updatedAt;
  final String statusUrl;
  final ContentSource source;
  final String? processingStage;
  final String? errorCode;
  final String? errorMessage;
  final int? durationMs;
  final String? readyAt;
  final String? deletedAt;
  final String? nfcUrl;
  final String? visualUrl;

  bool get isTerminal =>
      state == CloudContentState.ready ||
      state == CloudContentState.failed ||
      state == CloudContentState.deleted;

  factory ContentSummary.fromJson(Map<String, dynamic> json) => ContentSummary(
        contentId: json['content_id'] as String,
        state: CloudContentState.parse(json['state'] as String?),
        displayLabel: json['display_label'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
        statusUrl: json['status_url'] as String? ?? '',
        source: ContentSource.fromJson(
          (json['source'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        processingStage: json['processing_stage'] as String?,
        errorCode: json['error_code'] as String?,
        errorMessage: json['error_message'] as String?,
        durationMs: (json['duration_ms'] as num?)?.toInt(),
        readyAt: json['ready_at'] as String?,
        deletedAt: json['deleted_at'] as String?,
        nfcUrl: json['nfc_url'] as String?,
        visualUrl: json['visual_url'] as String?,
      );
}

class ContentList {
  const ContentList({required this.items, required this.total});

  final List<ContentSummary> items;
  final int total;

  factory ContentList.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List<dynamic>? ?? const [];
    return ContentList(
      items: raw
          .map((e) => ContentSummary.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? raw.length,
    );
  }
}

// --- Chain models ---

enum ChainState {
  none,
  minting,
  minted,
  failed,
  unknown;

  static ChainState parse(String? raw) {
    switch (raw) {
      case 'NONE':
        return ChainState.none;
      case 'MINTING':
        return ChainState.minting;
      case 'MINTED':
        return ChainState.minted;
      case 'FAILED':
        return ChainState.failed;
      default:
        return ChainState.unknown;
    }
  }

  String get wire {
    switch (this) {
      case ChainState.none:
        return 'NONE';
      case ChainState.minting:
        return 'MINTING';
      case ChainState.minted:
        return 'MINTED';
      case ChainState.failed:
        return 'FAILED';
      case ChainState.unknown:
        return 'UNKNOWN';
    }
  }
}

class ChainStatus {
  const ChainStatus({
    required this.contentId,
    required this.chainState,
    this.tokenId,
    this.txHash,
    this.contractAddress,
    this.tokenUri,
    this.ownerWallet,
    this.errorMessage,
    this.mintedAt,
  });

  final String contentId;
  final ChainState chainState;
  final int? tokenId;
  final String? txHash;
  final String? contractAddress;
  final String? tokenUri;
  final String? ownerWallet;
  final String? errorMessage;
  final String? mintedAt;

  factory ChainStatus.fromJson(Map<String, dynamic> json) => ChainStatus(
        contentId: json['content_id'] as String? ?? '',
        chainState: ChainState.parse(json['chain_state'] as String?),
        tokenId: (json['token_id'] as num?)?.toInt(),
        txHash: json['tx_hash'] as String?,
        contractAddress: json['contract_address'] as String?,
        tokenUri: json['token_uri'] as String?,
        ownerWallet: json['owner_wallet'] as String?,
        errorMessage: json['error_message'] as String?,
        mintedAt: json['minted_at'] as String?,
      );
}

class UnsignedTx {
  const UnsignedTx({
    required this.to,
    required this.data,
    required this.nonce,
    required this.gas,
    required this.gasPrice,
    required this.chainId,
    required this.value,
    required this.tokenUri,
  });

  final String to;
  final String data;
  final int nonce;
  final int gas;
  final BigInt gasPrice;
  final int chainId;
  final BigInt value;
  final String tokenUri;

  factory UnsignedTx.fromJson(Map<String, dynamic> json) => UnsignedTx(
        to: json['to'] as String? ?? '',
        data: json['data'] as String? ?? '',
        nonce: (json['nonce'] as num?)?.toInt() ?? 0,
        gas: (json['gas'] as num?)?.toInt() ?? 0,
        gasPrice: BigInt.tryParse(json['gas_price']?.toString() ?? '0') ?? BigInt.zero,
        chainId: (json['chain_id'] as num?)?.toInt() ?? 1439,
        value: BigInt.tryParse(json['value']?.toString() ?? '0') ?? BigInt.zero,
        tokenUri: json['token_uri'] as String? ?? '',
      );
}

class MintResult {
  const MintResult({
    required this.contentId,
    required this.tokenId,
    required this.txHash,
    required this.contractAddress,
  });

  final String contentId;
  final int tokenId;
  final String txHash;
  final String contractAddress;

  factory MintResult.fromJson(Map<String, dynamic> json) => MintResult(
        contentId: json['content_id'] as String? ?? '',
        tokenId: (json['token_id'] as num?)?.toInt() ?? 0,
        txHash: json['tx_hash'] as String? ?? '',
        contractAddress: json['contract_address'] as String? ?? '',
      );
}

class Edition {
  const Edition({
    required this.id,
    required this.contentId,
    required this.tokenId,
    required this.txHash,
    required this.ownerWallet,
    required this.tokenUri,
    required this.editionType,
    required this.mintedAt,
  });

  final String id;
  final String contentId;
  final int tokenId;
  final String txHash;
  final String ownerWallet;
  final String tokenUri;
  final String editionType;
  final String mintedAt;

  factory Edition.fromJson(Map<String, dynamic> json) => Edition(
        id: json['id'] as String? ?? '',
        contentId: json['content_id'] as String? ?? '',
        tokenId: (json['token_id'] as num?)?.toInt() ?? 0,
        txHash: json['tx_hash'] as String? ?? '',
        ownerWallet: json['owner_wallet'] as String? ?? '',
        tokenUri: json['token_uri'] as String? ?? '',
        editionType: json['edition_type'] as String? ?? 'CLAIM',
        mintedAt: json['minted_at'] as String? ?? '',
      );
}

class EditionsList {
  const EditionsList({required this.contentId, required this.editions});

  final String contentId;
  final List<Edition> editions;

  factory EditionsList.fromJson(Map<String, dynamic> json) {
    final raw = json['editions'] as List<dynamic>? ?? const [];
    return EditionsList(
      contentId: json['content_id'] as String? ?? '',
      editions: raw
          .map((e) => Edition.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}
