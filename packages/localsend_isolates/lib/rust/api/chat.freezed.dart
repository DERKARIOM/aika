// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RsChatError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsChatError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsChatError()';
}


}

/// @nodoc
class $RsChatErrorCopyWith<$Res>  {
$RsChatErrorCopyWith(RsChatError _, $Res Function(RsChatError) __);
}


/// Adds pattern-matching-related methods to [RsChatError].
extension RsChatErrorPatterns on RsChatError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsChatError_FingerprintMismatch value)?  fingerprintMismatch,TResult Function( RsChatError_Unsupported value)?  unsupported,TResult Function( RsChatError_TooManyConnections value)?  tooManyConnections,TResult Function( RsChatError_NotConnected value)?  notConnected,TResult Function( RsChatError_MessageTooLarge value)?  messageTooLarge,TResult Function( RsChatError_Timeout value)?  timeout,TResult Function( RsChatError_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsChatError_FingerprintMismatch() when fingerprintMismatch != null:
return fingerprintMismatch(_that);case RsChatError_Unsupported() when unsupported != null:
return unsupported(_that);case RsChatError_TooManyConnections() when tooManyConnections != null:
return tooManyConnections(_that);case RsChatError_NotConnected() when notConnected != null:
return notConnected(_that);case RsChatError_MessageTooLarge() when messageTooLarge != null:
return messageTooLarge(_that);case RsChatError_Timeout() when timeout != null:
return timeout(_that);case RsChatError_Other() when other != null:
return other(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsChatError_FingerprintMismatch value)  fingerprintMismatch,required TResult Function( RsChatError_Unsupported value)  unsupported,required TResult Function( RsChatError_TooManyConnections value)  tooManyConnections,required TResult Function( RsChatError_NotConnected value)  notConnected,required TResult Function( RsChatError_MessageTooLarge value)  messageTooLarge,required TResult Function( RsChatError_Timeout value)  timeout,required TResult Function( RsChatError_Other value)  other,}){
final _that = this;
switch (_that) {
case RsChatError_FingerprintMismatch():
return fingerprintMismatch(_that);case RsChatError_Unsupported():
return unsupported(_that);case RsChatError_TooManyConnections():
return tooManyConnections(_that);case RsChatError_NotConnected():
return notConnected(_that);case RsChatError_MessageTooLarge():
return messageTooLarge(_that);case RsChatError_Timeout():
return timeout(_that);case RsChatError_Other():
return other(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsChatError_FingerprintMismatch value)?  fingerprintMismatch,TResult? Function( RsChatError_Unsupported value)?  unsupported,TResult? Function( RsChatError_TooManyConnections value)?  tooManyConnections,TResult? Function( RsChatError_NotConnected value)?  notConnected,TResult? Function( RsChatError_MessageTooLarge value)?  messageTooLarge,TResult? Function( RsChatError_Timeout value)?  timeout,TResult? Function( RsChatError_Other value)?  other,}){
final _that = this;
switch (_that) {
case RsChatError_FingerprintMismatch() when fingerprintMismatch != null:
return fingerprintMismatch(_that);case RsChatError_Unsupported() when unsupported != null:
return unsupported(_that);case RsChatError_TooManyConnections() when tooManyConnections != null:
return tooManyConnections(_that);case RsChatError_NotConnected() when notConnected != null:
return notConnected(_that);case RsChatError_MessageTooLarge() when messageTooLarge != null:
return messageTooLarge(_that);case RsChatError_Timeout() when timeout != null:
return timeout(_that);case RsChatError_Other() when other != null:
return other(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  fingerprintMismatch,TResult Function( int status)?  unsupported,TResult Function()?  tooManyConnections,TResult Function()?  notConnected,TResult Function()?  messageTooLarge,TResult Function()?  timeout,TResult Function( String message)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsChatError_FingerprintMismatch() when fingerprintMismatch != null:
return fingerprintMismatch();case RsChatError_Unsupported() when unsupported != null:
return unsupported(_that.status);case RsChatError_TooManyConnections() when tooManyConnections != null:
return tooManyConnections();case RsChatError_NotConnected() when notConnected != null:
return notConnected();case RsChatError_MessageTooLarge() when messageTooLarge != null:
return messageTooLarge();case RsChatError_Timeout() when timeout != null:
return timeout();case RsChatError_Other() when other != null:
return other(_that.message);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  fingerprintMismatch,required TResult Function( int status)  unsupported,required TResult Function()  tooManyConnections,required TResult Function()  notConnected,required TResult Function()  messageTooLarge,required TResult Function()  timeout,required TResult Function( String message)  other,}) {final _that = this;
switch (_that) {
case RsChatError_FingerprintMismatch():
return fingerprintMismatch();case RsChatError_Unsupported():
return unsupported(_that.status);case RsChatError_TooManyConnections():
return tooManyConnections();case RsChatError_NotConnected():
return notConnected();case RsChatError_MessageTooLarge():
return messageTooLarge();case RsChatError_Timeout():
return timeout();case RsChatError_Other():
return other(_that.message);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  fingerprintMismatch,TResult? Function( int status)?  unsupported,TResult? Function()?  tooManyConnections,TResult? Function()?  notConnected,TResult? Function()?  messageTooLarge,TResult? Function()?  timeout,TResult? Function( String message)?  other,}) {final _that = this;
switch (_that) {
case RsChatError_FingerprintMismatch() when fingerprintMismatch != null:
return fingerprintMismatch();case RsChatError_Unsupported() when unsupported != null:
return unsupported(_that.status);case RsChatError_TooManyConnections() when tooManyConnections != null:
return tooManyConnections();case RsChatError_NotConnected() when notConnected != null:
return notConnected();case RsChatError_MessageTooLarge() when messageTooLarge != null:
return messageTooLarge();case RsChatError_Timeout() when timeout != null:
return timeout();case RsChatError_Other() when other != null:
return other(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class RsChatError_FingerprintMismatch extends RsChatError {
  const RsChatError_FingerprintMismatch(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsChatError_FingerprintMismatch);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsChatError.fingerprintMismatch()';
}


}




/// @nodoc


class RsChatError_Unsupported extends RsChatError {
  const RsChatError_Unsupported({required this.status}): super._();
  

 final  int status;

/// Create a copy of RsChatError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsChatError_UnsupportedCopyWith<RsChatError_Unsupported> get copyWith => _$RsChatError_UnsupportedCopyWithImpl<RsChatError_Unsupported>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsChatError_Unsupported&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode => Object.hash(runtimeType,status);

@override
String toString() {
  return 'RsChatError.unsupported(status: $status)';
}


}

/// @nodoc
abstract mixin class $RsChatError_UnsupportedCopyWith<$Res> implements $RsChatErrorCopyWith<$Res> {
  factory $RsChatError_UnsupportedCopyWith(RsChatError_Unsupported value, $Res Function(RsChatError_Unsupported) _then) = _$RsChatError_UnsupportedCopyWithImpl;
@useResult
$Res call({
 int status
});




}
/// @nodoc
class _$RsChatError_UnsupportedCopyWithImpl<$Res>
    implements $RsChatError_UnsupportedCopyWith<$Res> {
  _$RsChatError_UnsupportedCopyWithImpl(this._self, this._then);

  final RsChatError_Unsupported _self;
  final $Res Function(RsChatError_Unsupported) _then;

/// Create a copy of RsChatError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? status = null,}) {
  return _then(RsChatError_Unsupported(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RsChatError_TooManyConnections extends RsChatError {
  const RsChatError_TooManyConnections(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsChatError_TooManyConnections);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsChatError.tooManyConnections()';
}


}




/// @nodoc


class RsChatError_NotConnected extends RsChatError {
  const RsChatError_NotConnected(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsChatError_NotConnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsChatError.notConnected()';
}


}




/// @nodoc


class RsChatError_MessageTooLarge extends RsChatError {
  const RsChatError_MessageTooLarge(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsChatError_MessageTooLarge);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsChatError.messageTooLarge()';
}


}




/// @nodoc


class RsChatError_Timeout extends RsChatError {
  const RsChatError_Timeout(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsChatError_Timeout);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsChatError.timeout()';
}


}




/// @nodoc


class RsChatError_Other extends RsChatError {
  const RsChatError_Other({required this.message}): super._();
  

 final  String message;

/// Create a copy of RsChatError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsChatError_OtherCopyWith<RsChatError_Other> get copyWith => _$RsChatError_OtherCopyWithImpl<RsChatError_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsChatError_Other&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'RsChatError.other(message: $message)';
}


}

/// @nodoc
abstract mixin class $RsChatError_OtherCopyWith<$Res> implements $RsChatErrorCopyWith<$Res> {
  factory $RsChatError_OtherCopyWith(RsChatError_Other value, $Res Function(RsChatError_Other) _then) = _$RsChatError_OtherCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$RsChatError_OtherCopyWithImpl<$Res>
    implements $RsChatError_OtherCopyWith<$Res> {
  _$RsChatError_OtherCopyWithImpl(this._self, this._then);

  final RsChatError_Other _self;
  final $Res Function(RsChatError_Other) _then;

/// Create a copy of RsChatError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(RsChatError_Other(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$RsChatEvent {

 String get connectionId;
/// Create a copy of RsChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsChatEventCopyWith<RsChatEvent> get copyWith => _$RsChatEventCopyWithImpl<RsChatEvent>(this as RsChatEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsChatEvent&&(identical(other.connectionId, connectionId) || other.connectionId == connectionId));
}


@override
int get hashCode => Object.hash(runtimeType,connectionId);

@override
String toString() {
  return 'RsChatEvent(connectionId: $connectionId)';
}


}

/// @nodoc
abstract mixin class $RsChatEventCopyWith<$Res>  {
  factory $RsChatEventCopyWith(RsChatEvent value, $Res Function(RsChatEvent) _then) = _$RsChatEventCopyWithImpl;
@useResult
$Res call({
 String connectionId
});




}
/// @nodoc
class _$RsChatEventCopyWithImpl<$Res>
    implements $RsChatEventCopyWith<$Res> {
  _$RsChatEventCopyWithImpl(this._self, this._then);

  final RsChatEvent _self;
  final $Res Function(RsChatEvent) _then;

/// Create a copy of RsChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? connectionId = null,}) {
  return _then(_self.copyWith(
connectionId: null == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RsChatEvent].
extension RsChatEventPatterns on RsChatEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsChatEvent_Connected value)?  connected,TResult Function( RsChatEvent_Message value)?  message,TResult Function( RsChatEvent_Disconnected value)?  disconnected,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsChatEvent_Connected() when connected != null:
return connected(_that);case RsChatEvent_Message() when message != null:
return message(_that);case RsChatEvent_Disconnected() when disconnected != null:
return disconnected(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsChatEvent_Connected value)  connected,required TResult Function( RsChatEvent_Message value)  message,required TResult Function( RsChatEvent_Disconnected value)  disconnected,}){
final _that = this;
switch (_that) {
case RsChatEvent_Connected():
return connected(_that);case RsChatEvent_Message():
return message(_that);case RsChatEvent_Disconnected():
return disconnected(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsChatEvent_Connected value)?  connected,TResult? Function( RsChatEvent_Message value)?  message,TResult? Function( RsChatEvent_Disconnected value)?  disconnected,}){
final _that = this;
switch (_that) {
case RsChatEvent_Connected() when connected != null:
return connected(_that);case RsChatEvent_Message() when message != null:
return message(_that);case RsChatEvent_Disconnected() when disconnected != null:
return disconnected(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String connectionId,  String fingerprint,  String ip,  bool outbound)?  connected,TResult Function( String connectionId,  String text)?  message,TResult Function( String connectionId,  String reason)?  disconnected,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsChatEvent_Connected() when connected != null:
return connected(_that.connectionId,_that.fingerprint,_that.ip,_that.outbound);case RsChatEvent_Message() when message != null:
return message(_that.connectionId,_that.text);case RsChatEvent_Disconnected() when disconnected != null:
return disconnected(_that.connectionId,_that.reason);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String connectionId,  String fingerprint,  String ip,  bool outbound)  connected,required TResult Function( String connectionId,  String text)  message,required TResult Function( String connectionId,  String reason)  disconnected,}) {final _that = this;
switch (_that) {
case RsChatEvent_Connected():
return connected(_that.connectionId,_that.fingerprint,_that.ip,_that.outbound);case RsChatEvent_Message():
return message(_that.connectionId,_that.text);case RsChatEvent_Disconnected():
return disconnected(_that.connectionId,_that.reason);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String connectionId,  String fingerprint,  String ip,  bool outbound)?  connected,TResult? Function( String connectionId,  String text)?  message,TResult? Function( String connectionId,  String reason)?  disconnected,}) {final _that = this;
switch (_that) {
case RsChatEvent_Connected() when connected != null:
return connected(_that.connectionId,_that.fingerprint,_that.ip,_that.outbound);case RsChatEvent_Message() when message != null:
return message(_that.connectionId,_that.text);case RsChatEvent_Disconnected() when disconnected != null:
return disconnected(_that.connectionId,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class RsChatEvent_Connected extends RsChatEvent {
  const RsChatEvent_Connected({required this.connectionId, required this.fingerprint, required this.ip, required this.outbound}): super._();
  

@override final  String connectionId;
/// Verified SHA-256 fingerprint (uppercase hex) of the peer certificate.
 final  String fingerprint;
 final  String ip;
/// `true` when this device initiated the connection.
 final  bool outbound;

/// Create a copy of RsChatEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsChatEvent_ConnectedCopyWith<RsChatEvent_Connected> get copyWith => _$RsChatEvent_ConnectedCopyWithImpl<RsChatEvent_Connected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsChatEvent_Connected&&(identical(other.connectionId, connectionId) || other.connectionId == connectionId)&&(identical(other.fingerprint, fingerprint) || other.fingerprint == fingerprint)&&(identical(other.ip, ip) || other.ip == ip)&&(identical(other.outbound, outbound) || other.outbound == outbound));
}


@override
int get hashCode => Object.hash(runtimeType,connectionId,fingerprint,ip,outbound);

@override
String toString() {
  return 'RsChatEvent.connected(connectionId: $connectionId, fingerprint: $fingerprint, ip: $ip, outbound: $outbound)';
}


}

/// @nodoc
abstract mixin class $RsChatEvent_ConnectedCopyWith<$Res> implements $RsChatEventCopyWith<$Res> {
  factory $RsChatEvent_ConnectedCopyWith(RsChatEvent_Connected value, $Res Function(RsChatEvent_Connected) _then) = _$RsChatEvent_ConnectedCopyWithImpl;
@override @useResult
$Res call({
 String connectionId, String fingerprint, String ip, bool outbound
});




}
/// @nodoc
class _$RsChatEvent_ConnectedCopyWithImpl<$Res>
    implements $RsChatEvent_ConnectedCopyWith<$Res> {
  _$RsChatEvent_ConnectedCopyWithImpl(this._self, this._then);

  final RsChatEvent_Connected _self;
  final $Res Function(RsChatEvent_Connected) _then;

/// Create a copy of RsChatEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? connectionId = null,Object? fingerprint = null,Object? ip = null,Object? outbound = null,}) {
  return _then(RsChatEvent_Connected(
connectionId: null == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String,fingerprint: null == fingerprint ? _self.fingerprint : fingerprint // ignore: cast_nullable_to_non_nullable
as String,ip: null == ip ? _self.ip : ip // ignore: cast_nullable_to_non_nullable
as String,outbound: null == outbound ? _self.outbound : outbound // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class RsChatEvent_Message extends RsChatEvent {
  const RsChatEvent_Message({required this.connectionId, required this.text}): super._();
  

@override final  String connectionId;
 final  String text;

/// Create a copy of RsChatEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsChatEvent_MessageCopyWith<RsChatEvent_Message> get copyWith => _$RsChatEvent_MessageCopyWithImpl<RsChatEvent_Message>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsChatEvent_Message&&(identical(other.connectionId, connectionId) || other.connectionId == connectionId)&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,connectionId,text);

@override
String toString() {
  return 'RsChatEvent.message(connectionId: $connectionId, text: $text)';
}


}

/// @nodoc
abstract mixin class $RsChatEvent_MessageCopyWith<$Res> implements $RsChatEventCopyWith<$Res> {
  factory $RsChatEvent_MessageCopyWith(RsChatEvent_Message value, $Res Function(RsChatEvent_Message) _then) = _$RsChatEvent_MessageCopyWithImpl;
@override @useResult
$Res call({
 String connectionId, String text
});




}
/// @nodoc
class _$RsChatEvent_MessageCopyWithImpl<$Res>
    implements $RsChatEvent_MessageCopyWith<$Res> {
  _$RsChatEvent_MessageCopyWithImpl(this._self, this._then);

  final RsChatEvent_Message _self;
  final $Res Function(RsChatEvent_Message) _then;

/// Create a copy of RsChatEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? connectionId = null,Object? text = null,}) {
  return _then(RsChatEvent_Message(
connectionId: null == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsChatEvent_Disconnected extends RsChatEvent {
  const RsChatEvent_Disconnected({required this.connectionId, required this.reason}): super._();
  

@override final  String connectionId;
 final  String reason;

/// Create a copy of RsChatEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsChatEvent_DisconnectedCopyWith<RsChatEvent_Disconnected> get copyWith => _$RsChatEvent_DisconnectedCopyWithImpl<RsChatEvent_Disconnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsChatEvent_Disconnected&&(identical(other.connectionId, connectionId) || other.connectionId == connectionId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,connectionId,reason);

@override
String toString() {
  return 'RsChatEvent.disconnected(connectionId: $connectionId, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $RsChatEvent_DisconnectedCopyWith<$Res> implements $RsChatEventCopyWith<$Res> {
  factory $RsChatEvent_DisconnectedCopyWith(RsChatEvent_Disconnected value, $Res Function(RsChatEvent_Disconnected) _then) = _$RsChatEvent_DisconnectedCopyWithImpl;
@override @useResult
$Res call({
 String connectionId, String reason
});




}
/// @nodoc
class _$RsChatEvent_DisconnectedCopyWithImpl<$Res>
    implements $RsChatEvent_DisconnectedCopyWith<$Res> {
  _$RsChatEvent_DisconnectedCopyWithImpl(this._self, this._then);

  final RsChatEvent_Disconnected _self;
  final $Res Function(RsChatEvent_Disconnected) _then;

/// Create a copy of RsChatEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? connectionId = null,Object? reason = null,}) {
  return _then(RsChatEvent_Disconnected(
connectionId: null == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
