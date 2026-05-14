// Re:Box — Section 1: Inbox layout variations
// 4 distinctly different approaches to where the AI brief lives
// and how the 3-pane gets composed.

// ---------- A1 · Classic 3-pane, AI brief inline at top of reading
const InboxA1 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="Inbox — work · gmail">
      <Panel style={{ width: 220 }}><SidebarContents activeIdx={0} /></Panel>
      <Panel style={{ width: 320 }}><ThreadListContents /></Panel>
      <Panel inset style={{ flex: 1 }}>
        <div className="panel__head">
          <span>Thread</span>
          <span>Reply  ·  Snooze  ·  Send to ↗</span>
        </div>
        <div style={{ padding: "14px 20px" }}>
          <Brief />
        </div>
        <div style={{ padding: "0 20px 20px" }}>
          <ReadingContents />
        </div>
      </Panel>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>A1 · Classic 3-pane</Note>
    <Note style={{ top: 0, right: 36 }} right>brief sits <span className="u-scribble">above</span> the thread —<br/>most familiar pattern</Note>
    <Arrow x={690} y={140} dx={-60} dy={20} />
    <Note small style={{ top: 175, left: 600 }}>AI brief = hero</Note>
  </div>
);

// ---------- A2 · 4-column with dedicated AI rail on the right
const InboxA2 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="Inbox — 4-column with AI rail">
      <Panel style={{ width: 180 }}><SidebarContents activeIdx={1} /></Panel>
      <Panel style={{ width: 280 }}><ThreadListContents /></Panel>
      <Panel inset style={{ flex: 1 }}>
        <div className="panel__head">
          <span>Contract approval — Acme GmbH</span>
          <span>3 msg · 1 PDF</span>
        </div>
        <ReadingContents />
      </Panel>
      <Panel style={{ width: 260, background: "color-mix(in oklch, var(--citron) 10%, var(--paper-2))" }}>
        <div className="panel__head" style={{ color: "var(--citron-ink)" }}>
          <span>◉ AI rail · local</span>
        </div>
        <div style={{ padding: 14, display: "flex", flexDirection: "column", gap: 12 }}>
          <Brief accent compact />
          <div style={{ fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--ink-3)", textTransform: "uppercase" }}>Suggested replies</div>
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <div style={{ border: "1.25px dashed var(--line-soft)", borderRadius: 8, padding: "8px 10px", fontFamily: "var(--sketch)", fontSize: 12 }}>Confirm Friday delivery</div>
            <div style={{ border: "1.25px dashed var(--line-soft)", borderRadius: 8, padding: "8px 10px", fontFamily: "var(--sketch)", fontSize: 12 }}>Ask for extra day</div>
            <div style={{ border: "1.25px dashed var(--line-soft)", borderRadius: 8, padding: "8px 10px", fontFamily: "var(--sketch)", fontSize: 12 }}>Decline politely</div>
          </div>
          <div style={{ fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--ink-3)", textTransform: "uppercase", marginTop: 4 }}>Send to ↗</div>
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
            <Chip tone="ghost">SLACK</Chip>
            <Chip tone="ghost">NOTION</Chip>
            <Chip tone="ghost">HUBSPOT</Chip>
            <Chip tone="ghost">SALESFORCE</Chip>
          </div>
        </div>
      </Panel>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>A2 · AI rail right</Note>
    <Note style={{ top: 0, right: 36 }} right>brief + replies + actions<br/>live in a <span className="u-scribble">permanent rail</span></Note>
    <Arrow x={1100} y={120} dx={-40} dy={30} />
  </div>
);

// ---------- A3 · Editorial 2-pane (thread list collapses to spine)
const InboxA3 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="Editorial 2-pane">
      <Panel style={{ width: 64, background: "var(--paper-3)" }}>
        <div style={{ padding: "14px 8px", display: "flex", flexDirection: "column", gap: 10, alignItems: "center" }}>
          <span className="rebox" style={{ fontSize: 18 }}><em>Re:</em></span>
          {["IN", "RE", "DU", "AT", "LG", "AR"].map((s, i) => (
            <span key={s} style={{
              width: 38, height: 38, border: "1.25px solid var(--line)", borderRadius: 8,
              display: "flex", alignItems: "center", justifyContent: "center",
              fontFamily: "var(--mono)", fontSize: 10, letterSpacing: "0.08em",
              background: i === 0 ? "var(--paper)" : "transparent",
              boxShadow: i === 0 ? "inset 0 -2px 0 var(--citron)" : "none"
            }}>{s}</span>
          ))}
        </div>
      </Panel>
      <Panel style={{ width: 90, background: "var(--paper-2)" }}>
        <div style={{ padding: "14px 6px", display: "flex", flexDirection: "column", gap: 10 }}>
          <div style={{ fontFamily: "var(--mono)", fontSize: 8, letterSpacing: "0.16em", color: "var(--ink-3)", textTransform: "uppercase", textAlign: "center" }}>12 threads</div>
          {[
            ["MK", true, "citron"],
            ["JR", true, "amber"],
            ["CV", false, "ice"],
            ["SC", false, "jade"],
            ["LP", false, null],
            ["NO", false, "citron"],
            ["ST", false, "jade"],
          ].map(([initials, unread, tone], i) => (
            <div key={i} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 4, padding: 6, borderRadius: 8, background: i === 0 ? "var(--paper)" : "transparent", border: i === 0 ? "1.25px solid var(--citron)" : "1.25px solid transparent" }}>
              <Avatar initials={initials} citron={initials === "CV"} />
              {tone && <span className="chip" style={{ padding: "1px 4px", fontSize: 7 }}>{tone === "coral" ? "DUE" : tone === "amber" ? "REPLY" : tone === "ice" ? "PDF" : tone === "jade" ? "OK" : "AI"}</span>}
            </div>
          ))}
        </div>
      </Panel>
      <Panel inset style={{ flex: 1 }}>
        <div className="panel__head">
          <span>Contract approval — Acme GmbH</span>
          <span>Esc to list</span>
        </div>
        <div style={{ padding: "28px 80px", maxWidth: 760, margin: "0 auto" }}>
          <div style={{ fontFamily: "Instrument Serif, serif", fontStyle: "italic", fontSize: 40, lineHeight: 1.05, marginBottom: 14 }}>
            Contract approval — Acme GmbH
          </div>
          <Brief />
          <div style={{ marginTop: 22 }}>
            <ReadingContents />
          </div>
        </div>
      </Panel>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>A3 · Editorial 2-pane</Note>
    <Note style={{ top: 0, right: 36 }} right>list shrinks to a <span className="u-scribble">spine</span>;<br/>reading takes the stage</Note>
    <Note small style={{ top: 220, left: 280, transform: "rotate(2deg)" }}>tap initials to switch</Note>
    <Arrow x={180} y={300} dx={120} dy={-30} />
  </div>
);

// ---------- A4 · Command-driven (search-first, threads in tray)
const InboxA4 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="Command-driven · search-first">
      <div style={{ flex: 1, position: "relative", background: "var(--paper)" }}>
        <div style={{ padding: "20px 64px", display: "flex", flexDirection: "column", alignItems: "center" }}>
          <span className="rebox" style={{ fontSize: 24, marginBottom: 14 }}><em>Re:</em>Box</span>
          <div className="glass" data-rough style={{ width: "100%", maxWidth: 720, padding: "14px 18px", display: "flex", alignItems: "center", gap: 10 }}>
            <span style={{ fontFamily: "var(--mono)", fontSize: 11, color: "var(--ink-3)" }}>⌘K</span>
            <span style={{ fontFamily: "var(--sketch)", fontSize: 15, color: "var(--ink-2)", flex: 1 }}>
              ask anything, draft anything, find anything…
            </span>
            <span className="chip chip--citron">LOCAL AI</span>
          </div>
          <div style={{ marginTop: 10, display: "flex", gap: 8 }}>
            <Chip tone="ghost">"what did Marta send?"</Chip>
            <Chip tone="ghost">"draft Friday update"</Chip>
            <Chip tone="ghost">"unpaid invoices"</Chip>
          </div>
        </div>
        <div style={{ padding: "8px 64px 24px" }}>
          <div style={{ fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--ink-3)", textTransform: "uppercase", marginBottom: 8, display: "flex", justifyContent: "space-between" }}>
            <span>Today · needs attention</span>
            <span>3 of 12</span>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12 }}>
            {[
              { from: "Marta K.", subj: "Contract approval — Acme GmbH", tone: "coral", chip: "DUE FRI", brief: "Approved pricing. Send draft." },
              { from: "Jonas R.", subj: "Re: SaaS renewal — Q3", tone: "amber", chip: "NEEDS REPLY", brief: "Confirm seat count by Wed." },
              { from: "Cveta V.", subj: "Lease addendum", tone: "ice", chip: "1 PDF", brief: "12 months — ok to sign?" }
            ].map((t, i) => (
              <div key={i} className="glass" data-rough style={{ padding: 14, display: "flex", flexDirection: "column", gap: 8 }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                  <Avatar initials={t.from.split(" ").map(w=>w[0]).join("")} />
                  <span className={"chip chip--" + t.tone}>{t.chip}</span>
                </div>
                <div style={{ fontFamily: "var(--sketch)", fontSize: 13, fontWeight: 500 }}>{t.subj}</div>
                <div style={{ fontFamily: "var(--sketch)", fontSize: 12, color: "var(--ink-2)" }}>{t.brief}</div>
                <div style={{ display: "flex", gap: 6, marginTop: 4 }}>
                  <Btn primary sm>Draft</Btn>
                  <Btn ghost sm>Open</Btn>
                </div>
              </div>
            ))}
          </div>
          <div style={{ marginTop: 22, fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--ink-3)", textTransform: "uppercase", marginBottom: 8 }}>Rest of inbox · 9</div>
          <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
            {[1,2,3,4].map(i => (
              <div key={i} style={{ display: "flex", gap: 12, alignItems: "center", padding: "6px 4px", borderBottom: "1px dashed var(--line-softer)" }}>
                <Avatar initials="··" />
                <span style={{ fontFamily: "var(--sketch)", fontSize: 12, color: "var(--ink-2)", flex: 1 }}>placeholder thread {i}</span>
                <span style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--ink-3)" }}>—</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>A4 · Command-driven</Note>
    <Note style={{ top: 0, right: 36 }} right>no list, no folders.<br/>only <span className="u-scribble">today's signal</span> + ask box</Note>
    <Note small style={{ top: 175, left: 380, transform: "rotate(-3deg)" }}>everything starts here</Note>
    <Arrow x={420} y={210} dx={120} dy={-60} curve={-0.4} />
  </div>
);

Object.assign(window, { InboxA1, InboxA2, InboxA3, InboxA4 });
