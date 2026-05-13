// Re:Box — Wireframe atoms (shared building blocks)
// Sketchy, low-fi, handwritten-but-readable.

const RBX = ({ accent = false }) => (
  <span className="rebox"><em>Re:</em>Box</span>
);

// macOS window shell with traffic lights + optional title
const Win = ({ title, children, rough = true, style }) => (
  <div className="win" data-rough={rough || undefined} style={{ width: "100%", height: "100%", ...style }}>
    <div className="win__bar">
      <span className="win__dot" />
      <span className="win__dot" />
      <span className="win__dot" />
      {title && <span className="win__title">{title}</span>}
    </div>
    <div className="win__body">{children}</div>
  </div>
);

const Panel = ({ children, style, inset = false, label }) => (
  <div className={"panel" + (inset ? " panel--inset" : "")} style={style}>
    {children}
    {label && <span className="region-label" style={{ bottom: 8, right: 10 }}>{label}</span>}
  </div>
);

const Avatar = ({ initials = "MK", citron = false }) => (
  <span className="row__avatar" style={citron ? { background: "var(--citron)" } : {}}>{initials}</span>
);

const Row = ({ from, time, subj, unread = false, selected = false, chips = [], avatar = "··", citronAvatar = false }) => (
  <div className={"row" + (unread ? " row--unread" : "") + (selected ? " row--selected" : "")}>
    <Avatar initials={avatar} citron={citronAvatar} />
    <div className="row__main">
      <div className="row__topline">
        <span className="row__from">{from}</span>
        <span className="row__time">{time}</span>
      </div>
      <div className="row__subj">{subj}</div>
      <div className="row__preview">
        {chips.map((c, i) => <span key={i} className={"chip chip--" + c.tone}>{c.label}</span>)}
        <span className="row__line" />
      </div>
    </div>
  </div>
);

const Chip = ({ children, tone = "ghost" }) => (
  <span className={"chip chip--" + tone}>{children}</span>
);

const Btn = ({ children, primary = false, ghost = false, sm = false, style }) => (
  <span
    className={
      "btn" +
      (primary ? " btn--primary" : "") +
      (ghost ? " btn--ghost" : "") +
      (sm ? " btn--sm" : "")
    }
    data-rough
    style={style}
  >
    {children}
  </span>
);

// Handwritten note annotation (positioned absolutely by parent)
const Note = ({ children, style, big = false, small = false, right = false, accent = false }) => (
  <span
    className={
      "note" +
      (big ? " note--big" : "") +
      (small ? " note--small" : "") +
      (right ? " note--right" : "") +
      (accent ? " note--accent" : "")
    }
    style={style}
  >
    {children}
  </span>
);

// Sketchy SVG arrow. dx,dy define endpoint relative to start.
const Arrow = ({ x, y, dx, dy, curve = 0.4, style }) => {
  // wobbly bezier
  const cx = dx * 0.5 + (Math.abs(dx) > Math.abs(dy) ? 0 : dy * curve);
  const cy = dy * 0.5 + (Math.abs(dx) > Math.abs(dy) ? -dx * curve : 0);
  const w = Math.max(Math.abs(dx), 60) + 40;
  const h = Math.max(Math.abs(dy), 40) + 40;
  return (
    <span className="arrow" style={{ left: x, top: y, ...style }}>
      <svg width={w} height={h} viewBox={`${Math.min(0, dx) - 20} ${Math.min(0, dy) - 20} ${w} ${h}`}>
        <path d={`M 0 0 Q ${cx} ${cy} ${dx} ${dy}`} />
        {/* arrowhead */}
        <path d={`M ${dx} ${dy} l ${-8 * Math.sign(dx || 1) - (dy ? 2 : 0)} ${-4} M ${dx} ${dy} l ${-8 * Math.sign(dx || 1) - (dy ? -2 : 0)} 4`} />
      </svg>
    </span>
  );
};

// AI Brief card
const Brief = ({ accent = false, compact = false, style, children }) => (
  <div className={"brief" + (accent ? " brief--accent" : "")} data-rough style={style}>
    <div className="brief__eyebrow">AI BRIEF · LOCAL</div>
    {children || (
      <>
        <div className="brief__line">
          Marta wants the <span className="u-scribble">contract draft by Friday</span> — pricing is approved, legal window is tight.
        </div>
        {!compact && (
          <div className="brief__meta">
            <Chip tone="coral">DUE FRI · MAY 15</Chip>
            <Chip tone="amber">NEEDS REPLY</Chip>
            <Chip tone="ice">1 PDF · 7 PG</Chip>
          </div>
        )}
      </>
    )}
  </div>
);

// Sidebar contents
const SidebarContents = ({ activeIdx = 0 }) => {
  const folders = [
    { name: "Inbox", count: 12 },
    { name: "Needs reply", count: 4 },
    { name: "Has deadline", count: 3 },
    { name: "Attachments", count: 9 },
    { name: "Logged", count: 7 },
    { name: "Starred", count: 2 },
    { name: "Sent", count: null },
    { name: "Archive", count: null },
  ];
  return (
    <div style={{ padding: "14px 12px", fontFamily: "var(--sketch)", fontSize: 13 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 16 }}>
        <span className="rebox" style={{ fontSize: 20 }}><em>Re:</em>Box</span>
      </div>
      <div style={{ fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--ink-3)", textTransform: "uppercase", marginBottom: 6 }}>Accounts</div>
      <div style={{ display: "flex", flexDirection: "column", gap: 4, marginBottom: 14 }}>
        <span style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ width: 10, height: 10, borderRadius: 3, background: "#7892c4", border: "1.25px solid var(--line)" }} />
          work · gmail
        </span>
        <span style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ width: 10, height: 10, borderRadius: 3, background: "#a884d9", border: "1.25px solid var(--line)" }} />
          work · m365
        </span>
        <span style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ width: 10, height: 10, borderRadius: 3, background: "var(--citron)", border: "1.25px solid var(--line)" }} />
          personal
        </span>
      </div>
      <div style={{ fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--ink-3)", textTransform: "uppercase", marginBottom: 6 }}>Folders</div>
      <div style={{ display: "flex", flexDirection: "column", gap: 3 }}>
        {folders.map((f, i) => (
          <div
            key={f.name}
            style={{
              display: "flex",
              justifyContent: "space-between",
              padding: "4px 8px",
              borderRadius: 6,
              background: i === activeIdx ? "var(--paper-3)" : "transparent",
              boxShadow: i === activeIdx ? "inset 2px 0 0 var(--citron)" : "none",
            }}
          >
            <span>{f.name}</span>
            {f.count != null && <span style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--ink-3)" }}>{f.count}</span>}
          </div>
        ))}
      </div>
    </div>
  );
};

// Thread list contents
const ThreadListContents = ({ selectedId = "t1", compact = false }) => {
  const threads = [
    { id: "t1", from: "Marta Kowalski", time: "11:42", subj: "Contract approval — Acme GmbH", unread: true, chips: [{ label: "DUE FRI", tone: "coral" }], avatar: "MK" },
    { id: "t2", from: "Jonas R.", time: "10:08", subj: "Re: SaaS renewal — Q3", unread: true, chips: [{ label: "REPLY", tone: "amber" }], avatar: "JR" },
    { id: "t3", from: "Cveta Vlahova", time: "Yest", subj: "Lease addendum", chips: [{ label: "1 PDF", tone: "ice" }], avatar: "CV", citronAvatar: true },
    { id: "t4", from: "Sven Christensen", time: "Mon", subj: "Re: pricing thread", chips: [{ label: "LOGGED", tone: "jade" }], avatar: "SC" },
    { id: "t5", from: "Lena Park", time: "Mon", subj: "Design review — Tue 4pm", chips: [], avatar: "LP" },
    { id: "t6", from: "Recruiting · Notion", time: "Sun", subj: "Weekly digest — 4 candidates", chips: [{ label: "AI", tone: "citron" }], avatar: "NO" },
    { id: "t7", from: "Stripe", time: "Sat", subj: "Invoice #INV-2418", chips: [{ label: "PAID", tone: "jade" }], avatar: "ST" },
  ];
  return (
    <div>
      <div className="panel__head">
        <span>Inbox · 12</span>
        <span>⌘K · search</span>
      </div>
      {threads.map((t) => (
        <Row key={t.id} {...t} selected={t.id === selectedId} />
      ))}
    </div>
  );
};

// Reading pane contents (thread body)
const ReadingContents = ({ withBrief = false, briefInline = false }) => (
  <div style={{ padding: "16px 24px", overflow: "hidden", display: "flex", flexDirection: "column", gap: 14 }}>
    <div>
      <div style={{ fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--ink-3)", textTransform: "uppercase" }}>
        From Marta Kowalski · Acme GmbH · 3 messages
      </div>
      <div style={{ fontFamily: "var(--sketch)", fontSize: 22, lineHeight: 1.15, marginTop: 4 }}>
        Contract approval — Acme GmbH
      </div>
    </div>
    {briefInline && <Brief compact />}
    {/* message 1 */}
    <div style={{ display: "flex", gap: 10 }}>
      <Avatar initials="MK" />
      <div style={{ flex: 1 }}>
        <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
          <span style={{ fontFamily: "var(--sketch)", fontSize: 13, fontWeight: 500 }}>Marta Kowalski</span>
          <span style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--ink-3)" }}>Tue 11:42</span>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 5 }}>
          <span className="placeholder-line" />
          <span className="placeholder-line" />
          <span className="placeholder-line placeholder-line--mid" />
          <span className="placeholder-line" />
          <span className="placeholder-line placeholder-line--short" />
        </div>
        <div style={{ marginTop: 10, display: "flex", gap: 8, alignItems: "center" }}>
          <span className="hatch" style={{ width: 32, height: 40 }} />
          <span style={{ fontFamily: "var(--sketch)", fontSize: 12 }}>contract.pdf · 7 pg · 284 KB</span>
        </div>
      </div>
    </div>
    <hr style={{ border: 0, borderTop: "1px dashed var(--line-soft)", margin: 0 }} />
    {/* message 2 collapsed */}
    <div style={{ display: "flex", gap: 10, opacity: 0.65 }}>
      <Avatar initials="AX" citron />
      <div style={{ flex: 1 }}>
        <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
          <span style={{ fontFamily: "var(--sketch)", fontSize: 13 }}>Alex (you) — Mon 14:40</span>
          <span style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--ink-3)" }}>↕ expand</span>
        </div>
        <span className="placeholder-line placeholder-line--mid" />
      </div>
    </div>
  </div>
);

Object.assign(window, { RBX, Win, Panel, Avatar, Row, Chip, Btn, Note, Arrow, Brief, SidebarContents, ThreadListContents, ReadingContents });
