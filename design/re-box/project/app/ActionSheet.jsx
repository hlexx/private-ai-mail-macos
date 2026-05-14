/* global React, Icon */
const { useState: useStateAS } = React;
function ActionSheet({ thread, onClose }) {
  const [picked, setPicked] = useStateAS("snooze");
  const actions = [
    { id: "reply",    label: "Draft reply",   color: "var(--citron-500)", glyph: "↩" },
    { id: "snooze",   label: "Snooze to Fri", color: "var(--cobalt-500)", glyph: "◷" },
    { id: "log",      label: "Log to CRM",    color: "var(--violet-500)", glyph: "⤴" },
    { id: "task",     label: "Make a task",   color: "var(--burnt-orange-500)", glyph: "◆" },
    { id: "archive",  label: "Archive",       color: "var(--graphite-500)", glyph: "▣" },
    { id: "unsub",    label: "Unsubscribe",   color: "var(--graphite-500)", glyph: "✕" },
    { id: "rule",     label: "Make a rule",   color: "var(--graphite-500)", glyph: "≡" },
    { id: "share",    label: "Share thread",  color: "var(--graphite-500)", glyph: "↗" }
  ];
  const previews = {
    reply: "I'll draft a reply matching your tone and ask for the contract attachment.",
    snooze: "Thread will resurface Friday at 9:00 AM, with the brief pre-loaded.",
    log: "I'll push the summary and two action items to HubSpot under Acme GmbH.",
    task: "I'll create 'Send contract draft to Marta' due Fri, linked to this thread.",
    archive: "Thread is archived. Re:Box keeps the summary searchable.",
    unsub: "Re:Box will unsubscribe and filter future mail from this sender.",
    rule: "Suggested rule: From: marta@acme.de → label 'Acme · Contracts'.",
    share: "Generate a one-time link to share the brief with your team."
  };
  return (
    <div className="rb-sheet-mask" onClick={onClose}>
      <div className="rb-sheet" onClick={e => e.stopPropagation()}>
        <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 12 }}>
          <div>
            <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, letterSpacing: ".14em", textTransform: "uppercase", color: "var(--fg-3)" }}>What should I do with this thread?</div>
            <div style={{ fontSize: 14, fontWeight: 500, marginTop: 4 }}>{thread?.subject || "Selected thread"}</div>
          </div>
          <button className="rb-iconbtn" onClick={onClose}><Icon name="x" /></button>
        </div>
        <div className="rb-sheet-grid">
          {actions.map(a => (
            <div key={a.id} className={"rb-act" + (picked === a.id ? " on" : "")} onClick={() => setPicked(a.id)}>
              <div className="ic" style={{ background: a.color }}>{a.glyph}</div>
              <div className="label">{a.label}</div>
            </div>
          ))}
        </div>
        <div className="rb-preview">
          <div className="head">
            <span className="eb ok">◆ Re:Box will</span>
            <span className="eb">undo in 5s</span>
          </div>
          <div className="body">{previews[picked]}</div>
          <div className="stays">on-device · 0 bytes uploaded</div>
        </div>
        <div className="rb-sheet-cta">
          <button className="rb-btn rb-btn-ghost" onClick={onClose}>Cancel</button>
          <button className="rb-btn rb-btn-primary" onClick={onClose}>Do it</button>
        </div>
      </div>
    </div>
  );
}
window.ActionSheet = ActionSheet;
