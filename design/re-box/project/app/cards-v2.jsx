/* global React */
/* Re:Box ReadingPane v2 — 7 concept cards.
   Each card is a focused mini-mockup on the design canvas. */

// ── Inline icons (tiny set, sufficient for the cards) ──────────────────────
const Ic = ({ d, w = 14, h = 14, sw = 1.8 }) => (
  <svg width={w} height={h} viewBox="0 0 24 24" fill="none" stroke="currentColor"
       strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">{d}</svg>
);
const IcSend     = (p) => <Ic d={<><path d="M22 2L11 13"/><path d="M22 2l-7 20-4-9-9-4 20-7z"/></>} {...p} />;
const IcChev     = (p) => <Ic d={<polyline points="6 9 12 15 18 9"/>} {...p} />;
const IcChevR    = (p) => <Ic d={<polyline points="9 6 15 12 9 18"/>} {...p} />;
const IcArchive  = (p) => <Ic d={<><polyline points="21 8 21 21 3 21 3 8"/><rect x="1" y="3" width="22" height="5"/><line x1="10" y1="12" x2="14" y2="12"/></>} {...p} />;
const IcClock    = (p) => <Ic d={<><circle cx="12" cy="12" r="9"/><polyline points="12 7 12 12 15 14"/></>} {...p} />;
const IcMore     = (p) => <Ic d={<><circle cx="5" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="19" cy="12" r="1.4"/></>} {...p} sw={2.2} />;
const IcSparkle  = (p) => <Ic d={<><path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1"/></>} {...p} />;
const IcLock     = (p) => <Ic d={<><rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 1 1 8 0v4"/></>} {...p} />;
const IcCheck    = (p) => <Ic d={<polyline points="5 12 10 17 19 7"/>} {...p} sw={2.2} />;
const IcMail     = (p) => <Ic d={<><rect x="3" y="5" width="18" height="14" rx="2"/><polyline points="3 7 12 13 21 7"/></>} {...p} />;
const IcCal      = (p) => <Ic d={<><rect x="3" y="4" width="18" height="17" rx="2"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="16" y1="2" x2="16" y2="6"/></>} {...p} />;
const IcEye      = (p) => <Ic d={<><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></>} {...p} />;
const IcSun      = (p) => <Ic d={<><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></>} {...p} />;

// ── Card 1 — One primary action per thread ─────────────────────────────────
function Card1() {
  const [open, setOpen] = React.useState(false);
  return (
    <div className="rb2-pane" style={{ position: 'relative' }}>
      <div className="rb2-head">
        <div className="rb2-mono" style={{ fontSize: 10, color: 'var(--citron-500)', letterSpacing: '.14em' }}>
          THREAD · CONTRACT APPROVAL
        </div>
        <div className="subj">Contract approval — Acme GmbH</div>
        <div className="meta">
          <span>Marta Kowalski</span><span>·</span>
          <b>to alex@studio.eu</b><span>·</span>
          <span>3 messages</span><span>·</span>
          <span>1 attachment</span>
        </div>
      </div>
      <div className="rb2-actionrow">
        <div className="rb2-pri" onClick={() => setOpen(o => !o)}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
            <IcSend w={13} h={13} />
            <span className="lbl">Send draft to Marta</span>
            <span className="reason">· Friday EOD</span>
          </span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
            <span className="split" />
            <span className="chevron"><IcChev w={13} h={13} /></span>
          </span>
        </div>
        <button className="rb2-sec"><IcMore w={13} h={13} /></button>
      </div>

      <div className={"rb2-pri-menu" + (open ? " open" : "")} style={{ display: 'block' }}>
        <div className="it">
          <IcArchive w={13} h={13} /><span>Archive</span><span className="kbd">⌘E</span>
        </div>
        <div className="it">
          <IcClock w={13} h={13} /><span>Snooze · Friday</span><span className="kbd">⌘H</span>
        </div>
        <div className="it">
          <IcSend w={13} h={13} /><span>Send to HubSpot</span><span className="kbd">⌘L</span>
        </div>
        <div className="sep" />
        <div className="it">
          <IcSparkle w={13} h={13} style={{ color: 'var(--citron-500)' }} />
          <span>Ask AI to draft differently…</span>
        </div>
      </div>

      <div style={{ flex: 1, display: 'grid', gridTemplateColumns: '1fr 280px', minHeight: 0 }}>
        <div style={{ padding: '14px 24px', opacity: .6, fontSize: 12.5, color: 'var(--fg-2)', lineHeight: 1.55,
                      WebkitMaskImage: 'linear-gradient(180deg,#000 0%,transparent 80%)',
                      maskImage: 'linear-gradient(180deg,#000 0%,transparent 80%)' }}>
          <div style={{ marginBottom: 8 }}>
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 10.5, color: 'var(--fg-3)' }}>Marta Kowalski · Tue 11:42</span>
          </div>
          Quick nudge — Friday EOD would be ideal, otherwise we miss the legal window. Attaching the last revision of the contract for reference…
        </div>
        <aside className="rb2-rail-mini">
          <div className="eb">AI brief · highlighting choice</div>
          <div className="sum">Client approved pricing. Send contract draft <em style={{ fontStyle: 'normal', color: 'var(--citron-500)' }}>by Fri</em>.</div>
          <div style={{ display: 'grid', gap: 6, fontSize: 11.5, color: 'var(--fg-3)' }}>
            <div>Confidence · <span style={{ color: 'var(--fg-2)' }}>0.88</span></div>
            <div>Next step · <span style={{ color: 'var(--fg-1)' }}>draft reply</span></div>
          </div>
        </aside>
      </div>
    </div>
  );
}

// ── Card 2 — Living brief: every field is interactive ──────────────────────
function Card2() {
  const [showDates, setShowDates] = React.useState(true);
  return (
    <div className="rb2-brief-rail" style={{ position: 'relative' }}>
      <div className="rb2-brief-header">
        <div className="rb2-brief-eyebrow">AI brief · local</div>
        <div className="rb2-brief-conf">0.88</div>
      </div>
      <div className="rb2-brief-sum">
        Marta wants the contract draft by Friday EOD. Pricing already approved.
      </div>
      <div className="rb2-brief-fields">
        <div className="rb2-fld">
          <div className="k">Request</div>
          <div className="v">Send contract draft</div>
          <span className="rb2-fld-act"><IcChevR w={10} h={10} /></span>
        </div>

        <div className="rb2-fld" style={{ background: 'color-mix(in oklch, var(--citron-500) 10%, transparent)' }}>
          <div className="k">Deadline</div>
          <div className="v danger">
            <IcClock w={12} h={12} /> Fri · May 15
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--tone-coral-400)' }}>· in 52h</span>
          </div>
          <span className="rb2-fld-act" style={{ opacity: 1, transform: 'translateX(0)' }}>snooze ▸</span>
        </div>

        <div className="rb2-fld">
          <div className="k">Risk</div>
          <div className="v">Tight turnaround</div>
        </div>

        <div className="rb2-fld">
          <div className="k">Evidence</div>
          <div className="v">
            <span className="citelink">msg_1</span>
            <span style={{ color: 'var(--fg-3)' }}>·</span>
            <span className="citelink">msg_3</span>
            <span style={{ color: 'var(--fg-3)' }}>·</span>
            <span className="citelink">contract.pdf p.2</span>
          </div>
        </div>

        <div className="rb2-fld">
          <div className="k">Next step</div>
          <div className="v">
            Draft reply
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--citron-500)' }}>focus composer ↓</span>
          </div>
        </div>
      </div>

      {showDates && (
        <div className="rb2-datepop" style={{ left: 110, top: 188 }}>
          <div className="ttl">Snooze deadline</div>
          <div className="opts">
            <div className="opt"><span>Tomorrow morning</span><span className="d">Thu 09:00</span></div>
            <div className="opt on"><span>End of week</span><span className="d">Fri 17:00</span></div>
            <div className="opt"><span>Next Monday</span><span className="d">May 19</span></div>
            <div className="opt"><span style={{ color: 'var(--citron-500)' }}>Pick a date…</span></div>
          </div>
        </div>
      )}
    </div>
  );
}

// ── Card 3 — Progressive composer + selection rephrase ─────────────────────
function Card3() {
  return (
    <div style={{ padding: 22, display: 'grid', gap: 18, background: 'var(--bg-canvas)', height: '100%', boxSizing: 'border-box', overflow: 'hidden' }}>
      <div className="rb2-eyebrow">Default · text + Send only</div>
      <div className="rb2-composer">
        <div className="head">
          <span className="eb">Draft reply · local</span>
          <span className="more"><IcMore w={13} h={13} /></span>
        </div>
        <div className="ta">
          Hi Marta — thanks for the nudge. I'll have a draft over by Friday EOD; the pricing matches what we agreed, and I'll mark up the two clauses your team raised so legal can move fast next week.
        </div>
        <div className="foot">
          <span className="left"><IcLock w={11} h={11} style={{ verticalAlign: -1 }} /> 3 citations · local</span>
          <button className="send"><IcSend w={12} h={12} /> Send</button>
        </div>
      </div>

      <div className="rb2-eyebrow" style={{ marginTop: 4 }}>Selected text · hover-rephrase menu</div>
      <div className="rb2-composer">
        <div className="head">
          <span className="eb">Draft reply · local</span>
          <span className="more"><IcMore w={13} h={13} /></span>
        </div>
        <div className="ta" style={{ position: 'relative' }}>
          Hi Marta — thanks for the nudge.{' '}
          <span style={{ position: 'relative' }}>
            <span className="rb2-sel">I'll have a draft over by Friday EOD</span>
            <span className="rb2-rephrase">
              <button><IcSparkle w={11} h={11} className="sparkle" /> Rephrase</button>
              <span className="sep" />
              <button>shorter</button>
              <button>formalize</button>
              <button>warmer</button>
            </span>
          </span>
          {' '}; the pricing matches what we agreed.
        </div>
        <div className="foot">
          <span className="left"><IcLock w={11} h={11} style={{ verticalAlign: -1 }} /> 3 citations · local</span>
          <button className="send"><IcSend w={12} h={12} /> Send</button>
        </div>
      </div>

      <div className="rb2-eyebrow" style={{ marginTop: 4 }}>Expanded · "…" revealed CC / Subject / Attach</div>
      <div className="rb2-composer expanded">
        <div className="head">
          <span className="eb">Draft reply · local</span>
          <span className="more" style={{ background: 'var(--bg-elev-2)', color: 'var(--fg-1)' }}><IcMore w={13} h={13} /></span>
        </div>
        <div className="meta-row"><div className="k">To</div>
          <div className="v"><span className="chip">Marta Kowalski</span></div></div>
        <div className="meta-row"><div className="k">Cc</div>
          <div className="v" style={{ color: 'var(--fg-3)' }}>add people…</div></div>
        <div className="meta-row"><div className="k">Subj</div>
          <div className="v">Re: Contract approval — Acme GmbH</div></div>
        <div className="meta-row"><div className="k">Attach</div>
          <div className="v"><span className="chip">📄 contract_v3.pdf · 284 KB</span></div></div>
        <div className="ta" style={{ minHeight: 60 }}>
          Hi Marta — thanks for the nudge. Draft attached, pricing per proposal…
        </div>
        <div className="foot">
          <span className="left"><IcLock w={11} h={11} style={{ verticalAlign: -1 }} /> 3 citations · attaching contract_v3</span>
          <button className="send"><IcSend w={12} h={12} /> Send</button>
        </div>
      </div>
    </div>
  );
}

// ── Card 4 — AI summaries in thread list ───────────────────────────────────
function Card4() {
  return (
    <div className="rb2-pane">
      <div className="rb2-list-header">
        <div className="h">Inbox</div>
        <div className="meta">12 · 4 need reply</div>
      </div>
      <div className="rb2-list" style={{ flex: 1, overflow: 'hidden' }}>
        <div className="rb2-row active">
          <div className="av" style={{ background: 'linear-gradient(135deg,var(--cobalt-500),var(--violet-500))' }}>MK</div>
          <div className="body">
            <div className="top">
              <div className="from"><span className="udot"/>Marta Kowalski</div>
              <div className="time">11:42</div>
            </div>
            <div className="subj">Contract approval — Acme GmbH</div>
            <div className="ai-prev">
              <span className="diamond">◆</span>
              <span><em>Marta wants contract by Fri</em> — pricing already approved.</span>
            </div>
            <div className="chips">
              <span className="rb2-mini-chip due">Fri EOD</span>
              <span className="rb2-mini-chip att">📎 7p</span>
            </div>
          </div>
        </div>

        <div className="rb2-row">
          <div className="av" style={{ background: 'linear-gradient(135deg,#9a9c99,#56585a)' }}>JR</div>
          <div className="body">
            <div className="top">
              <div className="from"><span className="udot"/>Jonas R.</div>
              <div className="time">10:08</div>
            </div>
            <div className="subj">Re: SaaS renewal — Q3</div>
            <div className="ai-prev">
              <span className="diamond">◆</span>
              <span><em>Confirm seat count by Wed</em> — legal CC'd.</span>
            </div>
            <div className="chips">
              <span className="rb2-mini-chip reply">Wed</span>
            </div>
          </div>
        </div>

        <div className="rb2-row">
          <div className="av" style={{ background: 'linear-gradient(135deg,var(--citron-500),var(--citron-700))', color: 'var(--graphite-950)' }}>CV</div>
          <div className="body">
            <div className="top">
              <div className="from">Cveta Vlahova</div>
              <div className="time">Yest.</div>
            </div>
            <div className="subj">Lease addendum</div>
            <div className="ai-prev">
              <span className="diamond" style={{ color: 'var(--graphite-300)' }}>◆</span>
              <span style={{ color: 'var(--fg-2)' }}>FYI — 12-month addendum attached, no action requested.</span>
            </div>
            <div className="chips">
              <span className="rb2-mini-chip fyi">FYI</span>
              <span className="rb2-mini-chip att">📎 3p</span>
            </div>
          </div>
        </div>

        <div className="rb2-row">
          <div className="av" style={{ background: 'linear-gradient(135deg,#fff,#ccc)', color: '#0e1014' }}>NO</div>
          <div className="body">
            <div className="top">
              <div className="from">Recruiting · Notion</div>
              <div className="time">Sun</div>
            </div>
            <div className="subj">Weekly digest — 4 candidates</div>
            <div className="ai-prev">
              <span className="diamond">◆</span>
              <span><em>2 strong</em>, 1 maybe, 1 already archived by rules.</span>
            </div>
            <div className="chips"><span className="rb2-mini-chip fyi">digest</span></div>
          </div>
        </div>

        <div className="rb2-row">
          <div className="av" style={{ background: 'linear-gradient(135deg,#635bff,#3a31c0)' }}>ST</div>
          <div className="body">
            <div className="top">
              <div className="from">Stripe</div>
              <div className="time">Sat</div>
            </div>
            <div className="subj">Invoice #INV-2418</div>
            <div className="plain-prev">Paid · €1,840 · receipt attached</div>
          </div>
        </div>
      </div>
      <div style={{ padding: '10px 14px', borderTop: '1px solid var(--stroke-1)', fontFamily: 'var(--font-mono)',
                    fontSize: 10.5, color: 'var(--fg-3)', display: 'flex', justifyContent: 'space-between' }}>
        <span>◆ = AI summary · click to use first line</span>
        <span>local · {`<60ms`}</span>
      </div>
    </div>
  );
}

// ── Card 5 — "Done" terminal state after Send ──────────────────────────────
function Card5() {
  return (
    <div className="rb2-pane">
      <div className="rb2-done-head">
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span className="rb2-done-thread-pill">
            <span className="av"><IcCheck w={9} h={9} sw={3} /></span>
            Replied · 11:42
          </span>
          <span className="rb2-mono" style={{ fontSize: 11, color: 'var(--tone-jade-400)', letterSpacing: '.1em' }}>
            DONE
          </span>
        </div>
        <div className="subj" style={{ marginTop: 6 }}>Contract approval — Acme GmbH</div>
        <div className="meta">to Marta Kowalski · 4 messages · attachment sent</div>
      </div>
      <div className="rb2-done-body">
        <div className="rb2-thread-col-faded">
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: 10.5, color: 'var(--fg-3)', marginBottom: 4 }}>Alex (you) · 11:42</div>
          <div>Hi Marta — draft attached, pricing per proposal. I've flagged the two clauses for legal so they can move fast next week. Let me know if you want SLA terms attached too.</div>
          <div style={{ marginTop: 10, fontFamily: 'var(--font-mono)', fontSize: 10.5, color: 'var(--fg-3)' }}>contract_v3.pdf · 284 KB · sent</div>
        </div>
        <div className="rb2-done-rail">
          <div className="rb2-done-card">
            <div className="eb"><span className="check"><IcCheck w={8} h={8} sw={3} /></span> reply sent</div>
            <div className="summary">
              Draft delivered — flagged 2 clauses for legal.
              <span className="when">11:42 · local model · 0 PII redacted</span>
            </div>
            <div className="ask">
              <span className="q">Log to HubSpot?</span>
              <button className="yes">Log it</button>
            </div>
          </div>

          <div style={{ display: 'grid', gap: 8 }}>
            <div className="rb2-eyebrow" style={{ color: 'var(--fg-3)' }}>follow-up · auto-suggested</div>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              <span className="rb2-mini-chip" style={{ background: 'var(--bg-elev-2)', color: 'var(--fg-1)', padding: '0 8px' }}>
                <IcClock w={10} h={10} /> remind Fri 17:00
              </span>
              <span className="rb2-mini-chip" style={{ background: 'var(--bg-elev-2)', color: 'var(--fg-1)', padding: '0 8px' }}>
                <IcCal w={10} h={10} /> hold 30m Mon
              </span>
            </div>
          </div>

          <div style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--fg-3)', lineHeight: 1.6, paddingTop: 10, borderTop: '1px solid var(--stroke-1)' }}>
            next thread ↓<br/>
            <span style={{ color: 'var(--fg-2)' }}>Jonas R. — seat count by Wed</span>
          </div>
        </div>
      </div>
    </div>
  );
}

// ── Card 6 — Ambient FYI (replaces "no action found") ──────────────────────
function Card6() {
  return (
    <div className="rb2-fyi">
      <div className="rb2-eyebrow">AI brief · local</div>
      <div className="rb2-fyi-card">
        <div className="rb2-fyi-eb">just FYI · no reply needed</div>
        <div className="rb2-fyi-title">
          Cveta sent the lease addendum.<br/>
          <span style={{ color: 'var(--fg-3)' }}>You can read at leisure.</span>
        </div>
        <div className="rb2-fyi-reason">
          AI checked the thread — <b>no question</b>, <b>no deadline</b>, your past replies show you don't ack these.
        </div>
        <div className="rb2-fyi-cta">
          <button className="pri"><IcArchive w={12} h={12} /> Archive</button>
          <button><IcCheck w={12} h={12} /> Mark read</button>
          <button><IcEye w={12} h={12} /> Skim attachment</button>
        </div>
      </div>
      <div style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--fg-3)', lineHeight: 1.6, padding: '0 4px' }}>
        Replaces the old <span style={{ color: 'var(--fg-2)' }}>"no action found"</span> message.<br/>
        AI <em style={{ color: 'var(--citron-500)', fontStyle: 'normal' }}>actively confirms</em> nothing is owed.
      </div>
    </div>
  );
}

// ── Card 7 — Morning briefing on Inbox click ───────────────────────────────
function Card7() {
  return (
    <div className="rb2-mb">
      <div className="rb2-mb-head">
        <div className="rb2-mb-eyebrow" style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
          <IcSun w={12} h={12} /> Tuesday morning · 09:12
        </div>
        <div className="rb2-mb-title">
          You have <b style={{ color: 'var(--fg-1)' }}>3 threads</b> that <span className="em">need a reply today</span>.
        </div>
        <div className="rb2-mb-tally">
          <span><b>3</b> need reply</span>
          <span><b>2</b> waiting on others</span>
          <span><b>5</b> informational</span>
          <span><b>2</b> already handled</span>
        </div>
      </div>
      <div className="rb2-mb-body">
        <div className="rb2-mb-bucket urgent">
          <div className="rb2-mb-bucket-head">
            <div className="ttl"><span className="dot coral" /> Reply today <span className="count">· 3</span></div>
            <div className="bulkact">draft all ↑</div>
          </div>
          <div className="rb2-mb-item">
            <div>
              <div className="who">Marta Kowalski · Acme GmbH</div>
              <div className="what">Send contract draft <span className="when">· Fri EOD</span></div>
            </div>
            <button className="quick pri">Draft</button>
          </div>
          <div className="rb2-mb-item">
            <div>
              <div className="who">Jonas R. · SaaS renewal Q3</div>
              <div className="what">Confirm seat count <span className="when" style={{ color: 'var(--tone-amber-300)' }}>· Wed</span></div>
            </div>
            <button className="quick pri">Draft</button>
          </div>
          <div className="rb2-mb-item">
            <div>
              <div className="who">Lena Park · Design review</div>
              <div className="what">Accept invite & bring Q3 mocks <span className="when" style={{ color: 'var(--fg-3)' }}>· Tue 16:00</span></div>
            </div>
            <button className="quick">Accept</button>
          </div>
        </div>

        <div className="rb2-mb-bucket">
          <div className="rb2-mb-bucket-head">
            <div className="ttl"><span className="dot amber" /> Waiting on others <span className="count">· 2</span></div>
            <div className="bulkact">nudge all</div>
          </div>
          <div className="rb2-mb-item">
            <div>
              <div className="who">Sven Christensen · pricing</div>
              <div className="what" style={{ color: 'var(--fg-3)' }}>Awaiting his answer — 2 days · nudge?</div>
            </div>
            <button className="quick">Nudge</button>
          </div>
          <div className="rb2-mb-item">
            <div>
              <div className="who">Legal · Acme contract</div>
              <div className="what" style={{ color: 'var(--fg-3)' }}>Review requested · ETA Thu</div>
            </div>
            <button className="quick">View</button>
          </div>
        </div>

        <div className="rb2-mb-bucket">
          <div className="rb2-mb-bucket-head">
            <div className="ttl"><span className="dot muted" /> Informational <span className="count">· 5</span></div>
            <div className="bulkact" style={{ borderColor: 'color-mix(in oklch, var(--tone-jade-400) 40%, transparent)', color: 'var(--tone-jade-400)' }}>
              archive all ↦
            </div>
          </div>
          <div className="rb2-mb-item">
            <div>
              <div className="who">Stripe · Notion · GitHub · Linear · +1</div>
              <div className="what" style={{ color: 'var(--fg-3)' }}>Receipts, digests, status pings — no action found.</div>
            </div>
            <button className="quick">Skim</button>
          </div>
        </div>
      </div>
    </div>
  );
}

window.RB2 = { Card1, Card2, Card3, Card4, Card5, Card6, Card7 };
