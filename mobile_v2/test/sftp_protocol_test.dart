// Unit tests for the pure SFTP protocol logic
// (frame codec, entry parsing/sorting, path helpers, transfer URIs).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:nexterm_v2/api/nexterm_api.dart';
import 'package:nexterm_v2/screens/remote/sftp_protocol.dart';

void main() {
  test('encode/decode round-trip preserves op and payload', () {
    final bytes =
        encodeSftpMessage(SftpOp.listFiles, {'path': '/home/user'});
    expect(bytes[0], SftpOp.listFiles);
    final decoded = decodeSftpMessage(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.op, SftpOp.listFiles);
    expect(decoded.payload['path'], '/home/user');
  });

  test('single-byte ack decodes with empty payload', () {
    final decoded =
        decodeSftpMessage(Uint8List.fromList([SftpOp.createFolder]));
    expect(decoded, isNotNull);
    expect(decoded!.op, SftpOp.createFolder);
    expect(decoded.payload, isEmpty);
  });

  test('error frame exposes its message', () {
    final bytes = encodeSftpMessage(
        SftpOp.error, {'message': 'Permission denied'});
    final decoded = decodeSftpMessage(bytes);
    expect(decoded, isNotNull);
    expect(sftpErrorMessage(decoded!), 'Permission denied');
  });

  test('error frame falls back for empty payloads', () {
    final decoded =
        decodeSftpMessage(Uint8List.fromList([SftpOp.error]));
    expect(decoded, isNotNull);
    expect(sftpErrorMessage(decoded!), 'Operation failed.');
  });

  test('garbage input decodes to null', () {
    expect(decodeSftpMessage(null), isNull);
    expect(decodeSftpMessage(42), isNull);
    expect(decodeSftpMessage(Uint8List(0)), isNull);
  });

  test('path helpers handle root and nesting', () {
    expect(sftpJoin('/', 'a'), '/a');
    expect(sftpJoin('/a', 'b'), '/a/b');
    expect(sftpParent('/a/b'), '/a');
    expect(sftpParent('/a'), '/');
    expect(sftpParent('/'), '/');
    expect(sftpBasename('/a/b.txt'), 'b.txt');
    expect(sftpBasename('/'), '');
    expect(sftpSegments('/a/b/'), ['a', 'b']);
    expect(sftpSegments('/'), isEmpty);
    expect(sftpFromSegments(['a', 'b']), '/a/b');
    expect(sftpFromSegments([]), '/');
  });

  test('sftpIsWithin keeps navigation inside the root', () {
    expect(sftpIsWithin('/a/b', '/a'), isTrue);
    expect(sftpIsWithin('/a', '/a'), isTrue);
    expect(sftpIsWithin('/other', '/a'), isFalse);
    expect(sftpIsWithin('/anything', '/'), isTrue);
  });

  test('listing parses entries and sorts folders first', () {
    final entries = parseSftpListing({
      'files': [
        {'name': 'b.txt', 'type': 'file', 'size': 10},
        {'name': 'docs', 'type': 'folder'},
        {'name': 'a.txt', 'type': 'file', 'size': 2048},
      ],
    });
    expect(entries, hasLength(3));
    final sorted = sortSftpEntries(entries);
    expect(sorted.map((e) => e.name).toList(),
        ['docs', 'a.txt', 'b.txt']);
    expect(sorted[1].formattedSize, '2.0 KB');
  });

  test('listing ignores malformed payloads', () {
    expect(parseSftpListing({}), isEmpty);
    expect(parseSftpListing({'files': 'nope'}), isEmpty);
  });

  test('transfer URIs carry the query token', () {
    final upload =
        sftpUploadUri('https://host/api', 'tok', 'sid', '/a/b.txt');
    expect(upload.path, '/api/entries/sftp/upload');
    expect(upload.queryParameters['sessionToken'], 'tok');
    expect(upload.queryParameters['sessionId'], 'sid');
    expect(upload.queryParameters['path'], '/a/b.txt');

    final download =
        sftpDownloadUri('https://host/api', 'tok', 'sid', '/a/b.txt');
    expect(download.path, '/api/entries/sftp');
    expect(download.queryParameters['sessionToken'], 'tok');
    expect(download.queryParameters['sessionId'], 'sid');
    expect(download.queryParameters['path'], '/a/b.txt');
  });

  test('wsUrl builds the sftp endpoint', () {
    expect(
      NextermApi.wsUrl('https://host/api', '/ws/sftp',
          {'sessionToken': 't', 'sessionId': 's'}),
      'wss://host/api/ws/sftp?sessionToken=t&sessionId=s',
    );
  });
}
