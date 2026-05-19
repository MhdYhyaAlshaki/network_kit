import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_kit/network_kit.dart';

void main() {
  setUp(() {
    DioResponseKey.resetAll();
    ResponseStatusCode.clearAllCodeOverrides();
    ResponseStatusCode.clearAllCustomCodes();
  });

  test('prefers body status code over HTTP status code', () {
    DioResponseKey.setStatusCodeKeys(['code']);
    DioResponseKey.setMessageKeys(['message', 'msg']);

    final response = Response<dynamic>(
      requestOptions: RequestOptions(path: '/users/me'),
      statusCode: 500,
      data: {'code': '426', 'msg': 'Update required'},
    );

    final status = ResponseStatusCode.fromMap(
      response.data as Map<String, dynamic>,
    );
    final payload = NetworkEventPayload.fromResponse(response, status: status);

    expect(payload.statusCode, '426');
    expect(payload.errorMessage, 'Update required');
    expect(payload.body, {'code': '426', 'msg': 'Update required'});
    expect(payload.status, ResponseStatusCode.oldVersion);
  });

  test('falls back to HTTP status code when body has no status key', () {
    DioResponseKey.setStatusCodeKeys(['status_code']);
    DioResponseKey.setMessageKeys(['message']);

    final response = Response<dynamic>(
      requestOptions: RequestOptions(path: '/resource'),
      statusCode: 404,
      data: {'message': 'Not found'},
    );

    final payload = NetworkEventPayload.fromResponse(response);

    expect(payload.statusCode, '404');
    expect(payload.errorMessage, 'Not found');
    expect(payload.body, {'message': 'Not found'});
  });

  test('uses DioException message fallback when body has no message', () {
    DioResponseKey.setStatusCodeKeys(['status_code']);
    DioResponseKey.setMessageKeys(['message']);

    final error = DioException(
      requestOptions: RequestOptions(path: '/secure'),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: '/secure'),
        statusCode: 401,
        data: {'status_code': '401'},
      ),
      message: 'Token expired',
      type: DioExceptionType.badResponse,
    );

    final payload = NetworkEventPayload.fromException(error);

    expect(payload.statusCode, '401');
    expect(payload.errorMessage, 'Token expired');
    expect(payload.body, {'status_code': '401'});
  });
}
