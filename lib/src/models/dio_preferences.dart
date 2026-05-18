abstract class DioPreferences {
  String get accessToken;
  String get refreshToken;
  String get languageCode;

  Future<void> setAccessToken(String token);
  Future<void> setRefreshToken(String token);
}
