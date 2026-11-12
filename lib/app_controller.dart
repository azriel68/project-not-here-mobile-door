import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

/// Returns [preferred] when its server answers, otherwise [fallback].
/// Any HTTP response, even an error status, counts as reachable.
Future<String> resolveReachableApiBaseUrl(String preferred, String fallback,
    {Dio? dio}) async {
  if (preferred.isEmpty) return fallback;
  if (fallback.isEmpty ||
      normalizedApiBaseUrl(preferred) == normalizedApiBaseUrl(fallback)) {
    return preferred;
  }
  final probe = dio ??
      Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 5)));
  try {
    await probe
        .get<dynamic>('${normalizedApiBaseUrl(preferred)}/mobile/places');
    return preferred;
  } on DioException catch (error) {
    return error.response != null ? preferred : fallback;
  }
}

String normalizedApiBaseUrl(String value) =>
    value.trim().replaceFirst(RegExp(r'/+$'), '');

abstract interface class AppStorage {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class FlutterSecureAppStorage implements AppStorage {
  FlutterSecureAppStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

class Cowork {
  const Cowork(
      {required this.id,
      required this.name,
      required this.hostname,
      required this.frontUrl});

  final String id;
  final String name;
  final String hostname;
  final String frontUrl;

  factory Cowork.fromJson(Map<String, dynamic> json) => Cowork(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? 'Cowork'}',
        hostname: '${json['hostname'] ?? ''}',
        frontUrl: '${json['front_url'] ?? ''}',
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'hostname': hostname, 'front_url': frontUrl};
}

class AppController extends ChangeNotifier {
  AppController(
      {AppStorage? storage,
      Dio? dio,
      String? initialApiBaseUrl,
      this.productionApiBaseUrl = ''})
      : _storage = storage ?? FlutterSecureAppStorage(),
        _dio = dio ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 25))),
        apiBaseUrl = initialApiBaseUrl ?? apiBaseUrlOverride {
    if (apiBaseUrl.isNotEmpty) {
      _dio.options.baseUrl = apiBaseUrl;
    }
    _dio.interceptors.add(InterceptorsWrapper(onError: (error, handler) async {
      // An authenticated call refused with 401: the long-life token expired
      // or was revoked, so go back to login (cowork and email are kept).
      final sentToken = error.requestOptions.headers['Authorization'];
      if (error.response?.statusCode == 401 &&
          sentToken != null &&
          sentToken == 'Bearer $token' &&
          isReady) {
        await _clearStoredToken();
        user = {};
        notifyListeners();
      }
      handler.next(error);
    }));
  }

  final AppStorage _storage;
  final Dio _dio;
  static const _apiKey = 'api_base_url';
  static const _coworkKey = 'selected_cowork';
  static const _tokenKey = 'access_token';
  static const _emailKey = 'user_email';

  String apiBaseUrl;
  final String productionApiBaseUrl;
  String email = '';
  List<Cowork> coworkers = [];
  Cowork? selectedCowork;
  String? token;
  Map<String, dynamic> user = {};
  bool isReady = false;
  bool isBusy = false;

  bool get isAuthenticated => token != null && selectedCowork != null;

  bool get isProductionApi =>
      productionApiBaseUrl.isNotEmpty &&
      normalizedApiBaseUrl(apiBaseUrl) ==
          normalizedApiBaseUrl(productionApiBaseUrl);

  bool get canSwitchToProductionApi =>
      productionApiBaseUrl.isNotEmpty && !isProductionApi && !isAuthenticated;

  /// Leaves the development API for production, from the login page only:
  /// the cowork list and the selected cowork belong to the previous API.
  Future<void> useProductionApi() async {
    if (!canSwitchToProductionApi) return;
    apiBaseUrl = productionApiBaseUrl;
    _dio.options.baseUrl = apiBaseUrl;
    coworkers = [];
    selectedCowork = null;
    token = null;
    user = {};
    await _storage.delete(key: _coworkKey);
    await _storage.delete(key: _tokenKey);
    await _storage.write(key: _apiKey, value: apiBaseUrl);
    notifyListeners();
  }

  Future<void> initialize() async {
    try {
      final savedApiBaseUrl = await _storage.read(key: _apiKey);
      // The cowork and session belong to one API: drop them when the app
      // starts against another one (e.g. development falling back to prod).
      if (savedApiBaseUrl != null &&
          normalizedApiBaseUrl(savedApiBaseUrl) !=
              normalizedApiBaseUrl(apiBaseUrl)) {
        await _storage.delete(key: _coworkKey);
        await _storage.delete(key: _tokenKey);
      }
      if (apiBaseUrl.isNotEmpty) {
        await _storage.write(key: _apiKey, value: apiBaseUrl);
      }
      email = (await _storage.read(key: _emailKey) ?? '').trim();
      final savedCowork = await _storage.read(key: _coworkKey);
      if (savedCowork != null) {
        try {
          selectedCowork =
              Cowork.fromJson(jsonDecode(savedCowork) as Map<String, dynamic>);
        } on FormatException {
          await _storage.delete(key: _coworkKey);
        } on TypeError {
          await _storage.delete(key: _coworkKey);
        }
      }
      token = await _storage.read(key: _tokenKey);
      if (token == null) return;
      if (selectedCowork == null || apiBaseUrl.isEmpty) {
        await _clearStoredToken();
        return;
      }
      try {
        final response = await _dio.get<dynamic>('me', options: _authOptions);
        user = Map<String, dynamic>.from(response.data as Map);
      } on DioException catch (error) {
        user = {};
        if (error.response?.statusCode == 401) {
          await _clearStoredToken();
        }
      }
    } finally {
      isReady = true;
      notifyListeners();
    }
  }

  Future<void> loadCoworks() async {
    if (apiBaseUrl.isEmpty)
      throw const AppException(
          'L\'adresse de l\'API n\'est pas configurée pour cette version.');
    isBusy = true;
    notifyListeners();
    try {
      final response = await _dio.get<dynamic>('mobile/places');
      final data = response.data;
      if (data is! List) {
        throw const AppException(
            'L\'API a renvoyé une réponse inattendue pour la liste des coworks.');
      }
      coworkers = data
          .whereType<Map>()
          .map((item) => Cowork.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      if (selectedCowork != null) {
        selectedCowork = coworkers
            .where((item) => item.id == selectedCowork!.id)
            .firstOrNull;
        if (selectedCowork == null) {
          await _storage.delete(key: _coworkKey);
        } else {
          await _storage.write(
              key: _coworkKey, value: jsonEncode(selectedCowork!.toJson()));
        }
      }
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        throw const AppException(
            'L\'API configurée ne propose pas encore la liste des coworks. '
            'Le serveur doit être mis à jour pour exposer GET /mobile/places.');
      }
      throw AppException(_messageFor(error));
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> selectCowork(Cowork cowork) async {
    selectedCowork = cowork;
    await _storage.write(key: _coworkKey, value: jsonEncode(cowork.toJson()));
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final cowork = selectedCowork;
    if (cowork == null) throw const AppException('Choisissez votre cowork.');
    isBusy = true;
    notifyListeners();
    try {
      final normalizedEmail = email.trim();
      this.email = normalizedEmail;
      await _storage.write(key: _emailKey, value: normalizedEmail);
      final response = await _dio.post<dynamic>(
        'login',
        data: {
          'email': normalizedEmail,
          'password': password,
          'stayConnected': true,
        },
        options: Options(headers: {'Coworkid': cowork.id}),
      );
      final payload = Map<String, dynamic>.from(response.data as Map);
      final accessToken = payload['token'];
      if (accessToken is! String || accessToken.isEmpty) {
        throw const AppException('Le serveur n\'a pas fourni de jeton valide.');
      }
      await _storage.write(key: _tokenKey, value: accessToken);
      token = accessToken;
      user = Map<String, dynamic>.from(payload['user'] as Map);
      notifyListeners();
    } on DioException catch (error) {
      throw AppException(_messageFor(error,
          fallback: 'Identifiants incorrects ou cowork indisponible.'));
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post<dynamic>('logout', options: _authOptions);
    } catch (_) {}
    await _clearStoredToken();
    user = {};
    notifyListeners();
  }

  Options get _authOptions => Options(headers: {
        'Authorization': 'Bearer $token',
        if (selectedCowork != null) 'Coworkid': selectedCowork!.id,
      });

  Future<void> _clearStoredToken() async {
    token = null;
    await _storage.delete(key: _tokenKey);
  }

  Future<Map<String, dynamic>> getPlace() async {
    try {
      final response =
          await _dio.get<dynamic>('the-place-to-work', options: _authOptions);
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (error) {
      throw AppException(_messageFor(error));
    }
  }

  /// Doors the member may command now: the cowork's smartlocks, limited to
  /// shared doors and the rooms of today's reservations.
  Future<DoorAccess> loadDoors() async {
    final results = await Future.wait<dynamic>(
        [getPlace(), getTodayOccupations(), getDoorAccess()]);
    final place = results[0] as Map<String, dynamic>;
    final occupations = results[1] as List<dynamic>;
    final access = results[2] as Map<String, dynamic>;
    final roomIds = <String>{
      for (final item in occupations.whereType<Map>())
        if (item['desk'] is Map && (item['desk'] as Map)['room_id'] != null)
          '${(item['desk'] as Map)['room_id']}'
    };
    final doors = (place['smartlocks'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) => Door.fromJson(Map<String, dynamic>.from(item)))
        .where((door) => door.roomId == null || roomIds.contains(door.roomId))
        .toList();
    return DoorAccess(
        doors: doors,
        canOpen: access['canOpen'] == true,
        canClose: access['canClose'] == true);
  }

  Future<List<dynamic>> getTodayOccupations() async {
    try {
      final response = await _dio.get<dynamic>('user/occupations/today',
          options: _authOptions);
      return response.data is List ? response.data as List<dynamic> : [];
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return [];
      throw AppException(_messageFor(error));
    }
  }

  Future<Map<String, dynamic>> getDoorAccess() async {
    try {
      final response =
          await _dio.get<dynamic>('user/door/access', options: _authOptions);
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw const AppException(
          'Le serveur a renvoyé un état d\'accès invalide.');
    } on DioException catch (error) {
      // API without the access route: behave like the website, the server
      // still checks the request when the door is opened or closed.
      if (error.response?.statusCode == 404) {
        return {'canOpen': true, 'canClose': true};
      }
      throw AppException(_messageFor(error));
    }
  }

  Future<void> setDoor(int id,
      {required bool open,
      required double latitude,
      required double longitude}) async {
    try {
      await _dio.post<dynamic>(
        'user/door/$id/${open ? 'open' : 'close'}',
        data: {
          'coordinates': [latitude, longitude]
        },
        options: _authOptions,
      );
    } on DioException catch (error) {
      // The door routes return their refusal reason as a bare JSON string.
      final reason = error.response?.data;
      if (error.response?.statusCode == 403 &&
          reason is String &&
          reason.isNotEmpty) {
        throw AppException(reason);
      }
      throw AppException(
          _messageFor(error, fallback: 'La porte n\'a pas pu être commandée.'));
    }
  }

  String _messageFor(DioException error,
      {String fallback = 'Le serveur est momentanément indisponible.'}) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String)
      return data['message'] as String;
    if (error.response?.statusCode == 401)
      return 'Session expirée ou identifiants incorrects.';
    return fallback;
  }
}

class Door {
  const Door({required this.id, required this.label, this.roomId});

  final int id;
  final String label;
  final String? roomId;

  factory Door.fromJson(Map<String, dynamic> json) {
    final label = '${json['label'] ?? ''}'.trim();
    return Door(
      id: int.tryParse('${json['id']}') ?? 0,
      label: label.isEmpty ? 'Porte du cowork' : label,
      roomId: json['room_id'] == null ? null : '${json['room_id']}',
    );
  }
}

class DoorAccess {
  const DoorAccess(
      {required this.doors, required this.canOpen, required this.canClose});

  final List<Door> doors;
  final bool canOpen;
  final bool canClose;
}

class AppException implements Exception {
  const AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
