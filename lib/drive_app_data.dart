import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'cloud_state.dart';

typedef DriveTokenProvider =
    Future<String?> Function({required bool forceRefresh});

class DriveApiException implements Exception {
  const DriveApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.reason,
  });

  final DriveFailureKind kind;
  final String message;
  final int? statusCode;
  final String? reason;

  bool get retryable => switch (kind) {
    DriveFailureKind.network ||
    DriveFailureKind.rateLimited ||
    DriveFailureKind.server => true,
    _ => false,
  };

  @override
  String toString() => message;
}

class DriveAppDataFile {
  const DriveAppDataFile({
    required this.id,
    required this.name,
    this.modifiedTime,
    this.size,
  });

  factory DriveAppDataFile.fromJson(Map<String, Object?> json) {
    return DriveAppDataFile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      modifiedTime: DateTime.tryParse(json['modifiedTime'] as String? ?? ''),
      size: json['size'] is num ? (json['size'] as num).toInt() : null,
    );
  }

  final String id;
  final String name;
  final DateTime? modifiedTime;
  final int? size;
}

class DriveAppDataStore {
  DriveAppDataStore({required this._tokenProvider, http.Client? client})
    : _client = client ?? http.Client();

  final DriveTokenProvider _tokenProvider;
  final http.Client _client;

  Future<List<DriveAppDataFile>> listFiles({
    String? exactName,
    String? namePrefix,
  }) async {
    if (exactName == null && namePrefix == null) {
      throw ArgumentError('exactName or namePrefix is required');
    }
    final escaped = (exactName ?? namePrefix!).replaceAll("'", "\\'");
    final nameQuery = exactName != null
        ? "name='$escaped'"
        : "name contains '$escaped'";
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'spaces': 'appDataFolder',
      'q': "$nameQuery and 'appDataFolder' in parents and trashed=false",
      'pageSize': '1000',
      'orderBy': 'modifiedTime desc',
      'fields': 'files(id,name,modifiedTime,size)',
    });
    final response = await _request(
      (headers) => _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15)),
    );
    final body = jsonDecode(response.body) as Map<String, Object?>;
    return (body['files'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => DriveAppDataFile.fromJson(Map<String, Object?>.from(item)),
        )
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<Map<String, Object?>?> readJsonFile(String fileId) async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
      'alt': 'media',
    });
    final response = await _request(
      (headers) => _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15)),
    );
    if (response.body.trim().isEmpty) return null;
    return Map<String, Object?>.from(jsonDecode(response.body) as Map);
  }

  Future<String> upsertJsonFile({
    required String name,
    required Map<String, Object?> json,
    String? knownFileId,
  }) async {
    final body = jsonEncode(json);
    var fileId = knownFileId;
    if (fileId == null) {
      final matches = await listFiles(exactName: name);
      fileId = matches.firstOrNull?.id;
    }
    if (fileId == null) {
      return _createJsonFile(name, body);
    }
    await _updateJsonFile(fileId, body);
    return fileId;
  }

  Future<void> deleteFile(String fileId) async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files/$fileId');
    await _request(
      (headers) => _client
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 15)),
      allowEmptyBody: true,
    );
  }

  Future<String> _createJsonFile(String name, String body) async {
    final boundary = 'cloudPlayer${DateTime.now().microsecondsSinceEpoch}';
    final metadata = jsonEncode({
      'name': name,
      'parents': ['appDataFolder'],
    });
    final multipartBody =
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$metadata\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$body\r\n'
        '--$boundary--';
    final uri = Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
      'uploadType': 'multipart',
      'fields': 'id',
    });
    final response = await _request((headers) {
      return _client
          .post(
            uri,
            headers: {
              ...headers,
              'Content-Type': 'multipart/related; boundary=$boundary',
            },
            body: multipartBody,
          )
          .timeout(const Duration(seconds: 15));
    });
    final decoded = jsonDecode(response.body) as Map<String, Object?>;
    final id = decoded['id'] as String?;
    if (id == null || id.isEmpty) {
      throw const DriveApiException(
        kind: DriveFailureKind.unknown,
        message: 'Drive did not return a file id.',
      );
    }
    return id;
  }

  Future<void> _updateJsonFile(String fileId, String body) async {
    final uri = Uri.https(
      'www.googleapis.com',
      '/upload/drive/v3/files/$fileId',
      {'uploadType': 'media'},
    );
    await _request(
      (headers) => _client
          .patch(
            uri,
            headers: {
              ...headers,
              'Content-Type': 'application/json; charset=UTF-8',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 15)),
      allowEmptyBody: true,
    );
  }

  Future<http.Response> _request(
    Future<http.Response> Function(Map<String, String> headers) request, {
    bool allowEmptyBody = false,
  }) async {
    try {
      var token = await _tokenProvider(forceRefresh: false);
      if (token == null || token.isEmpty) {
        throw const DriveApiException(
          kind: DriveFailureKind.authRequired,
          message: 'Drive authorization is required.',
        );
      }
      var response = await request({'Authorization': 'Bearer $token'});
      if (response.statusCode == 401) {
        token = await _tokenProvider(forceRefresh: true);
        if (token != null && token.isNotEmpty) {
          response = await request({'Authorization': 'Bearer $token'});
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _exceptionFor(response);
      }
      if (!allowEmptyBody && response.body.trim().isEmpty) {
        throw const DriveApiException(
          kind: DriveFailureKind.unknown,
          message: 'Drive returned an empty response.',
        );
      }
      return response;
    } on DriveApiException {
      rethrow;
    } on TimeoutException catch (error) {
      throw DriveApiException(
        kind: DriveFailureKind.network,
        message: 'Drive request timed out.',
        reason: error.toString(),
      );
    } on SocketException catch (error) {
      throw DriveApiException(
        kind: DriveFailureKind.network,
        message: 'Network connection is unavailable.',
        reason: error.message,
      );
    } on http.ClientException catch (error) {
      throw DriveApiException(
        kind: DriveFailureKind.network,
        message: 'Drive network request failed.',
        reason: error.message,
      );
    }
  }

  DriveApiException _exceptionFor(http.Response response) {
    String? reason;
    String? apiMessage;
    try {
      final decoded = jsonDecode(response.body) as Map<String, Object?>;
      final error = decoded['error'];
      if (error is Map) {
        apiMessage = error['message'] as String?;
        final errors = error['errors'];
        if (errors is List && errors.isNotEmpty && errors.first is Map) {
          reason = (errors.first as Map)['reason'] as String?;
        }
      }
    } catch (_) {
      // The status code is still enough to classify the failure.
    }
    final status = response.statusCode;
    final rateLimitedReasons = {
      'rateLimitExceeded',
      'userRateLimitExceeded',
      'dailyLimitExceeded',
      'sharingRateLimitExceeded',
    };
    final kind = switch (status) {
      401 => DriveFailureKind.authRequired,
      403 when rateLimitedReasons.contains(reason) =>
        DriveFailureKind.rateLimited,
      403 => DriveFailureKind.accessDenied,
      404 => DriveFailureKind.fileMissing,
      429 => DriveFailureKind.rateLimited,
      >= 500 => DriveFailureKind.server,
      _ => DriveFailureKind.unknown,
    };
    return DriveApiException(
      kind: kind,
      statusCode: status,
      reason: reason,
      message: apiMessage ?? 'Drive request failed with HTTP $status.',
    );
  }

  void close() => _client.close();
}
