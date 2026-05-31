# Plan: Trust MVP 06 - Attachment Baseline

## Summary

Make attachments trustworthy before expanding AI promises. Trust MVP attachment
support means provider metadata, local download/cache, safe preview, failure
states, cache deletion, and search markers work for Gmail and Outlook. AI
summaries remain optional and must not be used to claim unsupported DOCX/OCR or
workflow automation.

## Impact Checklist

- Business flow: users can see, download, preview, and find attachments without
  losing trust in mail content.
- Domain boundaries: providers fetch bytes; `AttachmentKit` stores/extracts;
  `ThreadFeature` renders states; `MailIndex` indexes metadata.
- API / contracts: add or harden attachment byte fetch, cache, preview state,
  and unsupported reason contracts.
- Schema / data model: use existing attachment metadata/blob/extraction tables
  additively; avoid overloading provider metadata rows with large bytes.
- Auth / permissions: no new scopes beyond provider read attachment access.
- Cache / queue / async workflow: attachment downloads are explicit or
  prioritized by thread open; no unbounded background downloads.
- Observability: privacy-safe logs for metadata, download, preview failure, and
  cache deletion; no bytes or extracted text in logs.
- Migration: none expected unless missing cache metadata requires additive
  fields.
- Rollback: disable preview/download UI entry if unsafe; leave metadata visible.
- Debt impact: retires attachment overclaim and hidden unsupported states.
- ADR required: no new ADR if ADR 0002 and ADR 0005 already cover attachments;
  update them only if lifecycle changes.

## Validation Commands

- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git status --short --branch`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && git diff --check`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Attachments/AttachmentKit && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Attachments/AttachmentRAG && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailProviders && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/ThreadFeature && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailIndex && swift test`
- `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos && ! /usr/bin/grep -R -n -E '(Logger.*(attachment|body|html|payload)|print\\(.*(attachment|body|html|payload)|Bearer |refresh_token|client_secret)' Apps Packages --include='*.swift' --exclude-dir=.build --exclude='*Tests.swift'`

### Task 1: Audit attachment promises and current behavior

- [x] Create `docs/trust-mvp-attachment-baseline.md` with a table for Gmail and
      Outlook: metadata, inline CID, byte download, preview, cache, deletion,
      search marker, PDF text extraction, DOCX, OCR, and AI summary.
- [x] Mark DOCX and OCR as unsupported unless implemented and tested.
- [x] Ensure README/NOTES do not claim attachment features that are not wired in
      code.

### Task 2: Harden attachment metadata and byte fetch

- [x] Ensure provider attachment metadata includes id, message id, account id,
      filename, MIME, size, content id, inline/disposition if available, and
      provider-specific byte fetch handle.
- [x] Add provider tests for Gmail attachment fetch and Graph attachment fetch
      if Graph exists from tranche 03.
- [x] Ensure missing attachment id, auth failure, not found, rate limit, and
      provider errors produce user-actionable failures.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailProviders && swift test`.

### Task 3: Harden local attachment byte cache

- [x] Ensure `AttachmentByteStore` stores bytes by account/message/attachment
      without collisions and can load/delete them deterministically.
- [x] Exclude cache paths from backup where applicable.
- [x] Add tests for store/load/delete, path traversal resistance, duplicate
      store, SHA-256 mismatch, and account deletion cleanup.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Attachments/AttachmentKit && swift test`.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Core/Persistence && swift test`.

### Task 4: Add safe preview states

- [x] Add ThreadFeature attachment UI states: metadata only, downloading,
      cached, preview available, unsupported preview, failed, and deleted.
- [x] Use Quick Look or existing safe preview mechanisms for cached local files
      where available.
- [x] Do not enable "Ask about attachment" unless the AI summary handler and
      evidence are real.
- [x] Add tests for each UI state and no-attachment state.
- [x] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Features/ThreadFeature && swift test`.

### Task 5: Connect attachment metadata to search

- [ ] Ensure `MailIndex` indexes attachment filename, MIME, size bucket, and has
      attachment flags after tranche 04 search exists.
- [ ] Add tests for `has:attachment`, filename query, MIME filter, and thread
      result attachment indicator.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Mail/MailIndex && swift test`.

### Task 6: Keep AI attachment summaries honest

- [ ] Verify existing PDF/text attachment summary paths expose evidence and
      unsupported states.
- [ ] Ensure DOCX, image OCR, and scanned PDFs show unsupported/incomplete
      states if not implemented.
- [ ] Add tests that unsupported attachment types do not produce empty success
      summaries.
- [ ] Run `cd /Users/alexeykhaynovsky/Documents/Projects/Re_Box/private-ai-mail-macos/Packages/Attachments/AttachmentRAG && swift test`.
- [ ] Run all validation commands listed above and fix failures.

## Rollback / Recovery

If preview or download is unsafe, keep metadata visible and disable download or
preview actions. Never hide a failed attachment behind an AI summary.
