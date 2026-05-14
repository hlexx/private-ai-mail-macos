/* global React, Icon */
const { useState: useStateC } = React;
function Composer({ initial, onClose }) {
  const [body, setBody] = useStateC(initial || "Hi Marta — yes, I'll send a clean draft by Friday EOD. I'll match the pricing we agreed and flag the two clauses we discussed for your legal team.\n\nIf there's anything else you'd like me to include — SLA terms, payment schedule — let me know.\n\n— Alex");
  return (
    <div className="rb-composer">
      <div className="head">
        <span className="h">Re: Contract approval — Acme GmbH</span>
        <button className="rb-iconbtn" onClick={onClose}><Icon name="x" /></button>
      </div>
      <div className="body">
        <div className="row"><span className="k">to</span><span className="v">marta@acme.de</span></div>
        <div className="row"><span className="k">cc</span><span className="v" style={{ color: "var(--fg-3)" }}>add recipient…</span></div>
        <div className="row"><span className="k">subj</span><span className="v">Re: Contract approval — Acme GmbH</span></div>
        <textarea value={body} onChange={e => setBody(e.target.value)} />
      </div>
      <div className="foot">
        <span className="meta">◆ drafted locally · attached contract.pdf · tone: concise</span>
        <div style={{ display: "flex", gap: 6 }}>
          <button className="rb-btn rb-btn-ghost">Save draft</button>
          <button className="rb-btn rb-btn-secondary"><Icon name="sparkle" />Rewrite</button>
          <button className="rb-btn rb-btn-primary"><Icon name="arrowUp" />Send</button>
        </div>
      </div>
    </div>
  );
}
window.Composer = Composer;
