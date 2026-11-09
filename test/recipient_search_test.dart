/// Recipients of a new message: how `send_message` names them
/// ([Recipient.reference]) and which of the users and groups the search
/// found a name or reference names ([RecipientRequest.matches]).
library;

import 'package:flutter_smartschool/flutter_smartschool.dart';
import 'package:smartschool_mcp/src/messages/recipient_search.dart';
import 'package:test/test.dart';

/// A user as a search on a compose form of the own platform [ownPlatform]
/// finds them: [MessageSearchUser.otherSchool] says whether [ssId] is
/// another platform, as the library sets it (yvanvds/dartschool#246), and
/// is `null` without [ownPlatform], when the library cannot tell.
UserRecipient _user(
  String name,
  int id, {
  int userLt = 0,
  String? className,
  String? coaccountName,
  int ssId = 4069,
  int? ownPlatform = 4069,
  String schoolName = 'Sint-Jozefscollege',
  String? platformName,
}) => UserRecipient(
  MessageSearchUser(
    userId: id,
    displayName: name,
    ssId: ssId,
    otherSchool: ownPlatform == null ? null : ssId != ownPlatform,
    userLt: userLt,
    className: className,
    coaccountName: coaccountName,
    schoolName: schoolName,
    platformName: platformName,
  ),
);

/// A person of another school of the school group, as a search with the
/// people of other schools finds them: on that school's platform, which
/// [MessageSearchUser.platformName] names (yvanvds/dartschool#238).
UserRecipient _elsewhere(
  String name,
  int id, {
  int userLt = 0,
  String? className,
  String? coaccountName,
  int? ownPlatform = 4069,
}) => _user(
  name,
  id,
  userLt: userLt,
  className: className,
  coaccountName: coaccountName,
  ownPlatform: ownPlatform,
  ssId: 5810,
  schoolName: 'Sint-Lodewijkscollege',
  platformName: 'Sint-Lodewijkscollege',
);

GroupRecipient _group(String name, int id, {String? description}) =>
    GroupRecipient(
      MessageSearchGroup(
        groupId: id,
        displayName: name,
        ssId: 4069,
        description: description,
      ),
    );

void main() {
  group('a recipient is named', () {
    test('a user by name and user id, with the class after a "|"', () {
      final sven = _user(' Sven Lamber ', 146, className: 'Klas: 5GZ');
      expect(sven.name, 'Sven Lamber');
      expect(sven.reference, 'Sven Lamber (user 146)');
      expect(sven.listing, 'Sven Lamber (user 146) | Klas: 5GZ');
      expect(sven.label, 'Sven Lamber');
      expect(_user('An Claes', 7).listing, 'An Claes (user 7)');
    });

    test('a co-account with its number, and its name after the "|"', () {
      final parent = _user(
        'Sven Lamber',
        146,
        userLt: 1,
        className: 'Klas: 5GZ',
        coaccountName: 'Moeder',
      );
      expect(parent.reference, 'Sven Lamber (user 146, co-account 1)');
      expect(
        parent.listing,
        'Sven Lamber (user 146, co-account 1) | Klas: 5GZ, co-account: Moeder',
      );
    });

    test('a person of another school with the platform in the brackets, and '
        'the school first after the "|"', () {
      final ned = _elsewhere('Ned Flanders', 2231, className: 'Klas: 4A');
      expect(ned.platform, 5810);
      expect(ned.reference, 'Ned Flanders (user 2231, platform 5810)');
      expect(
        ned.listing,
        'Ned Flanders (user 2231, platform 5810) | '
        'school: Sint-Lodewijkscollege, Klas: 4A',
      );
      expect(ned.label, 'Ned Flanders');

      final parent = _elsewhere(
        'Ned Flanders',
        2231,
        userLt: 1,
        coaccountName: 'Vader',
      );
      expect(
        parent.listing,
        'Ned Flanders (user 2231, co-account 1, platform 5810) | '
        'school: Sint-Lodewijkscollege, co-account: Vader',
      );

      expect(_user('Sven Lamber', 146).platform, isNull, reason: 'own school');
    });

    test('a person of the own school without a platform, also when the search '
        'included the people of the other schools and so named the own '
        'school as their platform (#219)', () {
      final me = _user(
        'Jan Peeters',
        146,
        className: 'Leerkracht',
        platformName: 'Sint-Jozefscollege',
      );
      expect(me.platform, isNull);
      expect(me.reference, 'Jan Peeters (user 146)');
      expect(me.listing, 'Jan Peeters (user 146) | Leerkracht');
    });

    test("a person of another school with the platform, by the library's "
        'otherSchool, also without a platform name', () {
      final ned = _user(
        'Ned Flanders',
        2231,
        ssId: 5810,
        schoolName: 'Sint-Lodewijkscollege',
      );
      expect(ned.platform, 5810);
      expect(
        ned.listing,
        'Ned Flanders (user 2231, platform 5810) | '
        'school: Sint-Lodewijkscollege',
      );
    });

    test('when the library cannot tell the own school from another, a '
        'platform name marks another school, as with the option off', () {
      expect(
        _elsewhere('Ned Flanders', 2231, ownPlatform: null).platform,
        5810,
      );
      expect(_user('Sven Lamber', 146, ownPlatform: null).platform, isNull);
      expect(
        _user(
          'Sven Lamber',
          146,
          ownPlatform: null,
          platformName: 'Sint-Jozefscollege',
        ).reference,
        'Sven Lamber (user 146, platform 4069)',
      );
    });

    test('a group by name and group id, said to be a group', () {
      final group = _group('5GZ', 298, description: '5 Grieks-Ziekenzorg');
      expect(group.reference, '5GZ (group 298)');
      expect(group.listing, '5GZ (group 298) | group: 5 Grieks-Ziekenzorg');
      expect(group.label, '5GZ (group)');
      expect(_group('lkr5', 312).listing, 'lkr5 (group 312) | group');
    });
  });

  group('RecipientRequest.parse', () {
    test('reads a reference: the name, the kind and the id', () {
      final user = RecipientRequest.parse(' Sven Lamber (user 146) ');
      expect(user.text, 'Sven Lamber (user 146)');
      expect(user.name, 'Sven Lamber');
      expect((user.group, user.id, user.coaccount), (false, 146, 0));

      final parent = RecipientRequest.parse(
        'Sven Lamber (User 146, co-account 2)',
      );
      expect(parent.name, 'Sven Lamber');
      expect((parent.group, parent.id, parent.coaccount), (false, 146, 2));

      final group = RecipientRequest.parse('5GZ(group 298)');
      expect(group.name, '5GZ');
      expect((group.group, group.id), (true, 298));
      expect((user.platform, user.otherSchool), (null, false));
    });

    test('reads the platform of a person of another school', () {
      final ned = RecipientRequest.parse(
        'Ned Flanders (user 2231, platform 5810)',
      );
      expect(ned.name, 'Ned Flanders');
      expect((ned.id, ned.coaccount, ned.platform), (2231, 0, 5810));
      expect(ned.otherSchool, isTrue);

      final parent = RecipientRequest.parse(
        'Ned Flanders (user 2231, co-account 1, Platform 5810)',
      );
      expect((parent.id, parent.coaccount, parent.platform), (2231, 1, 5810));
    });

    test('reads anything else as a name', () {
      for (final text in [
        'Sven Lamber',
        'Jan Peeters (vervanger)',
        '(user 146)',
        'Sven (user)',
        'Sven (user 14a)',
      ]) {
        final request = RecipientRequest.parse(text);
        expect(request.name, text, reason: text);
        expect(request.id, isNull, reason: text);
      }
    });
  });

  group('matches', () {
    final sven = _user('Sven Lamber', 146, className: 'Klas: 5GZ');
    final otherSven = _user('Sven Lamber', 330, className: 'Klas: 6WE');
    final svenParent = _user('Sven Lamber', 146, userLt: 1);
    final svenGroup = _group('Sven Lamber', 146);
    final svenja = _user('Svenja Lamberts', 412);

    List<Recipient> matches(String text, List<Recipient> found) =>
        RecipientRequest.parse(text).matches(found);

    test('one: the only one with exactly that name, ignoring case and extra '
        'spaces', () {
      expect(matches('Sven Lamber', [sven, svenja]), [sven]);
      expect(matches('  sven   LAMBER ', [svenja, sven]), [sven]);
      expect(matches('Svenja Lamberts', [sven, svenja]), [svenja]);
    });

    test('none: no one has exactly that name, also when the search found '
        'names that contain it', () {
      expect(matches('Sven', [sven, svenja]), isEmpty);
      expect(matches('Sven Lambert', [sven, svenja]), isEmpty);
      expect(matches('Sven Lamber', []), isEmpty);
    });

    test('several: users with the same name, a user and a co-account, or a '
        'user and a group', () {
      expect(matches('Sven Lamber', [sven, otherSven]), [sven, otherSven]);
      expect(matches('Sven Lamber', [sven, svenParent]), [sven, svenParent]);
      expect(matches('Sven Lamber', [sven, svenGroup]), [sven, svenGroup]);
    });

    test('a reference picks one of them by its kind and id', () {
      final found = [sven, otherSven, svenParent, svenGroup];
      expect(matches('Sven Lamber (user 146)', found), [sven]);
      expect(matches('Sven Lamber (user 330)', found), [otherSven]);
      expect(matches('Sven Lamber (user 146, co-account 1)', found), [
        svenParent,
      ]);
      expect(matches('Sven Lamber (group 146)', found), [svenGroup]);
    });

    test('a reference names no one when its name or id does not fit', () {
      final found = [sven, otherSven, svenGroup];
      expect(matches('Sven Lamber (user 999)', found), isEmpty);
      expect(matches('Sven (user 146)', found), isEmpty);
      expect(matches('Svenja Lamberts (user 146)', [...found, svenja]), []);
      expect(matches('Sven Lamber (user 146, co-account 2)', found), isEmpty);
    });

    test('a reference with a platform names the person of that other school; '
        'one without names the own school', () {
      final ned = _elsewhere('Sven Lamber', 146);
      final found = [sven, ned, otherSven];
      expect(matches('Sven Lamber (user 146, platform 5810)', found), [ned]);
      expect(matches('Sven Lamber (user 146)', found), [sven]);
      expect(matches('Sven Lamber (user 146, platform 6120)', found), isEmpty);
      expect(matches('Sven Lamber (user 330, platform 5810)', found), isEmpty);
      expect(matches('Sven Lamber', found), [sven, ned, otherSven]);
    });

    test('a reference without a platform names a person of the own school '
        'whom a search with the other schools found with the own school as '
        'their platform name (#219)', () {
      final svenWithOthers = _user(
        'Sven Lamber',
        146,
        className: 'Klas: 5GZ',
        platformName: 'Sint-Jozefscollege',
      );
      final ned = _elsewhere('Sven Lamber', 146);
      final found = [svenWithOthers, ned];
      expect(matches('Sven Lamber (user 146)', found), [svenWithOthers]);
      expect(matches('Sven Lamber (user 146, platform 4069)', found), isEmpty);
      expect(matches('Sven Lamber (user 146, platform 5810)', found), [ned]);
    });

    test('a reference finds several only when the search found the same id '
        'twice, in another school the library cannot tell apart', () {
      final elsewhere = _user(
        'Sven Lamber',
        146,
        ssId: 5000,
        ownPlatform: null,
      );
      expect(matches('Sven Lamber (user 146)', [sven, elsewhere]), [
        sven,
        elsewhere,
      ]);
    });
  });

  test('withoutRepeats keeps the first of each recipient; sameRecipient '
      'compares kind and ids', () {
    final sven = _user('Sven Lamber', 146);
    final again = _user('sven lamber', 146);
    final parent = _user('Sven Lamber', 146, userLt: 1);
    final group = _group('Sven Lamber', 146);

    expect(withoutRepeats([sven, parent, again, group, sven]), [
      sven,
      parent,
      group,
    ]);
    expect(sameRecipient(sven, again), isTrue);
    expect(sameRecipient(sven, parent), isFalse);
    expect(sameRecipient(sven, group), isFalse);
  });
}
