import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:localsend_app/util/link_download/github_source.dart';
import 'package:localsend_app/util/link_download/link_http.dart';
import 'package:localsend_app/util/link_download/link_problem.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('GitHubAccount');

const _tokenKey = 'aika_github_token';
const _loginKey = 'aika_github_login';

/// The GitHub account used to download Actions artifacts.
class GitHubAccountState {
  /// `false` until the secure storage was read once.
  final bool loaded;

  /// GitHub user name when a token is set.
  final String? login;

  const GitHubAccountState({required this.loaded, required this.login});

  bool get connected => login != null;
}

/// Why connecting failed.
enum GitHubConnectError { malformed, invalid, network, storage }

class GitHubConnectException implements Exception {
  final GitHubConnectError error;

  const GitHubConnectException(this.error);
}

/// GitHub personal access token for "Télécharger depuis un lien".
///
/// - stored with the platform's secure storage (Keychain, Keystore, DPAPI,
///   libsecret), never in the settings, the queue or the logs;
/// - sent only over https to `api.github.com`, never to the storage
///   servers GitHub redirects to;
/// - verified with GitHub before being saved; removable at any time.
final githubAccountProvider = NotifierProvider<GitHubAccountService, GitHubAccountState>((ref) => GitHubAccountService());

class GitHubAccountService extends Notifier<GitHubAccountState> {
  final FlutterSecureStorage _storage;
  final LinkHttp _http;

  GitHubAccountService({FlutterSecureStorage? storage, LinkHttp http = const LinkHttp()})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
          ),
      _http = http;

  @override
  GitHubAccountState init() {
    unawaited(_load());
    return const GitHubAccountState(loaded: false, login: null);
  }

  Future<void> _load() async {
    String? login;
    try {
      if (await _storage.read(key: _tokenKey) != null) {
        login = await _storage.read(key: _loginKey);
      }
    } catch (e) {
      _logger.warning('Secure storage unavailable: $e');
    }
    state = GitHubAccountState(loaded: true, login: login);
  }

  /// The saved token, or `null` when not connected.
  Future<String?> readToken() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (e) {
      _logger.warning('Secure storage unavailable: $e');
      return null;
    }
  }

  /// Checks [token] with GitHub (`GET /user`) and saves it. Returns the
  /// GitHub user name.
  Future<String> connect(String token) async {
    final trimmed = token.trim();
    if (!looksLikeGitHubToken(trimmed)) {
      throw const GitHubConnectException(GitHubConnectError.malformed);
    }
    final String login;
    try {
      final json = await _http.getJson(
        Uri.https(githubApiHost, '/user'),
        auth: LinkAuth(host: githubApiHost, authorization: 'Bearer $trimmed'),
        headers: githubApiHeaders,
      );
      final value = json['login'];
      if (value is! String || value.isEmpty) {
        throw const GitHubConnectException(GitHubConnectError.invalid);
      }
      login = value;
    } on LinkDownloadException catch (e) {
      throw GitHubConnectException(e.problem == LinkProblem.requiresAuth ? GitHubConnectError.invalid : GitHubConnectError.network);
    }
    try {
      await _storage.write(key: _tokenKey, value: trimmed);
      await _storage.write(key: _loginKey, value: login);
    } catch (e) {
      _logger.warning('Could not save the GitHub token: $e');
      throw const GitHubConnectException(GitHubConnectError.storage);
    }
    state = GitHubAccountState(loaded: true, login: login);
    return login;
  }

  /// Forgets the token on this device. (Revoking it is done on GitHub.)
  Future<void> disconnect() async {
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _loginKey);
    } catch (e) {
      _logger.warning('Could not delete the GitHub token: $e');
    }
    state = const GitHubAccountState(loaded: true, login: null);
  }
}
