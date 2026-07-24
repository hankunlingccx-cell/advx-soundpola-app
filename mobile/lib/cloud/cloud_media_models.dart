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
