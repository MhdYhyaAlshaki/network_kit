import 'package:dio/dio.dart';

sealed class NetworkError {
  final String? message;
  final String? statusCode;
  final int? httpStatus;
  final dynamic body;
  final DioException? dioException;

  const NetworkError({
    this.message,
    this.statusCode,
    this.httpStatus,
    this.body,
    this.dioException,
  });
}

final class TimeoutError extends NetworkError {
  const TimeoutError({
    super.message,
    super.statusCode,
    super.httpStatus,
    super.body,
    super.dioException,
  });
}

final class CancelledError extends NetworkError {
  const CancelledError({
    super.message,
    super.statusCode,
    super.httpStatus,
    super.body,
    super.dioException,
  });
}

final class UnauthorizedError extends NetworkError {
  const UnauthorizedError({
    super.message,
    super.statusCode,
    super.httpStatus,
    super.body,
    super.dioException,
  });
}

final class ForbiddenError extends NetworkError {
  const ForbiddenError({
    super.message,
    super.statusCode,
    super.httpStatus,
    super.body,
    super.dioException,
  });
}

final class NotFoundError extends NetworkError {
  const NotFoundError({
    super.message,
    super.statusCode,
    super.httpStatus,
    super.body,
    super.dioException,
  });
}

final class ServerError extends NetworkError {
  const ServerError({
    super.message,
    super.statusCode,
    super.httpStatus,
    super.body,
    super.dioException,
  });
}

final class NetworkConnectionError extends NetworkError {
  const NetworkConnectionError({
    super.message,
    super.statusCode,
    super.httpStatus,
    super.body,
    super.dioException,
  });
}

final class ParsingError extends NetworkError {
  const ParsingError({
    super.message,
    super.statusCode,
    super.httpStatus,
    super.body,
    super.dioException,
  });
}

final class UnknownNetworkError extends NetworkError {
  const UnknownNetworkError({
    super.message,
    super.statusCode,
    super.httpStatus,
    super.body,
    super.dioException,
  });
}
