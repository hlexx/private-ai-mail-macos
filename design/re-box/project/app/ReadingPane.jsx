/* global React, Icon, AIBrief */
const { useState: useStateRP } = React;

function ReadingPane({ thread, onDraft, onSchedule, onLog }) {
  const tones = [
    { id: "concise", label: "Concise", len: "42w" },
    { id: "warm",    label: "Warm",    len: "61w" },
    { id: "direct",  label: "Direct",  len: "28w" }
  ];
  const draftBodies = {
    concise: "Hi Marta — yes, I'll send a clean draft by Friday EOD. I'll match the pricing we agreed and flag the two clauses we discussed for your legal team. Stand by.",
    warm:    "Hi Marta — thanks for the nudge. I'll have a draft over by Friday EOD; the pricing matches what we agreed, and I'll mark up the two clauses your team raised so legal can move fast next week. Anything else you'd like me to include?",
    direct:  "Marta — draft by Friday EOD. Pricing per proposal. Two clauses flagged for legal. Confirm if you want SLA terms attached too."
  };
  const [tone, setTone] = useStateRP("warm");
  const [draftText, setDraftText] = useStateRP(draftBodies.warm);
  React.useEffect(() => { setDraftText(draftBodies[tone]); }, [tone]);

  if (!thread) {
    return (
      <div className="rb-empty">
        <div className="ed">Re:</div>
        <div className="h">Select a thread</div>
        <div className="s">Re:Box will brief you the moment you open it.</div>
      </div>
    );
  }

  return (
    <section className="rb-read">
      <div className="rb-read-head">
        <div className="subj">{thread.subject}</div>
        <div className="meta">
          <span>{thread.from}</span><span>·</span>
          <span>to alex@studio.eu</span><span>·</span>
          <span>{thread.messages?.length || 0} messages</span>
          {thread.attachment && <><span>·</span><span>1 attachment</span></>}
        </div>
        <div className="rb-read-actions">
          <button className="rb-btn rb-btn-ghost"><Icon name="archive" />Archive</button>
          <button className="rb-btn rb-btn-ghost" onClick={onSchedule}><Icon name="clock" />Snooze</button>
          <button className="rb-btn rb-btn-ghost" onClick={onLog}><Icon name="send" />Send to ↗</button>
        </div>
      </div>
      <div className="rb-read-body">
        <div className="rb-thread-col">
          {(thread.messages || []).map((m, i) => (
            <div key={i} className="rb-msg">
              <div className="rb-msg-head">
                <div className="rb-msg-av" style={{ background: thread.fromColor, color: thread.fromTextColor || "#fff" }}>
                  {m.from.split(" ").map(x => x[0]).slice(0, 2).join("")}
                </div>
                <span className="rb-msg-name">{m.from}</span>
                <span className="rb-msg-time">{m.time}</span>
              </div>
              <div className="rb-msg-body">{m.body}</div>
            </div>
          ))}
          {thread.attachment && (
            <div className="rb-att">
              <div className="rb-att-thumb" />
              <div style={{ flex: 1 }}>
                <div className="rb-att-name">{thread.attachment.name}</div>
                <div className="rb-att-meta">{thread.attachment.pages} pages · {thread.attachment.size} · summarized locally</div>
              </div>
              <button className="rb-btn rb-btn-ghost"><Icon name="eye" />Preview</button>
              <button className="rb-btn rb-btn-secondary"><Icon name="sparkle" />Summarize</button>
            </div>
          )}

          {thread.brief && (
            <div className="rb-composer-inline">
              <div className="rb-composer-head">
                <span className="rb-composer-eyebrow">Draft reply · local</span>
                <div className="rb-tone-seg">
                  {tones.map(t => (
                    <button
                      key={t.id}
                      className={"rb-tone-btn" + (tone === t.id ? " on" : "")}
                      onClick={() => setTone(t.id)}
                    >
                      {t.label}
                      <span className="rb-tone-len">{t.len}</span>
                    </button>
                  ))}
                </div>
              </div>
              <textarea
                className="rb-composer-area"
                value={draftText}
                onChange={(e) => setDraftText(e.target.value)}
                rows={5}
              />
              <div className="rb-composer-foot">
                <div className="rb-composer-cites">
                  <Icon name="lock" size={11} /> 3 citations · {thread.brief.evidence.join(" · ")}
                </div>
                <div className="rb-composer-cta">
                  <button className="rb-btn rb-btn-ghost" onClick={() => setDraftText(draftBodies[tone])}><Icon name="sparkle" />Regenerate</button>
                  <button className="rb-btn rb-btn-secondary" onClick={onDraft}>Edit in full</button>
                  <button className="rb-btn rb-btn-primary"><Icon name="send" />Send</button>
                </div>
              </div>
            </div>
          )}
        </div>
        <aside className="rb-brief-rail">
          <AIBrief brief={thread.brief} onDraft={onDraft} onSchedule={onSchedule} onLog={onLog} />
        </aside>
      </div>
    </section>
  );
}
window.ReadingPane = ReadingPane;
