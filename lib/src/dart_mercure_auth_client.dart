import 'dart:async';
import 'package:http/http.dart' as http;

class AuthClient extends http.BaseClient {

  final String _token;
  final http.Client _inner;

  AuthClient(this._token, this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }
}