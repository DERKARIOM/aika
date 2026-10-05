import 'package:localsend_app/model/update/update_policy.dart';
import 'package:test/test.dart';

void main() {
  const policy = UpdatePolicy(mandatoryPriority: 4);

  group('UpdatePolicy.decide', () {
    test('Should propose a newer build as optional by default', () {
      expect(policy.decide(installedVersionCode: 18, availableVersionCode: 19, updatePriority: 0), UpdateDecision.optional);
    });

    test('Should require an update at or above the mandatory priority', () {
      expect(policy.decide(installedVersionCode: 18, availableVersionCode: 19, updatePriority: 4), UpdateDecision.mandatory);
      expect(policy.decide(installedVersionCode: 18, availableVersionCode: 30, updatePriority: 5), UpdateDecision.mandatory);
      expect(policy.decide(installedVersionCode: 18, availableVersionCode: 19, updatePriority: 3), UpdateDecision.optional);
    });

    test('Should require an update below the minimum versionCode', () {
      expect(
        policy.decide(installedVersionCode: 17, availableVersionCode: 19, updatePriority: 0, minimumVersionCode: 18),
        UpdateDecision.mandatory,
      );
    });

    test('Should not require an update at or above the minimum versionCode', () {
      expect(
        policy.decide(installedVersionCode: 18, availableVersionCode: 19, updatePriority: 0, minimumVersionCode: 18),
        UpdateDecision.optional,
      );
      expect(
        policy.decide(installedVersionCode: 20, availableVersionCode: 21, updatePriority: 0, minimumVersionCode: 18),
        UpdateDecision.optional,
      );
    });

    test('Should ignore a build that is not newer', () {
      expect(policy.decide(installedVersionCode: 18, availableVersionCode: 18, updatePriority: 5), UpdateDecision.none);
      expect(
        policy.decide(installedVersionCode: 18, availableVersionCode: 17, updatePriority: 5, minimumVersionCode: 30),
        UpdateDecision.none,
      );
    });

    test('Should compare version codes numerically, not as text', () {
      // "9" > "10" as text; 10 > 9 as versionCode.
      expect(policy.decide(installedVersionCode: 9, availableVersionCode: 10, updatePriority: 0), UpdateDecision.optional);
      expect(policy.decide(installedVersionCode: 10, availableVersionCode: 9, updatePriority: 0), UpdateDecision.none);
    });

    test('Should not make an update mandatory from an unknown installed versionCode', () {
      expect(
        policy.decide(installedVersionCode: null, availableVersionCode: 19, updatePriority: 0, minimumVersionCode: 30),
        UpdateDecision.optional,
      );
      expect(policy.decide(installedVersionCode: null, availableVersionCode: null, updatePriority: 4), UpdateDecision.mandatory);
    });
  });

  group('parseVersionCode', () {
    test('Should parse a build number', () {
      expect(parseVersionCode('18'), 18);
      expect(parseVersionCode(' 18 '), 18);
    });

    test('Should return null for a non-integer build number', () {
      expect(parseVersionCode(''), isNull);
      expect(parseVersionCode('1.1.4'), isNull);
    });
  });
}
