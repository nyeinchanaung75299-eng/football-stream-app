import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:football_viewer/screens/highlights_page.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://fixture.example',
      publishableKey: 'test-public',
      authOptions: const FlutterAuthClientOptions(
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
      httpClient: MockClient((request) async {
        expect(request.url.path, endsWith('/highlights'));
        expect(request.url.queryParameters['is_active'], 'eq.true');
        return http.Response(
          jsonEncode([
            {
              'id': 'highlight',
              'title': 'Home vs Away highlights',
              'video_url': 'https://cdn.example/highlight.mp4',
              'stream_type': 'mp4',
              'referer': 'https://publisher.example/',
              'origin': 'https://publisher.example',
              'user_agent': 'Public player',
            },
          ]),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  testWidgets(
    'published highlight opens the native player with its source headers',
    (tester) async {
      Map? arguments;
      const bridge = MethodChannel('football_stream/native_player');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (
        call,
      ) async {
        arguments = call.arguments as Map;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          bridge,
          null,
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: HighlightsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home vs Away highlights'));
      await tester.pumpAndSettle();
      final source =
          (jsonDecode(arguments!['sourcesJson'] as String) as List).single
              as Map;
      expect(source['url'], 'https://cdn.example/highlight.mp4');
      expect(source['streamType'], 'mp4');
      expect(source['referer'], 'https://publisher.example/');
      expect(source['origin'], 'https://publisher.example');
      expect(source['userAgent'], 'Public player');
      expect(tester.takeException(), isNull);
    },
  );
}
