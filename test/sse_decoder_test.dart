import 'dart:convert';

import 'package:dart_mercure/src/sse_decoder.dart';
import 'package:test/test.dart';

Future<List<SseFrame>> decode(List<String> chunks) =>
    Stream<List<int>>.fromIterable(
      chunks.map(utf8.encode),
    ).transform(sseDecoder).toList();

Matcher isEvent(String data, {String type = 'message', String? id}) =>
    isA<SseEvent>()
        .having((e) => e.data, 'data', data)
        .having((e) => e.type, 'type', type)
        .having((e) => e.lastEventId, 'lastEventId', id);

void main() {
  test('dispatches an event on a blank line', () async {
    expect(await decode(['data: hello\n\n']), [isEvent('hello')]);
  });

  test('joins data lines with line feeds', () async {
    expect(await decode(['data: a\ndata: b\n\n']), [isEvent('a\nb')]);
  });

  test('keeps the last event ID across events', () async {
    expect(await decode(['id: 1\nevent: ping\ndata: a\n\ndata: b\n\n']), [
      isEvent('a', type: 'ping', id: '1'),
      isEvent('b', id: '1'),
    ]);
  });

  test('ignores comments and unknown fields', () async {
    expect(await decode([':heartbeat\nfoo: bar\ndata: x\n\n']), [isEvent('x')]);
  });

  test('strips only one leading space from values', () async {
    expect(await decode(['data:  x\n\ndata:y\n\n']), [
      isEvent(' x'),
      isEvent('y'),
    ]);
  });

  test('treats a line without colon as a field with an empty value', () async {
    expect(await decode(['data\n\n']), [isEvent('')]);
  });

  test('does not dispatch a block without data', () async {
    expect(await decode(['event: ping\n\ndata: x\n\n']), [isEvent('x')]);
  });

  test('accepts CRLF and CR line endings', () async {
    expect(await decode(['data: a\r\n\r\ndata: b\r\r']), [
      isEvent('a'),
      isEvent('b'),
    ]);
  });

  test('reassembles lines and characters split across chunks', () async {
    final bytes = utf8.encode('data: é\r\n\r\n');
    final frames = await Stream<List<int>>.fromIterable([
      bytes.sublist(0, 7),
      bytes.sublist(7, 9),
      bytes.sublist(9),
    ]).transform(sseDecoder).toList();
    expect(frames, [isEvent('é')]);
  });

  test('discards an event left incomplete at the end of the stream', () async {
    expect(await decode(['data: a\n\ndata: b\n']), [isEvent('a')]);
  });

  test('emits retry delays made of digits only', () async {
    final frames = await decode(['retry: 1500\nretry: 1s\n\n']);
    expect(frames, [
      isA<SseRetry>().having(
        (r) => r.delay,
        'delay',
        const Duration(milliseconds: 1500),
      ),
    ]);
  });

  test('ignores an ID containing NUL', () async {
    expect(await decode(['id: 1\n\nid: a\u0000b\ndata: x\n\n']), [
      isEvent('x', id: '1'),
    ]);
  });

  test('strips a leading byte order mark', () async {
    expect(await decode(['﻿data: x\n\n']), [isEvent('x')]);
  });
}
