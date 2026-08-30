import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sync pulls only the signed-in user operations subcollection', () {
    final source = File(
      'lib/data/repositories/firebase_sync_transport.dart',
    ).readAsStringSync();

    expect(source, contains(".collection('quicksplitUsers')"));
    expect(source, contains(".collection('operations')"));
    expect(source, isNot(contains('collectionGroup(')));
    expect(source, isNot(contains('FieldPath.documentId')));
  });
}
