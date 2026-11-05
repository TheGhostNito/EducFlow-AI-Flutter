import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AiChatCryptoException implements Exception {
  const AiChatCryptoException(this.code);
  final String code;
}

class AiChatCipher {
  const AiChatCipher({
    required this.ciphertext,
    required this.nonce,
    required this.authTag,
  });

  final List<int> ciphertext;
  final List<int> nonce;
  final List<int> authTag;

  static const algorithm = 'aes-256-gcm';
  static const version = 1;

  factory AiChatCipher.fromFunction(Map<String, dynamic> data) {
    if (data['algorithm'] != algorithm || data['version'] != version) {
      throw const AiChatCryptoException('version_incompatible');
    }
    try {
      final cipher = AiChatCipher(
        ciphertext: base64Decode(data['ciphertext'] as String),
        nonce: base64Decode(data['nonce'] as String),
        authTag: base64Decode(data['authTag'] as String),
      );
      cipher._validate();
      return cipher;
    } catch (_) {
      throw const AiChatCryptoException('payload_invalido');
    }
  }

  factory AiChatCipher.fromSql(Map<String, dynamic> row, String field) {
    if (row['algoritmo_cifrado'] != algorithm ||
        row['version_cifrado'] != version) {
      throw const AiChatCryptoException('version_incompatible');
    }
    final cipher = AiChatCipher(
      ciphertext: _decodeBytea(row['${field}_cifrado']),
      nonce: _decodeBytea(row['${field}_nonce']),
      authTag: _decodeBytea(row['${field}_auth_tag']),
    );
    cipher._validate();
    return cipher;
  }

  Map<String, dynamic> toRpcPayload() {
    _validate();
    return {
      'ciphertext_hex': _hex(ciphertext),
      'nonce_hex': _hex(nonce),
      'auth_tag_hex': _hex(authTag),
      'algorithm': algorithm,
      'version': version,
    };
  }

  Map<String, dynamic> toFunctionPayload() {
    _validate();
    return {
      'ciphertext': base64Encode(ciphertext),
      'nonce': base64Encode(nonce),
      'authTag': base64Encode(authTag),
    };
  }

  void _validate() {
    if (nonce.length != 12 || authTag.length != 16) {
      throw const AiChatCryptoException('parametros_invalidos');
    }
  }

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _decodeBytea(Object? value) {
    if (value is! String || !value.startsWith(r'\x')) {
      throw const AiChatCryptoException('bytea_invalido');
    }
    final hex = value.substring(2);
    if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) {
      throw const AiChatCryptoException('bytea_invalido');
    }
    return List<int>.generate(
      hex.length ~/ 2,
      (index) => int.parse(hex.substring(index * 2, index * 2 + 2), radix: 16),
    );
  }
}

abstract interface class AiChatCryptoGateway {
  Future<AiChatCipher> encryptTitle(String uid, String chatId, String text);
  Future<String> decryptTitle(String uid, String chatId, AiChatCipher cipher);
  Future<AiChatCipher> encryptMessage(
    String uid,
    String chatId,
    String messageId,
    String role,
    String text,
  );
  Future<String> decryptMessage(
    String uid,
    String chatId,
    String messageId,
    String role,
    AiChatCipher cipher,
  );
}

class SupabaseAiChatCryptoGateway implements AiChatCryptoGateway {
  SupabaseAiChatCryptoGateway({
    SupabaseClient? client,
    Future<String?> Function(String uid)? tokenProvider,
  }) : _client = client ?? Supabase.instance.client,
       _tokenProvider = tokenProvider ?? _firebaseToken;

  final SupabaseClient _client;
  final Future<String?> Function(String uid) _tokenProvider;

  static Future<String?> _firebaseToken(String uid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) return null;
    final token = await user.getIdToken();
    if (FirebaseAuth.instance.currentUser?.uid != uid) return null;
    return token;
  }

  Future<Map<String, dynamic>> _invoke(
    Map<String, dynamic> body,
    String uid,
  ) async {
    final token = await _tokenProvider(uid);
    if (token == null || token.isEmpty) {
      throw const AiChatCryptoException('sesion_no_disponible');
    }
    try {
      final response = await _client.functions.invoke(
        'chat-crypto',
        headers: {'Authorization': 'Bearer $token'},
        body: body,
      );
      final data = response.data;
      if (data is! Map) throw const AiChatCryptoException('respuesta_invalida');
      return Map<String, dynamic>.from(data);
    } on AiChatCryptoException {
      rethrow;
    } on FunctionException catch (error) {
      if (body['action'] == 'decrypt' && error.status == 400) {
        throw const AiChatCryptoException('descifrado_incompatible');
      }
      throw const AiChatCryptoException('funcion_no_disponible');
    } catch (_) {
      throw const AiChatCryptoException('funcion_no_disponible');
    }
  }

  @override
  Future<AiChatCipher> encryptTitle(
    String uid,
    String chatId,
    String text,
  ) async {
    final data = await _invoke({
      'action': 'encrypt',
      'purpose': 'chat-title',
      'chatId': chatId,
      'plaintext': text,
    }, uid);
    return AiChatCipher.fromFunction(data);
  }

  @override
  Future<String> decryptTitle(
    String uid,
    String chatId,
    AiChatCipher cipher,
  ) async {
    final data = await _invoke({
      'action': 'decrypt',
      'purpose': 'chat-title',
      'chatId': chatId,
      ...cipher.toFunctionPayload(),
    }, uid);
    if (data['algorithm'] != AiChatCipher.algorithm ||
        data['version'] != AiChatCipher.version ||
        data['plaintext'] is! String) {
      throw const AiChatCryptoException('respuesta_invalida');
    }
    return data['plaintext'] as String;
  }

  @override
  Future<AiChatCipher> encryptMessage(
    String uid,
    String chatId,
    String messageId,
    String role,
    String text,
  ) async {
    final data = await _invoke({
      'action': 'encrypt',
      'purpose': 'chat-message',
      'chatId': chatId,
      'messageId': messageId,
      'role': role,
      'plaintext': text,
    }, uid);
    return AiChatCipher.fromFunction(data);
  }

  @override
  Future<String> decryptMessage(
    String uid,
    String chatId,
    String messageId,
    String role,
    AiChatCipher cipher,
  ) async {
    final data = await _invoke({
      'action': 'decrypt',
      'purpose': 'chat-message',
      'chatId': chatId,
      'messageId': messageId,
      'role': role,
      ...cipher.toFunctionPayload(),
    }, uid);
    if (data['algorithm'] != AiChatCipher.algorithm ||
        data['version'] != AiChatCipher.version ||
        data['plaintext'] is! String) {
      throw const AiChatCryptoException('respuesta_invalida');
    }
    return data['plaintext'] as String;
  }
}
