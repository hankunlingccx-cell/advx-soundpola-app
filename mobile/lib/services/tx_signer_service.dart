import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart' as w3;
import 'package:web3dart/crypto.dart' as w3crypto;
import '../cloud/cloud_media_models.dart';

class TxSignerService {
  TxSignerService._();

  static Future<String> signTransaction(UnsignedTx tx, String privateKey) async {
    final credentials = w3.EthPrivateKey.fromHex(privateKey);

    final transaction = w3.Transaction(
      to: w3.EthereumAddress.fromHex(tx.to),
      nonce: tx.nonce,
      gasPrice: w3.EtherAmount.inWei(tx.gasPrice),
      maxGas: tx.gas,
      value: w3.EtherAmount.inWei(tx.value),
      data: _hexToBytes(tx.data),
    );

    final client = w3.Web3Client('http://localhost:1', http.Client());
    try {
      final signed = await client.signTransaction(
        credentials,
        transaction,
        chainId: tx.chainId,
      );
      return '0x${w3crypto.bytesToHex(signed)}';
    } finally {
      client.dispose();
    }
  }
}

Uint8List _hexToBytes(String hex) {
  final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
  if (clean.isEmpty) return Uint8List(0);
  final result = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}
