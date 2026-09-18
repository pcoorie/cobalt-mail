import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imap_mail/models/enums.dart';
import 'package:imap_mail/models/mail_folder.dart';
import 'package:imap_mail/widgets/folder_tree_expander.dart';

void main() {
  final archive = MailFolder(
    id: 1,
    accountId: 1,
    name: 'Archive',
    path: 'Archive',
    type: MailFolderType.other,
  );

  testWidgets('folder list is hidden until "More folders" is tapped', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FolderTreeExpander(folders: [archive], onSelect: (_) {}),
      ),
    ));

    expect(find.text('Archive'), findsNothing);

    await tester.tap(find.text('More folders'));
    await tester.pumpAndSettle();

    expect(find.text('Archive'), findsOneWidget);
  });

  testWidgets('tapping a revealed folder calls onSelect with that folder', (tester) async {
    MailFolder? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FolderTreeExpander(folders: [archive], onSelect: (folder) => tapped = folder),
      ),
    ));

    await tester.tap(find.text('More folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));

    expect(tapped, archive);
  });
}
