import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';

/// PEM/DER helpers for Sunshine/Moonlight certificates stored in SharedPreferences.
class CertificateCodec {
  CertificateCodec._();

  static String normalizePem(String pem) {
    return pem.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  }

  static Uint8List pemToDer(String pem) {
    final normalized = normalizePem(pem);
    if (normalized.isEmpty) {
      throw FormatException('Empty certificate PEM');
    }

    try {
      return CryptoUtils.getBytesFromPEMString(normalized);
    } catch (_) {
      // basic_utils is strict about PEM headers; fall back below.
    }

    final match = RegExp(
      r'-----BEGIN CERTIFICATE-----\s*([\s\S]*?)\s*-----END CERTIFICATE-----',
      multiLine: true,
    ).firstMatch(normalized);
    if (match != null) {
      final body = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
      return Uint8List.fromList(base64.decode(body));
    }

    throw FormatException('X.509 certificate not found in stored PEM');
  }

  static String derToPem(Uint8List der) {
    final b64 = base64.encode(der);
    final chunks = <String>[];
    for (var i = 0; i < b64.length; i += 64) {
      chunks.add(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
    }
    return '-----BEGIN CERTIFICATE-----\n${chunks.join('\n')}\n-----END CERTIFICATE-----';
  }
}
