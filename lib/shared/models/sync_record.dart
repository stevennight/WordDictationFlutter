enum SyncStatus {
  pending,
  inProgress,
  success,
  failed,
  conflict,
  skipped,
}

enum SyncType {
  upload,
  download,
  bidirectional,
}

enum ConflictResolution {
  useLocal,
  useRemote,
  manual,
  ignore,
}

class SyncRecord {
  final int? id;
  final String fileName;
  final SyncType syncType;
  final SyncStatus status;
  final DateTime startTime;
  final DateTime? endTime;
  final String? errorMessage;
  final String? localPath;
  final String? remotePath;
  final String? localHash;
  final String? remoteHash;
  final ConflictResolution? conflictResolution;
  final DateTime? localModifiedTime;
  final DateTime? remoteModifiedTime;

  const SyncRecord({
    this.id,
    required this.fileName,
    required this.syncType,
    required this.status,
    required this.startTime,
    this.endTime,
    this.errorMessage,
    this.localPath,
    this.remotePath,
    this.localHash,
    this.remoteHash,
    this.conflictResolution,
    this.localModifiedTime,
    this.remoteModifiedTime,
  });

  SyncRecord copyWith({
    int? id,
    String? fileName,
    SyncType? syncType,
    SyncStatus? status,
    DateTime? startTime,
    DateTime? endTime,
    String? errorMessage,
    String? localPath,
    String? remotePath,
    String? localHash,
    String? remoteHash,
    ConflictResolution? conflictResolution,
    DateTime? localModifiedTime,
    DateTime? remoteModifiedTime,
  }) {
    return SyncRecord(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      syncType: syncType ?? this.syncType,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      errorMessage: errorMessage ?? this.errorMessage,
      localPath: localPath ?? this.localPath,
      remotePath: remotePath ?? this.remotePath,
      localHash: localHash ?? this.localHash,
      remoteHash: remoteHash ?? this.remoteHash,
      conflictResolution: conflictResolution ?? this.conflictResolution,
      localModifiedTime: localModifiedTime ?? this.localModifiedTime,
      remoteModifiedTime: remoteModifiedTime ?? this.remoteModifiedTime,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_name': fileName,
      'sync_type': syncType.index,
      'status': status.index,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime?.millisecondsSinceEpoch,
      'error_message': errorMessage,
      'local_path': localPath,
      'remote_path': remotePath,
      'local_hash': localHash,
      'remote_hash': remoteHash,
      'conflict_resolution': conflictResolution?.index,
      'local_modified_time': localModifiedTime?.millisecondsSinceEpoch,
      'remote_modified_time': remoteModifiedTime?.millisecondsSinceEpoch,
    };
  }

  factory SyncRecord.fromMap(Map<String, dynamic> map) {
    return SyncRecord(
      id: map['id']?.toInt(),
      fileName: map['file_name'] ?? '',
      syncType: SyncType.values[map['sync_type'] ?? 0],
      status: SyncStatus.values[map['status'] ?? 0],
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time']),
      endTime: map['end_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['end_time'])
          : null,
      errorMessage: map['error_message'],
      localPath: map['local_path'],
      remotePath: map['remote_path'],
      localHash: map['local_hash'],
      remoteHash: map['remote_hash'],
      conflictResolution: map['conflict_resolution'] != null
          ? ConflictResolution.values[map['conflict_resolution']]
          : null,
      localModifiedTime: map['local_modified_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['local_modified_time'])
          : null,
      remoteModifiedTime: map['remote_modified_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['remote_modified_time'])
          : null,
    );
  }

  bool get isCompleted => status == SyncStatus.success || status == SyncStatus.failed;
  bool get hasConflict => status == SyncStatus.conflict;
  bool get isInProgress => status == SyncStatus.inProgress;

  @override
  String toString() {
    return 'SyncRecord(fileName: $fileName, status: $status, syncType: $syncType)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncRecord && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}