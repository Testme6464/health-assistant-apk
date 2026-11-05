import 'dart:convert';

import 'package:http/http.dart' as http;

import 'key_store.dart';

/// Gemini API client (free tier) with automatic multi-key rotation.
/// When a key hits its limit (429/403/quota), the next usable key is tried.
/// Adapted from VideoTool's GeminiService; default model follows the web app.
class GeminiService {
  static const _base = 'https://generativelanguage.googleapis.com/v1beta';
  // Free-tier models (verified Nov 2026 — same list as the web app).
  static const List<String> freeModels = [
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-3-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
    'gemma-4',
  ];
  static const defaultModel = 'gemini-3.8-flash';

  final KeyStore keys;
  String model;

  GeminiService(this.keys, {this.model = defaultModel});

  /// Generate text from a prompt, optionally with base64 media attachments.
  /// Returns the text, or throws [GeminiException] if all keys are exhausted.
  Future<String> generate(
    String prompt, {
    List<GeminiMedia> media = const [],
    double temperature = 0.7,
    int maxOutputTokens = 8192,
  }) async {
    await keys.load();
    final tried = <String>[];
    final attempted = keys.keys.length;

    for (var attempt = 0; attempt < attempted; attempt++) {
      final k = keys.pickKey();
      if (k == null) break;
      tried.add(k.label);
      try {
        final text = await _callOnce(k.key, prompt,
            media: media, temperature: temperature, maxTokens: maxOutputTokens);
        await keys.reportSuccess(k.id);
        return text;
      } on _QuotaHit catch (e) {
        await keys.reportFailure(k.id, e.message, isQuota: true);
        continue; // try next key
      } on _LocationBlocked {
        // Geo-block affects every key — stop immediately, don't rotate.
        rethrow;
      } on _ModelGone {
        // Model retired/renamed — not the key's fault. Don't penalize keys,
        // don't burn through rotation; surface it immediately.
        rethrow;
      } on _BadKey catch (e) {
        await keys.reportFailure(k.id, e.message, isQuota: false);
        continue;
      }
    }

    if (!keys.hasKeys) {
      throw GeminiException(
          'API key မရှိသေးပါ။ Keys tab မှာ Google AI Studio (aistudio.google.com) က အခမဲ့ key ထည့်ပါ။');
    }
    throw GeminiException(
        'Key အားလုံး limit ထိသွားပါပြီ (${tried.join(', ')})။ ခဏစောင့်ပြီး ပြန်လုပ်ပါ၊ ဒါမှမဟုတ် key အသစ်ထပ်ထည့်ပါ။');
  }

  /// Quick key validity check — tiny prompt, no rotation.
  /// Returns null on success, or the detailed error message on failure.
  Future<String?> testKeyDetailed(String rawKey) async {
    try {
      // NOTE: new models (3.5+) use chain-of-thought; maxOutputTokens must
      // leave room for thinking tokens, else we get "Empty text".
      await _callOnce(rawKey, 'Reply with exactly: ok',
          media: const [], temperature: 0, maxTokens: 256);
      return null;
    } on _LocationBlocked catch (e) {
      return e.message;
    } on GeminiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Network error: $e';
    }
  }

  /// Quick key validity check — tiny prompt, no rotation.
  Future<bool> testKey(String rawKey) async =>
      await testKeyDetailed(rawKey) == null;

  Future<String> _callOnce(
    String apiKey,
    String prompt, {
    required List<GeminiMedia> media,
    required double temperature,
    required int maxTokens,
  }) async {
    final parts = <Map<String, dynamic>>[
      {'text': prompt},
      for (final m in media)
        {
          'inline_data': {'mime_type': m.mimeType, 'data': m.base64}
        },
    ];
    final body = jsonEncode({
      'contents': [
        {
          'parts': parts,
        }
      ],
      'generationConfig': {
        'temperature': temperature,
        'maxOutputTokens': maxTokens,
      },
    });

    final uri = Uri.parse('$_base/models/$model:generateContent?key=$apiKey');
    http.Response res;
    try {
      res = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(minutes: 3));
    } catch (e) {
      throw GeminiException('Network error: $e');
    }

    Map<String, dynamic> j = {};
    try {
      j = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}

    if (res.statusCode == 200 && j['error'] == null) {
      final candidates = j['candidates'] as List?;
      final content = candidates?.firstOrNull?['content'];
      final parts = content?['parts'] as List?;
      final text = parts
              ?.map((p) => p['text'] as String?)
              .whereType<String>()
              .join() ??
          '';
      if (text.isEmpty) throw GeminiException('Empty text');
      return text;
    }

    final errObj = j['error'];
    final message = errObj is Map
        ? (errObj['message'] as String? ?? 'HTTP ${res.statusCode}')
        : 'HTTP ${res.statusCode}';
    final status = errObj is Map ? (errObj['status'] as String? ?? '') : '';
    final lower = message.toLowerCase();

    if (res.statusCode == 404 ||
        lower.contains('not found') ||
        lower.contains('is not found')) {
      throw _ModelGone('Model မတွေ့ပါ ($model) — model နာမည် မှားနေနိုင်သည်။');
    }
    if (res.statusCode == 400 && lower.contains('api key not valid')) {
      throw _BadKey('API key မမှန်ပါ။');
    }
    if (res.statusCode == 403 && lower.contains('location')) {
      throw _LocationBlocked(
          'ဒီနေရာက Gemini သုံးလို့မရပါ (location blocked)။');
    }
    if (res.statusCode == 429 ||
        res.statusCode == 503 ||
        status == 'RESOURCE_EXHAUSTED' ||
        lower.contains('quota') ||
        lower.contains('rate') ||
        lower.contains('overloaded') ||
        lower.contains('too many')) {
      throw _QuotaHit(message);
    }
    if (res.statusCode == 400 || res.statusCode == 401 || res.statusCode == 403) {
      throw _BadKey(message);
    }
    throw GeminiException(message);
  }
}

class GeminiMedia {
  const GeminiMedia({required this.mimeType, required this.base64});
  final String mimeType;
  final String base64;
}

class GeminiException implements Exception {
  GeminiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _QuotaHit extends GeminiException {
  _QuotaHit(super.message);
}

class _BadKey extends GeminiException {
  _BadKey(super.message);
}

class _ModelGone extends GeminiException {
  _ModelGone(super.message);
}

class _LocationBlocked extends GeminiException {
  _LocationBlocked(super.message);
}
