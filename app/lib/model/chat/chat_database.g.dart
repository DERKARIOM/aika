// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_database.dart';

// ignore_for_file: type=lint
class $ChatConversationsTable extends ChatConversations with TableInfo<$ChatConversationsTable, ChatConversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _peerFingerprintMeta = const VerificationMeta(
    'peerFingerprint',
  );
  @override
  late final GeneratedColumn<String> peerFingerprint = GeneratedColumn<String>(
    'peer_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerAliasMeta = const VerificationMeta(
    'peerAlias',
  );
  @override
  late final GeneratedColumn<String> peerAlias = GeneratedColumn<String>(
    'peer_alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerDeviceModelMeta = const VerificationMeta(
    'peerDeviceModel',
  );
  @override
  late final GeneratedColumn<String> peerDeviceModel = GeneratedColumn<String>(
    'peer_device_model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastMessagePreviewMeta = const VerificationMeta('lastMessagePreview');
  @override
  late final GeneratedColumn<String> lastMessagePreview = GeneratedColumn<String>(
    'last_message_preview',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastMessageAtMeta = const VerificationMeta(
    'lastMessageAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastMessageAt = GeneratedColumn<DateTime>(
    'last_message_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    peerFingerprint,
    peerAlias,
    peerDeviceModel,
    lastSeenAt,
    unreadCount,
    lastMessagePreview,
    lastMessageAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatConversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('peer_fingerprint')) {
      context.handle(
        _peerFingerprintMeta,
        peerFingerprint.isAcceptableOrUnknown(
          data['peer_fingerprint']!,
          _peerFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_peerFingerprintMeta);
    }
    if (data.containsKey('peer_alias')) {
      context.handle(
        _peerAliasMeta,
        peerAlias.isAcceptableOrUnknown(data['peer_alias']!, _peerAliasMeta),
      );
    } else if (isInserting) {
      context.missing(_peerAliasMeta);
    }
    if (data.containsKey('peer_device_model')) {
      context.handle(
        _peerDeviceModelMeta,
        peerDeviceModel.isAcceptableOrUnknown(
          data['peer_device_model']!,
          _peerDeviceModelMeta,
        ),
      );
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('last_message_preview')) {
      context.handle(
        _lastMessagePreviewMeta,
        lastMessagePreview.isAcceptableOrUnknown(
          data['last_message_preview']!,
          _lastMessagePreviewMeta,
        ),
      );
    }
    if (data.containsKey('last_message_at')) {
      context.handle(
        _lastMessageAtMeta,
        lastMessageAt.isAcceptableOrUnknown(
          data['last_message_at']!,
          _lastMessageAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {peerFingerprint};
  @override
  ChatConversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatConversation(
      peerFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_fingerprint'],
      )!,
      peerAlias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_alias'],
      )!,
      peerDeviceModel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_device_model'],
      ),
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      ),
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      lastMessagePreview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_preview'],
      ),
      lastMessageAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_message_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ChatConversationsTable createAlias(String alias) {
    return $ChatConversationsTable(attachedDatabase, alias);
  }
}

class ChatConversation extends DataClass implements Insertable<ChatConversation> {
  /// The peer's certificate fingerprint (SHA-256), see [Device.fingerprint].
  final String peerFingerprint;

  /// Best-known alias for the peer. Kept in sync with live discovery data
  /// (like `FavoriteDevice.alias`) so the conversation list never shows a
  /// stale name after the peer renames itself.
  final String peerAlias;
  final String? peerDeviceModel;

  /// Updated whenever the peer is seen via discovery (multicast/HTTP scan)
  /// or sends anything. Used to render "last seen" when the peer is
  /// currently offline; while online, the UI derives status live from
  /// [nearbyDevicesProvider] instead of this column.
  final DateTime? lastSeenAt;

  /// Denormalized counter, incremented on every incoming message while the
  /// conversation is not open, reset to 0 when the user opens it.
  final int unreadCount;

  /// Denormalized preview of the most recent message (either direction),
  /// so the conversation list can render without joining `chatMessages`.
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final DateTime createdAt;
  const ChatConversation({
    required this.peerFingerprint,
    required this.peerAlias,
    this.peerDeviceModel,
    this.lastSeenAt,
    required this.unreadCount,
    this.lastMessagePreview,
    this.lastMessageAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['peer_fingerprint'] = Variable<String>(peerFingerprint);
    map['peer_alias'] = Variable<String>(peerAlias);
    if (!nullToAbsent || peerDeviceModel != null) {
      map['peer_device_model'] = Variable<String>(peerDeviceModel);
    }
    if (!nullToAbsent || lastSeenAt != null) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    }
    map['unread_count'] = Variable<int>(unreadCount);
    if (!nullToAbsent || lastMessagePreview != null) {
      map['last_message_preview'] = Variable<String>(lastMessagePreview);
    }
    if (!nullToAbsent || lastMessageAt != null) {
      map['last_message_at'] = Variable<DateTime>(lastMessageAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ChatConversationsCompanion toCompanion(bool nullToAbsent) {
    return ChatConversationsCompanion(
      peerFingerprint: Value(peerFingerprint),
      peerAlias: Value(peerAlias),
      peerDeviceModel: peerDeviceModel == null && nullToAbsent ? const Value.absent() : Value(peerDeviceModel),
      lastSeenAt: lastSeenAt == null && nullToAbsent ? const Value.absent() : Value(lastSeenAt),
      unreadCount: Value(unreadCount),
      lastMessagePreview: lastMessagePreview == null && nullToAbsent ? const Value.absent() : Value(lastMessagePreview),
      lastMessageAt: lastMessageAt == null && nullToAbsent ? const Value.absent() : Value(lastMessageAt),
      createdAt: Value(createdAt),
    );
  }

  factory ChatConversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatConversation(
      peerFingerprint: serializer.fromJson<String>(json['peerFingerprint']),
      peerAlias: serializer.fromJson<String>(json['peerAlias']),
      peerDeviceModel: serializer.fromJson<String?>(json['peerDeviceModel']),
      lastSeenAt: serializer.fromJson<DateTime?>(json['lastSeenAt']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      lastMessagePreview: serializer.fromJson<String?>(
        json['lastMessagePreview'],
      ),
      lastMessageAt: serializer.fromJson<DateTime?>(json['lastMessageAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'peerFingerprint': serializer.toJson<String>(peerFingerprint),
      'peerAlias': serializer.toJson<String>(peerAlias),
      'peerDeviceModel': serializer.toJson<String?>(peerDeviceModel),
      'lastSeenAt': serializer.toJson<DateTime?>(lastSeenAt),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'lastMessagePreview': serializer.toJson<String?>(lastMessagePreview),
      'lastMessageAt': serializer.toJson<DateTime?>(lastMessageAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ChatConversation copyWith({
    String? peerFingerprint,
    String? peerAlias,
    Value<String?> peerDeviceModel = const Value.absent(),
    Value<DateTime?> lastSeenAt = const Value.absent(),
    int? unreadCount,
    Value<String?> lastMessagePreview = const Value.absent(),
    Value<DateTime?> lastMessageAt = const Value.absent(),
    DateTime? createdAt,
  }) => ChatConversation(
    peerFingerprint: peerFingerprint ?? this.peerFingerprint,
    peerAlias: peerAlias ?? this.peerAlias,
    peerDeviceModel: peerDeviceModel.present ? peerDeviceModel.value : this.peerDeviceModel,
    lastSeenAt: lastSeenAt.present ? lastSeenAt.value : this.lastSeenAt,
    unreadCount: unreadCount ?? this.unreadCount,
    lastMessagePreview: lastMessagePreview.present ? lastMessagePreview.value : this.lastMessagePreview,
    lastMessageAt: lastMessageAt.present ? lastMessageAt.value : this.lastMessageAt,
    createdAt: createdAt ?? this.createdAt,
  );
  ChatConversation copyWithCompanion(ChatConversationsCompanion data) {
    return ChatConversation(
      peerFingerprint: data.peerFingerprint.present ? data.peerFingerprint.value : this.peerFingerprint,
      peerAlias: data.peerAlias.present ? data.peerAlias.value : this.peerAlias,
      peerDeviceModel: data.peerDeviceModel.present ? data.peerDeviceModel.value : this.peerDeviceModel,
      lastSeenAt: data.lastSeenAt.present ? data.lastSeenAt.value : this.lastSeenAt,
      unreadCount: data.unreadCount.present ? data.unreadCount.value : this.unreadCount,
      lastMessagePreview: data.lastMessagePreview.present ? data.lastMessagePreview.value : this.lastMessagePreview,
      lastMessageAt: data.lastMessageAt.present ? data.lastMessageAt.value : this.lastMessageAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatConversation(')
          ..write('peerFingerprint: $peerFingerprint, ')
          ..write('peerAlias: $peerAlias, ')
          ..write('peerDeviceModel: $peerDeviceModel, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('lastMessagePreview: $lastMessagePreview, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    peerFingerprint,
    peerAlias,
    peerDeviceModel,
    lastSeenAt,
    unreadCount,
    lastMessagePreview,
    lastMessageAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatConversation &&
          other.peerFingerprint == this.peerFingerprint &&
          other.peerAlias == this.peerAlias &&
          other.peerDeviceModel == this.peerDeviceModel &&
          other.lastSeenAt == this.lastSeenAt &&
          other.unreadCount == this.unreadCount &&
          other.lastMessagePreview == this.lastMessagePreview &&
          other.lastMessageAt == this.lastMessageAt &&
          other.createdAt == this.createdAt);
}

class ChatConversationsCompanion extends UpdateCompanion<ChatConversation> {
  final Value<String> peerFingerprint;
  final Value<String> peerAlias;
  final Value<String?> peerDeviceModel;
  final Value<DateTime?> lastSeenAt;
  final Value<int> unreadCount;
  final Value<String?> lastMessagePreview;
  final Value<DateTime?> lastMessageAt;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ChatConversationsCompanion({
    this.peerFingerprint = const Value.absent(),
    this.peerAlias = const Value.absent(),
    this.peerDeviceModel = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.lastMessagePreview = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatConversationsCompanion.insert({
    required String peerFingerprint,
    required String peerAlias,
    this.peerDeviceModel = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.lastMessagePreview = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : peerFingerprint = Value(peerFingerprint),
       peerAlias = Value(peerAlias);
  static Insertable<ChatConversation> custom({
    Expression<String>? peerFingerprint,
    Expression<String>? peerAlias,
    Expression<String>? peerDeviceModel,
    Expression<DateTime>? lastSeenAt,
    Expression<int>? unreadCount,
    Expression<String>? lastMessagePreview,
    Expression<DateTime>? lastMessageAt,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (peerFingerprint != null) 'peer_fingerprint': peerFingerprint,
      if (peerAlias != null) 'peer_alias': peerAlias,
      if (peerDeviceModel != null) 'peer_device_model': peerDeviceModel,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (lastMessagePreview != null) 'last_message_preview': lastMessagePreview,
      if (lastMessageAt != null) 'last_message_at': lastMessageAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatConversationsCompanion copyWith({
    Value<String>? peerFingerprint,
    Value<String>? peerAlias,
    Value<String?>? peerDeviceModel,
    Value<DateTime?>? lastSeenAt,
    Value<int>? unreadCount,
    Value<String?>? lastMessagePreview,
    Value<DateTime?>? lastMessageAt,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ChatConversationsCompanion(
      peerFingerprint: peerFingerprint ?? this.peerFingerprint,
      peerAlias: peerAlias ?? this.peerAlias,
      peerDeviceModel: peerDeviceModel ?? this.peerDeviceModel,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (peerFingerprint.present) {
      map['peer_fingerprint'] = Variable<String>(peerFingerprint.value);
    }
    if (peerAlias.present) {
      map['peer_alias'] = Variable<String>(peerAlias.value);
    }
    if (peerDeviceModel.present) {
      map['peer_device_model'] = Variable<String>(peerDeviceModel.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (lastMessagePreview.present) {
      map['last_message_preview'] = Variable<String>(lastMessagePreview.value);
    }
    if (lastMessageAt.present) {
      map['last_message_at'] = Variable<DateTime>(lastMessageAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatConversationsCompanion(')
          ..write('peerFingerprint: $peerFingerprint, ')
          ..write('peerAlias: $peerAlias, ')
          ..write('peerDeviceModel: $peerDeviceModel, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('lastMessagePreview: $lastMessagePreview, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatMessagesTable extends ChatMessages with TableInfo<$ChatMessagesTable, ChatMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES chat_conversations (peer_fingerprint)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<ChatMessageDirectionColumn, String> direction =
      GeneratedColumn<String>(
        'direction',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<ChatMessageDirectionColumn>(
        $ChatMessagesTable.$converterdirection,
      );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
    'content_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attachmentPathMeta = const VerificationMeta(
    'attachmentPath',
  );
  @override
  late final GeneratedColumn<String> attachmentPath = GeneratedColumn<String>(
    'attachment_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attachmentFileNameMeta = const VerificationMeta('attachmentFileName');
  @override
  late final GeneratedColumn<String> attachmentFileName = GeneratedColumn<String>(
    'attachment_file_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attachmentSizeMeta = const VerificationMeta(
    'attachmentSize',
  );
  @override
  late final GeneratedColumn<int> attachmentSize = GeneratedColumn<int>(
    'attachment_size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ChatMessageStatusColumn, String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<ChatMessageStatusColumn>($ChatMessagesTable.$converterstatus);
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deliveredAtMeta = const VerificationMeta(
    'deliveredAt',
  );
  @override
  late final GeneratedColumn<DateTime> deliveredAt = GeneratedColumn<DateTime>(
    'delivered_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readAtMeta = const VerificationMeta('readAt');
  @override
  late final GeneratedColumn<DateTime> readAt = GeneratedColumn<DateTime>(
    'read_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    direction,
    contentType,
    body,
    attachmentPath,
    attachmentFileName,
    attachmentSize,
    status,
    errorMessage,
    createdAt,
    deliveredAt,
    readAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentTypeMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('attachment_path')) {
      context.handle(
        _attachmentPathMeta,
        attachmentPath.isAcceptableOrUnknown(
          data['attachment_path']!,
          _attachmentPathMeta,
        ),
      );
    }
    if (data.containsKey('attachment_file_name')) {
      context.handle(
        _attachmentFileNameMeta,
        attachmentFileName.isAcceptableOrUnknown(
          data['attachment_file_name']!,
          _attachmentFileNameMeta,
        ),
      );
    }
    if (data.containsKey('attachment_size')) {
      context.handle(
        _attachmentSizeMeta,
        attachmentSize.isAcceptableOrUnknown(
          data['attachment_size']!,
          _attachmentSizeMeta,
        ),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('delivered_at')) {
      context.handle(
        _deliveredAtMeta,
        deliveredAt.isAcceptableOrUnknown(
          data['delivered_at']!,
          _deliveredAtMeta,
        ),
      );
    }
    if (data.containsKey('read_at')) {
      context.handle(
        _readAtMeta,
        readAt.isAcceptableOrUnknown(data['read_at']!, _readAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      direction: $ChatMessagesTable.$converterdirection.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}direction'],
        )!,
      ),
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_type'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      ),
      attachmentPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachment_path'],
      ),
      attachmentFileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachment_file_name'],
      ),
      attachmentSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attachment_size'],
      ),
      status: $ChatMessagesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      deliveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}delivered_at'],
      ),
      readAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}read_at'],
      ),
    );
  }

  @override
  $ChatMessagesTable createAlias(String alias) {
    return $ChatMessagesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ChatMessageDirectionColumn, String, String> $converterdirection = const EnumNameConverter<ChatMessageDirectionColumn>(
    ChatMessageDirectionColumn.values,
  );
  static JsonTypeConverter2<ChatMessageStatusColumn, String, String> $converterstatus = const EnumNameConverter<ChatMessageStatusColumn>(
    ChatMessageStatusColumn.values,
  );
}

class ChatMessage extends DataClass implements Insertable<ChatMessage> {
  final String id;
  final String conversationId;
  final ChatMessageDirectionColumn direction;
  final String contentType;

  /// The message's text content (or caption, for media messages).
  /// Named `body` on the Dart side only to avoid shadowing the inherited
  /// `text()` column builder method with a same-named getter; the
  /// generated SQL column is still called `body`.
  final String? body;

  /// Absolute local path once the attachment bytes are available (either
  /// because we sent it from local storage, or because we finished
  /// receiving it). Null while a media message is still in flight.
  final String? attachmentPath;
  final String? attachmentFileName;
  final int? attachmentSize;
  final ChatMessageStatusColumn status;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.direction,
    required this.contentType,
    this.body,
    this.attachmentPath,
    this.attachmentFileName,
    this.attachmentSize,
    required this.status,
    this.errorMessage,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    {
      map['direction'] = Variable<String>(
        $ChatMessagesTable.$converterdirection.toSql(direction),
      );
    }
    map['content_type'] = Variable<String>(contentType);
    if (!nullToAbsent || body != null) {
      map['body'] = Variable<String>(body);
    }
    if (!nullToAbsent || attachmentPath != null) {
      map['attachment_path'] = Variable<String>(attachmentPath);
    }
    if (!nullToAbsent || attachmentFileName != null) {
      map['attachment_file_name'] = Variable<String>(attachmentFileName);
    }
    if (!nullToAbsent || attachmentSize != null) {
      map['attachment_size'] = Variable<int>(attachmentSize);
    }
    {
      map['status'] = Variable<String>(
        $ChatMessagesTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || deliveredAt != null) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt);
    }
    if (!nullToAbsent || readAt != null) {
      map['read_at'] = Variable<DateTime>(readAt);
    }
    return map;
  }

  ChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return ChatMessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      direction: Value(direction),
      contentType: Value(contentType),
      body: body == null && nullToAbsent ? const Value.absent() : Value(body),
      attachmentPath: attachmentPath == null && nullToAbsent ? const Value.absent() : Value(attachmentPath),
      attachmentFileName: attachmentFileName == null && nullToAbsent ? const Value.absent() : Value(attachmentFileName),
      attachmentSize: attachmentSize == null && nullToAbsent ? const Value.absent() : Value(attachmentSize),
      status: Value(status),
      errorMessage: errorMessage == null && nullToAbsent ? const Value.absent() : Value(errorMessage),
      createdAt: Value(createdAt),
      deliveredAt: deliveredAt == null && nullToAbsent ? const Value.absent() : Value(deliveredAt),
      readAt: readAt == null && nullToAbsent ? const Value.absent() : Value(readAt),
    );
  }

  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatMessage(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      direction: $ChatMessagesTable.$converterdirection.fromJson(
        serializer.fromJson<String>(json['direction']),
      ),
      contentType: serializer.fromJson<String>(json['contentType']),
      body: serializer.fromJson<String?>(json['body']),
      attachmentPath: serializer.fromJson<String?>(json['attachmentPath']),
      attachmentFileName: serializer.fromJson<String?>(
        json['attachmentFileName'],
      ),
      attachmentSize: serializer.fromJson<int?>(json['attachmentSize']),
      status: $ChatMessagesTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      deliveredAt: serializer.fromJson<DateTime?>(json['deliveredAt']),
      readAt: serializer.fromJson<DateTime?>(json['readAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'direction': serializer.toJson<String>(
        $ChatMessagesTable.$converterdirection.toJson(direction),
      ),
      'contentType': serializer.toJson<String>(contentType),
      'body': serializer.toJson<String?>(body),
      'attachmentPath': serializer.toJson<String?>(attachmentPath),
      'attachmentFileName': serializer.toJson<String?>(attachmentFileName),
      'attachmentSize': serializer.toJson<int?>(attachmentSize),
      'status': serializer.toJson<String>(
        $ChatMessagesTable.$converterstatus.toJson(status),
      ),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'deliveredAt': serializer.toJson<DateTime?>(deliveredAt),
      'readAt': serializer.toJson<DateTime?>(readAt),
    };
  }

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    ChatMessageDirectionColumn? direction,
    String? contentType,
    Value<String?> body = const Value.absent(),
    Value<String?> attachmentPath = const Value.absent(),
    Value<String?> attachmentFileName = const Value.absent(),
    Value<int?> attachmentSize = const Value.absent(),
    ChatMessageStatusColumn? status,
    Value<String?> errorMessage = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> deliveredAt = const Value.absent(),
    Value<DateTime?> readAt = const Value.absent(),
  }) => ChatMessage(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    direction: direction ?? this.direction,
    contentType: contentType ?? this.contentType,
    body: body.present ? body.value : this.body,
    attachmentPath: attachmentPath.present ? attachmentPath.value : this.attachmentPath,
    attachmentFileName: attachmentFileName.present ? attachmentFileName.value : this.attachmentFileName,
    attachmentSize: attachmentSize.present ? attachmentSize.value : this.attachmentSize,
    status: status ?? this.status,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    createdAt: createdAt ?? this.createdAt,
    deliveredAt: deliveredAt.present ? deliveredAt.value : this.deliveredAt,
    readAt: readAt.present ? readAt.value : this.readAt,
  );
  ChatMessage copyWithCompanion(ChatMessagesCompanion data) {
    return ChatMessage(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present ? data.conversationId.value : this.conversationId,
      direction: data.direction.present ? data.direction.value : this.direction,
      contentType: data.contentType.present ? data.contentType.value : this.contentType,
      body: data.body.present ? data.body.value : this.body,
      attachmentPath: data.attachmentPath.present ? data.attachmentPath.value : this.attachmentPath,
      attachmentFileName: data.attachmentFileName.present ? data.attachmentFileName.value : this.attachmentFileName,
      attachmentSize: data.attachmentSize.present ? data.attachmentSize.value : this.attachmentSize,
      status: data.status.present ? data.status.value : this.status,
      errorMessage: data.errorMessage.present ? data.errorMessage.value : this.errorMessage,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deliveredAt: data.deliveredAt.present ? data.deliveredAt.value : this.deliveredAt,
      readAt: data.readAt.present ? data.readAt.value : this.readAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessage(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('direction: $direction, ')
          ..write('contentType: $contentType, ')
          ..write('body: $body, ')
          ..write('attachmentPath: $attachmentPath, ')
          ..write('attachmentFileName: $attachmentFileName, ')
          ..write('attachmentSize: $attachmentSize, ')
          ..write('status: $status, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('createdAt: $createdAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('readAt: $readAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    direction,
    contentType,
    body,
    attachmentPath,
    attachmentFileName,
    attachmentSize,
    status,
    errorMessage,
    createdAt,
    deliveredAt,
    readAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessage &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.direction == this.direction &&
          other.contentType == this.contentType &&
          other.body == this.body &&
          other.attachmentPath == this.attachmentPath &&
          other.attachmentFileName == this.attachmentFileName &&
          other.attachmentSize == this.attachmentSize &&
          other.status == this.status &&
          other.errorMessage == this.errorMessage &&
          other.createdAt == this.createdAt &&
          other.deliveredAt == this.deliveredAt &&
          other.readAt == this.readAt);
}

class ChatMessagesCompanion extends UpdateCompanion<ChatMessage> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<ChatMessageDirectionColumn> direction;
  final Value<String> contentType;
  final Value<String?> body;
  final Value<String?> attachmentPath;
  final Value<String?> attachmentFileName;
  final Value<int?> attachmentSize;
  final Value<ChatMessageStatusColumn> status;
  final Value<String?> errorMessage;
  final Value<DateTime> createdAt;
  final Value<DateTime?> deliveredAt;
  final Value<DateTime?> readAt;
  final Value<int> rowid;
  const ChatMessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.direction = const Value.absent(),
    this.contentType = const Value.absent(),
    this.body = const Value.absent(),
    this.attachmentPath = const Value.absent(),
    this.attachmentFileName = const Value.absent(),
    this.attachmentSize = const Value.absent(),
    this.status = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.readAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatMessagesCompanion.insert({
    required String id,
    required String conversationId,
    required ChatMessageDirectionColumn direction,
    required String contentType,
    this.body = const Value.absent(),
    this.attachmentPath = const Value.absent(),
    this.attachmentFileName = const Value.absent(),
    this.attachmentSize = const Value.absent(),
    required ChatMessageStatusColumn status,
    this.errorMessage = const Value.absent(),
    required DateTime createdAt,
    this.deliveredAt = const Value.absent(),
    this.readAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       conversationId = Value(conversationId),
       direction = Value(direction),
       contentType = Value(contentType),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<ChatMessage> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? direction,
    Expression<String>? contentType,
    Expression<String>? body,
    Expression<String>? attachmentPath,
    Expression<String>? attachmentFileName,
    Expression<int>? attachmentSize,
    Expression<String>? status,
    Expression<String>? errorMessage,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? deliveredAt,
    Expression<DateTime>? readAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (direction != null) 'direction': direction,
      if (contentType != null) 'content_type': contentType,
      if (body != null) 'body': body,
      if (attachmentPath != null) 'attachment_path': attachmentPath,
      if (attachmentFileName != null) 'attachment_file_name': attachmentFileName,
      if (attachmentSize != null) 'attachment_size': attachmentSize,
      if (status != null) 'status': status,
      if (errorMessage != null) 'error_message': errorMessage,
      if (createdAt != null) 'created_at': createdAt,
      if (deliveredAt != null) 'delivered_at': deliveredAt,
      if (readAt != null) 'read_at': readAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatMessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? conversationId,
    Value<ChatMessageDirectionColumn>? direction,
    Value<String>? contentType,
    Value<String?>? body,
    Value<String?>? attachmentPath,
    Value<String?>? attachmentFileName,
    Value<int?>? attachmentSize,
    Value<ChatMessageStatusColumn>? status,
    Value<String?>? errorMessage,
    Value<DateTime>? createdAt,
    Value<DateTime?>? deliveredAt,
    Value<DateTime?>? readAt,
    Value<int>? rowid,
  }) {
    return ChatMessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      direction: direction ?? this.direction,
      contentType: contentType ?? this.contentType,
      body: body ?? this.body,
      attachmentPath: attachmentPath ?? this.attachmentPath,
      attachmentFileName: attachmentFileName ?? this.attachmentFileName,
      attachmentSize: attachmentSize ?? this.attachmentSize,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(
        $ChatMessagesTable.$converterdirection.toSql(direction.value),
      );
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (attachmentPath.present) {
      map['attachment_path'] = Variable<String>(attachmentPath.value);
    }
    if (attachmentFileName.present) {
      map['attachment_file_name'] = Variable<String>(attachmentFileName.value);
    }
    if (attachmentSize.present) {
      map['attachment_size'] = Variable<int>(attachmentSize.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $ChatMessagesTable.$converterstatus.toSql(status.value),
      );
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (deliveredAt.present) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt.value);
    }
    if (readAt.present) {
      map['read_at'] = Variable<DateTime>(readAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('direction: $direction, ')
          ..write('contentType: $contentType, ')
          ..write('body: $body, ')
          ..write('attachmentPath: $attachmentPath, ')
          ..write('attachmentFileName: $attachmentFileName, ')
          ..write('attachmentSize: $attachmentSize, ')
          ..write('status: $status, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('createdAt: $createdAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('readAt: $readAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatOutboxEntriesTable extends ChatOutboxEntries with TableInfo<$ChatOutboxEntriesTable, ChatOutboxEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatOutboxEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES chat_messages (id)',
    ),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt = GeneratedColumn<DateTime>(
    'next_attempt_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    messageId,
    attempts,
    nextAttemptAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_outbox_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatOutboxEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nextAttemptAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {messageId};
  @override
  ChatOutboxEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatOutboxEntry(
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ChatOutboxEntriesTable createAlias(String alias) {
    return $ChatOutboxEntriesTable(attachedDatabase, alias);
  }
}

class ChatOutboxEntry extends DataClass implements Insertable<ChatOutboxEntry> {
  final String messageId;
  final int attempts;
  final DateTime nextAttemptAt;
  final DateTime createdAt;
  const ChatOutboxEntry({
    required this.messageId,
    required this.attempts,
    required this.nextAttemptAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['message_id'] = Variable<String>(messageId);
    map['attempts'] = Variable<int>(attempts);
    map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ChatOutboxEntriesCompanion toCompanion(bool nullToAbsent) {
    return ChatOutboxEntriesCompanion(
      messageId: Value(messageId),
      attempts: Value(attempts),
      nextAttemptAt: Value(nextAttemptAt),
      createdAt: Value(createdAt),
    );
  }

  factory ChatOutboxEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatOutboxEntry(
      messageId: serializer.fromJson<String>(json['messageId']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime>(json['nextAttemptAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'messageId': serializer.toJson<String>(messageId),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime>(nextAttemptAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ChatOutboxEntry copyWith({
    String? messageId,
    int? attempts,
    DateTime? nextAttemptAt,
    DateTime? createdAt,
  }) => ChatOutboxEntry(
    messageId: messageId ?? this.messageId,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    createdAt: createdAt ?? this.createdAt,
  );
  ChatOutboxEntry copyWithCompanion(ChatOutboxEntriesCompanion data) {
    return ChatOutboxEntry(
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present ? data.nextAttemptAt.value : this.nextAttemptAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatOutboxEntry(')
          ..write('messageId: $messageId, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(messageId, attempts, nextAttemptAt, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatOutboxEntry &&
          other.messageId == this.messageId &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.createdAt == this.createdAt);
}

class ChatOutboxEntriesCompanion extends UpdateCompanion<ChatOutboxEntry> {
  final Value<String> messageId;
  final Value<int> attempts;
  final Value<DateTime> nextAttemptAt;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ChatOutboxEntriesCompanion({
    this.messageId = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatOutboxEntriesCompanion.insert({
    required String messageId,
    this.attempts = const Value.absent(),
    required DateTime nextAttemptAt,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : messageId = Value(messageId),
       nextAttemptAt = Value(nextAttemptAt);
  static Insertable<ChatOutboxEntry> custom({
    Expression<String>? messageId,
    Expression<int>? attempts,
    Expression<DateTime>? nextAttemptAt,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (messageId != null) 'message_id': messageId,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatOutboxEntriesCompanion copyWith({
    Value<String>? messageId,
    Value<int>? attempts,
    Value<DateTime>? nextAttemptAt,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ChatOutboxEntriesCompanion(
      messageId: messageId ?? this.messageId,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatOutboxEntriesCompanion(')
          ..write('messageId: $messageId, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatBlockedDevicesTable extends ChatBlockedDevices with TableInfo<$ChatBlockedDevicesTable, ChatBlockedDevice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatBlockedDevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aliasMeta = const VerificationMeta('alias');
  @override
  late final GeneratedColumn<String> alias = GeneratedColumn<String>(
    'alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _blockedAtMeta = const VerificationMeta(
    'blockedAt',
  );
  @override
  late final GeneratedColumn<DateTime> blockedAt = GeneratedColumn<DateTime>(
    'blocked_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [fingerprint, alias, blockedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_blocked_devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatBlockedDevice> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('alias')) {
      context.handle(
        _aliasMeta,
        alias.isAcceptableOrUnknown(data['alias']!, _aliasMeta),
      );
    } else if (isInserting) {
      context.missing(_aliasMeta);
    }
    if (data.containsKey('blocked_at')) {
      context.handle(
        _blockedAtMeta,
        blockedAt.isAcceptableOrUnknown(data['blocked_at']!, _blockedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {fingerprint};
  @override
  ChatBlockedDevice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatBlockedDevice(
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      alias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alias'],
      )!,
      blockedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}blocked_at'],
      )!,
    );
  }

  @override
  $ChatBlockedDevicesTable createAlias(String alias) {
    return $ChatBlockedDevicesTable(attachedDatabase, alias);
  }
}

class ChatBlockedDevice extends DataClass implements Insertable<ChatBlockedDevice> {
  final String fingerprint;
  final String alias;
  final DateTime blockedAt;
  const ChatBlockedDevice({
    required this.fingerprint,
    required this.alias,
    required this.blockedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['fingerprint'] = Variable<String>(fingerprint);
    map['alias'] = Variable<String>(alias);
    map['blocked_at'] = Variable<DateTime>(blockedAt);
    return map;
  }

  ChatBlockedDevicesCompanion toCompanion(bool nullToAbsent) {
    return ChatBlockedDevicesCompanion(
      fingerprint: Value(fingerprint),
      alias: Value(alias),
      blockedAt: Value(blockedAt),
    );
  }

  factory ChatBlockedDevice.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatBlockedDevice(
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      alias: serializer.fromJson<String>(json['alias']),
      blockedAt: serializer.fromJson<DateTime>(json['blockedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'fingerprint': serializer.toJson<String>(fingerprint),
      'alias': serializer.toJson<String>(alias),
      'blockedAt': serializer.toJson<DateTime>(blockedAt),
    };
  }

  ChatBlockedDevice copyWith({
    String? fingerprint,
    String? alias,
    DateTime? blockedAt,
  }) => ChatBlockedDevice(
    fingerprint: fingerprint ?? this.fingerprint,
    alias: alias ?? this.alias,
    blockedAt: blockedAt ?? this.blockedAt,
  );
  ChatBlockedDevice copyWithCompanion(ChatBlockedDevicesCompanion data) {
    return ChatBlockedDevice(
      fingerprint: data.fingerprint.present ? data.fingerprint.value : this.fingerprint,
      alias: data.alias.present ? data.alias.value : this.alias,
      blockedAt: data.blockedAt.present ? data.blockedAt.value : this.blockedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatBlockedDevice(')
          ..write('fingerprint: $fingerprint, ')
          ..write('alias: $alias, ')
          ..write('blockedAt: $blockedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(fingerprint, alias, blockedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatBlockedDevice && other.fingerprint == this.fingerprint && other.alias == this.alias && other.blockedAt == this.blockedAt);
}

class ChatBlockedDevicesCompanion extends UpdateCompanion<ChatBlockedDevice> {
  final Value<String> fingerprint;
  final Value<String> alias;
  final Value<DateTime> blockedAt;
  final Value<int> rowid;
  const ChatBlockedDevicesCompanion({
    this.fingerprint = const Value.absent(),
    this.alias = const Value.absent(),
    this.blockedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatBlockedDevicesCompanion.insert({
    required String fingerprint,
    required String alias,
    this.blockedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : fingerprint = Value(fingerprint),
       alias = Value(alias);
  static Insertable<ChatBlockedDevice> custom({
    Expression<String>? fingerprint,
    Expression<String>? alias,
    Expression<DateTime>? blockedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (alias != null) 'alias': alias,
      if (blockedAt != null) 'blocked_at': blockedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatBlockedDevicesCompanion copyWith({
    Value<String>? fingerprint,
    Value<String>? alias,
    Value<DateTime>? blockedAt,
    Value<int>? rowid,
  }) {
    return ChatBlockedDevicesCompanion(
      fingerprint: fingerprint ?? this.fingerprint,
      alias: alias ?? this.alias,
      blockedAt: blockedAt ?? this.blockedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (alias.present) {
      map['alias'] = Variable<String>(alias.value);
    }
    if (blockedAt.present) {
      map['blocked_at'] = Variable<DateTime>(blockedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatBlockedDevicesCompanion(')
          ..write('fingerprint: $fingerprint, ')
          ..write('alias: $alias, ')
          ..write('blockedAt: $blockedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ChatDatabase extends GeneratedDatabase {
  _$ChatDatabase(QueryExecutor e) : super(e);
  $ChatDatabaseManager get managers => $ChatDatabaseManager(this);
  late final $ChatConversationsTable chatConversations = $ChatConversationsTable(this);
  late final $ChatMessagesTable chatMessages = $ChatMessagesTable(this);
  late final $ChatOutboxEntriesTable chatOutboxEntries = $ChatOutboxEntriesTable(this);
  late final $ChatBlockedDevicesTable chatBlockedDevices = $ChatBlockedDevicesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    chatConversations,
    chatMessages,
    chatOutboxEntries,
    chatBlockedDevices,
  ];
}

typedef $$ChatConversationsTableCreateCompanionBuilder =
    ChatConversationsCompanion Function({
      required String peerFingerprint,
      required String peerAlias,
      Value<String?> peerDeviceModel,
      Value<DateTime?> lastSeenAt,
      Value<int> unreadCount,
      Value<String?> lastMessagePreview,
      Value<DateTime?> lastMessageAt,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$ChatConversationsTableUpdateCompanionBuilder =
    ChatConversationsCompanion Function({
      Value<String> peerFingerprint,
      Value<String> peerAlias,
      Value<String?> peerDeviceModel,
      Value<DateTime?> lastSeenAt,
      Value<int> unreadCount,
      Value<String?> lastMessagePreview,
      Value<DateTime?> lastMessageAt,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$ChatConversationsTableReferences extends BaseReferences<_$ChatDatabase, $ChatConversationsTable, ChatConversation> {
  $$ChatConversationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$ChatMessagesTable, List<ChatMessage>> _chatMessagesRefsTable(_$ChatDatabase db) => MultiTypedResultKey.fromTable(
    db.chatMessages,
    aliasName: 'chat_conversations__peer_fingerprint__chat_messages__conversation_id',
  );

  $$ChatMessagesTableProcessedTableManager get chatMessagesRefs {
    final manager = $$ChatMessagesTableTableManager($_db, $_db.chatMessages).filter(
      (f) => f.conversationId.peerFingerprint.sqlEquals(
        $_itemColumn<String>('peer_fingerprint')!,
      ),
    );

    final cache = $_typedResult.readTableOrNull(_chatMessagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ChatConversationsTableFilterComposer extends Composer<_$ChatDatabase, $ChatConversationsTable> {
  $$ChatConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get peerFingerprint => $composableBuilder(
    column: $table.peerFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerAlias => $composableBuilder(
    column: $table.peerAlias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerDeviceModel => $composableBuilder(
    column: $table.peerDeviceModel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> chatMessagesRefs(
    Expression<bool> Function($$ChatMessagesTableFilterComposer f) f,
  ) {
    final $$ChatMessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.peerFingerprint,
      referencedTable: $db.chatMessages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatMessagesTableFilterComposer(
            $db: $db,
            $table: $db.chatMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChatConversationsTableOrderingComposer extends Composer<_$ChatDatabase, $ChatConversationsTable> {
  $$ChatConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get peerFingerprint => $composableBuilder(
    column: $table.peerFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerAlias => $composableBuilder(
    column: $table.peerAlias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerDeviceModel => $composableBuilder(
    column: $table.peerDeviceModel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatConversationsTableAnnotationComposer extends Composer<_$ChatDatabase, $ChatConversationsTable> {
  $$ChatConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get peerFingerprint => $composableBuilder(
    column: $table.peerFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerAlias => $composableBuilder(column: $table.peerAlias, builder: (column) => column);

  GeneratedColumn<String> get peerDeviceModel => $composableBuilder(
    column: $table.peerDeviceModel,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt => $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> chatMessagesRefs<T extends Object>(
    Expression<T> Function($$ChatMessagesTableAnnotationComposer a) f,
  ) {
    final $$ChatMessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.peerFingerprint,
      referencedTable: $db.chatMessages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatMessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.chatMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChatConversationsTableTableManager
    extends
        RootTableManager<
          _$ChatDatabase,
          $ChatConversationsTable,
          ChatConversation,
          $$ChatConversationsTableFilterComposer,
          $$ChatConversationsTableOrderingComposer,
          $$ChatConversationsTableAnnotationComposer,
          $$ChatConversationsTableCreateCompanionBuilder,
          $$ChatConversationsTableUpdateCompanionBuilder,
          (ChatConversation, $$ChatConversationsTableReferences),
          ChatConversation,
          PrefetchHooks Function({bool chatMessagesRefs})
        > {
  $$ChatConversationsTableTableManager(
    _$ChatDatabase db,
    $ChatConversationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$ChatConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$ChatConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$ChatConversationsTableAnnotationComposer(
            $db: db,
            $table: table,
          ),
          updateCompanionCallback:
              ({
                Value<String> peerFingerprint = const Value.absent(),
                Value<String> peerAlias = const Value.absent(),
                Value<String?> peerDeviceModel = const Value.absent(),
                Value<DateTime?> lastSeenAt = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<String?> lastMessagePreview = const Value.absent(),
                Value<DateTime?> lastMessageAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatConversationsCompanion(
                peerFingerprint: peerFingerprint,
                peerAlias: peerAlias,
                peerDeviceModel: peerDeviceModel,
                lastSeenAt: lastSeenAt,
                unreadCount: unreadCount,
                lastMessagePreview: lastMessagePreview,
                lastMessageAt: lastMessageAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String peerFingerprint,
                required String peerAlias,
                Value<String?> peerDeviceModel = const Value.absent(),
                Value<DateTime?> lastSeenAt = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<String?> lastMessagePreview = const Value.absent(),
                Value<DateTime?> lastMessageAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatConversationsCompanion.insert(
                peerFingerprint: peerFingerprint,
                peerAlias: peerAlias,
                peerDeviceModel: peerDeviceModel,
                lastSeenAt: lastSeenAt,
                unreadCount: unreadCount,
                lastMessagePreview: lastMessagePreview,
                lastMessageAt: lastMessageAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ChatConversationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({chatMessagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (chatMessagesRefs) db.chatMessages],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (chatMessagesRefs)
                    await $_getPrefetchedData<ChatConversation, $ChatConversationsTable, ChatMessage>(
                      currentTable: table,
                      referencedTable: $$ChatConversationsTableReferences._chatMessagesRefsTable(db),
                      managerFromTypedResult: (p0) => $$ChatConversationsTableReferences(
                        db,
                        table,
                        p0,
                      ).chatMessagesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) => referencedItems.where(
                        (e) => e.conversationId == item.peerFingerprint,
                      ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ChatConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$ChatDatabase,
      $ChatConversationsTable,
      ChatConversation,
      $$ChatConversationsTableFilterComposer,
      $$ChatConversationsTableOrderingComposer,
      $$ChatConversationsTableAnnotationComposer,
      $$ChatConversationsTableCreateCompanionBuilder,
      $$ChatConversationsTableUpdateCompanionBuilder,
      (ChatConversation, $$ChatConversationsTableReferences),
      ChatConversation,
      PrefetchHooks Function({bool chatMessagesRefs})
    >;
typedef $$ChatMessagesTableCreateCompanionBuilder =
    ChatMessagesCompanion Function({
      required String id,
      required String conversationId,
      required ChatMessageDirectionColumn direction,
      required String contentType,
      Value<String?> body,
      Value<String?> attachmentPath,
      Value<String?> attachmentFileName,
      Value<int?> attachmentSize,
      required ChatMessageStatusColumn status,
      Value<String?> errorMessage,
      required DateTime createdAt,
      Value<DateTime?> deliveredAt,
      Value<DateTime?> readAt,
      Value<int> rowid,
    });
typedef $$ChatMessagesTableUpdateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<String> id,
      Value<String> conversationId,
      Value<ChatMessageDirectionColumn> direction,
      Value<String> contentType,
      Value<String?> body,
      Value<String?> attachmentPath,
      Value<String?> attachmentFileName,
      Value<int?> attachmentSize,
      Value<ChatMessageStatusColumn> status,
      Value<String?> errorMessage,
      Value<DateTime> createdAt,
      Value<DateTime?> deliveredAt,
      Value<DateTime?> readAt,
      Value<int> rowid,
    });

final class $$ChatMessagesTableReferences extends BaseReferences<_$ChatDatabase, $ChatMessagesTable, ChatMessage> {
  $$ChatMessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ChatConversationsTable _conversationIdTable(_$ChatDatabase db) => db.chatConversations.createAlias(
    'chat_messages__conversation_id__chat_conversations__peer_fingerprint',
  );

  $$ChatConversationsTableProcessedTableManager get conversationId {
    final $_column = $_itemColumn<String>('conversation_id')!;

    final manager = $$ChatConversationsTableTableManager(
      $_db,
      $_db.chatConversations,
    ).filter((f) => f.peerFingerprint.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ChatOutboxEntriesTable, List<ChatOutboxEntry>> _chatOutboxEntriesRefsTable(_$ChatDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.chatOutboxEntries,
        aliasName: 'chat_messages__id__chat_outbox_entries__message_id',
      );

  $$ChatOutboxEntriesTableProcessedTableManager get chatOutboxEntriesRefs {
    final manager = $$ChatOutboxEntriesTableTableManager(
      $_db,
      $_db.chatOutboxEntries,
    ).filter((f) => f.messageId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _chatOutboxEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ChatMessagesTableFilterComposer extends Composer<_$ChatDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ChatMessageDirectionColumn, ChatMessageDirectionColumn, String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentPath => $composableBuilder(
    column: $table.attachmentPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentFileName => $composableBuilder(
    column: $table.attachmentFileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attachmentSize => $composableBuilder(
    column: $table.attachmentSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ChatMessageStatusColumn, ChatMessageStatusColumn, String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ChatConversationsTableFilterComposer get conversationId {
    final $$ChatConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.chatConversations,
      getReferencedColumn: (t) => t.peerFingerprint,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatConversationsTableFilterComposer(
            $db: $db,
            $table: $db.chatConversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> chatOutboxEntriesRefs(
    Expression<bool> Function($$ChatOutboxEntriesTableFilterComposer f) f,
  ) {
    final $$ChatOutboxEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chatOutboxEntries,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatOutboxEntriesTableFilterComposer(
            $db: $db,
            $table: $db.chatOutboxEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChatMessagesTableOrderingComposer extends Composer<_$ChatDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentPath => $composableBuilder(
    column: $table.attachmentPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentFileName => $composableBuilder(
    column: $table.attachmentFileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attachmentSize => $composableBuilder(
    column: $table.attachmentSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ChatConversationsTableOrderingComposer get conversationId {
    final $$ChatConversationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.chatConversations,
      getReferencedColumn: (t) => t.peerFingerprint,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatConversationsTableOrderingComposer(
            $db: $db,
            $table: $db.chatConversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChatMessagesTableAnnotationComposer extends Composer<_$ChatDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id => $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ChatMessageDirectionColumn, String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body => $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get attachmentPath => $composableBuilder(
    column: $table.attachmentPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attachmentFileName => $composableBuilder(
    column: $table.attachmentFileName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attachmentSize => $composableBuilder(
    column: $table.attachmentSize,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<ChatMessageStatusColumn, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt => $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get readAt => $composableBuilder(column: $table.readAt, builder: (column) => column);

  $$ChatConversationsTableAnnotationComposer get conversationId {
    final $$ChatConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.chatConversations,
      getReferencedColumn: (t) => t.peerFingerprint,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.chatConversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> chatOutboxEntriesRefs<T extends Object>(
    Expression<T> Function($$ChatOutboxEntriesTableAnnotationComposer a) f,
  ) {
    final $$ChatOutboxEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.chatOutboxEntries,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatOutboxEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.chatOutboxEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChatMessagesTableTableManager
    extends
        RootTableManager<
          _$ChatDatabase,
          $ChatMessagesTable,
          ChatMessage,
          $$ChatMessagesTableFilterComposer,
          $$ChatMessagesTableOrderingComposer,
          $$ChatMessagesTableAnnotationComposer,
          $$ChatMessagesTableCreateCompanionBuilder,
          $$ChatMessagesTableUpdateCompanionBuilder,
          (ChatMessage, $$ChatMessagesTableReferences),
          ChatMessage,
          PrefetchHooks Function({
            bool conversationId,
            bool chatOutboxEntriesRefs,
          })
        > {
  $$ChatMessagesTableTableManager(_$ChatDatabase db, $ChatMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$ChatMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$ChatMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$ChatMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<ChatMessageDirectionColumn> direction = const Value.absent(),
                Value<String> contentType = const Value.absent(),
                Value<String?> body = const Value.absent(),
                Value<String?> attachmentPath = const Value.absent(),
                Value<String?> attachmentFileName = const Value.absent(),
                Value<int?> attachmentSize = const Value.absent(),
                Value<ChatMessageStatusColumn> status = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatMessagesCompanion(
                id: id,
                conversationId: conversationId,
                direction: direction,
                contentType: contentType,
                body: body,
                attachmentPath: attachmentPath,
                attachmentFileName: attachmentFileName,
                attachmentSize: attachmentSize,
                status: status,
                errorMessage: errorMessage,
                createdAt: createdAt,
                deliveredAt: deliveredAt,
                readAt: readAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String conversationId,
                required ChatMessageDirectionColumn direction,
                required String contentType,
                Value<String?> body = const Value.absent(),
                Value<String?> attachmentPath = const Value.absent(),
                Value<String?> attachmentFileName = const Value.absent(),
                Value<int?> attachmentSize = const Value.absent(),
                required ChatMessageStatusColumn status,
                Value<String?> errorMessage = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatMessagesCompanion.insert(
                id: id,
                conversationId: conversationId,
                direction: direction,
                contentType: contentType,
                body: body,
                attachmentPath: attachmentPath,
                attachmentFileName: attachmentFileName,
                attachmentSize: attachmentSize,
                status: status,
                errorMessage: errorMessage,
                createdAt: createdAt,
                deliveredAt: deliveredAt,
                readAt: readAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ChatMessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({conversationId = false, chatOutboxEntriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (chatOutboxEntriesRefs) db.chatOutboxEntries,
              ],
              addJoins:
                  <T extends TableManagerState<dynamic, dynamic, dynamic, dynamic, dynamic, dynamic, dynamic, dynamic, dynamic, dynamic, dynamic>>(
                    state,
                  ) {
                    if (conversationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.conversationId,
                                referencedTable: $$ChatMessagesTableReferences._conversationIdTable(db),
                                referencedColumn: $$ChatMessagesTableReferences._conversationIdTable(db).peerFingerprint,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (chatOutboxEntriesRefs)
                    await $_getPrefetchedData<ChatMessage, $ChatMessagesTable, ChatOutboxEntry>(
                      currentTable: table,
                      referencedTable: $$ChatMessagesTableReferences._chatOutboxEntriesRefsTable(db),
                      managerFromTypedResult: (p0) => $$ChatMessagesTableReferences(
                        db,
                        table,
                        p0,
                      ).chatOutboxEntriesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) => referencedItems.where(
                        (e) => e.messageId == item.id,
                      ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ChatMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$ChatDatabase,
      $ChatMessagesTable,
      ChatMessage,
      $$ChatMessagesTableFilterComposer,
      $$ChatMessagesTableOrderingComposer,
      $$ChatMessagesTableAnnotationComposer,
      $$ChatMessagesTableCreateCompanionBuilder,
      $$ChatMessagesTableUpdateCompanionBuilder,
      (ChatMessage, $$ChatMessagesTableReferences),
      ChatMessage,
      PrefetchHooks Function({bool conversationId, bool chatOutboxEntriesRefs})
    >;
typedef $$ChatOutboxEntriesTableCreateCompanionBuilder =
    ChatOutboxEntriesCompanion Function({
      required String messageId,
      Value<int> attempts,
      required DateTime nextAttemptAt,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$ChatOutboxEntriesTableUpdateCompanionBuilder =
    ChatOutboxEntriesCompanion Function({
      Value<String> messageId,
      Value<int> attempts,
      Value<DateTime> nextAttemptAt,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$ChatOutboxEntriesTableReferences extends BaseReferences<_$ChatDatabase, $ChatOutboxEntriesTable, ChatOutboxEntry> {
  $$ChatOutboxEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ChatMessagesTable _messageIdTable(_$ChatDatabase db) => db.chatMessages.createAlias('chat_outbox_entries__message_id__chat_messages__id');

  $$ChatMessagesTableProcessedTableManager get messageId {
    final $_column = $_itemColumn<String>('message_id')!;

    final manager = $$ChatMessagesTableTableManager(
      $_db,
      $_db.chatMessages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_messageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ChatOutboxEntriesTableFilterComposer extends Composer<_$ChatDatabase, $ChatOutboxEntriesTable> {
  $$ChatOutboxEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ChatMessagesTableFilterComposer get messageId {
    final $$ChatMessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.chatMessages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatMessagesTableFilterComposer(
            $db: $db,
            $table: $db.chatMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChatOutboxEntriesTableOrderingComposer extends Composer<_$ChatDatabase, $ChatOutboxEntriesTable> {
  $$ChatOutboxEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ChatMessagesTableOrderingComposer get messageId {
    final $$ChatMessagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.chatMessages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatMessagesTableOrderingComposer(
            $db: $db,
            $table: $db.chatMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChatOutboxEntriesTableAnnotationComposer extends Composer<_$ChatDatabase, $ChatOutboxEntriesTable> {
  $$ChatOutboxEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get attempts => $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt => $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ChatMessagesTableAnnotationComposer get messageId {
    final $$ChatMessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.chatMessages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChatMessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.chatMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ChatOutboxEntriesTableTableManager
    extends
        RootTableManager<
          _$ChatDatabase,
          $ChatOutboxEntriesTable,
          ChatOutboxEntry,
          $$ChatOutboxEntriesTableFilterComposer,
          $$ChatOutboxEntriesTableOrderingComposer,
          $$ChatOutboxEntriesTableAnnotationComposer,
          $$ChatOutboxEntriesTableCreateCompanionBuilder,
          $$ChatOutboxEntriesTableUpdateCompanionBuilder,
          (ChatOutboxEntry, $$ChatOutboxEntriesTableReferences),
          ChatOutboxEntry,
          PrefetchHooks Function({bool messageId})
        > {
  $$ChatOutboxEntriesTableTableManager(
    _$ChatDatabase db,
    $ChatOutboxEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$ChatOutboxEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$ChatOutboxEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$ChatOutboxEntriesTableAnnotationComposer(
            $db: db,
            $table: table,
          ),
          updateCompanionCallback:
              ({
                Value<String> messageId = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime> nextAttemptAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatOutboxEntriesCompanion(
                messageId: messageId,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String messageId,
                Value<int> attempts = const Value.absent(),
                required DateTime nextAttemptAt,
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatOutboxEntriesCompanion.insert(
                messageId: messageId,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ChatOutboxEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({messageId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <T extends TableManagerState<dynamic, dynamic, dynamic, dynamic, dynamic, dynamic, dynamic, dynamic, dynamic, dynamic, dynamic>>(
                    state,
                  ) {
                    if (messageId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.messageId,
                                referencedTable: $$ChatOutboxEntriesTableReferences._messageIdTable(db),
                                referencedColumn: $$ChatOutboxEntriesTableReferences._messageIdTable(db).id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ChatOutboxEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$ChatDatabase,
      $ChatOutboxEntriesTable,
      ChatOutboxEntry,
      $$ChatOutboxEntriesTableFilterComposer,
      $$ChatOutboxEntriesTableOrderingComposer,
      $$ChatOutboxEntriesTableAnnotationComposer,
      $$ChatOutboxEntriesTableCreateCompanionBuilder,
      $$ChatOutboxEntriesTableUpdateCompanionBuilder,
      (ChatOutboxEntry, $$ChatOutboxEntriesTableReferences),
      ChatOutboxEntry,
      PrefetchHooks Function({bool messageId})
    >;
typedef $$ChatBlockedDevicesTableCreateCompanionBuilder =
    ChatBlockedDevicesCompanion Function({
      required String fingerprint,
      required String alias,
      Value<DateTime> blockedAt,
      Value<int> rowid,
    });
typedef $$ChatBlockedDevicesTableUpdateCompanionBuilder =
    ChatBlockedDevicesCompanion Function({
      Value<String> fingerprint,
      Value<String> alias,
      Value<DateTime> blockedAt,
      Value<int> rowid,
    });

class $$ChatBlockedDevicesTableFilterComposer extends Composer<_$ChatDatabase, $ChatBlockedDevicesTable> {
  $$ChatBlockedDevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get blockedAt => $composableBuilder(
    column: $table.blockedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatBlockedDevicesTableOrderingComposer extends Composer<_$ChatDatabase, $ChatBlockedDevicesTable> {
  $$ChatBlockedDevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get blockedAt => $composableBuilder(
    column: $table.blockedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatBlockedDevicesTableAnnotationComposer extends Composer<_$ChatDatabase, $ChatBlockedDevicesTable> {
  $$ChatBlockedDevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get alias => $composableBuilder(column: $table.alias, builder: (column) => column);

  GeneratedColumn<DateTime> get blockedAt => $composableBuilder(column: $table.blockedAt, builder: (column) => column);
}

class $$ChatBlockedDevicesTableTableManager
    extends
        RootTableManager<
          _$ChatDatabase,
          $ChatBlockedDevicesTable,
          ChatBlockedDevice,
          $$ChatBlockedDevicesTableFilterComposer,
          $$ChatBlockedDevicesTableOrderingComposer,
          $$ChatBlockedDevicesTableAnnotationComposer,
          $$ChatBlockedDevicesTableCreateCompanionBuilder,
          $$ChatBlockedDevicesTableUpdateCompanionBuilder,
          (
            ChatBlockedDevice,
            BaseReferences<_$ChatDatabase, $ChatBlockedDevicesTable, ChatBlockedDevice>,
          ),
          ChatBlockedDevice,
          PrefetchHooks Function()
        > {
  $$ChatBlockedDevicesTableTableManager(
    _$ChatDatabase db,
    $ChatBlockedDevicesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$ChatBlockedDevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$ChatBlockedDevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$ChatBlockedDevicesTableAnnotationComposer(
            $db: db,
            $table: table,
          ),
          updateCompanionCallback:
              ({
                Value<String> fingerprint = const Value.absent(),
                Value<String> alias = const Value.absent(),
                Value<DateTime> blockedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatBlockedDevicesCompanion(
                fingerprint: fingerprint,
                alias: alias,
                blockedAt: blockedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String fingerprint,
                required String alias,
                Value<DateTime> blockedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatBlockedDevicesCompanion.insert(
                fingerprint: fingerprint,
                alias: alias,
                blockedAt: blockedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0.map((e) => (e.readTable(table), BaseReferences(db, table, e))).toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatBlockedDevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$ChatDatabase,
      $ChatBlockedDevicesTable,
      ChatBlockedDevice,
      $$ChatBlockedDevicesTableFilterComposer,
      $$ChatBlockedDevicesTableOrderingComposer,
      $$ChatBlockedDevicesTableAnnotationComposer,
      $$ChatBlockedDevicesTableCreateCompanionBuilder,
      $$ChatBlockedDevicesTableUpdateCompanionBuilder,
      (
        ChatBlockedDevice,
        BaseReferences<_$ChatDatabase, $ChatBlockedDevicesTable, ChatBlockedDevice>,
      ),
      ChatBlockedDevice,
      PrefetchHooks Function()
    >;

class $ChatDatabaseManager {
  final _$ChatDatabase _db;
  $ChatDatabaseManager(this._db);
  $$ChatConversationsTableTableManager get chatConversations => $$ChatConversationsTableTableManager(_db, _db.chatConversations);
  $$ChatMessagesTableTableManager get chatMessages => $$ChatMessagesTableTableManager(_db, _db.chatMessages);
  $$ChatOutboxEntriesTableTableManager get chatOutboxEntries => $$ChatOutboxEntriesTableTableManager(_db, _db.chatOutboxEntries);
  $$ChatBlockedDevicesTableTableManager get chatBlockedDevices => $$ChatBlockedDevicesTableTableManager(_db, _db.chatBlockedDevices);
}
