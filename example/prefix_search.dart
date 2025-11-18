import 'dart:io';
import 'package:mdict_flutter/mdict_flutter.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart run example/prefix_search.dart <mdx_path> <prefix> [limit]');
    exit(1);
  }
  final mdxPath = args[0];
  final prefix = args[1];
  final limit = args.length > 2 ? int.tryParse(args[2]) ?? 50 : 50;
  final mdx = MdictReader(mdxPath);
  await mdx.open();
  final list = await mdx.prefixSearch(prefix, limit: limit);
  print('Found ${list.length} keys for prefix "$prefix" (limit $limit):');
  for (final k in list) {
    print(k);
  }
  await mdx.close();
}