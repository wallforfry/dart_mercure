import 'dart:convert';

import 'package:dart_mercure/dart_mercure.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final hubUrl = Uri.parse('https://hub.test/.well-known/mercure');

const anyTopic = [TopicMatcher.exact('t')];

http.StreamedResponse eventStream(Stream<String> body, {int status = 200}) =>
    http.StreamedResponse(
      body.map(utf8.encode),
      status,
      headers: {'content-type': 'text/event-stream; charset=utf-8'},
    );

Mercure mercureWith(
  Future<http.StreamedResponse> Function(http.BaseRequest request) handler, {
  String? subscriberToken,
  Duration defaultRetry = Duration.zero,
}) => Mercure(
  hubUrl: hubUrl,
  subscriberToken: subscriberToken,
  defaultRetry: defaultRetry,
  client: MockClient.streaming((request, _) => handler(request)),
);
