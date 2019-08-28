import 'package:dart_mercure/dart_mercure.dart';
import 'package:test/test.dart';

void main() {
  group('Test mercure package', () {
    Mercure mercure;
    Mercure mercure_bad_token;
    String token;
    String hub_url;
    String topic;

    setUp(() {
      topic = "http://mercure/test";
      token =
          "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJtZXJjdXJlIjp7InN1YnNjcmliZSI6WyIqIl0sInB1Ymxpc2giOlsiKiJdfX0.Gfj3BFrSOFhyFN0hPOYg-Pe4dfYWOKq7QJiMWYC2Z_k";
      hub_url = "http://mercure/hub";
      mercure = Mercure(token: token, hub_url: hub_url);
    });

    test('Subscribe Topic', () {
      String value = "NODATA";
      mercure.subscribeTopic(
          topic: topic,
          onData: (Event event) {
            value = event.data;
          });
      Future.delayed(const Duration(seconds: 1), () {
        mercure.publish(topic: topic, data: "DATA").then((_) {
          expect(value, "DATA");
        });
      });
    });

    test('Test Publish', () async {
      expect(await mercure.publish(topic: topic, data: "DATA"), 200);
    });

    test('Test Publish bad token', () async {
      mercure_bad_token = Mercure(token: token + "A", hub_url: hub_url);
      expect(await mercure_bad_token.publish(topic: topic, data: "DATA"), 401);
    });
  });
}
