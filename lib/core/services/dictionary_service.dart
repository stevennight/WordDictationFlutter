import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/dictionary.dart';

class DictionaryService {
  static const _dictionariesKey = 'dictionaries';

  Future<List<Dictionary>> getDictionaries() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_dictionariesKey);
    if (jsonString != null) {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((json) => Dictionary.fromJson(json)).toList();
    }
    return [];
  }

  Future<void> addDictionary(Dictionary dictionary) async {
    final dictionaries = await getDictionaries();
    if (!dictionaries.any((d) => d.path == dictionary.path)) {
      dictionaries.add(dictionary);
      await _saveDictionaries(dictionaries);
    }
  }

  Future<void> removeDictionary(String path) async {
    final dictionaries = await getDictionaries();
    dictionaries.removeWhere((d) => d.path == path);
    await _saveDictionaries(dictionaries);
  }

  Future<void> _saveDictionaries(List<Dictionary> dictionaries) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(dictionaries.map((d) => d.toJson()).toList());
    await prefs.setString(_dictionariesKey, jsonString);
  }
}