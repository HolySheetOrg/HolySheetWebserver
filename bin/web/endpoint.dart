import 'dart:async';

import 'package:HolySheetWebserver/generated/holysheet_service.pbgrpc.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../request_utils.dart';
import 'service.dart';

abstract class Endpoint implements Service {

  final log = Logger('Endpoint');

  HolySheetServiceClient client;

  String route;
  String verb = 'GET';
  AuthMethod authMethod;

  Endpoint({@required String route, AuthMethod authMethod = AuthMethod.Header}) : route = route, authMethod = authMethod;

  @override
  void register(Router router, HolySheetServiceClient client) {
    this.client = client;

    router.add(verb, route, (Request request) async {
      final token = ({
        AuthMethod.Header: () => request.headers['Authorization'],
        AuthMethod.Query: () => request.url.queryParameters['Authorization'],
      })[authMethod]();

      if (token == null) {
        return forbidden('No token found');
      }

      if (!await verifyToken(token)) {
        return forbidden('Invalid checked token');
      }

      try {
        return await handle(request, token, request.url?.queryParameters ?? {});
      } catch (e, s) {
        log.severe('An error has occurred while processing endpoint $verb $route', e, s);
        return ise('An internal server error has occurred');
      }
    });
  }

  Future<Response> handle(
      Request request, String token, Map<String, String> query);
}
