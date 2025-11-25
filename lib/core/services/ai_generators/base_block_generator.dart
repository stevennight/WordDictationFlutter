import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config_service.dart';
import 'package:http/http.dart' as http;

/// Base class for all content block generators
/// Provides common functionality for generation, reflection, and correction
abstract class BaseBlockGenerator {
  final ConfigService configService;

  BaseBlockGenerator(this.configService);

  /// Generate a content block
  Future<Map<String, dynamic>> generate({
    required String prompt,
    required String answer,
    String? sourceLanguage,
    String? targetLanguage,
    List<String>? sourcesHtml,
    List<Map<String, String>>? sourcesMeta,
  }) async {
    final generatedJson = await generateBlock(
      prompt: prompt,
      answer: answer,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      sourcesHtml: sourcesHtml,
      sourcesMeta: sourcesMeta,
    );

    // Check if reflection is enabled
    final reflectionEnabled = await configService.getAIReflectionEnabled();
    if (!reflectionEnabled) {
      return generatedJson;
    }

    // Validate and correct with retry
    return await _validateAndCorrectWithRetry(
      prompt: prompt,
      answer: answer,
      generatedJson: generatedJson,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
  }

  /// Generate the content block (to be implemented by subclasses)
  Future<Map<String, dynamic>> generateBlock({
    required String prompt,
    required String answer,
    String? sourceLanguage,
    String? targetLanguage,
    List<String>? sourcesHtml,
    List<Map<String, String>>? sourcesMeta,
  });

  /// Get the block-specific generation prompt
  String getGenerationPrompt({
    required String prompt,
    required String answer,
    String? sourceLanguage,
    String? targetLanguage,
    String? referencesText,
  });

  /// Get the block-specific reflection prompt
  String getReflectionPrompt({
    required String prompt,
    required String answer,
    required String generatedJson,
    String? sourceLanguage,
    String? targetLanguage,
  });

  /// Get the block name for logging
  String get blockName;

  /// Validate and correct with retry mechanism (configurable max attempts)
  Future<Map<String, dynamic>> _validateAndCorrectWithRetry({
    required String prompt,
    required String answer,
    required Map<String, dynamic> generatedJson,
    String? sourceLanguage,
    String? targetLanguage,
  }) async {
    final maxAttempts = await configService.getAIReflectionMaxAttempts();
    Map<String, dynamic> currentJson = generatedJson;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      debugPrint('[$blockName] Validation attempt $attempt/$maxAttempts');

      final reflectionResult = await _reflectOnResponse(
        prompt: prompt,
        answer: answer,
        generatedJson: jsonEncode(currentJson),
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );

      if (reflectionResult == null) {
        // Validation passed
        if (attempt == 1) {
          debugPrint('[$blockName] Reflection passed on first attempt');
        } else {
          debugPrint('[$blockName] Reflection passed after $attempt attempts');
        }
        return currentJson;
      }

      // Validation failed
      final issues = reflectionResult['issues'] as List?;
      debugPrint('[$blockName] Reflection found ${issues?.length ?? 0} issues on attempt $attempt');

      if (attempt < maxAttempts) {
        // Try to correct
        debugPrint('[$blockName] Attempting correction...');
        final correctedJson = await _correctWithReflection(
          prompt: prompt,
          answer: answer,
          generatedJson: jsonEncode(currentJson),
          reflectionResult: reflectionResult,
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
        );

        // Validate the JSON format
        try {
          currentJson = jsonDecode(correctedJson) as Map<String, dynamic>;
          debugPrint('[$blockName] Correction completed, will re-validate');
        } catch (e) {
          debugPrint('[$blockName] Corrected JSON is invalid: $e');
          // If correction produces invalid JSON, retry with original
          currentJson = generatedJson;
        }
      } else {
        // Max attempts reached
        debugPrint('[$blockName] Max correction attempts ($maxAttempts) reached, using last version');
        return currentJson;
      }
    }

    return currentJson;
  }

  /// Reflect on the AI response
  Future<Map<String, dynamic>?> _reflectOnResponse({
    required String prompt,
    required String answer,
    required String generatedJson,
    String? sourceLanguage,
    String? targetLanguage,
  }) async {
    final endpoint = await configService.getAIEndpoint();
    final apiKey = await configService.getAIApiKey();
    final model = await configService.getAIModel();

    if (apiKey.isEmpty) {
      debugPrint('[$blockName][Reflection] No API key, skipping reflection');
      return null;
    }

    final reflectionPrompt = getReflectionPrompt(
      prompt: prompt,
      answer: answer,
      generatedJson: generatedJson,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );

    try {
      final response = await http.post(
        Uri.parse('$endpoint/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': reflectionPrompt}
          ],
          'temperature': 0.1,
          'response_format': {'type': 'json_object'},
        }),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
        final choice = jsonResponse['choices'][0];
        final content = choice['message']['content'] as String;
        final finishReason = choice['finish_reason'] as String?;

        debugPrint('[$blockName][Reflection] Finish reason: $finishReason');

        // Check if response was truncated
        if (finishReason == 'length') {
          debugPrint('[$blockName][Reflection] Warning: Response truncated');
          return null;
        }

        // Parse JSON
        try {
          final decoded = jsonDecode(content);
          
          // Debug: Print the actual AI response
          debugPrint('[$blockName][Reflection] AI response type: ${decoded.runtimeType}');
          debugPrint('[$blockName][Reflection] AI response content: $decoded');
          
          // Handle both Map and List responses
          if (decoded is List) {
            debugPrint('[$blockName][Reflection] AI returned List instead of Map, treating as validation passed');
            return null;
          }
          
          final result = decoded as Map<String, dynamic>;
          final isValid = result['valid'] == true;

          if (isValid) {
            debugPrint('[$blockName][Reflection] Validation passed');
            return null;
          } else {
            final issues = result['issues'] as List?;
            debugPrint('[$blockName][Reflection] Validation failed with ${issues?.length ?? 0} issues');
            return result;
          }
        } catch (e) {
          debugPrint('[$blockName][Reflection] Failed to parse JSON: $e');
          debugPrint('[$blockName][Reflection] Raw content: $content');
          return null;
        }
      } else {
        debugPrint('[$blockName][Reflection] API error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[$blockName][Reflection] Exception: $e');
      return null;
    }
  }

  /// Correct the generated JSON based on reflection issues
  Future<String> _correctWithReflection({
    required String prompt,
    required String answer,
    required String generatedJson,
    required Map<String, dynamic> reflectionResult,
    String? sourceLanguage,
    String? targetLanguage,
  }) async {
    final endpoint = await configService.getAIEndpoint();
    final apiKey = await configService.getAIApiKey();
    final model = await configService.getAIModel();
    final temperature = await configService.getAITemperature();

    final issues = reflectionResult['issues'] as List;
    final issuesText = issues.map((issue) {
      final field = issue['field'] ?? '';
      final problem = issue['problem'] ?? '';
      final current = issue['current'] ?? '';
      final suggested = issue['suggested'] ?? '';

      if (current.isNotEmpty && suggested.isNotEmpty) {
        return '''
字段：$field
问题：$problem
当前内容：$current
建议修正：$suggested''';
      } else {
        return '- $field: $problem';
      }
    }).join('\n\n');

    final correctionPrompt = '''
以下是你之前生成的${blockName}内容，但存在一些问题需要修正。

原始单词：$prompt
词义：$answer
${sourceLanguage != null ? '源语言（原文）：$sourceLanguage' : ''}
${targetLanguage != null ? '目标语言（译文）：$targetLanguage' : ''}

之前生成的JSON：
$generatedJson

发现的问题及修正建议：
$issuesText

**修正指导**：
1. 对于每个问题，如果提供了"建议修正"，请直接使用建议的内容替换"当前内容"
2. 确保修正后的内容符合语言规则：
   - highlights、extras 等说明字段：完全使用目标语言（译文）
   - textHtml、例句等原文字段：使用源语言（原文）；仅当源语言为日语时，才允许对日语汉字加 ruby
   - translation 等翻译字段：使用目标语言（译文），不要加 ruby
3. 如果需要在译文说明中引用原文词汇，用「」包裹，日语原文可以在「」内加 ruby 标注

请修正这些问题，返回完整的修正后的JSON。

只返回一个 JSON 对象，严禁输出除 JSON 外的任何内容；禁止使用 Markdown 代码块或 ```json 包裹。
''';

    try {
      final response = await http.post(
        Uri.parse('$endpoint/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': correctionPrompt}
          ],
          'temperature': temperature,
          'response_format': {'type': 'json_object'},
        }),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
        final content = jsonResponse['choices'][0]['message']['content'] as String;

        debugPrint('[$blockName][Correction] Corrected JSON generated');
        return content.trim();
      } else {
        debugPrint('[$blockName][Correction] API error: ${response.statusCode}');
        return generatedJson;
      }
    } catch (e) {
      debugPrint('[$blockName][Correction] Exception: $e');
      return generatedJson;
    }
  }

  /// Common helper to call AI API
  Future<Map<String, dynamic>> callAI({
    required String systemPrompt,
    required String userPrompt,
    String? referencesText,
  }) async {
    final endpoint = await configService.getAIEndpoint();
    final apiKey = await configService.getAIApiKey();
    final model = await configService.getAIModel();
    final temperature = await configService.getAITemperature();

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      if (referencesText != null && referencesText.isNotEmpty)
        {'role': 'user', 'content': referencesText},
      {'role': 'user', 'content': userPrompt},
    ];

    final response = await http.post(
      Uri.parse('$endpoint/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': temperature,
        'response_format': {'type': 'json_object'},
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('AI request failed: ${response.statusCode}');
    }

    final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
    final content = jsonResponse['choices'][0]['message']['content'] as String;

    return jsonDecode(content) as Map<String, dynamic>;
  }

  /// Build references text from sources HTML (sync, with optional budget)
  String? buildReferencesText(List<String>? sourcesHtml, {int budget = 16000}) {
    if (sourcesHtml == null || sourcesHtml.isEmpty) return null;
    
    final refs = sourcesHtml.where((e) => e.trim().isNotEmpty).toList();
    if (refs.isEmpty) return null;
    
    String decodeEntities(String s) {
      var out = s;
      out = out.replaceAll('&nbsp;', ' ');
      out = out.replaceAll('&amp;', '&');
      out = out.replaceAll('&lt;', '<');
      out = out.replaceAll('&gt;', '>');
      out = out.replaceAll('&quot;', '"');
      out = out.replaceAll('&#39;', "'");
      out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
        final code = int.tryParse(m.group(1)!);
        if (code == null) return m.group(0)!;
        return String.fromCharCode(code);
      });
      out = out.replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'), (m) {
        final code = int.tryParse(m.group(1)!, radix: 16);
        if (code == null) return m.group(0)!;
        return String.fromCharCode(code);
      });
      return out;
    }

    String cleanHtml(String html) {
      var s = html.trim();
      s = s.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '');
      s = s.replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '');
      s = s.replaceAllMapped(RegExp(r'<ruby><rb>(.*?)</rb><rt>(.*?)</rt></ruby>'), (m) => '${m.group(1)}(${m.group(2)})');
      s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
      s = s.replaceAll(RegExp(r'</?p[^>]*>', caseSensitive: false), '\n');
      s = s.replaceAll(RegExp(r'</?div[^>]*>', caseSensitive: false), '\n');
      s = s.replaceAll(RegExp(r'</?li[^>]*>', caseSensitive: false), '\n');
      s = s.replaceAll(RegExp(r'</?ul[^>]*>', caseSensitive: false), '\n');
      s = s.replaceAll(RegExp(r'</?ol[^>]*>', caseSensitive: false), '\n');
      s = s.replaceAll(RegExp(r'</?table[^>]*>', caseSensitive: false), '\n');
      s = s.replaceAll(RegExp(r'</?tr[^>]*>', caseSensitive: false), '\n');
      s = s.replaceAll(RegExp(r'</?td[^>]*>', caseSensitive: false), ' ');
      s = s.replaceAll(RegExp(r'</?th[^>]*>', caseSensitive: false), ' ');
      s = s.replaceAll(RegExp(r'</?h[1-6][^>]*>', caseSensitive: false), '\n');
      s = s.replaceAll(RegExp(r'<[^>]+>'), '');
      s = decodeEntities(s);
      s = s.replaceAll(RegExp(r'[ \t\f\r]+'), ' ');
      s = s.replaceAll(RegExp(r'\s*\n\s*'), '\n');
      s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
      return s.trim();
    }

    String truncateToBudget(List<String> items, int budget) {
      const sep = '\n\n---\n\n';
      final lengths = items.map((s) => s.length).toList();
      final total = lengths.fold<int>(0, (a, b) => a + b);
      if (total <= budget) return items.join(sep);
      final out = <String>[];
      for (var i = 0; i < items.length; i++) {
        final s = items[i];
        final share = ((s.length * budget) / total).floor();
        if (share <= 0) continue;
        var piece = s.substring(0, share);
        final cut = piece.lastIndexOf('\n');
        if (cut > 40) piece = piece.substring(0, cut);
        out.add(piece);
      }
      var joined = out.join(sep);
      if (joined.length > budget) {
        joined = joined.substring(0, budget);
        final cut = joined.lastIndexOf('\n');
        if (cut > 1000) joined = joined.substring(0, cut);
      }
      return joined;
    }

    final plainRefs = refs.map(cleanHtml).where((s) => s.isNotEmpty).toList();
    if (plainRefs.isEmpty) return null;
    final body = truncateToBudget(plainRefs, budget);
    return '参考词典原始HTML：\n' + body;
  }

  /// Async helper that reads budget from ConfigService
  Future<String?> buildReferencesTextWithConfig(List<String>? sourcesHtml) async {
    final b = await configService.getReferencesBudget();
    return buildReferencesText(sourcesHtml, budget: b);
  }
}
