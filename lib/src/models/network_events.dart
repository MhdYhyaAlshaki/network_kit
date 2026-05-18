class NetworkEvents {
  final Future<void> Function()? onUnauthorized;
  final Future<void> Function(dynamic payload)? onOldVersion;
  final Future<void> Function()? onNeedCompleteProfile;
  final Future<void> Function()? onVpnDetected;

  const NetworkEvents({
    this.onUnauthorized,
    this.onOldVersion,
    this.onNeedCompleteProfile,
    this.onVpnDetected,
  });
}
