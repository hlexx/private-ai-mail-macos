# Trust MVP Attachment Baseline

This baseline records the current attachment behavior before expanding preview
or AI promises. It is intentionally conservative: a capability is marked
supported only when it is wired in the current app boundary and covered by local
tests.

| Capability | Gmail | Outlook | Evidence and trust boundary |
|---|---|---|---|
| Metadata | Supported for synced messages: id, message id, filename, MIME, size, and content id where Gmail provides it. Account id is added when persisted. | Partial: Graph mapping supports id, message id, account id, filename, MIME, size, and content id when attachment metadata is present in the Graph message payload. The current delta request does not explicitly expand attachments. | `GmailMapper.extractAttachments`, `GraphMapper.attachments`, `RecordMapping.makeAttachmentRecord`, `AttachmentRecord`. |
| Inline CID | Supported for inline image parts with `Content-ID` and inline body data. Thread rendering resolves CID references to local data URLs. | Metadata content id is normalized, but inline byte data is not mapped into `Attachment.inlineData`, so CID rendering is not fully wired for Outlook. | `GmailMapper.collectAttachments`, `ThreadStore.InlineAttachment`, `HTMLWebView.resolveCIDReferences`, `GraphMapper.normalizedContentId`. |
| Byte download | Supported through the Gmail API and wired into attachment summarization through `GmailAttachmentByteProvider`. | Provider client API exists through `GraphAPI.getAttachment`, but the app composition does not currently provide an Outlook `AttachmentByteProvider` to AttachmentRAG. | `GmailAPIClient.getAttachmentData`, `CompositionRoot.GmailAttachmentByteProvider`, `GraphAPIClient.getAttachment`. |
| Preview | Not supported yet. The ThreadFeature Preview button is disabled. | Not supported yet. The ThreadFeature Preview button is disabled. | `ThreadView.attachmentBlock` disables Preview and exposes help text that opening is unavailable. |
| Cache | Supported for bytes fetched by the attachment summary path. Bytes are stored under Application Support with account/message/attachment path components and SHA-256 metadata. | Not wired through the app summary path yet because Outlook byte provider wiring is missing. The same cache can support Outlook once provider-neutral byte fetch is connected. | `AttachmentByteStore`, `AttachmentBlobRecord`, `AttachmentSummaryOrchestrator.loadOrFetchBlob`. |
| Deletion | Partial. Database foreign keys cascade attachment metadata, extraction rows, chunks, AI artifacts, and blob records. File deletion is available by relative path, but account-level cleanup is not yet fully exercised here. | Same persistence boundary as Gmail once Outlook blobs are created; provider wiring is not yet active. | `AttachmentByteStore.delete`, `attachment_blob` migration, attachment data-plane foreign keys. |
| Search marker | Supported locally for metadata: attachment filename, MIME, and `has_attachment` indicators are indexed. Attachment bytes and extracted full text are not indexed. | Supported for persisted Outlook attachment metadata. Completeness depends on Graph sync receiving attachment metadata. | `LocalSearchIndexPersistence`, `MailIndex`, `MailIndexTests`, `LocalSearchIndexMigrationTests`. |
| PDF text extraction | Supported for text-bearing PDFs through PDFKit and available to the local summary path after byte fetch. Scanned-image PDFs without extractable text return unsupported. | Extraction code is provider-neutral, but Outlook is blocked by missing app-side byte provider wiring. | `AttachmentTextExtractor.extractPDF`, `AttachmentSummaryOrchestrator`. |
| DOCX | Unsupported. DOCX must not produce a successful summary until real extraction is implemented and tested. | Unsupported for the same provider-neutral extraction boundary. | `AttachmentTextExtractor` returns unsupported for unknown types; `AttachmentKitTests.textExtractorRejectsUnsupportedTypes`. |
| OCR | Unsupported. Image OCR and scanned PDF OCR are not implemented. | Unsupported for the same provider-neutral extraction boundary. | `AttachmentTextExtractor` has no OCR path; `AttachmentKitTests.textExtractorRejectsImageOCR`. |
| AI summary | Supported narrowly for fetched Gmail attachments with extractable local text, HTML, JSON, CSV, or text-bearing PDFs. Summaries include structured evidence and unsupported states. | Not wired end-to-end yet because Outlook attachment bytes are not connected to AttachmentRAG in app composition. | `AttachmentSummaryOrchestrator`, `AttachmentSummaryStore`, `AIAttachmentSummary`, `AttachmentRAGTests`, `ThreadFeatureTests`. |

## README and NOTES review

`README.md` and `NOTES.md` do not currently claim broad attachment preview,
DOCX extraction, OCR, or Outlook attachment summary support. No README/NOTES
wording change is required for this baseline.

## Follow-up boundaries

- Add provider-neutral Outlook attachment byte-provider wiring before claiming
  Outlook download, cache, preview, or summary support in the app.
- Keep Preview disabled until a safe local open or Quick Look path is implemented
  and tested.
- Keep DOCX, image OCR, and scanned PDF OCR as unsupported states until their
  extractors, user states, privacy-safe logs, and tests exist.
