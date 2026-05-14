// Re:Box — Section 2: AI brief placement
// Where does the brief live relative to the thread?

// ---------- B1 · Banner brief at top
const BriefB1 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="Brief as banner">
      <Panel style={{ width: 220 }}><SidebarContents /></Panel>
      <Panel inset style={{ flex: 1 }}>
        <div style={{ padding: 20 }}>
          <Brief />
        </div>
        <hr style={{ border: 0, borderTop: "1px dashed var(--line-soft)", margin: "0 20px" }} />
        <ReadingContents />
      </Panel>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>B1 · Banner brief</Note>
    <Note style={{ top: 0, right: 36 }} right>brief reads first,<br/>thread follows</Note>
  </div>
);

// ---------- B2 · Floating side card
const BriefB2 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="Brief as floating card">
      <Panel style={{ width: 220 }}><SidebarContents /></Panel>
      <Panel inset style={{ flex: 1, position: "relative" }}>
        <ReadingContents />
        <div style={{ position: "absolute", top: 18, right: 18, width: 290 }}>
          <Brief />
        </div>
        <span className="region-label" style={{ top: 220, right: 320, transform: "rotate(-90deg)", transformOrigin: "right center" }}>floats over right gutter</span>
      </Panel>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>B2 · Floating card</Note>
    <Note style={{ top: 0, right: 36 }} right>brief <span className="u-scribble">floats</span> on top-right.<br/>dismissable.</Note>
    <Arrow x={1120} y={170} dx={-40} dy={20} />
  </div>
);

// ---------- B3 · Inline expandable
const BriefB3 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="Brief inline, expandable">
      <Panel style={{ width: 220 }}><SidebarContents /></Panel>
      <Panel inset style={{ flex: 1 }}>
        <div style={{ padding: 20 }}>
          <div className="brief" data-rough style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "10px 14px" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
              <span className="brief__eyebrow" style={{ margin: 0 }}>BRIEF</span>
              <span style={{ fontFamily: "var(--sketch)", fontSize: 13 }}>contract draft due Friday — pricing approved.</span>
            </div>
            <span className="chip">↓ expand</span>
          </div>
          <Note small style={{ position: "relative", top: 8, left: 8 }}>collapsed by default →</Note>
        </div>
        <ReadingContents />
        <div style={{ padding: "0 20px 20px" }}>
          <div className="brief" data-rough style={{ marginTop: 12 }}>
            <div className="brief__eyebrow">AI BRIEF · EXPANDED</div>
            <div className="brief__line">When opened, the brief expands inline between header and first message — pushes thread down, never overlays.</div>
            <div className="brief__meta">
              <Chip tone="coral">DUE FRI</Chip>
              <Chip tone="amber">REPLY</Chip>
              <Chip tone="ice">⌖ msg 1 · msg 3 · pdf p.2</Chip>
            </div>
          </div>
        </div>
      </Panel>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>B3 · Inline expandable</Note>
    <Note style={{ top: 0, right: 36 }} right>collapsed one-liner;<br/>expands on tap</Note>
  </div>
);

// ---------- B4 · Split — brief left, thread right
const BriefB4 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="Split — brief and thread side by side">
      <Panel style={{ width: 220 }}><SidebarContents /></Panel>
      <Panel style={{ width: 360, background: "color-mix(in oklch, var(--citron) 8%, var(--paper-2))" }}>
        <div className="panel__head"><span>◉ AI BRIEF · LOCAL</span><span>0.88</span></div>
        <div style={{ padding: 18, display: "flex", flexDirection: "column", gap: 14 }}>
          <div style={{ fontFamily: "var(--sketch)", fontSize: 16, lineHeight: 1.4 }}>
            Marta wants the <span className="u-scribble">contract draft by Friday</span>. Pricing is approved. Tight legal window.
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <div style={{ fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--ink-3)", textTransform: "uppercase" }}>Request</div>
            <div style={{ fontFamily: "var(--sketch)", fontSize: 13 }}>Send contract draft</div>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <div style={{ fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--ink-3)", textTransform: "uppercase" }}>Deadline</div>
            <div style={{ display: "flex", gap: 6 }}><Chip tone="coral">FRI · MAY 15</Chip></div>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <div style={{ fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--ink-3)", textTransform: "uppercase" }}>Evidence</div>
            <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
              <Chip tone="ghost">⌖ msg 1</Chip>
              <Chip tone="ghost">⌖ msg 3</Chip>
              <Chip tone="ghost">⌖ contract.pdf p.2</Chip>
            </div>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 6, marginTop: 4 }}>
            <div style={{ fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--ink-3)", textTransform: "uppercase" }}>Next step</div>
            <Btn primary>Draft reply with contract</Btn>
          </div>
        </div>
      </Panel>
      <Panel inset style={{ flex: 1 }}>
        <div className="panel__head"><span>Thread · 3 msg</span><span>↕ scroll</span></div>
        <ReadingContents />
      </Panel>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>B4 · Split brief / thread</Note>
    <Note style={{ top: 0, right: 36 }} right>brief gets a full column.<br/>every field is its own line.</Note>
    <Note small style={{ top: 270, left: 270, transform: "rotate(-2deg)" }}>tap ⌖ to scroll to source</Note>
    <Arrow x={340} y={310} dx={80} dy={20} />
  </div>
);

Object.assign(window, { BriefB1, BriefB2, BriefB3, BriefB4 });
