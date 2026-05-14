/* global React, Icon */
function AIBrief({ brief, onDraft, onSchedule, onLog }) {
  if (!brief) {
    return (
      <div className="rb-brief" style={{ background: "var(--bg-elev-1)" }}>
        <div className="rb-brief-head">
          <span className="rb-brief-eyebrow">Re:Box brief</span>
          <span className="rb-brief-conf">no action found</span>
        </div>
        <div className="rb-brief-sum" style={{ color: "var(--fg-3)" }}>Nothing to summarize here — informational thread.</div>
      </div>
    );
  }
  return (
    <div className="rb-brief">
      <div className="rb-brief-head">
        <span className="rb-brief-eyebrow">◆ Re:Box brief · local</span>
        <span className="rb-brief-conf">confidence {Math.round(brief.confidence * 100)}%</span>
      </div>
      <div className="rb-brief-sum">{brief.summary}</div>
      <div className="rb-brief-fields">
        <div className="rb-brief-field"><span className="rb-brief-k">Request</span><span className="rb-brief-v">{brief.request}</span></div>
        <div className="rb-brief-field"><span className="rb-brief-k">Deadline</span><span className="rb-brief-v danger">{brief.deadline}</span></div>
        <div className="rb-brief-field"><span className="rb-brief-k">Risk</span><span className="rb-brief-v">{brief.risk}</span></div>
        <div className="rb-brief-field"><span className="rb-brief-k">Next step</span><span className="rb-brief-v">{brief.nextStep}</span></div>
      </div>
      <div className="rb-brief-ev">Evidence: {brief.evidence.join(" · ")}</div>
      <div className="rb-brief-cta">
        <button className="rb-btn rb-btn-primary" onClick={onDraft}><Icon name="sparkle" />Draft reply</button>
        <button className="rb-btn rb-btn-secondary" onClick={onSchedule}><Icon name="clock" />Snooze to Fri AM</button>
        <button className="rb-btn rb-btn-ghost" onClick={onLog}>Log to CRM</button>
      </div>
    </div>
  );
}
window.AIBrief = AIBrief;
