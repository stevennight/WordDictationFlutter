import '../database/database_helper.dart';
import '../../shared/models/dictation_session.dart';
import 'dictation_service.dart';
import 'sync_service.dart';
import 'history_sync_service.dart';

/// 会话冲突处理结果
enum ConflictResolution {
  /// 同步远端数据（使用远端数据覆盖本地）
  useRemote,
  /// 保留本地数据（忽略远端数据）
  useLocal,
  /// 需要用户手动选择
  requireUserChoice,
}

/// 会话冲突信息
class SessionConflict {
  final String sessionId;
  final DictationSession localSession;
  final DictationSession? remoteSession;
  final ConflictResolution resolution;
  final String reason;

  SessionConflict({
    required this.sessionId,
    required this.localSession,
    required this.remoteSession,
    required this.resolution,
    required this.reason,
  });

  @override
  String toString() {
    return 'SessionConflict(sessionId: $sessionId, resolution: $resolution, reason: $reason)';
  }
}

/// 会话冲突检测和处理器
class SessionConflictResolver {
  static final SessionConflictResolver _instance = SessionConflictResolver._internal();
  factory SessionConflictResolver() => _instance;
  SessionConflictResolver._internal();

  final DictationService _dictationService = DictationService();

  /// 检测并解决会话冲突
  /// 返回冲突列表，每个冲突包含处理建议
  Future<List<SessionConflict>> detectAndResolveConflicts(
    List<SessionSyncData> remoteSessions,
    String remoteDeviceId,
    String localDeviceId,
  ) async {
    final List<SessionConflict> conflicts = [];
    
    // 获取所有本地会话（包括已删除的）
    final localSessions = await _dictationService.getAllSessionsIncludingDeleted();
    final localSessionMap = <String, DictationSession>{};
    for (final session in localSessions) {
      localSessionMap[session.sessionId] = session;
    }

    // 创建远程会话ID集合
    final remoteSessionIds = remoteSessions.map((s) => s.sessionId).toSet();

    // 1. 检测远程会话与本地会话的冲突
    for (final remoteSessionSync in remoteSessions) {
      final remoteSession = DictationSession.fromMap(remoteSessionSync.sessionData);
      final localSession = localSessionMap[remoteSession.sessionId];
      
      if (localSession != null) {
        // 会话存在冲突，需要检测冲突类型和处理方式
        final conflict = _analyzeSessionConflict(
          localSession,
          remoteSession,
          remoteSessionSync,
          remoteDeviceId,
          localDeviceId,
        );
        
        if (conflict != null) {
          conflicts.add(conflict);
        }
      }
    }

    // 2. 检测本地存在但远端不存在的会话（需要删除）
    for (final localSession in localSessions) {
      // 跳过进行中的会话和已删除的会话
      if (localSession.status.index == 0 || localSession.deleted) {
        continue;
      }
      
      // 如果本地会话在远端不存在，标记为需要删除
      if (!remoteSessionIds.contains(localSession.sessionId)) {
        conflicts.add(SessionConflict(
          sessionId: localSession.sessionId,
          localSession: localSession,
          remoteSession: null,
          resolution: ConflictResolution.useRemote, // 使用远端数据（即删除本地数据）
          reason: '本地存在但远端不存在，需要删除本地记录',
        ));
      }
    }

    return conflicts;
  }

  /// 分析单个会话的冲突情况
  SessionConflict? _analyzeSessionConflict(
    DictationSession localSession,
    DictationSession remoteSession,
    SessionSyncData remoteSessionSync,
    String remoteDeviceId,
    String localDeviceId,
  ) {
    // 如果是同一设备，通常不应该有冲突，直接使用远端数据
    if (remoteDeviceId == localDeviceId) {
      return SessionConflict(
        sessionId: localSession.sessionId,
        localSession: localSession,
        remoteSession: remoteSession,
        resolution: ConflictResolution.useRemote,
        reason: '同一设备数据，使用远端数据',
      );
    }

    // 检查删除状态冲突
    if (localSession.deleted != remoteSession.deleted) {
      return _resolveDeleteStatusConflict(localSession, remoteSession, remoteSessionSync);
    }

    // 检查修改时间冲突
    final localModified = localSession.startTime;
    final remoteModified = remoteSessionSync.lastModified;
    final timeDiff = localModified.difference(remoteModified).abs();
    
    // 如果时间差很小（1秒内），认为是同一次修改，使用远端数据
    if (timeDiff.inSeconds <= 1) {
      return SessionConflict(
        sessionId: localSession.sessionId,
        localSession: localSession,
        remoteSession: remoteSession,
        resolution: ConflictResolution.useRemote,
        reason: '修改时间相近，使用远端数据',
      );
    }

    // 如果远端数据更新，使用远端数据
    if (remoteModified.isAfter(localModified)) {
      return SessionConflict(
        sessionId: localSession.sessionId,
        localSession: localSession,
        remoteSession: remoteSession,
        resolution: ConflictResolution.useRemote,
        reason: '远端数据更新，使用远端数据',
      );
    }

    // 如果本地数据更新，保留本地数据
    if (localModified.isAfter(remoteModified)) {
      return SessionConflict(
        sessionId: localSession.sessionId,
        localSession: localSession,
        remoteSession: remoteSession,
        resolution: ConflictResolution.useLocal,
        reason: '本地数据更新，保留本地数据',
      );
    }

    // 其他情况，需要用户选择（暂时使用远端数据）
    return SessionConflict(
      sessionId: localSession.sessionId,
      localSession: localSession,
      remoteSession: remoteSession,
      resolution: ConflictResolution.useRemote,
      reason: '无法自动判断，暂时使用远端数据',
    );
  }

  /// 解决删除状态冲突
  SessionConflict _resolveDeleteStatusConflict(
    DictationSession localSession,
    DictationSession remoteSession,
    SessionSyncData remoteSessionSync,
  ) {
    if (remoteSession.deleted && localSession.deleted) {
      // 两边都删除了，比较删除时间，保留最新的
      final remoteDeletedAt = remoteSession.deletedAt;
      final localDeletedAt = localSession.deletedAt;
      
      if (remoteDeletedAt != null && localDeletedAt != null) {
        if (remoteDeletedAt.isAfter(localDeletedAt)) {
          return SessionConflict(
            sessionId: localSession.sessionId,
            localSession: localSession,
            remoteSession: remoteSession,
            resolution: ConflictResolution.useRemote,
            reason: '远端删除时间更晚，使用远端删除状态',
          );
        } else {
          return SessionConflict(
            sessionId: localSession.sessionId,
            localSession: localSession,
            remoteSession: remoteSession,
            resolution: ConflictResolution.useLocal,
            reason: '本地删除时间更晚，保留本地删除状态',
          );
        }
      } else if (remoteDeletedAt != null) {
        return SessionConflict(
          sessionId: localSession.sessionId,
          localSession: localSession,
          remoteSession: remoteSession,
          resolution: ConflictResolution.useRemote,
          reason: '远端有删除时间，本地没有，使用远端删除状态',
        );
      } else {
        return SessionConflict(
          sessionId: localSession.sessionId,
          localSession: localSession,
          remoteSession: remoteSession,
          resolution: ConflictResolution.useLocal,
          reason: '本地有删除时间，远端没有，保留本地删除状态',
        );
      }
    } else if (remoteSession.deleted && !localSession.deleted) {
      // 远端删除了，本地没删除，使用远端的删除状态
      return SessionConflict(
        sessionId: localSession.sessionId,
        localSession: localSession,
        remoteSession: remoteSession,
        resolution: ConflictResolution.useRemote,
        reason: '远端已删除，本地未删除，使用远端删除状态',
      );
    } else if (!remoteSession.deleted && localSession.deleted) {
      // 本地删除了，远端没删除，保留本地的删除状态
      return SessionConflict(
        sessionId: localSession.sessionId,
        localSession: localSession,
        remoteSession: remoteSession,
        resolution: ConflictResolution.useLocal,
        reason: '本地已删除，远端未删除，保留本地删除状态',
      );
    }

    // 不应该到达这里
    return SessionConflict(
      sessionId: localSession.sessionId,
      localSession: localSession,
      remoteSession: remoteSession,
      resolution: ConflictResolution.requireUserChoice,
      reason: '未知的删除状态冲突',
    );
  }

  /// 应用冲突解决方案
  /// 返回是否需要更新本地数据
  bool shouldUpdateLocal(SessionConflict conflict) {
    switch (conflict.resolution) {
      case ConflictResolution.useRemote:
        return true;
      case ConflictResolution.useLocal:
        return false;
      case ConflictResolution.requireUserChoice:
        // 暂时默认使用远端数据，后续可以添加用户选择界面
        return true;
    }
  }

  /// 获取应该应用的会话数据
  /// 如果返回 null，表示应该删除本地会话
  /// 如果需要用户选择，会抛出 UserChoiceRequiredException
  DictationSession? getSessionToApply(SessionConflict conflict) {
    switch (conflict.resolution) {
      case ConflictResolution.useRemote:
        // 如果远程会话为 null，表示需要删除本地会话
        return conflict.remoteSession;
      case ConflictResolution.useLocal:
        return conflict.localSession;
      case ConflictResolution.requireUserChoice:
        // 默认使用远程数据，实际应用中应该让用户选择
        return conflict.remoteSession;
    }
  }
}