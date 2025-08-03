class OssConfig {
  final String? endpoint;
  final String? accessKeyId;
  final String? accessKeySecret;
  final String? bucketName;
  final String? syncDirectory;
  final bool enabled;
  final DateTime? lastSyncTime;
  final String? region;
  final String? securityToken;

  const OssConfig({
    this.endpoint,
    this.accessKeyId,
    this.accessKeySecret,
    this.bucketName,
    this.syncDirectory,
    this.enabled = false,
    this.lastSyncTime,
    this.region,
    this.securityToken,
  });

  OssConfig copyWith({
    String? endpoint,
    String? accessKeyId,
    String? accessKeySecret,
    String? bucketName,
    String? syncDirectory,
    bool? enabled,
    DateTime? lastSyncTime,
    String? region,
    String? securityToken,
  }) {
    return OssConfig(
      endpoint: endpoint ?? this.endpoint,
      accessKeyId: accessKeyId ?? this.accessKeyId,
      accessKeySecret: accessKeySecret ?? this.accessKeySecret,
      bucketName: bucketName ?? this.bucketName,
      syncDirectory: syncDirectory ?? this.syncDirectory,
      enabled: enabled ?? this.enabled,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      region: region ?? this.region,
      securityToken: securityToken ?? this.securityToken,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'endpoint': endpoint,
      'access_key_id': accessKeyId,
      'access_key_secret': accessKeySecret,
      'bucket_name': bucketName,
      'sync_directory': syncDirectory,
      'enabled': enabled ? 1 : 0,
      'last_sync_time': lastSyncTime?.millisecondsSinceEpoch,
      'region': region,
      'security_token': securityToken,
    };
  }

  factory OssConfig.fromMap(Map<String, dynamic> map) {
    return OssConfig(
      endpoint: map['endpoint'],
      accessKeyId: map['access_key_id'],
      accessKeySecret: map['access_key_secret'],
      bucketName: map['bucket_name'],
      syncDirectory: map['sync_directory'],
      enabled: (map['enabled'] ?? 0) == 1,
      lastSyncTime: map['last_sync_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_sync_time'])
          : null,
      region: map['region'],
      securityToken: map['security_token'],
    );
  }

  bool get isConfigured {
    return endpoint != null &&
        endpoint!.isNotEmpty &&
        accessKeyId != null &&
        accessKeyId!.isNotEmpty &&
        accessKeySecret != null &&
        accessKeySecret!.isNotEmpty &&
        bucketName != null &&
        bucketName!.isNotEmpty;
  }

  @override
  String toString() {
    return 'OssConfig(endpoint: $endpoint, bucketName: $bucketName, enabled: $enabled, syncDirectory: $syncDirectory)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OssConfig &&
        other.endpoint == endpoint &&
        other.accessKeyId == accessKeyId &&
        other.bucketName == bucketName &&
        other.syncDirectory == syncDirectory &&
        other.enabled == enabled;
  }

  @override
  int get hashCode {
    return endpoint.hashCode ^
        accessKeyId.hashCode ^
        bucketName.hashCode ^
        syncDirectory.hashCode ^
        enabled.hashCode;
  }
}