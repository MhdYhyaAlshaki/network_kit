abstract class DioPreferences {
  String get accessToken;
  String get refreshToken;
  String get languageCode;
  Future<String?> get fcmToken;

  //this method is used for after refreshing the access token, to update the access token in the preferences
  Future<void> setAccessToken(String token);
  Future<void> setRefreshToken(String token);
}
