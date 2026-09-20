import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_user_app/components/initials_avatar.dart';

/// U-1 / U-2: the rider app must not ship invented people, invented photos
/// or pictures of a journey nobody took. These are source scans rather than
/// widget tests on purpose — the failure mode being guarded against is
/// someone reintroducing a placeholder in ANY screen, not a specific screen
/// regressing.
void main() {
  final libDir = Directory('lib');
  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  /// The file's code, with comment lines removed. Doc comments legitimately
  /// name what was taken out and why ("this used to show fake_profile.png"),
  /// and that history is worth keeping — what must never come back is a
  /// reference the app actually renders.
  String codeOf(File f) => f
      .readAsStringSync()
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('no external placeholder-image service is referenced anywhere', () {
    // i.pravatar.cc served a stock portrait of a stranger as "your driver".
    final offenders = <String>[];
    for (final pattern in [
      'i.pravatar.cc',
      'placehold.co',
      'via.placeholder.com',
      'randomuser.me',
      'loremflickr.com',
      'dummyimage.com',
    ]) {
      for (final f in dartFiles) {
        if (codeOf(f).contains(pattern)) offenders.add('${f.path}: $pattern');
      }
    }
    expect(offenders, isEmpty,
        reason: 'placeholder image services must never stand in for real data');
  });

  test('the fabricated profile/map bitmaps are gone from code and assets', () {
    for (final name in ['fake_profile.png', 'fake_map.png', 'fake_dp.png']) {
      expect(File('assets/$name').existsSync(), isFalse,
          reason: '$name is a fabricated asset');
      for (final f in dartFiles) {
        expect(codeOf(f).contains('assets/$name'), isFalse,
            reason: '${f.path} still references $name');
      }
      expect(
          File('pubspec.yaml')
              .readAsStringSync()
              .split('\n')
              .where((line) => !line.trimLeft().startsWith('#'))
              .join('\n')
              .contains(name),
          isFalse,
          reason: 'pubspec.yaml still declares $name');
    }
  });

  test('the invented rider identity is gone from the UI', () {
    // "Thelma Ibeh" and a "4.55 Rating" were shown to every rider as their
    // own profile, and as the driver on a fake in-progress ride.
    for (final f in dartFiles) {
      final src = codeOf(f);
      expect(src.contains('Thelma'), isFalse, reason: '${f.path}');
      expect(src.contains('4.55 Rating'), isFalse, reason: '${f.path}');
    }
  });

  testWidgets('InitialsAvatar shows real initials, and a neutral icon with no name',
      (tester) async {
    expect(InitialsAvatar.initialsOf('Ada Obi'), 'AO');
    expect(InitialsAvatar.initialsOf('  ada   nwosu  '), 'AN');
    expect(InitialsAvatar.initialsOf('Ada'), 'A');
    expect(InitialsAvatar.initialsOf('Ada Chidinma Obi'), 'AO');
    expect(InitialsAvatar.initialsOf(''), '');
    expect(InitialsAvatar.initialsOf(null), '');

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: InitialsAvatar(name: 'Ada Obi')),
    ));
    expect(find.text('AO'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsNothing);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: InitialsAvatar(name: null)),
    ));
    // No name loaded yet: a neutral icon, never someone else's face.
    expect(find.byIcon(Icons.person), findsOneWidget);
  });
}
