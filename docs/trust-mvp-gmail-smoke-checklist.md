# Trust MVP Gmail Smoke Checklist

Run this checklist against a real Gmail account before declaring the Gmail Trust
MVP release candidate ready. Use a non-production mailbox with representative
messages, labels, attachments, and HTML newsletters. Do not paste message body,
HTML, attachment bytes, access tokens, or refresh credentials into notes.

## Preconditions

- Build under test is identified by commit SHA and app version.
- Test Gmail account has at least one inbox thread, one sent thread, one
  archived thread, one starred thread, one unread thread, one trash candidate,
  one message with a normal attachment, one message with inline CID content, and
  one HTML message with remote images.
- Network can be toggled offline and restored.
- Test notes record only account id hash, thread id hash, timestamps, visible
  UI state, and error categories.

## Checklist

| Area | Manual step | Expected result | Evidence to record |
| --- | --- | --- | --- |
| Fresh sync | Connect the Gmail account from Settings and allow the initial sync to finish. | Inbox, labels, thread list, message previews, attachments, and unread/starred state appear without duplicate threads. | Commit SHA, account id hash, synced thread count, completion timestamp. |
| Search placeholder | Use the visible search field before the Trust MVP search tranche is enabled. | UI remains honest about search being unavailable or placeholder-only; no fake results are shown. | Visible state and any disabled/placeholder copy. |
| Send | Compose a new message to a controlled recipient and send it. | Gmail accepts the send; the app shows sent state only after provider success; Sent contains one local row. | Sent thread id hash and timestamp. |
| Reply | Reply to an existing thread. | Reply stays in the same Gmail thread and has correct reply ordering after refresh. | Original thread id hash, sent message id hash. |
| Archive | Archive an Inbox thread, then refresh. | Thread leaves Inbox and is available from All Mail or non-Inbox views according to current UI support. | Thread id hash and post-refresh folder state. |
| Star | Star and unstar a thread, refreshing after each action. | Starred state changes locally and remains correct after refresh. | Thread id hash and final starred state. |
| Read/unread | Mark a thread read, then unread, refreshing after each action. | Unread badge and thread state match Gmail after refresh. | Thread id hash and final unread state. |
| Trash | Move a thread to Trash, then undo or restore it. | Trash label is applied, Inbox is removed while trashed, and restore returns the expected mailbox state. | Thread id hash and final label/folder state. |
| Attachment open | Open or summarize a normal attachment. | Metadata is shown, bytes download only on request, cache path is local, and unsupported files show an honest unsupported state. | Attachment id hash, file type, user-visible result. |
| HTML remote image blocking | Open the HTML message with remote images. | Remote images are blocked by default and the UI exposes blocked remote content state without loading trackers. | Thread id hash and blocked-content state. |
| Offline open | Disable network and open an already-synced thread. | Cached thread content opens; actions that require Gmail fail visibly or stay disabled without silent success. | Thread id hash and visible offline behavior. |
| Auth expiry | Expire or remove the stored credential, then refresh or send. | App shows reconnect or reauthorize state; no misleading local success is committed before auth recovery. | Error category and reconnect entry point. |
| Rate limit | Simulate or trigger a provider rate limit using the test harness or controlled account. | User-visible error identifies rate limiting; optimistic state rolls back where applicable. | Error category, action name, rollback state. |

## Pass Criteria

- Every row above passes on the same release candidate build.
- Any failure has an owner, reproduction notes, and a decision to fix, disable,
  or explicitly defer before release.
- Privacy notes contain no body text, raw HTML, attachment bytes, tokens, or
  raw credential values.
