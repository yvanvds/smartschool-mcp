# Messages

[Back to the overview](../../README.md)

Smartschool's messages: the inbox, the sent box, the archive and the folders
you made in Smartschool ("Map toevoegen"). For everyone, without a switch.
Tools that change something follow the
[shared rules](../../README.md#changes-and-approval).

| Tool | What it does | Changes Smartschool? |
| --- | --- | --- |
| [`list_messages`](#list_messages) | Lists the messages of a box or folder, with filters | No |
| [`read_message`](#read_message) | Reads one message with its recipients and attachments | No |
| [`save_message_attachment`](#save_message_attachment) | Saves an attachment into the download folder | No, saves a file on this PC |
| [`search_messages`](#search_messages) | Searches the text, subject and sender of messages | No |
| [`archive_messages`](#archive_messages) | Moves inbox messages to the archive | Yes |
| [`mark_messages`](#mark_messages) | Marks messages read or unread | Yes |
| [`flag_messages`](#flag_messages) | Sets or clears the colour flag of messages | Yes |
| [`trash_messages`](#trash_messages) | Moves messages to Smartschool's trash | Yes, asks approval |
| [`reply_to_message`](#reply_to_message) | Sends a reply, optionally with files | Yes, asks approval |
| [`search_recipients`](#search_recipients) | Finds the users and groups a new message can go to | No |
| [`send_message`](#send_message) | Sends a new message, optionally with files | Yes, asks approval |

## Tools

### `list_messages`

Lists the messages of the inbox, the sent box, the archive or a folder you
made, newest first, filtered by words in the subject or sender, by unread,
and by a date range. Claude reaches older messages by moving the end of the
range back. When nothing matches in a box, the answer names the folders you
made in it, which were not listed.

### `read_message`

Reads one message: its recipients, its attachments (numbered, with name and
size) and its text, as plain text. It does not mark the message as read.

### `save_message_attachment`

Saves one attachment of a message, by its number in `read_message` or its
file name, into your [download folder](../development.md#saving-files), and
returns its full path, name and size.

### `search_messages`

Searches the text, subject and sender of your messages for words, ignoring
case and accents, optionally within a date range: by default the inbox, its
folders and the archive, and the sent box when you name it. Returns the
matching messages newest first, with their box or folder and a snippet
around the words. Each message text is downloaded once and kept on this PC
(the [message text cache](../development.md#message-text-cache)), so the
first search of a large box takes a few searches and later ones are quick;
the answer says when messages were left unsearched.

### `archive_messages`

Moves up to 100 inbox messages to the archive, and says per message whether
it was archived, was already in the archive, or why not. A message in a
folder you made is not archived: the answer says which folder it is in.
Claude proposes messages when you ask for advice, and archives them when you
ask it to.

### `mark_messages`

Marks up to 100 messages of the inbox, the archive or a folder in the inbox
as read or unread, and says per message what Smartschool confirmed. Reading
a message never marks it: that is your choice. Claude proposes messages when
you ask for advice, and marks them when you ask it to.

### `flag_messages`

Sets the colour flag (green, yellow, red or blue) of up to 100 messages of
any box or folder, or clears it, and says per message what Smartschool
confirmed.

### `trash_messages`

Moves up to 100 messages of any box or folder to Smartschool's trash, and
says per message whether it was moved. A move, not a deletion: you restore a
message from the trash in Smartschool until the trash is emptied. Asks for
approval; Claude shows you the list first.

### `reply_to_message`

Sends a reply to the sender of a message, or to everyone on it, with `Re:`
before the subject, optionally with 1 to 10 files from this PC. Smartschool
links the reply to the original. Asks for approval; Claude shows you the
text, the recipients and every file with its size first. A reply is
[never sent twice](../../README.md#changes-and-approval).

### `search_recipients`

Finds the users and groups (such as a class) a new message can go to, by
name, with what tells namesakes apart: a class, a co-account, a group's
description.

### `send_message`

Sends a new message to users and groups, in To, CC and BCC, optionally with
1 to 10 files from this PC. Each recipient must name exactly one user or
group: a name that no one has, or that several have, stops the send before
anything is sent, with who the search finds, for you to choose. The tool
never picks one. Asks for approval; Claude looks up every recipient and
shows you the recipients, the subject, the text and every file with its size
first. A message is [never sent twice](../../README.md#changes-and-approval).

## How it works

How the tools find a message in a folder the user made is in
[Message folders](../development.md#message-folders).

### How `list_messages` works

`folder` takes a folder the user made in Smartschool (see
[Message folders](../development.md#message-folders)). Smartschool lists a
box 50 messages at a time; the tool asks for the next 50 only while they can
change the result (more messages to show, or not yet past `since`), and
Claude reaches older messages with `until`.

### How `read_message` works

A message in a folder is read with the box the folder is in: Smartschool
finds it by its id.

### How `save_message_attachment` works

See [Saving files](../development.md#saving-files) for the download folder,
the names, the size limit and the clean-up.

### How `search_messages` works

It searches the inbox and archive (or the boxes named), and the folders the
user made in the inbox (in the sent box, when `sent` is named). It downloads
each message text once (at most 100 per search, 4 at a time, newest first)
and keeps it in the [message text cache](../development.md#message-text-cache),
so later searches are quick; the result says when messages were left
unsearched. It lists the whole of each box and folder searched (with
`since`, only back to that date), so a search of a large box takes a few
searches the first time.

### How `archive_messages` works

Up to 100 inbox messages, by their ids from `list_messages`. It lists the
inbox (and the archive, for ids not in the inbox) until it has found every
id. An id in neither is looked up in the folders the user made in the inbox,
to say which folder the message is in; it is not archived from there.
Whether Smartschool's archive request takes a message out of such a folder
has not been tried (#134), and the user may keep it there on purpose.

### How `mark_messages` works

Ids from `list_messages`; the sent box has no read state for the user.
`read_message` leaves the read state alone. It lists the box until it has
found every id, changes the messages one at a time and reports per id the
new state Smartschool confirmed, that the message is not in the box, or that
Smartschool did not confirm the change.

### How `flag_messages` works

The flag is green, yellow, red or blue, or `none` to clear it. One message
at a time, reporting per id, like `mark_messages`.

### How `trash_messages` works

One message at a time. The server cannot take a message out of the trash
again, so the tool is marked destructive (Claude Desktop asks for approval
every time), and Claude is told to show the list and wait for the user's
confirmation first. Each message is moved with the library's
`moveToTrashFrom`, which names its box (the archive or a folder with its box
id), never with `moveToTrash`, whose `quick delete` names no box and deletes
a copy in the trash for good. Smartschool answers a move the same whether it
moved the message or not, so each message is read back from its box
afterwards. The result says per id: moved, not in the box, or still in the
box after the move. A message the user sent to themselves has the same id in
the inbox and the sent box: only the copy in the box named is moved.

### How `reply_to_message` works

The text is plain text or simple Markdown. `reply_all` sends it to everyone
on the message, with one `Re:` before the subject. A reply to a sent message
goes to its recipients, except those in BCC. `attachments` takes 1 to 10
files from this PC, as `send_message` takes them. The tool is marked
destructive, so Claude Desktop asks for approval every time, and Claude is
told to show the text, the recipients and every attachment with its name
and size, and wait for the user's confirmation first. It never sends a reply
twice by itself: when Smartschool does not confirm a send, it says the reply
may have been sent and to check the sent box. The reply is sent with the
message's own reply form, so Smartschool links it to the original.

### How `search_recipients` works

It searches with the search of Smartschool's compose form (the library's
`searchRecipientsForCompose`). Each user or group is listed as
`send_message` takes it, its name with its kind and id in brackets, like
`Sven Lamber (user 146)` or `5GZ (group 298)`, then what tells namesakes
apart. It changes nothing in Smartschool: the compose form it searches on is
left unused.

### How `send_message` works

The text is plain text or simple Markdown, as for `reply_to_message`.
Claude is told to look every recipient up with `search_recipients`, show the
user the recipients, subject and text, and wait for the user's confirmation
first; the tool is marked destructive, so Claude Desktop asks for approval
every time. Each recipient is a name or a reference as `search_recipients`
lists it; the tool looks each one up again and sends only when each names
exactly one user or group (the name exactly, ignoring case and extra spaces,
and the kind and id of a reference). A name that no one has exactly, or that
several users or groups have (also a user and a group), stops the send
before anything is sent, with who the search finds, for the user to choose:
the tool never picks one. It sends once, as `reply_to_message` does
(`submitOnce`).

`attachments` takes 1 to 10 full paths of files on this PC (an empty list is
none), checked before anything is sent, as `upload_intradesk_files` checks
them (see [Uploading files](../development.md#uploading-files)), and
uploaded by the library (`SendMessageParams.attachmentPaths`) into the
compose form's own upload directory before the submit. Claude is told to
show every file with its name and size along with the recipients, subject
and text; the result names them, and `read_message` lists them on the sent
message. A file Smartschool's upload step refuses stops the send before the
submit, with Smartschool's reason: nothing was sent.

### Helpers and tests

Message helpers for later tools live in `lib/src/messages/`: `MessageBox`
(inbox / sent / archive and the folders the user made, their headers and one
message), the `box` and `folder` arguments (`BoxArgument`, `folderSchema`)
and `withMessages` in `message_box.dart`, the HTML-to-text converter
`htmlToText` in `html_to_text.dart`, the Markdown-to-HTML converter for
message text Claude writes (`markdownToHtml`, which escapes all HTML) in
`markdown_to_html.dart`, who a reply goes to (`loadReplyRecipients`) in
`reply_recipients.dart`, the recipients of a new message
(`searchRecipients`, `RecipientRequest`) in `recipient_search.dart`, the
filters and date-range arguments in `message_filter.dart`, the output lines
in `message_format.dart`, full-text matching and snippets (`SearchQuery`) in
`message_search.dart` and the message text cache (`MessageTextCache`) in
`message_cache.dart`.

The tools that change messages named by id share their `message_ids`
argument (`messageIdsSchema`, `messageIdsArgument`) and, for a change made
one message at a time, the per-id loop and result (`changeEach`,
`changesResult`) in `lib/src/tools/message_changes.dart`. A change that
takes a message out of its box (`trash_messages`) passes `changeEach` a
`started` map, so that a repeat of the call (after Smartschool refused the
session) does not report a message moved before as not in the box. The
tools that send a message (`reply_to_message`, `send_message`) share their
`attachments` argument (`messageAttachmentsSchema`,
`messageAttachmentsArgument`, `messageAttachmentsDescription`, through the
local-file helper), the submit that is never repeated (`submitOnce`, which
also turns a refused upload into a `ToolError` with `uploadToolError`) and
how its outcome is reported (`notConfirmedResult`, `sendSummary`) in
`lib/src/tools/message_sending.dart`. How a send is kept from being
repeated after a refused session is in [Login](../development.md#login).

Their tests run against a fake Messages module
(`test/support/fake_messages.dart`) whose compose forms each open their
`randomDir` in the fake upload step, bound to the session the form was
loaded in (an upload into it from another session fails the test), and
whose submit sends the files of that directory with the message. Its folder
tree (`requestmovelist`) holds the archive and the folders a test adds with
`addFolder` (in the inbox, the sent box or another folder), each listed,
read and changed as the archive is.
