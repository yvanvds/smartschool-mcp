# Intradesk

[Back to the overview](../../README.md)

Intradesk, the school's shared folders, files and weblinks. For everyone,
without a switch. Tools that change something follow the
[shared rules](../../README.md#changes-and-approval).

| Tool | What it does | Changes Smartschool? |
| --- | --- | --- |
| [`search_intradesk`](#search_intradesk) | Finds folders, files and weblinks by name | No |
| [`list_intradesk_folder`](#list_intradesk_folder) | Lists what is in one folder | No |
| [`read_intradesk_file`](#read_intradesk_file) | Returns the text of a file, or an image | No |
| [`save_intradesk_file`](#save_intradesk_file) | Saves a file into the download folder | No, saves a file on this PC |
| [`create_intradesk_folder`](#create_intradesk_folder) | Adds a folder | Yes, asks approval |
| [`add_intradesk_weblink`](#add_intradesk_weblink) | Adds a weblink | Yes, asks approval |
| [`upload_intradesk_files`](#upload_intradesk_files) | Uploads files from this PC | Yes, asks approval |
| [`trash_intradesk_items`](#trash_intradesk_items) | Moves folders, files and weblinks to the trash | Yes, asks approval |

## Tools

### `search_intradesk`

Finds the folders, files and weblinks on Intradesk by their names (not what
is in the files), ignoring case and accents, optionally within one folder.
Every word must occur in the full path and at least one in the name itself,
so `formulier uitstap` finds `Leerkrachten / Formulieren / uitstap.docx`,
while `formulieren` finds the folder but not every file in it. Returns the
matches with their full path, id, size and date changed. It searches an
[index](../development.md#intradesk-index) of Intradesk's names, which takes a
few minutes to build on a large Intradesk; until then, the answer says to
search again.

### `list_intradesk_folder`

Lists what is in one Intradesk folder, or at the top of Intradesk, live from
Smartschool: folders, files and weblinks, with their ids.

### `read_intradesk_file`

Opens one Intradesk file and returns its text, or an image, so Claude can
check what is in it, quote from it or summarise it: Word, Excel, PowerPoint,
PDF, text files, web pages and images, up to 25 MB. A scan, an old Office
file or another format cannot be read: `save_intradesk_file` saves it
instead. See [Reading Intradesk files](../development.md#reading-intradesk-files)
for what is read and the limits.

### `save_intradesk_file`

Saves one Intradesk file into your
[download folder](../development.md#saving-files) and returns its full path,
name and size: for a file `read_intradesk_file` cannot read, or when you want
the file itself.

### `create_intradesk_folder`

Adds a folder to an Intradesk folder (not to the top of Intradesk), in one of
Intradesk's eleven colours, yellow by default, or a confidential folder.
Refuses a name the folder holds already. Asks for approval; Claude shows you
the folder's path and what goes there first.

### `add_intradesk_weblink`

Adds a weblink, with its name, address and icon, to an Intradesk folder, as
`create_intradesk_folder` adds a folder. The address is sent as Intradesk's
web client sends it (with `http://` in front when it has no scheme), and the
answer says so. Asks for approval.

### `upload_intradesk_files`

Uploads 1 to 10 files from this PC, of at most 200 MB each, into an
Intradesk folder, each under its own name. Asks for approval; Claude shows
you every file with its name and size, and the folder's path, first.

### `trash_intradesk_items`

Moves 1 to 20 folders, files and weblinks to Intradesk's trash. A move, not a
deletion: Intradesk keeps its trash for 30 days, and you restore an item from
it in Intradesk itself. A folder goes with everything in it. Asks for
approval; Claude shows you each item by name and path first. It stops at the
first item that fails, and says what was moved and what was not.

## How it works

### How `search_intradesk` works

`folder_id` keeps the search within one folder. It searches the Intradesk
index (see [Intradesk index](../development.md#intradesk-index)).

### How `list_intradesk_folder` works

Without `folder_id`, the top level of Intradesk.

### How `read_intradesk_file` works

The id comes from `search_intradesk` or `list_intradesk_folder`. See
[Reading Intradesk files](../development.md#reading-intradesk-files).

### How `save_intradesk_file` works

For a file `read_intradesk_file` cannot read (a scan, an old Office file, any
other format) or when the user wants the file itself (see
[Saving files](../development.md#saving-files)).

### How `create_intradesk_folder` works

It adds a folder (`name`, an optional `color` of Intradesk's eleven, yellow
by default) to an Intradesk folder (`folder_id`; the top of Intradesk is not
offered), with the library's `createFolder` (dartschool#128). With
`confidential`, a confidential folder, the only kind Intradesk adds inside a
confidential folder. The three tools that add to Intradesk are marked
destructive, so Claude Desktop asks for approval every time, and Claude is
told to show the user what goes where (the folder's path, from
`search_intradesk`) and wait for the user's confirmation first. Before
sending, each reads the folder: its path, with the library's `getFolderPath`
(its parents, then the listing of the top and of each folder above it,
dartschool#132), and its listing, and refuses a name the folder holds
already (any kind, ignoring case and spaces: Intradesk would not refuse it,
but rename the new item to `name (1)`). The library reads the folder's entry
again right before it sends a create (its parents and the listing of the
folder above, dartschool#138) and refuses, with nothing sent, a folder the
account may not add to (`canAdd`) and a folder of the wrong kind for its
parent (only a confidential folder inside a confidential one); the tool says
so in its own words, by the library's reason, with the folder's path. None
of this needs the Intradesk index. The library sends a create once, never
again after logging in again; a create Intradesk does not confirm is
reported as maybe made, with how to check it (`list_intradesk_folder`), and
Claude is told not to call the tool again for it. The result is the item as
Intradesk made it (its id, the name as stored, the folder's path); a name
Intradesk changed anyway is pointed out. What was made goes into the
Intradesk index at once, when one is loaded, so `search_intradesk` finds it
without walking (see [Intradesk index](../development.md#intradesk-index)).

### How `add_intradesk_weblink` works

It adds a weblink (`name`, `url`, an optional `icon`, `earth` by default)
with the library's `createWeblink`, as `create_intradesk_folder` adds a
folder. The address is sent as Intradesk's web client sends it (without
white space, with `http://` in front when it has no scheme; the library's
`normalizeWeblinkUrl`), and the result says so; an address the web client
refuses is refused before sending. A refusal by Intradesk (HTTP 400) is
reported with its reason, in its own words.

### How `upload_intradesk_files` works

It uploads the files (`paths`, absolute) with the library's `uploadFiles`,
as `create_intradesk_folder` adds a folder. The server reads any file the
user's Windows account can read; Claude is told to list the files with their
names and sizes and the folder with its path for the user's confirmation.
Each path must be absolute and name an existing file of at most 200 MB with
a name Smartschool takes, and no two files may have the same name (see
[Uploading files](../development.md#uploading-files)). A file Smartschool's
upload step refuses is reported in Smartschool's words, and then nothing was
added; a file Intradesk did not take is listed with its reason next to the
files it added.

### How `trash_intradesk_items` works

`items` holds 1 to 20 items, each `{"kind": "folder" | "file" | "weblink",
"id"}`, with the ids `list_intradesk_folder` and `search_intradesk` show,
also a weblink's. They are moved with the library's `trashFolder`,
`trashFile` and `trashWeblink` (dartschool#128). The library neither reads
nor restores the trash, and never deletes for good. The tool is marked
destructive, so Claude Desktop asks for approval every time, and Claude is
told to show the user each item by name and path, say that a folder goes
with everything in it and how long the trash keeps it, and wait for the
user's confirmation. It is marked idempotent: Intradesk answers the move of
an item in the trash already with `204`, as the first time (so the result
cannot tell the two apart).

Before sending, it refuses an id that is not an Intradesk id, an id passed
with two kinds, and an id the Intradesk index knows as another kind. The
items are moved one at a time, in order, each in a session call of its own
(the library sends a move again after logging in again, which is harmless);
at the first failure it stops, and the result lists what was moved, the item
that failed and what was not tried. An id Intradesk has no item of that kind
for (an unknown id, the id of an item of another kind, also one in the
trash, or of an item that does not exist any more) is reported as no such
item, not moved: Intradesk answers it with `404` and moves nothing, which the
library throws as `SmartschoolIntradeskItemNotFoundError` (dartschool#133,
#124). Any other refusal (HTTP 400 to 499) is reported as not moved, with
Intradesk's reasons; any other failure as maybe moved, with the folder to
list to check it, as for the writes that add to Intradesk (see
[`create_intradesk_folder`](#how-create_intradesk_folder-works)). Items are named by their path
when the index knows them, and the result says what the index had in a
folder that went along. What was moved leaves the index at once (see
[Intradesk index](../development.md#intradesk-index)).

### Helpers and tests

Intradesk helpers live in `lib/src/intradesk/`: `withIntradesk`, the id
argument (`intradeskIdArgument`) and listing-to-items conversion
(`intradeskItems`) in `intradesk_access.dart`; `IntradeskItem` (kind, id,
name with extension, path, size, date changed, `extension`, `mimeType`) and
`IntradeskIndex` (lookup by id, with `findItem` for a weblink too, the items
inside a folder) in `intradesk_index.dart`; the tree walk
(`buildIntradeskIndex`) in `intradesk_walk.dart`; the index cache
(`IntradeskIndexCache`, with `patch` for what a write added or removed) in
`intradesk_cache.dart`; name matching in `intradesk_search.dart` and output
lines in `intradesk_format.dart`. In `intradesk_writes.dart`, for the tools
that add to Intradesk: the `folder_id` and `name` arguments
(`intradeskFolderArgument`, `intradeskNameArgument`), the folder read before
a write (`readIntradeskParent`, an `IntradeskParent` with its path and
listing, which refuses a taken name), `withIntradeskWrite` (the library's
refusals as `ToolError`s that say nothing was added, among them its refusal
of a folder without `canAdd` or of the wrong kind, worded by its reason),
the result of a write Intradesk did not confirm
(`intradeskWriteNotConfirmed`) and the index patch after a write
(`addToIntradeskIndex`); a header note says why the session's repeat of a
write cannot add twice. `trash_intradesk_items` reads nothing before its
moves but the index, and keeps its helpers to itself.

The tests run against a fake Intradesk (`test/support/fake_intradesk.dart`)
that carries out the creates, the upload and the moves to the trash of
dartschool#128 as the live Intradesk did (renaming a taken name, the bare
`500`s, the `400`s with `violations`, a `204` for an item in the trash
already, and a bare `404` for the move of an id it has no item of that kind
for, as captured in dartschool#133), behind the fake upload step
(`test/support/fake_uploads.dart`) that the attachments of lesfiches and
messages share.
