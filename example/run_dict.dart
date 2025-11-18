import 'dart:io';
import 'dart:convert';
import 'package:mdict_flutter/mdict_flutter.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart run example/run_dict.dart <mdx_path> <word> [mdd_path]');
    exit(1);
  }
  final mdxPath = args[0];
  final queryWord = args[1];
  final mddPath = args.length > 2 ? args[2] : null;

  print('MDX: $mdxPath');
  final mdx = MdictReader(mdxPath);
  await mdx.open();

  final def = await mdx.lookup(queryWord);
  print('Lookup "$queryWord":');
  if (def == null) {
    print('No definition found, trying fallback scan...');
    String? hitKey;
    for (var b = 0; b < mdx.keyBlockInfoList.length && b < 50; b++) {
      final list = mdx.decodeKeyBlockById(b);
      for (final k in list) {
        if (k.key == queryWord) { hitKey = k.key; break; }
        if (hitKey == null && k.key.contains(queryWord)) { hitKey = k.key; }
      }
      if (hitKey != null) break;
    }
    if (hitKey != null) {
      final def2 = await mdx.lookup(hitKey);
      if (def2 != null) {
        final preview = def2.length <= 400 ? def2 : def2.substring(0, 400);
        print(preview);
      } else {
        print('Fallback found a close key "$hitKey" but cannot decode definition');
      }
    } else {
      print('No close key discovered in first 50 blocks');
    }
  } else {
    final preview = def.length <= 400 ? def : def.substring(0, 400);
    print(preview);
  }
  await mdx.close();

  if (mddPath != null) {
    print('\nMDD: $mddPath');
    final mdd = MdictReader(mddPath);
    await mdd.open();
    // Try to extract audio path from definition
    String? audioKey;
    if (def != null) {
      final re = RegExp(r'(?:src|href)="([^"]+\.(?:mp3|wav|ogg))"', caseSensitive: false);
      final m = re.firstMatch(def);
      if (m != null) audioKey = m.group(1);
    }
    if (audioKey == null) {
      print('Audio path not found in definition, trying to probe MDD keys...');
      // Fallback: probe keys in first few blocks for audio files related to word
      final audioExt = RegExp(r"\.(mp3|wav|ogg)$", caseSensitive: false);
      for (var b = 0; b < mdd.keyBlockInfoList.length && b < 10; b++) {
        final list = mdd.decodeKeyBlockById(b);
        for (final k in list) {
          if (k.key.contains(queryWord) && audioExt.hasMatch(k.key)) {
            audioKey = k.key; break;
          }
        }
        if (audioKey != null) break;
      }
    }

    if (audioKey != null) {
      print('Audio key: $audioKey');
      final base64 = await mdd.locate(audioKey, encodingOut: OutputEncoding.base64);
      if (base64 != null) {
        final ext = audioKey.split('.').last.toLowerCase();
        final outFile = File('output_audio.$ext');
        outFile.writeAsBytesSync(base64Decode(base64));
        print('Audio extracted to: ${outFile.absolute.path}');
      } else {
        print('Failed to locate audio content in MDD');
      }
    } else {
      print('No audio key discovered');
    }
    await mdd.close();
  }
}