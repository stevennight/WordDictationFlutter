import 'dart:convert';
import 'dart:io';
import 'package:mdict_flutter/mdict_flutter.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart run example/locate_key.dart <mdd_path> <resource_key>');
    exit(1);
  }
  final mddPath = args[0];
  final resourceKey = args[1];
  print('MDD: $mddPath');
  print('Key: $resourceKey');

  final mdd = MdictReader(mddPath);
  await mdd.open();

  final base64 = await mdd.locate(resourceKey, encodingOut: OutputEncoding.base64);
  if (base64 == null) {
    print('Resource not found');
    await mdd.close();
    exit(2);
  }

  final bytes = base64Decode(base64);
  final namePart = resourceKey.replaceAll('\\', '/').split('/').last;
  final outFile = File('extracted_' + namePart);
  outFile.writeAsBytesSync(bytes);
  print('Extracted to: ${outFile.absolute.path}');

  await mdd.close();
}