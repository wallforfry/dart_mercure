import 'package:dart_mercure/dart_mercure.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final hubUrl = Uri.parse('https://hub.test/.well-known/mercure');

void main() {
  test('posts a form-encoded update and returns its ID', () async {
    late http.Request sent;
    final mercure = Mercure(
      hubUrl: hubUrl,
      publisherToken: 'pub-jwt',
      client: MockClient((request) async {
        sent = request;
        return http.Response('urn:uuid:1', 200);
      }),
    );

    final id = await mercure.publish(
      topics: ['https://example.com/books/1', 'books'],
      data: 'a b&c',
      id: 'custom',
      private: true,
      type: 'update',
      retry: const Duration(seconds: 2),
    );

    expect(id, 'urn:uuid:1');
    expect(sent.method, 'POST');
    expect(sent.url, hubUrl);
    expect(sent.headers['Authorization'], 'Bearer pub-jwt');
    expect(
      sent.headers['Content-Type'],
      startsWith('application/x-www-form-urlencoded'),
    );
    expect(Uri(query: sent.body).queryParametersAll, {
      'topic': ['https://example.com/books/1', 'books'],
      'data': ['a b&c'],
      'id': ['custom'],
      'private': ['on'],
      'type': ['update'],
      'retry': ['2000'],
    });
  });

  test('omits optional fields and authorization when not set', () async {
    late http.Request sent;
    final mercure = Mercure(
      hubUrl: hubUrl,
      client: MockClient((request) async {
        sent = request;
        return http.Response('id', 200);
      }),
    );

    await mercure.publish(topics: ['t'], data: 'd');

    expect(sent.headers, isNot(contains('Authorization')));
    expect(Uri(query: sent.body).queryParametersAll.keys, ['topic', 'data']);
  });

  test('throws MercurePublishException when the hub rejects the update', () {
    final mercure = Mercure(
      hubUrl: hubUrl,
      client: MockClient((_) async => http.Response('Unauthorized', 401)),
    );

    expect(
      mercure.publish(topics: ['t'], data: 'd'),
      throwsA(
        isA<MercurePublishException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', contains('Unauthorized')),
      ),
    );
  });

  test('rejects an empty topic list', () {
    final mercure = Mercure(
      hubUrl: hubUrl,
      client: MockClient((_) async => http.Response('', 200)),
    );

    expect(() => mercure.publish(topics: [], data: 'd'), throwsArgumentError);
  });
}
