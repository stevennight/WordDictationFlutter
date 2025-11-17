import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';

class MddReader {
  final String path;
  RandomAccessFile? _raf;
  bool _inited = false;
  int _dataOffset = 0;
  final Map<String, _RecordRef> _index = {};
  int _fileLength = 0;
  String? _uuid;
  bool _encrypted = false;

  MddReader(this.path);

  Future<void> init() async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      _fileLength = await file.length();
      _raf = await file.open();
      final raf = _raf!;
      raf.setPositionSync(0);
      final headerLenBytes = await raf.read(4);
      if (headerLenBytes.length != 4) {
        print('[MddReader] header length bytes insufficient');
        return;
      }
      final bb = ByteData.sublistView(Uint8List.fromList(headerLenBytes));
      final lenBE = bb.getUint32(0, Endian.big);
      final lenLE = bb.getUint32(0, Endian.little);
      int headerLen = 0;
      String picked = '';
      if (lenBE > 0 && lenBE <= (_fileLength - 4) && lenBE <= 8 * 1024 * 1024) {
        headerLen = lenBE;
        picked = 'BE';
      } else if (lenLE > 0 && lenLE <= (_fileLength - 4) && lenLE <= 8 * 1024 * 1024) {
        headerLen = lenLE;
        picked = 'LE';
      }
      if (headerLen <= 0) {
        print('[MddReader] invalid header length candidates: BE=$lenBE LE=$lenLE fileLen=$_fileLength');
        return;
      }
      final headerBytes = await raf.read(headerLen);
      final headerText = _decodeHeader(headerBytes);
      final v = _extractVersion(headerText);
      final encrypted = _extractEncrypted(headerText);
      _encrypted = encrypted;
      _uuid = _extractUUID(headerText);
      try {
        final clip = _clip(headerText, 120);
        print('[MddReader] headerLen=$headerLen($picked) version=$v, encrypted=${encrypted ? 'Yes' : 'No'}, uuid=${_uuid ?? 'none'} header="$clip"');
      } catch (_) {}
      final startPos = 4 + headerLen;
      if (startPos >= _fileLength) return;
      raf.setPositionSync(startPos);
      try {
        if (v >= 3.0) {
          await _readV3(raf, encrypted);
        } else {
          await _readV2(raf, encrypted);
        }
      } catch (_) {
        print('[MddReader] parse error at startPos=$startPos');
        return;
      }
      _inited = true;
    } catch (_) {
      print('[MddReader] init exception');
      return;
    }
  }

  List<String> keys() {
    return _index.keys.toList();
  }

  Uint8List? query(String key) {
    final rr = _index[key];
    if (rr == null || _raf == null) return null;
    final raf = _raf!;
    if (rr.blockOffset < 0 || rr.blockOffset + rr.blockSize > _fileLength) return null;
    raf.setPositionSync(rr.blockOffset);
    final block = raf.readSync(rr.blockSize);
    final data = _decodeBlock(Uint8List.fromList(block), rr.decompressedSize);
    if (data.isEmpty) {
      print('[MddReader] query decode empty for "$key" at ${rr.blockOffset}/${rr.blockSize}');
      return null;
    }
    final s = rr.start - rr.offset;
    final e = rr.end - rr.offset;
    if (s < 0 || e > data.length || s >= e) return Uint8List(0);
    return Uint8List.sublistView(data, s, e);
  }

  void close() {
    try {
      _raf?.closeSync();
    } catch (_) {}
    _raf = null;
    _index.clear();
    _inited = false;
  }

  String debugState() {
    return 'init=${_inited} fileLen=${_fileLength} encrypted=${_encrypted} uuid=${_uuid ?? 'none'} keys=${_index.length}';
  }

  String _decodeHeader(List<int> bytes) {
    try {
      final u = Uint8List.fromList(bytes);
      final s16 = String.fromCharCodes(Uint16List.view(u.buffer));
      if (s16.contains('Version') || s16.contains('Encrypted') || s16.contains('UUID') || s16.contains('DictID')) {
        return s16;
      }
    } catch (_) {}
    try {
      return String.fromCharCodes(bytes);
    } catch (_) {}
    return '';
  }

  double _extractVersion(String header) {
    final m = RegExp(r'"Version"\s*:\s*"([0-9.]+)"').firstMatch(header);
    if (m != null) {
      return double.tryParse(m.group(1)!) ?? 2.0;
    }
    return 2.0;
  }

  bool _extractEncrypted(String header) {
    final m = RegExp(r'"Encrypted"\s*:\s*"(Yes|No)"', caseSensitive: false).firstMatch(header);
    if (m != null) {
      return m.group(1)!.toLowerCase() == 'yes';
    }
    return false;
  }
  String? _extractUUID(String header) {
    final m1 = RegExp(r'"UUID"\s*:\s*"([^"]+)"', caseSensitive: false).firstMatch(header);
    if (m1 != null) return m1.group(1);
    final m2 = RegExp(r'"DictID"\s*:\s*"([^"]+)"', caseSensitive: false).firstMatch(header);
    if (m2 != null) return m2.group(1);
    return null;
  }

  Future<void> _readV3(RandomAccessFile raf, bool encrypted) async {
    final pos0 = raf.positionSync();
    if (_fileLength - pos0 < 40) {
      print('[MddReader] v3 header insufficient at $pos0');
      return;
    }
    final rawHdr = raf.readSync(40);
    Uint8List hdr = Uint8List.fromList(rawHdr);
    if (encrypted) {
      final h1 = Uint8List.fromList(hdr);
      _salsaDecryptInPlace(h1, _deriveKey16FromUuid(_uuid), 16);
      hdr = h1;
    }
    final bdHdr = ByteData.sublistView(hdr);
    final nBE = bdHdr.getUint64(0, Endian.big).toInt();
    final eBE = bdHdr.getUint64(8, Endian.big).toInt();
    final dBE = bdHdr.getUint64(16, Endian.big).toInt();
    final cBE = bdHdr.getUint64(24, Endian.big).toInt();
    final bBE = bdHdr.getUint64(32, Endian.big).toInt();
    final nLE = bdHdr.getUint64(0, Endian.little).toInt();
    final eLE = bdHdr.getUint64(8, Endian.little).toInt();
    final dLE = bdHdr.getUint64(16, Endian.little).toInt();
    final cLE = bdHdr.getUint64(24, Endian.little).toInt();
    final bLE = bdHdr.getUint64(32, Endian.little).toInt();
    int kbNum = 0, kbEntries = 0, kbIndexDecomp = 0, kbIndexComp = 0, kbBlocksLen = 0;
    bool be = false;
    if (nBE > 0 && nBE <= 8192 && cBE > 0 && dBE > 0 && cBE < (_fileLength - raf.positionSync())) {
      kbNum = nBE; kbEntries = eBE; kbIndexComp = cBE; kbIndexDecomp = dBE; kbBlocksLen = bBE; be = true;
    } else if (nLE > 0 && nLE <= 8192 && cLE > 0 && dLE > 0 && cLE < (_fileLength - raf.positionSync())) {
      kbNum = nLE; kbEntries = eLE; kbIndexComp = cLE; kbIndexDecomp = dLE; kbBlocksLen = bLE; be = false;
    }
    print('[MddReader] v3 key hdr: num='+kbNum.toString()+' entries='+kbEntries.toString()+' idxComp='+kbIndexComp.toString()+' idxDecomp='+kbIndexDecomp.toString()+' dataBytes='+kbBlocksLen.toString());
    if (kbNum <= 0 || kbNum > 8192) {
      print('[MddReader] v3 key hdr invalid, fallback');
      raf.setPositionSync(pos0);
      await _readV3Fallback(raf, encrypted);
      return;
    }
    if (raf.positionSync() + kbIndexComp > _fileLength) {
      print('[MddReader] v3 key index out of range');
      return;
    }
    final idxComp = raf.readSync(kbIndexComp);
    final idxData = _decodeBlock(Uint8List.fromList(idxComp), kbIndexDecomp);
    if (idxData.isEmpty) {
      print('[MddReader] v3 key index decode failed');
      raf.setPositionSync(pos0);
      await _readV3Fallback(raf, encrypted);
      return;
    }
    final keyBlockSizes = _parseSizePairs(idxData, kbNum, kbBlocksLen);
    print('[MddReader] v3 key index parsed: ${keyBlockSizes.length}/${kbNum} blocks');
    if (keyBlockSizes.length != kbNum) {
      print('[MddReader] v3 key index pair count mismatch');
      return;
    }
    final keysCollected = <String>[];
    for (int i = 0; i < keyBlockSizes.length; i++) {
      final pair = keyBlockSizes[i];
      if (raf.positionSync() + pair.comp > _fileLength) {
        print('[MddReader] v3 key block $i exceeds file');
        return;
      }
      final comp = raf.readSync(pair.comp);
      final data = _decodeBlock(Uint8List.fromList(comp), pair.decomp);
      if (data.isEmpty) {
        print('[MddReader] v3 key block $i decode empty');
        return;
      }
      _collectKeysFromKeyData(data, keysCollected);
    }
    print('[MddReader] v3 keys collected: ${keysCollected.length}');
    if (raf.positionSync() + 40 > _fileLength) {
      print('[MddReader] v3 record hdr out of range');
      return;
    }
    final recHdrRaw = raf.readSync(40);
    Uint8List rh = Uint8List.fromList(recHdrRaw);
    if (encrypted) {
      _salsaDecryptInPlace(rh, _deriveKey16FromUuid(_uuid), 16);
    }
    final bdRh = ByteData.sublistView(rh);
    final rnBE = bdRh.getUint64(0, Endian.big).toInt();
    final reBE = bdRh.getUint64(8, Endian.big).toInt();
    final rdBE = bdRh.getUint64(16, Endian.big).toInt();
    final rcBE = bdRh.getUint64(24, Endian.big).toInt();
    final rbBE = bdRh.getUint64(32, Endian.big).toInt();
    final rnLE = bdRh.getUint64(0, Endian.little).toInt();
    final reLE = bdRh.getUint64(8, Endian.little).toInt();
    final rdLE = bdRh.getUint64(16, Endian.little).toInt();
    final rcLE = bdRh.getUint64(24, Endian.little).toInt();
    final rbLE = bdRh.getUint64(32, Endian.little).toInt();
    int rbNum = 0, rbEntries = 0, rbIndexDecomp = 0, rbIndexComp = 0, rbBlocksLen = 0;
    if (rnBE > 0 && rnBE <= 16384 && rcBE > 0 && rdBE > 0 && rcBE < (_fileLength - raf.positionSync())) {
      rbNum = rnBE; rbEntries = reBE; rbIndexComp = rcBE; rbIndexDecomp = rdBE; rbBlocksLen = rbBE;
    } else if (rnLE > 0 && rnLE <= 16384 && rcLE > 0 && rdLE > 0 && rcLE < (_fileLength - raf.positionSync())) {
      rbNum = rnLE; rbEntries = reLE; rbIndexComp = rcLE; rbIndexDecomp = rdLE; rbBlocksLen = rbLE;
    }
    print('[MddReader] v3 rec hdr: num='+rbNum.toString()+' entries='+rbEntries.toString()+' idxComp='+rbIndexComp.toString()+' idxDecomp='+rbIndexDecomp.toString()+' dataBytes='+rbBlocksLen.toString());
    if (rbNum <= 0 || rbNum > 16384) {
      print('[MddReader] v3 rec hdr invalid');
      return;
    }
    if (raf.positionSync() + rbIndexComp > _fileLength) {
      print('[MddReader] v3 rec index out of range');
      return;
    }
    final recIdxComp = raf.readSync(rbIndexComp);
    final recIdxData = _decodeBlock(Uint8List.fromList(recIdxComp), rbIndexDecomp);
    if (recIdxData.isEmpty) {
      print('[MddReader] v3 rec index decode failed');
      return;
    }
    final recBlockSizes = _parseSizePairs(recIdxData, rbNum, rbBlocksLen);
    print('[MddReader] v3 rec index parsed: ${recBlockSizes.length}/${rbNum} blocks');
    if (recBlockSizes.length != rbNum) {
      print('[MddReader] v3 rec index pair count mismatch');
      return;
    }
    final recordIndex = <_RecordIndexEntry>[];
    int offset = 0;
    for (int i = 0; i < recBlockSizes.length; i++) {
      final pair = recBlockSizes[i];
      if (raf.positionSync() + pair.comp > _fileLength) {
        print('[MddReader] v3 rec idx block $i exceeds file');
        return;
      }
      final comp = raf.readSync(pair.comp);
      final data = _decodeBlock(Uint8List.fromList(comp), pair.decomp);
      if (data.isEmpty) {
        print('[MddReader] v3 rec idx block $i decode empty');
        return;
      }
      final entries = _parseRecordIndexBlock(data, blockOffset: offset);
      recordIndex.addAll(entries);
      offset += pair.decomp;
    }
    print('[MddReader] v3 rec index entries: ${recordIndex.length}');
    int runningOffset = 0;
    for (int i = 0; i < recBlockSizes.length; i++) {
      final pair = recBlockSizes[i];
      final blockOffset = raf.positionSync();
      if (blockOffset + pair.comp > _fileLength) {
        print('[MddReader] v3 rec data block $i exceeds file');
        return;
      }
      raf.setPositionSync(blockOffset + pair.comp);
      final entries = recordIndex.where((e) => e.start >= runningOffset && e.end <= runningOffset + pair.decomp).toList();
      for (final e in entries) {
        final idx = e.index;
        if (idx >= 0 && idx < keysCollected.length) {
          final key = keysCollected[idx];
          _index[key] = _RecordRef(
            blockOffset: blockOffset,
            blockSize: pair.comp,
            decompressedSize: pair.decomp,
            offset: runningOffset,
            start: e.start,
            end: e.end,
          );
        }
      }
      runningOffset += pair.decomp;
    }
  }

  Future<void> _readV3Fallback(RandomAccessFile raf, bool encrypted) async {
    final pos0 = raf.positionSync();
    if (_fileLength - pos0 < 16) return;
    final kbHdr = raf.readSync(16);
    final bd = ByteData.sublistView(Uint8List.fromList(kbHdr));
    final kbNumBE = bd.getUint32(0, Endian.big);
    final kbEntriesBE = bd.getUint32(4, Endian.big);
    final kbIndexDecompBE = bd.getUint32(8, Endian.big);
    final kbIndexCompBE = bd.getUint32(12, Endian.big);
    final kbNumLE = bd.getUint32(0, Endian.little);
    final kbEntriesLE = bd.getUint32(4, Endian.little);
    final kbIndexDecompLE = bd.getUint32(8, Endian.little);
    final kbIndexCompLE = bd.getUint32(12, Endian.little);
    int kbNum = 0, kbEntries = 0, kbIndexComp = 0, kbIndexDecomp = 0;
    bool be = false;
    if (kbNumBE > 0 && kbNumBE <= 65536 && kbIndexCompBE > 0 && kbIndexDecompBE > 0) {
      kbNum = kbNumBE;
      kbEntries = kbEntriesBE;
      kbIndexComp = kbIndexCompBE;
      kbIndexDecomp = kbIndexDecompBE;
      be = true;
    } else if (kbNumLE > 0 && kbNumLE <= 65536 && kbIndexCompLE > 0 && kbIndexDecompLE > 0) {
      kbNum = kbNumLE;
      kbEntries = kbEntriesLE;
      kbIndexComp = kbIndexCompLE;
      kbIndexDecomp = kbIndexDecompLE;
      be = false;
    }
    try {
      print('[MddReader] v2 key hdr: num='+kbNum.toString()+', entries='+kbEntries.toString()+', idxComp='+kbIndexComp.toString()+', idxDecomp='+kbIndexDecomp.toString()+', endian='+(be?'BE':'LE'));
    } catch (_) {}
    print('[MddReader] v2/fallback key blocks: $kbNum');
    if (kbNum <= 0 || kbNum > 65536) {
      return;
    }
    if (raf.positionSync() + kbIndexComp > _fileLength) return;
    final kbIndexCompData = raf.readSync(kbIndexComp);
    Uint8List kbIndexData = _decodeBlock(Uint8List.fromList(kbIndexCompData), kbIndexDecomp);
    if (kbIndexData.isEmpty || kbIndexData.length != kbIndexDecomp) {
      kbIndexData = _decodeBlock(Uint8List.fromList(kbIndexCompData), kbIndexComp);
    }
    if (kbIndexData.isEmpty) {
      return;
    }
    final keyBlockSizes = _parseSizePairs(kbIndexData, kbNum, 0);
    final keysCollected = <String>[];
    for (int i = 0; i < keyBlockSizes.length; i++) {
      final pair = keyBlockSizes[i];
      if (raf.positionSync() + pair.comp > _fileLength) return;
      final comp = raf.readSync(pair.comp);
      final data = _decodeBlock(Uint8List.fromList(comp), pair.decomp);
      _collectKeysFromKeyData(data, keysCollected);
    }
    print('[MddReader] v2/fallback keys collected: ${keysCollected.length}');
    if (_fileLength - raf.positionSync() < 16) return;
    final rbHdr = raf.readSync(16);
    final bd2 = ByteData.sublistView(Uint8List.fromList(rbHdr));
    final rbNumBE = bd2.getUint32(0, Endian.big);
    final rbEntriesBE = bd2.getUint32(4, Endian.big);
    final rbIndexDecompBE = bd2.getUint32(8, Endian.big);
    final rbIndexCompBE = bd2.getUint32(12, Endian.big);
    final rbNumLE = bd2.getUint32(0, Endian.little);
    final rbEntriesLE = bd2.getUint32(4, Endian.little);
    final rbIndexDecompLE = bd2.getUint32(8, Endian.little);
    final rbIndexCompLE = bd2.getUint32(12, Endian.little);
    int rbNum = 0, rbEntries = 0, rbIndexComp = 0, rbIndexDecomp = 0;
    if (rbNumBE > 0 && rbNumBE <= 65536 && rbIndexCompBE > 0 && rbIndexDecompBE > 0) {
      rbNum = rbNumBE; rbEntries = rbEntriesBE; rbIndexComp = rbIndexCompBE; rbIndexDecomp = rbIndexDecompBE;
    } else if (rbNumLE > 0 && rbNumLE <= 65536 && rbIndexCompLE > 0 && rbIndexDecompLE > 0) {
      rbNum = rbNumLE; rbEntries = rbEntriesLE; rbIndexComp = rbIndexCompLE; rbIndexDecomp = rbIndexDecompLE;
    }
    try {
      print('[MddReader] v2 rec hdr: num='+rbNum.toString()+', entries='+rbEntries.toString()+', idxComp='+rbIndexComp.toString()+', idxDecomp='+rbIndexDecomp.toString());
    } catch (_) {}
    print('[MddReader] v2/fallback record blocks: $rbNum');
    if (rbNum <= 0 || rbNum > 65536) {
      return;
    }
    if (raf.positionSync() + rbIndexComp > _fileLength) return;
    final rbIndexCompData = raf.readSync(rbIndexComp);
    Uint8List rbIndexData = _decodeBlock(Uint8List.fromList(rbIndexCompData), rbIndexDecomp);
    if (rbIndexData.isEmpty || rbIndexData.length != rbIndexDecomp) {
      rbIndexData = _decodeBlock(Uint8List.fromList(rbIndexCompData), rbIndexComp);
    }
    if (rbIndexData.isEmpty) {
      return;
    }
    final recBlockSizes = _parseSizePairs(rbIndexData, rbNum, 0);
    final recordIndex = <_RecordIndexEntry>[];
    int offset = 0;
    for (int i = 0; i < recBlockSizes.length; i++) {
      final pair = recBlockSizes[i];
      if (raf.positionSync() + pair.comp > _fileLength) return;
      final comp = raf.readSync(pair.comp);
      final data = _decodeBlock(Uint8List.fromList(comp), pair.decomp);
      final entries = _parseRecordIndexBlock(data, blockOffset: offset);
      recordIndex.addAll(entries);
      offset += pair.decomp;
    }
    print('[MddReader] v2/fallback rec index entries: ${recordIndex.length}');
    int runningOffset = 0;
    for (int i = 0; i < recBlockSizes.length; i++) {
      final pair = recBlockSizes[i];
      final blockOffset = raf.positionSync();
      if (blockOffset + pair.comp > _fileLength) return;
      raf.setPositionSync(blockOffset + pair.comp);
      final entries = recordIndex.where((e) => e.start >= runningOffset && e.end <= runningOffset + pair.decomp).toList();
      for (final e in entries) {
        final idx = e.index;
        if (idx >= 0 && idx < keysCollected.length) {
          final key = keysCollected[idx];
          _index[key] = _RecordRef(
            blockOffset: blockOffset,
            blockSize: pair.comp,
            decompressedSize: pair.decomp,
            offset: runningOffset,
            start: e.start,
            end: e.end,
          );
        }
      }
      runningOffset += pair.decomp;
    }
    print('[MddReader] v2/fallback index built: ${_index.length}');
  }

  List<_SizePair> _parseSizePairs(Uint8List indexData, int expectedCount, int totalCompBytes) {
    final pairsBE = <_SizePair>[];
    final pairsLE = <_SizePair>[];
    final bd = ByteData.sublistView(indexData);
    for (int p = 0; p + 8 <= indexData.length; p += 8) {
      final dBE = bd.getUint32(p, Endian.big);
      final cBE = bd.getUint32(p + 4, Endian.big);
      if (dBE > 0 && cBE > 0 && dBE <= 512 * 1024 * 1024 && cBE <= 128 * 1024 * 1024) {
        pairsBE.add(_SizePair(decomp: dBE, comp: cBE));
      }
      final dLE = bd.getUint32(p, Endian.little);
      final cLE = bd.getUint32(p + 4, Endian.little);
      if (dLE > 0 && cLE > 0 && dLE <= 512 * 1024 * 1024 && cLE <= 128 * 1024 * 1024) {
        pairsLE.add(_SizePair(decomp: dLE, comp: cLE));
      }
      if (pairsBE.length >= expectedCount && pairsLE.length >= expectedCount) break;
    }
    int sumBE = 0;
    for (int i = 0; i < pairsBE.length && i < expectedCount; i++) sumBE += pairsBE[i].comp;
    int sumLE = 0;
    for (int i = 0; i < pairsLE.length && i < expectedCount; i++) sumLE += pairsLE[i].comp;
    if (pairsBE.length >= expectedCount && (totalCompBytes == 0 || sumBE <= totalCompBytes)) {
      return pairsBE.take(expectedCount).toList();
    }
    if (pairsLE.length >= expectedCount && (totalCompBytes == 0 || sumLE <= totalCompBytes)) {
      return pairsLE.take(expectedCount).toList();
    }
    return pairsBE.length >= pairsLE.length ? pairsBE : pairsLE;
  }

  Future<void> _readV2(RandomAccessFile raf, bool encrypted) async {
    print('[MddReader] using v2 fallback parser');
    await _readV3Fallback(raf, encrypted);
  }

  String _clip(String s, int max) {
    if (s.isEmpty) return '';
    if (s.length <= max) return s.replaceAll(RegExp(r'[\r\n]+'), ' ');
    return s.substring(0, max).replaceAll(RegExp(r'[\r\n]+'), ' ') + '...';
  }

  void _collectKeysFromKeyData(Uint8List data, List<String> out) {
    int p = 0;
    while (p < data.length) {
      final start = p;
      while (p < data.length && data[p] != 0) {
        p++;
      }
      if (p > start) {
        final seg = Uint8List.sublistView(data, start, p);
        String key;
        final zeroCount = seg.where((b) => b == 0).length;
        if (zeroCount > seg.length / 4) {
          try {
            key = String.fromCharCodes(Uint16List.view(seg.buffer, seg.offsetInBytes, seg.length ~/ 2));
          } catch (_) {
            key = String.fromCharCodes(seg);
          }
        } else {
          key = String.fromCharCodes(seg);
        }
        out.add(key);
      }
      p++;
    }
  }

  List<_RecordIndexEntry> _parseRecordIndexBlock(Uint8List data, {required int blockOffset}) {
    final out64BE = <_RecordIndexEntry>[];
    final out64LE = <_RecordIndexEntry>[];
    final out32BE = <_RecordIndexEntry>[];
    final out32LE = <_RecordIndexEntry>[];
    final bd = ByteData.sublistView(data);
    if (data.length % 16 == 0) {
      for (int p = 0, i = 0; p + 16 <= data.length; p += 16, i++) {
        final sBE = bd.getUint64(p, Endian.big);
        final eBE = bd.getUint64(p + 8, Endian.big);
        out64BE.add(_RecordIndexEntry(index: i, start: sBE, end: eBE));
        final sLE = bd.getUint64(p, Endian.little);
        final eLE = bd.getUint64(p + 8, Endian.little);
        out64LE.add(_RecordIndexEntry(index: i, start: sLE, end: eLE));
      }
    }
    if (data.length % 8 == 0) {
      for (int p = 0, i = 0; p + 8 <= data.length; p += 8, i++) {
        final sBE = bd.getUint32(p, Endian.big);
        final eBE = bd.getUint32(p + 4, Endian.big);
        out32BE.add(_RecordIndexEntry(index: i, start: sBE, end: eBE));
        final sLE = bd.getUint32(p, Endian.little);
        final eLE = bd.getUint32(p + 4, Endian.little);
        out32LE.add(_RecordIndexEntry(index: i, start: sLE, end: eLE));
      }
    }
    int valid64BE = 0; for (final e in out64BE) { if (e.start >= 0 && e.end >= e.start) valid64BE++; }
    int valid64LE = 0; for (final e in out64LE) { if (e.start >= 0 && e.end >= e.start) valid64LE++; }
    int valid32BE = 0; for (final e in out32BE) { if (e.start >= 0 && e.end >= e.start) valid32BE++; }
    int valid32LE = 0; for (final e in out32LE) { if (e.start >= 0 && e.end >= e.start) valid32LE++; }
    final best64 = valid64BE >= valid64LE ? out64BE : out64LE;
    final best32 = valid32BE >= valid32LE ? out32BE : out32LE;
    if (best64.isNotEmpty && valid64BE + valid64LE >= valid32BE + valid32LE) return best64;
    if (best32.isNotEmpty) return best32;
    return best64.isNotEmpty ? best64 : best32;
  }

  int _readInt32Sync(RandomAccessFile raf) {
    final b = raf.readSync(4);
    if (b.length != 4) return 0;
    return ByteData.sublistView(Uint8List.fromList(b)).getUint32(0, Endian.little);
  }

  int _readNumberSync(RandomAccessFile raf) {
    final b = raf.readSync(8);
    if (b.length != 8) return 0;
    return ByteData.sublistView(Uint8List.fromList(b)).getUint64(0, Endian.little).toInt();
  }

  int _readInt32BE(RandomAccessFile raf) {
    final b = raf.readSync(4);
    if (b.length != 4) return 0;
    return ByteData.sublistView(Uint8List.fromList(b)).getUint32(0, Endian.big);
  }

  int _getUint64BE(Uint8List data, int offset) {
    return ByteData.sublistView(data).getUint64(offset, Endian.big).toInt();
  }

  Uint8List _decodeBlock(Uint8List comp, int decompressed) {
    if (comp.length <= 8) return comp;
    final bd = ByteData.sublistView(comp);
    int compTypeBE = bd.getUint32(0, Endian.big);
    int checksumBE = bd.getUint32(4, Endian.big);
    int compTypeLE = bd.getUint32(0, Endian.little);
    int checksumLE = bd.getUint32(4, Endian.little);
    var payload = Uint8List.sublistView(comp, 8);

    // Try BE header first
    Uint8List? out = _decodeBlockWithHeader(payload, compTypeBE, checksumBE, decompressed);
    if (out != null && out.isNotEmpty) return out;
    // Then try LE header
    out = _decodeBlockWithHeader(payload, compTypeLE, checksumLE, decompressed);
    if (out != null && out.isNotEmpty) return out;
    // Fallback: plain inflate attempt
    final d = _tryInflate(payload, decompressed);
    if (d.isNotEmpty) return d;
    return payload;
  }

  Uint8List? _decodeBlockWithHeader(Uint8List payload, int compType, int checksum, int expected) {
    if (compType == 0) {
      return payload;
    }
    if (_encrypted && payload.length >= 16) {
      final pS1 = Uint8List.fromList(payload);
      _salsaDecryptInPlace(pS1, _deriveKey16FromUuid(_uuid), 16);
      final dS1 = _tryInflate(pS1, expected);
      if (dS1.isNotEmpty) return dS1;
      final pS2 = Uint8List.fromList(payload);
      _salsaDecryptInPlace(pS2, _deriveKey16FromAdler(checksum), 16);
      final dS2 = _tryInflate(pS2, expected);
      if (dS2.isNotEmpty) return dS2;
      final pF1 = Uint8List.fromList(payload);
      _fastDecryptInPlace(pF1, _deriveKey16FromUuid(_uuid), 16);
      final dF1 = _tryInflate(pF1, expected);
      if (dF1.isNotEmpty) return dF1;
      final pF2 = Uint8List.fromList(payload);
      _fastDecryptInPlace(pF2, _deriveKey16FromAdler(checksum), 16);
      final dF2 = _tryInflate(pF2, expected);
      if (dF2.isNotEmpty) return dF2;
    }
    if (compType == 2) {
      final d = _tryInflate(payload, expected);
      if (d.isNotEmpty) return d;
    }
    return null;
  }

  Uint8List _tryInflate(Uint8List payload, int expected) {
    try {
      final data = ZLibDecoder().decodeBytes(payload);
      if (data.isEmpty) return Uint8List(0);
      final out = Uint8List.fromList(data);
      if (expected > 0 && out.length != expected) return Uint8List(0);
      return out;
    } catch (_) {
      return Uint8List(0);
    }
  }

  void _fastDecryptInPlace(Uint8List data, List<int> key, int n) {
    if (data.isEmpty || key.isEmpty) return;
    final k = Uint8List.fromList(key);
    int previous = 0x36;
    final limit = n <= 0 || n > data.length ? data.length : n;
    for (int i = 0; i < limit; i++) {
      int t = ((data[i] >> 4) | (data[i] << 4)) & 0xff;
      t = t ^ previous ^ (i & 0xff) ^ k[i % k.length];
      previous = data[i];
      data[i] = t;
    }
  }

  List<int> _deriveKey16FromUuid(String? uuid) {
    if (uuid == null || uuid.isEmpty) return List<int>.filled(16, 0);
    final b = Uint8List.fromList(uuid.codeUnits);
    final split = b.length >= 18 ? 18 : b.length;
    final h1 = _fnv32(b.sublist(0, split));
    final h2 = _fnv32(b.sublist(split));
    final h3 = _fnv32(b);
    final h4 = _murmur32(b);
    final out = Uint8List(16);
    final bd = ByteData.sublistView(out);
    bd.setUint32(0, h1, Endian.big);
    bd.setUint32(4, h2, Endian.big);
    bd.setUint32(8, h3, Endian.big);
    bd.setUint32(12, h4, Endian.big);
    return out;
  }

  List<int> _deriveKey16FromAdler(int checksum) {
    final c = Uint8List(4);
    final bd = ByteData.sublistView(c);
    bd.setUint32(0, checksum, Endian.big);
    final out = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      out[i] = c[i % 4];
    }
    out[0] ^= 0x36;
    out[1] ^= 0x95;
    return out;
  }

  int _fnv32(List<int> input) {
    int hash = 0x811C9DC5;
    for (final b in input) {
      hash ^= (b & 0xff);
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0xffffffff;
  }

  int _murmur32(List<int> input, {int seed = 0}) {
    int h = seed;
    int i = 0;
    while (i + 4 <= input.length) {
      int k = (input[i] & 0xff) | ((input[i + 1] & 0xff) << 8) | ((input[i + 2] & 0xff) << 16) | ((input[i + 3] & 0xff) << 24);
      k = (k * 0x5bd1e995) & 0xffffffff;
      k ^= (k >> 24);
      k = (k * 0x5bd1e995) & 0xffffffff;
      h = (h * 0x5bd1e995) & 0xffffffff;
      h ^= k;
      i += 4;
    }
    int rem = input.length - i;
    if (rem > 0) {
      int k = 0;
      if (rem >= 3) k |= (input[i + 2] & 0xff) << 16;
      if (rem >= 2) k |= (input[i + 1] & 0xff) << 8;
      if (rem >= 1) k |= (input[i] & 0xff);
      k = (k * 0x5bd1e995) & 0xffffffff;
      h ^= k;
    }
    h ^= input.length;
    h ^= (h >> 13);
    h = (h * 0x5bd1e995) & 0xffffffff;
    h ^= (h >> 15);
    return h & 0xffffffff;
  }

  void _salsaDecryptInPlace(Uint8List data, List<int> key, int n) {
    if (data.isEmpty || key.isEmpty) return;
    final ks = _salsa20_8_keystream(Uint8List.fromList(key), Uint8List(8));
    final limit = n <= 0 || n > data.length ? data.length : n;
    for (int i = 0; i < limit; i++) {
      data[i] = data[i] ^ ks[i];
    }
  }

  Uint8List _salsa20_8_keystream(Uint8List key, Uint8List iv8) {
    final state = List<int>.filled(16, 0);
    final c0 = 0x61707865;
    final c1 = 0x3120646e;
    final c2 = 0x79622d36;
    final c3 = 0x6b206574;
    state[0] = c0;
    state[5] = c1;
    state[10] = c2;
    state[15] = c3;
    final k = ByteData.sublistView(key);
    state[1] = k.getUint32(0, Endian.little);
    state[2] = k.getUint32(4, Endian.little);
    state[3] = k.getUint32(8, Endian.little);
    state[4] = k.getUint32(12, Endian.little);
    state[11] = state[1];
    state[12] = state[2];
    state[13] = state[3];
    state[14] = state[4];
    final iv = ByteData.sublistView(iv8);
    state[6] = iv8.length >= 4 ? iv.getUint32(0, Endian.little) : 0;
    state[7] = iv8.length >= 8 ? iv.getUint32(4, Endian.little) : 0;
    state[8] = 0;
    state[9] = 0;
    final x = List<int>.from(state);
    for (int i = 0; i < 4; i++) {
      _doubleRound(x);
    }
    for (int i = 0; i < 16; i++) {
      x[i] = (x[i] + state[i]) & 0xffffffff;
    }
    final out = Uint8List(64);
    final bd = ByteData.sublistView(out);
    for (int i = 0; i < 16; i++) {
      bd.setUint32(i * 4, x[i], Endian.little);
    }
    return out;
  }

  void _doubleRound(List<int> x) {
    _columnRound(x);
    _rowRound(x);
  }

  int _rotl32(int v, int n) {
    return ((v << n) | ((v & 0xffffffff) >> (32 - n))) & 0xffffffff;
  }

  void _columnRound(List<int> x) {
    x[4] ^= _rotl32((x[0] + x[12]) & 0xffffffff, 7);
    x[8] ^= _rotl32((x[4] + x[0]) & 0xffffffff, 9);
    x[12] ^= _rotl32((x[8] + x[4]) & 0xffffffff, 13);
    x[0] ^= _rotl32((x[12] + x[8]) & 0xffffffff, 18);

    x[9] ^= _rotl32((x[5] + x[1]) & 0xffffffff, 7);
    x[13] ^= _rotl32((x[9] + x[5]) & 0xffffffff, 9);
    x[1] ^= _rotl32((x[13] + x[9]) & 0xffffffff, 13);
    x[5] ^= _rotl32((x[1] + x[13]) & 0xffffffff, 18);

    x[14] ^= _rotl32((x[10] + x[6]) & 0xffffffff, 7);
    x[2] ^= _rotl32((x[14] + x[10]) & 0xffffffff, 9);
    x[6] ^= _rotl32((x[2] + x[14]) & 0xffffffff, 13);
    x[10] ^= _rotl32((x[6] + x[2]) & 0xffffffff, 18);

    x[3] ^= _rotl32((x[15] + x[11]) & 0xffffffff, 7);
    x[7] ^= _rotl32((x[3] + x[15]) & 0xffffffff, 9);
    x[11] ^= _rotl32((x[7] + x[3]) & 0xffffffff, 13);
    x[15] ^= _rotl32((x[11] + x[7]) & 0xffffffff, 18);
  }

  void _rowRound(List<int> x) {
    x[1] ^= _rotl32((x[0] + x[3]) & 0xffffffff, 7);
    x[2] ^= _rotl32((x[1] + x[0]) & 0xffffffff, 9);
    x[3] ^= _rotl32((x[2] + x[1]) & 0xffffffff, 13);
    x[0] ^= _rotl32((x[3] + x[2]) & 0xffffffff, 18);

    x[6] ^= _rotl32((x[5] + x[4]) & 0xffffffff, 7);
    x[7] ^= _rotl32((x[6] + x[5]) & 0xffffffff, 9);
    x[4] ^= _rotl32((x[7] + x[6]) & 0xffffffff, 13);
    x[5] ^= _rotl32((x[4] + x[7]) & 0xffffffff, 18);

    x[11] ^= _rotl32((x[10] + x[9]) & 0xffffffff, 7);
    x[8] ^= _rotl32((x[11] + x[10]) & 0xffffffff, 9);
    x[9] ^= _rotl32((x[8] + x[11]) & 0xffffffff, 13);
    x[10] ^= _rotl32((x[9] + x[8]) & 0xffffffff, 18);

    x[12] ^= _rotl32((x[15] + x[14]) & 0xffffffff, 7);
    x[13] ^= _rotl32((x[12] + x[15]) & 0xffffffff, 9);
    x[14] ^= _rotl32((x[13] + x[12]) & 0xffffffff, 13);
    x[15] ^= _rotl32((x[14] + x[13]) & 0xffffffff, 18);
  }
}

class _RecordIndexEntry {
  final int index;
  final int start;
  final int end;
  _RecordIndexEntry({required this.index, required this.start, required this.end});
}

class _RecordRef {
  final int blockOffset;
  final int blockSize;
  final int decompressedSize;
  final int offset;
  final int start;
  final int end;
  _RecordRef({
    required this.blockOffset,
    required this.blockSize,
    required this.decompressedSize,
    required this.offset,
    required this.start,
    required this.end,
  });
}

class _SizePair {
  final int decomp;
  final int comp;
  _SizePair({required this.decomp, required this.comp});
}