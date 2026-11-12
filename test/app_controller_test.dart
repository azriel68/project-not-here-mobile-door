import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:door/app_controller.dart';

class MemoryAppStorage implements AppStorage {
  MemoryAppStorage([Map<String, String>? initialValues])
      : values = initialValues ?? {};

  final Map<String, String> values;

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

Dio dioWithResponder(
    Future<Response<dynamic>> Function(RequestOptions options) respond) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final response = await respond(options);
      if ((response.statusCode ?? 200) >= 400) {
        handler.reject(DioException(
          requestOptions: options,
          response: response,
          type: DioExceptionType.badResponse,
        ));
      } else {
        handler.resolve(response);
      }
    },
  ));
  return dio;
}

const testCowork = Cowork(
  id: 'cowork-1',
  name: 'Cowork de test',
  hostname: 'cowork.test',
  frontUrl: 'https://cowork.test/',
);

void main() {
  test('keeps the configured localhost address for USB-connected Android', () {
    final dio = Dio();
    AppController(
      storage: MemoryAppStorage(),
      dio: dio,
      initialApiBaseUrl: 'http://127.0.0.1:8000/',
    );

    expect(dio.options.baseUrl, 'http://127.0.0.1:8000/');
  });

  test('switches from the test API to production on the login page', () async {
    final storage = MemoryAppStorage({
      'selected_cowork': jsonEncode(testCowork.toJson()),
      'user_email': 'membre@example.test',
    });
    final dio = Dio();
    final controller = AppController(
      storage: storage,
      dio: dio,
      initialApiBaseUrl: 'http://127.0.0.1:8000/',
      productionApiBaseUrl: 'https://api.example.test/',
    );
    await controller.initialize();
    expect(controller.canSwitchToProductionApi, isTrue);

    await controller.useProductionApi();

    expect(controller.isProductionApi, isTrue);
    expect(controller.canSwitchToProductionApi, isFalse);
    expect(dio.options.baseUrl, 'https://api.example.test/');
    expect(controller.selectedCowork, isNull);
    expect(controller.email, 'membre@example.test');
    expect(storage.values['api_base_url'], 'https://api.example.test/');
    expect(storage.values.containsKey('selected_cowork'), isFalse);
  });

  test('explains when the configured API has not deployed the places route',
      () async {
    final controller = AppController(
      storage: MemoryAppStorage(),
      dio: dioWithResponder((options) async => Response(
            requestOptions: options,
            data: {'error': 'Not Found'},
            statusCode: 404,
          )),
      initialApiBaseUrl: 'https://api.example.test/',
    );

    await expectLater(
      controller.loadCoworks(),
      throwsA(
        isA<AppException>().having(
          (error) => error.message,
          'message',
          contains('GET /mobile/places'),
        ),
      ),
    );
  });

  test('restores cowork, email, and an unexpired token', () async {
    final storage = MemoryAppStorage({
      'selected_cowork': jsonEncode(testCowork.toJson()),
      'user_email': 'membre@example.test',
      'access_token': 'valid-token',
    });
    RequestOptions? request;
    final controller = AppController(
      storage: storage,
      dio: dioWithResponder((options) async {
        request = options;
        return Response(
          requestOptions: options,
          data: {'email': 'membre@example.test'},
          statusCode: 200,
        );
      }),
      initialApiBaseUrl: 'https://api.example.test/',
    );

    await controller.initialize();

    expect(controller.isAuthenticated, isTrue);
    expect(controller.email, 'membre@example.test');
    expect(controller.selectedCowork?.id, testCowork.id);
    expect(controller.user['email'], 'membre@example.test');
    expect(request?.path, 'me');
    expect(request?.headers['Authorization'], 'Bearer valid-token');
    expect(storage.values['access_token'], 'valid-token');
  });

  test('clears an expired token and keeps the remembered email and cowork',
      () async {
    final storage = MemoryAppStorage({
      'selected_cowork': jsonEncode(testCowork.toJson()),
      'user_email': 'membre@example.test',
      'access_token': 'expired-token',
    });
    final controller = AppController(
      storage: storage,
      dio: dioWithResponder((options) async => Response(
            requestOptions: options,
            data: {'message': 'TokenExpired'},
            statusCode: 401,
          )),
      initialApiBaseUrl: 'https://api.example.test/',
    );

    await controller.initialize();

    expect(controller.isAuthenticated, isFalse);
    expect(controller.token, isNull);
    expect(storage.values.containsKey('access_token'), isFalse);
    expect(controller.email, 'membre@example.test');
    expect(controller.selectedCowork?.id, testCowork.id);
  });

  test('requests a long-life token and remembers the email on login', () async {
    final storage = MemoryAppStorage();
    RequestOptions? request;
    final controller = AppController(
      storage: storage,
      dio: dioWithResponder((options) async {
        request = options;
        return Response(
          requestOptions: options,
          data: {
            'token': 'long-life-token',
            'user': {'email': 'membre@example.test'},
          },
          statusCode: 200,
        );
      }),
      initialApiBaseUrl: 'https://api.example.test/',
    );
    await controller.selectCowork(testCowork);

    await controller.login(' membre@example.test ', 'password');

    expect(request?.data['stayConnected'], isTrue);
    expect(controller.email, 'membre@example.test');
    expect(storage.values['user_email'], 'membre@example.test');
    expect(storage.values['access_token'], 'long-life-token');
    expect(controller.isAuthenticated, isTrue);
  });

  test('falls back to production when the development API is unreachable',
      () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) => handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      )),
    ));
    final url = await resolveReachableApiBaseUrl(
      'http://127.0.0.1:8000/',
      'https://api.example.test/',
      dio: dio,
    );

    expect(url, 'https://api.example.test/');
  });

  test('keeps the development API when it answers, even with an error',
      () async {
    final url = await resolveReachableApiBaseUrl(
      'http://127.0.0.1:8000/',
      'https://api.example.test/',
      dio: dioWithResponder((options) async => Response(
            requestOptions: options,
            data: {'error': 'Not Found'},
            statusCode: 404,
          )),
    );

    expect(url, 'http://127.0.0.1:8000/');
  });

  test('forgets cowork and session when the API changes', () async {
    final storage = MemoryAppStorage({
      'api_base_url': 'http://127.0.0.1:8000/',
      'selected_cowork': jsonEncode(testCowork.toJson()),
      'user_email': 'membre@example.test',
      'access_token': 'dev-token',
    });
    final controller = AppController(
      storage: storage,
      dio: dioWithResponder((options) async =>
          Response(requestOptions: options, statusCode: 200, data: {})),
      initialApiBaseUrl: 'https://api.example.test/',
      productionApiBaseUrl: 'https://api.example.test',
    );

    await controller.initialize();

    expect(controller.isProductionApi, isTrue);
    expect(controller.token, isNull);
    expect(controller.selectedCowork, isNull);
    expect(controller.email, 'membre@example.test');
    expect(storage.values['api_base_url'], 'https://api.example.test/');
  });

  test('allows doors when the API has no door access route', () async {
    final controller = AppController(
      storage: MemoryAppStorage(),
      dio: dioWithResponder((options) async => Response(
            requestOptions: options,
            statusCode: 404,
          )),
      initialApiBaseUrl: 'https://api.example.test/',
    );

    expect(
        await controller.getDoorAccess(), {'canOpen': true, 'canClose': true});
  });

  test('keeps only shared doors and the rooms booked today', () async {
    final controller = AppController(
      storage: MemoryAppStorage(),
      dio: dioWithResponder((options) async => Response(
            requestOptions: options,
            statusCode: 200,
            data: switch (options.path) {
              'the-place-to-work' => {
                  'smartlocks': [
                    {'id': 1, 'label': 'Entrée', 'room_id': null},
                    {'id': 2, 'label': 'Salle A', 'room_id': 10},
                    {'id': 3, 'label': '', 'room_id': 20},
                  ]
                },
              'user/occupations/today' => [
                  {
                    'desk': {'room_id': 20}
                  }
                ],
              _ => {'canOpen': true, 'canClose': false},
            },
          )),
      initialApiBaseUrl: 'https://api.example.test/',
    )
      ..token = 'test-token'
      ..selectedCowork = testCowork;

    final access = await controller.loadDoors();

    expect(access.doors.map((door) => door.id), [1, 3]);
    expect(access.doors.last.label, 'Porte du cowork');
    expect(access.canOpen, isTrue);
    expect(access.canClose, isFalse);
  });

  test('sends the door command with the position', () async {
    RequestOptions? request;
    final controller = AppController(
      storage: MemoryAppStorage(),
      dio: dioWithResponder((options) async {
        request = options;
        return Response(requestOptions: options, statusCode: 200);
      }),
      initialApiBaseUrl: 'https://api.example.test/',
    )
      ..token = 'test-token'
      ..selectedCowork = testCowork;

    await controller.setDoor(3, open: true, latitude: 48.8, longitude: 2.3);

    expect(request?.path, 'user/door/3/open');
    expect(request?.data, {
      'coordinates': [48.8, 2.3]
    });
    expect(request?.headers['Coworkid'], 'cowork-1');
  });

  test('returns to login when the token is refused during use', () async {
    final storage = MemoryAppStorage({'access_token': 'old-token'});
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 401),
            type: DioExceptionType.badResponse,
          ),
          true),
    ));
    final controller = AppController(
      storage: storage,
      dio: dio,
      initialApiBaseUrl: 'https://api.example.test/',
    )
      ..token = 'old-token'
      ..selectedCowork = testCowork
      ..isReady = true;

    await expectLater(controller.loadDoors(), throwsA(isA<AppException>()));

    expect(controller.isAuthenticated, isFalse);
    expect(storage.values.containsKey('access_token'), isFalse);
    expect(controller.selectedCowork, testCowork);
  });

  test('remembers who is signed in for an offline start', () async {
    final storage = MemoryAppStorage({
      'selected_cowork': jsonEncode(testCowork.toJson()),
      'user_email': 'camille@example.test',
    });
    final online = AppController(
      storage: storage,
      dio: dioWithResponder((options) async => Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'token': 'long-token',
              'user': {
                'firstname': 'Camille',
                'lastname': 'Martin',
                'email': 'camille@example.test',
                'phone': '0600000000',
              },
            },
          )),
      initialApiBaseUrl: 'https://api.example.test/',
    );
    await online.initialize();
    await online.login('camille@example.test', 'secret');
    expect(online.firstName, 'Camille');

    final offline = AppController(
      storage: storage,
      dio: dioWithResponder((options) async =>
          Response(requestOptions: options, statusCode: 503)),
      initialApiBaseUrl: 'https://api.example.test/',
    );
    await offline.initialize();

    expect(offline.isAuthenticated, isTrue);
    expect(offline.firstName, 'Camille');
    expect(offline.identity, 'Camille Martin · camille@example.test');
    expect(storage.values['user_identity'], isNot(contains('0600000000')));
  });
}
