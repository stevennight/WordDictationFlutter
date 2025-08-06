// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_word_dictation/main.dart';

void main() {
  setUpAll(() {
    // Initialize sqflite for testing
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  
  testWidgets('Word Dictation App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const WordDictationApp());
    
    // Wait for initial frame
    await tester.pump();
    
    // Verify that the app shows loading initially
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    
    // Wait for app to initialize with a timeout
    await tester.pump(const Duration(seconds: 2));
    
    // The test passes if the app can be built without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
