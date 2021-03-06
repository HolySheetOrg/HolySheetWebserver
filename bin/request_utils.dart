import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart' as grpc;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

final log = Logger('RequestUtils');
final ACCESS_TOKEN_PATTERN = RegExp(r'^[a-zA-Z0-9-._~+\/]*$');
final uuid = Uuid();

const CLIENT_ID =
    '916425013479-6jdls4crv26mhurj43eakbs72f5e1m8t.apps.googleusercontent.com';
final FULL_SCOPES = [
  'https://www.googleapis.com/auth/userinfo.profile',
  'https://www.googleapis.com/auth/userinfo.email',
  'https://www.googleapis.com/auth/drive'
];

enum AuthMethod { Header, Query }

Future<Response> serveFile(Request request, String name, File file,
    [String contentType]) async {
  var stat = file.statSync();

  var headers = {
    HttpHeaders.contentLengthHeader: stat.size.toString(),
    'Content-Disposition': 'attachment; filename="$name"'
  };

  try {
    return Response.ok(file.openRead(), headers: headers);
  } finally {
    log.fine('Set timer for 15 minutes to delete ${file.absolute.path}');
    Timer(Duration(minutes: 15), () {
      log.fine('Deleting ${file.absolute.path}');
      file.delete();
    });
  }
}

/// Returns a [Response] with the code 200 Okay.
/// To see [body] docs, see [getBody].
Response ok(dynamic body) => getBody(200, body);

/// Returns a [Response] with the code 400 Bad Request.
/// To see [body] docs, see [getBody].
Response bad(dynamic body) => getBody(400, body);

/// Returns a [Response] with the code 403 Forbidden.
/// To see [body] docs, see [getBody].
Response forbidden(dynamic body) => getBody(403, body);

/// Returns a [Response] with the code 403 Forbidden.
/// To see [body] docs, see [getBody].
Response notFound(dynamic body) => getBody(404, body);

/// Returns a [Response] with the code 500 Internal Server Error.
/// To see [body] docs, see [getBody].
Response ise(String message) {
  return getBody(500, {'message': message});
}

/// Gets the body, used for [Request]s.
/// [body] can be either a Map<String, String> which is encoded into a JSON
/// map, whereas anything else will be [toString]'d and put with an `error`
/// key.
Response getBody(int code, dynamic body, {String defaultKey = 'message'}) {
  if (body is String) {
    body = {defaultKey: body ?? 'Unknown message'};
  }
  return Response(code, body: jsonEncode(body), headers: {'Content-Type': 'application/json'});
}

/// Processes a stream [stream], until [breakOut] returns true, being compared
/// with elements in the stream via [listen]. Once completed, [finResult] will
/// be invoked with the last element and returned.
Future<R> processStream<R, I>(Stream<I> stream, bool Function(I input) breakOut,
    R Function(I input) finResult) async {
  final completer = Completer<R>();

  StreamSubscription<I> sub;
  sub = stream.listen((i) {
    if (breakOut(i)) {
      sub.cancel();
      completer.complete(finResult(i));
    }
  });

  sub.onError((error) =>
      completer.completeError('Ane error occurred during processing: $error'));

  return completer.future;
}

/// Decodes post values
Future<Map<String, String>> decodeRequest(Request request) async =>
    Map.fromEntries((await request.readAsString()).split('&').map((kv) {
      var split = kv.split('=').map((str) => Uri.decodeComponent(str)).toList();
      return MapEntry(split[0], split[1]);
    }).toList());

bool isValidParam(String param) =>
    param != null && param != 'null' && param.isNotEmpty;

Future<bool> verifyToken(String accessToken) async {
  try {
    if (accessToken == null || !ACCESS_TOKEN_PATTERN.hasMatch(accessToken)) {
      return Future.value(false);
    }

    var response = await http.get(
        'https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=$accessToken');
    var json = jsonDecode(response.body);

    if (json['audience'] != CLIENT_ID) {
      return false;
    }

    var split = json['scope']?.split(' ')?.toSet();
    if (!(split?.containsAll(FULL_SCOPES) ?? true)) {
      return false;
    }

    return true;
  } catch (ignored) {
    return false;
  }
}

extension ErrorStreamCatcher<T> on grpc.ResponseStream<T> {
  grpc.ResponseStream<T> printErrors() {
    handleError((e, s) => log.severe('An error has occurred during a gRPC request future', e, s));
    return this;
  }
}

extension ErrorFutureCatcher<T> on grpc.ResponseFuture<T> {
  grpc.ResponseFuture<T> printErrors() {
    catchError((e, s) => log.severe('An error has occurred during a gRPC request future', e, s));
    return this;
  }
}

extension PathUtils on String {
  String correctPath() {
    if (length == 0) {
      return '/';
    } else if (length == 1) {
      if (this == '/') {
        return this;
      } else {
        return '/$this/';
      }
    } else {
      var out = this;
      if (!startsWith('/')) {
        out = '/$out';
      }

      if (!endsWith('/')) {
        out = '$out/';
      }
      return out;
    }
  }
}

extension NumberPad on int {
  String get timePadded => toString().padLeft(2, '0');
}

String json(Map<String, dynamic> json) => jsonEncode(json);
