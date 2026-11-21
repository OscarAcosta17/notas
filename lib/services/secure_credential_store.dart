import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _WinDataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _LocalAllocNative = Pointer<Void> Function(Uint32 uFlags, IntPtr uBytes);
typedef _LocalAllocDart = Pointer<Void> Function(int uFlags, int uBytes);

typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> hMem);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> hMem);

typedef _CryptProtectDataNative = Int32 Function(
  Pointer<_WinDataBlob> pDataIn,
  Pointer<Void> szDataDescr,
  Pointer<_WinDataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<_WinDataBlob> pDataOut,
);
typedef _CryptProtectDataDart = int Function(
  Pointer<_WinDataBlob> pDataIn,
  Pointer<Void> szDataDescr,
  Pointer<_WinDataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<_WinDataBlob> pDataOut,
);

typedef _CryptUnprotectDataNative = Int32 Function(
  Pointer<_WinDataBlob> pDataIn,
  Pointer<Pointer<Void>> ppszDataDescr,
  Pointer<_WinDataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<_WinDataBlob> pDataOut,
);
typedef _CryptUnprotectDataDart = int Function(
  Pointer<_WinDataBlob> pDataIn,
  Pointer<Pointer<Void>> ppszDataDescr,
  Pointer<_WinDataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<_WinDataBlob> pDataOut,
);

/// Encrypted-at-rest credential store backed by Android KeyStore (AES-GCM),
/// Windows DPAPI (`CryptProtectData`), and transparent migration from legacy
/// plaintext `SharedPreferences` entries.
class SecureCredentialStore {
  static const MethodChannel _channel =
      MethodChannel('com.example.notas/secure_storage');

  static const String _androidPrefix = 'enc_v1:';
  static const String _dpapiPrefix = 'dpapi_v1:';
  static const String _testPlainPrefix = 'sec_plain_';

  static bool get _isTestEnv =>
      Platform.environment.containsKey('FLUTTER_TEST');

  @visibleForTesting
  static bool allowDpapiInTests = false;

  static DynamicLibrary? _kernel32;
  static DynamicLibrary? _crypt32;

  /// Reads and decrypts a credential for [key], transparently migrating legacy
  /// unencrypted values in `SharedPreferences` when running on a host platform.
  static Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key) ?? prefs.getString('$_testPlainPrefix$key');
    if (raw == null || raw.isEmpty) return null;

    if (raw.startsWith(_testPlainPrefix)) {
      return raw.substring(_testPlainPrefix.length);
    }

    if (raw.startsWith(_androidPrefix)) {
      final decrypted = await _decryptAndroid(raw);
      return decrypted;
    }

    if (raw.startsWith(_dpapiPrefix)) {
      final decrypted = _decryptDpapi(raw);
      return decrypted;
    }

    // Legacy plaintext entry: return it and transparently migrate to encrypted storage.
    await write(key, raw);
    return raw;
  }

  /// Encrypts and writes [value] for [key], or deletes [key] when null/empty.
  static Future<void> write(String key, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(key);
      await prefs.remove('$_testPlainPrefix$key');
      return;
    }

    if (_isTestEnv && !allowDpapiInTests) {
      await prefs.setString(key, '$_testPlainPrefix$value');
      return;
    }

    if (Platform.isAndroid) {
      final encrypted = await _encryptAndroid(value);
      if (encrypted != null) {
        await prefs.setString(key, encrypted);
        return;
      }
    }

    if (Platform.isWindows) {
      final encrypted = _encryptDpapi(value);
      if (encrypted != null) {
        await prefs.setString(key, encrypted);
        return;
      }
    }

    // Fallback on unsupported desktop OS or restricted environments.
    await prefs.setString(key, value);
  }

  /// Deletes [key] from credential storage.
  static Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    await prefs.remove('$_testPlainPrefix$key');
  }

  static Future<String?> _encryptAndroid(String plain) async {
    try {
      final res = await _channel.invokeMethod<String>('encrypt', {'value': plain});
      if (res != null && res.startsWith(_androidPrefix)) {
        return res;
      }
    } catch (e) {
      debugPrint('Error cifrando credencial en Android KeyStore: $e');
    }
    return null;
  }

  static Future<String?> _decryptAndroid(String cipher) async {
    try {
      return await _channel.invokeMethod<String>('decrypt', {'value': cipher});
    } catch (e) {
      debugPrint('Error descifrando credencial en Android KeyStore: $e');
      return null;
    }
  }

  static String? _encryptDpapi(String plain) {
    if (!Platform.isWindows) return null;
    try {
      _kernel32 ??= DynamicLibrary.open('kernel32.dll');
      _crypt32 ??= DynamicLibrary.open('crypt32.dll');

      final localAlloc = _kernel32!
          .lookupFunction<_LocalAllocNative, _LocalAllocDart>('LocalAlloc');
      final localFree = _kernel32!
          .lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
      final cryptProtect = _crypt32!
          .lookupFunction<_CryptProtectDataNative, _CryptProtectDataDart>(
              'CryptProtectData');

      const lptr = 0x0040;
      const cryptprotectUiForbidden = 0x01;
      final plainBytes = Uint8List.fromList(utf8.encode(plain));

      final inBuf = localAlloc(lptr, plainBytes.isEmpty ? 1 : plainBytes.length)
          .cast<Uint8>();
      final inBlob =
          localAlloc(lptr, sizeOf<_WinDataBlob>()).cast<_WinDataBlob>();
      final outBlob =
          localAlloc(lptr, sizeOf<_WinDataBlob>()).cast<_WinDataBlob>();

      try {
        if (plainBytes.isNotEmpty) {
          inBuf.asTypedList(plainBytes.length).setAll(0, plainBytes);
        }
        inBlob.ref.cbData = plainBytes.length;
        inBlob.ref.pbData = inBuf;

        final ok = cryptProtect(
          inBlob,
          nullptr,
          nullptr,
          nullptr,
          nullptr,
          cryptprotectUiForbidden,
          outBlob,
        );
        if (ok == 0) return null;

        try {
          final outLen = outBlob.ref.cbData;
          final outBytes =
              Uint8List.fromList(outBlob.ref.pbData.asTypedList(outLen));
          return '$_dpapiPrefix${base64Encode(outBytes)}';
        } finally {
          if (outBlob.ref.pbData != nullptr) {
            localFree(outBlob.ref.pbData.cast<Void>());
          }
        }
      } finally {
        for (var i = 0; i < plainBytes.length; i++) {
          inBuf[i] = 0;
        }
        localFree(inBuf.cast<Void>());
        localFree(inBlob.cast<Void>());
        localFree(outBlob.cast<Void>());
      }
    } catch (e) {
      debugPrint('Error cifrando credencial con DPAPI: $e');
      return null;
    }
  }

  static String? _decryptDpapi(String encoded) {
    if (!Platform.isWindows) return null;
    if (!encoded.startsWith(_dpapiPrefix)) return null;
    try {
      _kernel32 ??= DynamicLibrary.open('kernel32.dll');
      _crypt32 ??= DynamicLibrary.open('crypt32.dll');

      final localAlloc = _kernel32!
          .lookupFunction<_LocalAllocNative, _LocalAllocDart>('LocalAlloc');
      final localFree = _kernel32!
          .lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
      final cryptUnprotect = _crypt32!.lookupFunction<_CryptUnprotectDataNative,
          _CryptUnprotectDataDart>('CryptUnprotectData');

      const lptr = 0x0040;
      const cryptprotectUiForbidden = 0x01;
      final cipherBytes = base64Decode(encoded.substring(_dpapiPrefix.length));

      final inBuf = localAlloc(lptr, cipherBytes.isEmpty ? 1 : cipherBytes.length)
          .cast<Uint8>();
      final inBlob =
          localAlloc(lptr, sizeOf<_WinDataBlob>()).cast<_WinDataBlob>();
      final outBlob =
          localAlloc(lptr, sizeOf<_WinDataBlob>()).cast<_WinDataBlob>();

      try {
        if (cipherBytes.isNotEmpty) {
          inBuf.asTypedList(cipherBytes.length).setAll(0, cipherBytes);
        }
        inBlob.ref.cbData = cipherBytes.length;
        inBlob.ref.pbData = inBuf;

        final ok = cryptUnprotect(
          inBlob,
          nullptr,
          nullptr,
          nullptr,
          nullptr,
          cryptprotectUiForbidden,
          outBlob,
        );
        if (ok == 0) return null;

        try {
          final outLen = outBlob.ref.cbData;
          final plainList = outBlob.ref.pbData.asTypedList(outLen);
          final result = utf8.decode(plainList);
          for (var i = 0; i < outLen; i++) {
            plainList[i] = 0;
          }
          return result;
        } finally {
          if (outBlob.ref.pbData != nullptr) {
            localFree(outBlob.ref.pbData.cast<Void>());
          }
        }
      } finally {
        localFree(inBuf.cast<Void>());
        localFree(inBlob.cast<Void>());
        localFree(outBlob.cast<Void>());
      }
    } catch (e) {
      debugPrint('Error descifrando credencial con DPAPI: $e');
      return null;
    }
  }
}
