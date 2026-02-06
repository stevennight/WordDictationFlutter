import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../ai_debug_service.dart';
import '../config_service.dart';

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
    void Function()? onReflectionStart,
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

    // Notify that reflection is starting
    onReflectionStart?.call();

    // Validate and correct with retry
    return await validateAndCorrectWithRetry(
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
  Future<Map<String, dynamic>> validateAndCorrectWithRetry({
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

      // Log reflection result
      try {
        final debugService = await AIDebugService.getInstance();
        await debugService.logReflection(
          blockName: blockName,
          attempt: attempt,
          prompt: prompt,
          generatedJson: jsonEncode(currentJson),
          reflectionResult: reflectionResult,
        );
      } catch (e) {
        debugPrint('Failed to log reflection: $e');
      }

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

        // Log correction result
        try {
          final debugService = await AIDebugService.getInstance();
          await debugService.logCorrection(
            blockName: blockName,
            attempt: attempt,
            correctedJson: correctedJson,
          );
        } catch (e) {
          debugPrint('Failed to log correction: $e');
        }

        // Validate the JSON format
        try {
          currentJson = jsonDecode(correctedJson) as Map<String, dynamic>;
          debugPrint('[$blockName] Correction completed, will re-validate');
        } catch (e) {
          debugPrint('[$blockName] Corrected JSON is invalid: $e');
          // If correction produces invalid JSON on last attempt, fail
          if (attempt >= maxAttempts - 1) {
            throw Exception('[$blockName] Correction produced invalid JSON on attempt $attempt: $e');
          }
          // Otherwise keep current version and retry
          debugPrint('[$blockName] Keeping current version for next attempt');
        }
      } else {
        // Max attempts reached, validation still failed
        debugPrint('[$blockName] Max correction attempts ($maxAttempts) reached, validation failed');
        throw Exception('[$blockName] Reflection failed after $maxAttempts attempts. Issues found: ${issues?.join(", ") ?? "unknown"}');
      }
    }

    // This should never be reached due to the loop logic, but just in case
    throw Exception('[$blockName] Reflection validation loop ended unexpectedly');
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
    // Force low temperature for reflection to ensure strict rule checking
    const temperature = 0.1;

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

    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
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
            'temperature': temperature,
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
          // Check if error is retryable (5xx server errors)
          final isRetryable = response.statusCode >= 500 && response.statusCode < 600;
          debugPrint('[$blockName][Reflection] API error: ${response.statusCode}');
          
          if (isRetryable && attempt < maxRetries) {
            final delayMs = 1000 * (1 << (attempt - 1));
            debugPrint('[$blockName][Reflection] Retrying in ${delayMs}ms...');
            await Future.delayed(Duration(milliseconds: delayMs));
            continue;
          }
          
          // Non-retryable error or max retries reached
          return null;
        }
      } catch (e) {
        debugPrint('[$blockName][Reflection] Exception on attempt $attempt/$maxRetries: $e');
        
        // Only retry on network errors or 5xx errors
        if (attempt < maxRetries && (e.toString().contains('500') || e.toString().contains('502') || 
            e.toString().contains('503') || e.toString().contains('504') || 
            e.toString().contains('SocketException') || e.toString().contains('TimeoutException'))) {
          final delayMs = 1000 * (1 << (attempt - 1));
          debugPrint('[$blockName][Reflection] Retrying in ${delayMs}ms...');
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        
        // Non-retryable error or max retries reached
        return null;
      }
    }
    
    // All retries exhausted
    debugPrint('[$blockName][Reflection] All retry attempts exhausted');
    return null;
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
    final temperature = 0.1; // Force low temperature for correction to ensure precision

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
你是一个专业的辞书编辑。之前的生成内容在质量审查中被发现存在问题。
请根据审查意见（Issues），重新生成并修正 JSON 内容。

原始单词：$prompt
词义：$answer
${sourceLanguage != null ? '源语言（原文）：$sourceLanguage' : ''}
${targetLanguage != null ? '目标语言（译文）：$targetLanguage' : ''}

之前生成的JSON：
$generatedJson

**审查意见**：
$issuesText

**严格修正标准（必须遵守）**：
1. **精准修正**：只修改审查意见中指出的错误，保持其他正确内容不变。
2. **格式规范**：必须返回合法的 JSON，严禁破坏 JSON 结构。
3. **语言学规则（高频错误预警）**：
   - **Ruby 标注规则**：
     - ❌ 错误：`<ruby>平假名<rt>...</rt></ruby>` (绝对禁止给平/片假名注音)
     - ❌ 错误：`<ruby>中文翻译<rt>...</rt></ruby>` (绝对禁止给中文/译文注音)
     - ✅ 正确：`<ruby>漢字<rt>かんじ</rt></ruby>` (仅给源语言中的汉字注音)
   - **字段语言归属**：
     - textHtml、例句原文 -> 使用源语言
     - translation、解释说明 -> 使用目标语言

请输出修正后的完整 JSON。
只返回一个 JSON 对象，严禁输出除 JSON 外的任何内容。
''';

    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
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
          // Check if error is retryable (5xx server errors)
          final isRetryable = response.statusCode >= 500 && response.statusCode < 600;
          debugPrint('[$blockName][Correction] API error: ${response.statusCode}');
          
          if (isRetryable && attempt < maxRetries) {
            final delayMs = 1000 * (1 << (attempt - 1));
            debugPrint('[$blockName][Correction] Retrying in ${delayMs}ms...');
            await Future.delayed(Duration(milliseconds: delayMs));
            continue;
          }
          
          // Non-retryable error or max retries reached
          debugPrint('[$blockName][Correction] Returning original JSON after $attempt attempts');
          return generatedJson;
        }
      } catch (e) {
        debugPrint('[$blockName][Correction] Exception on attempt $attempt/$maxRetries: $e');
        
        // Only retry on network errors or 5xx errors
        if (attempt < maxRetries && (e.toString().contains('500') || e.toString().contains('502') || 
            e.toString().contains('503') || e.toString().contains('504') || 
            e.toString().contains('SocketException') || e.toString().contains('TimeoutException'))) {
          final delayMs = 1000 * (1 << (attempt - 1));
          debugPrint('[$blockName][Correction] Retrying in ${delayMs}ms...');
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        
        // Non-retryable error or max retries reached
        debugPrint('[$blockName][Correction] Returning original JSON after exception');
        return generatedJson;
      }
    }
    
    // All retries exhausted
    debugPrint('[$blockName][Correction] All retry attempts exhausted, returning original JSON');
    return generatedJson;
  }

  /// Common helper to call AI API with retry mechanism
  Future<Map<String, dynamic>> callAI({
    required String systemPrompt,
    required String userPrompt,
    String? referencesText,
  }) async {
    return _callAIWithRetry(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      referencesText: referencesText,
    );
  }

  /// Internal method to call AI API with retry logic
  Future<Map<String, dynamic>> _callAIWithRetry({
    required String systemPrompt,
    required String userPrompt,
    String? referencesText,
    int maxRetries = 3,
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

    Exception? lastException;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
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

        if (response.statusCode == 200) {
          final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
          final content = jsonResponse['choices'][0]['message']['content'] as String;
          return jsonDecode(content) as Map<String, dynamic>;
        }

        // Check if error is retryable (5xx server errors)
        final isRetryable = response.statusCode >= 500 && response.statusCode < 600;
        if (!isRetryable) {
          throw Exception('AI request failed: ${response.statusCode} ${response.body}');
        }

        // Retryable error
        lastException = Exception('AI request failed: ${response.statusCode}');
        debugPrint('[$blockName] API error ${response.statusCode} on attempt $attempt/$maxRetries');
        
        if (attempt < maxRetries) {
          // Exponential backoff: 1s, 2s, 4s
          final delayMs = 1000 * (1 << (attempt - 1));
          debugPrint('[$blockName] Retrying in ${delayMs}ms...');
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        debugPrint('[$blockName] Exception on attempt $attempt/$maxRetries: $e');
        
        // Only retry on network errors or 5xx errors
        if (attempt < maxRetries && (e.toString().contains('500') || e.toString().contains('502') || 
            e.toString().contains('503') || e.toString().contains('504') || 
            e.toString().contains('SocketException') || e.toString().contains('TimeoutException'))) {
          final delayMs = 1000 * (1 << (attempt - 1));
          debugPrint('[$blockName] Retrying in ${delayMs}ms...');
          await Future.delayed(Duration(milliseconds: delayMs));
        } else {
          // Non-retryable error or max retries reached
          rethrow;
        }
      }
    }

    // All retries exhausted
    throw lastException ?? Exception('AI request failed after $maxRetries attempts');
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
