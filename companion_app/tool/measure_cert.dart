import 'dart:convert';

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/export.dart';

void main() {
  final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final privateKey = keyPair.privateKey as RSAPrivateKey;
  final publicKey = keyPair.publicKey as RSAPublicKey;
  final csr = X509Utils.generateRsaCsrPem(
    {'CN': 'PlayniteCompanion'},
    privateKey,
    publicKey,
  );
  final pemCert = X509Utils.generateSelfSignedCertificate(privateKey, csr, 3650);
  final hex = utf8
      .encode(pemCert)
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();
  print('PEM bytes: ${utf8.encode(pemCert).length}');
  print('Hex length: ${hex.length}');
}
