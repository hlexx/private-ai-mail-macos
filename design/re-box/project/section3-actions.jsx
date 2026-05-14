// Re:Box — Section 3: Action sheet variations
// How does "send to Slack / Notion / HubSpot / Salesforce" surface?

// ---------- C1 · Bottom glass sheet (canonical macOS pattern)
const ActionC1 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="Bottom action sheet">
      <Panel style={{ width: 220 }}><SidebarContents /></Panel>
      <Panel inset style={{ flex: 1, position: "relative" }}>
        <div style={{ opacity: 0.45 }}>
          <ReadingContents briefInline />
        </div>
        {/* Sheet */}
        <div className="glass" data-rough style={{ position: "absolute", left: 20, right: 20, bottom: 18, padding: 16 }}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 12 }}>
            <span className="brief__eyebrow" style={{ margin: 0 }}>SEND TO</span>
            <span style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--ink-3)" }}>esc · cancel</span>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 10 }}>
            {[
              ["#", "Slack", "#4A154B"],
              ["N", "Notion", "#000"],
              ["H", "HubSpot", "#ff7a59"],
              ["⊕", "Salesforce", "#00a1e0"],
            ].map(([g, name, color]) => (
              <div key={name} style={{ border: "1.25px solid var(--line)", borderRadius: 10, padding: 12, display: "flex", alignItems: "center", gap: 10, background: "var(--paper-2)" }}>
                <span style={{ width: 32, height: 32, borderRadius: 8, background: color, color: "#fff", fontFamily: "var(--mono)", display: "flex", alignItems: "center", justifyContent: "center" }}>{g}</span>
                <div>
                  <div style={{ fontFamily: "var(--sketch)", fontSize: 13 }}>{name}</div>
                  <div style={{ fontFamily: "var(--mono)", fontSize: 9, color: "var(--ink-3)" }}>preview · approve</div>
                </div>
              </div>
            ))}
          </div>
          <div style={{ marginTop: 12, borderTop: "1px dashed var(--line-soft)", paddingTop: 10, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ fontFamily: "var(--sketch)", fontSize: 12, color: "var(--ink-2)" }}>summary stays on this Mac · only the chosen payload leaves</span>
            <span className="chip chip--citron">LOCAL AI</span>
          </div>
        </div>
        <span className="region-label" style={{ top: 18, right: 22 }}>thread dims behind sheet</span>
      </Panel>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>C1 · Bottom glass sheet</Note>
    <Note style={{ top: 0, right: 36 }} right>full-width sheet,<br/>familiar macOS pattern</Note>
    <Arrow x={420} y={520} dx={120} dy={-30} curve={-0.4} />
    <Note small style={{ top: 540, left: 320, transform: "rotate(-2deg)" }}>4 integrations · 1 tap</Note>
  </div>
);

// ---------- C2 · Inline chip morph (chips already on the message)
const ActionC2 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="Inline chips morph into action">
      <Panel style={{ width: 220 }}><SidebarContents /></Panel>
      <Panel inset style={{ flex: 1, padding: 0 }}>
        <ReadingContents briefInline />
        <div style={{ padding: "0 24px 20px" }}>
          <div style={{ fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--ink-3)", textTransform: "uppercase", marginBottom: 10 }}>Send this thread to</div>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <Chip tone="ghost">SLACK · #sales</Chip>
            <Chip tone="ghost">NOTION · Deals</Chip>
            <Chip tone="ghost">HUBSPOT · Acme</Chip>
            <Chip tone="ghost">SALESFORCE · Opp</Chip>
          </div>
          <Note small style={{ position: "relative", top: 10, left: 0 }}>hover a chip → preview opens above it</Note>
          <div className="glass" data-rough style={{ marginTop: 28, padding: 14, width: 460, position: "relative" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <span style={{ width: 22, height: 22, borderRadius: 6, background: "#4A154B", color: "#fff", fontFamily: "var(--mono)", display: "inline-flex", alignItems: "center", justifyContent: "center", fontSize: 11 }}>#</span>
                <span style={{ fontFamily: "var(--sketch)", fontSize: 13 }}>preview · #sales</span>
              </div>
              <span style={{ fontFamily: "var(--mono)", fontSize: 9, color: "var(--ink-3)" }}>NEEDS APPROVAL</span>
            </div>
            <div style={{ background: "var(--paper-2)", border: "1.25px dashed var(--line-soft)", borderRadius: 8, padding: 10, fontFamily: "var(--sketch)", fontSize: 12, lineHeight: 1.4 }}>
              "Marta @ Acme wants the contract draft by Fri May 15. Pricing approved. I'll send today."
            </div>
            <div style={{ display: "flex", gap: 8, marginTop: 10, justifyContent: "flex-end" }}>
              <Btn ghost sm>edit</Btn>
              <Btn primary sm>approve & send</Btn>
            </div>
            <span className="circled" style={{ left: -10, right: -10, top: -8, bottom: -8 }} />
          </div>
        </div>
      </Panel>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>C2 · Chip morph</Note>
    <Note style={{ top: 0, right: 36 }} right>chips live <span className="u-scribble">in-thread</span>.<br/>hover = preview, no modal.</Note>
  </div>
);

// ---------- C3 · Command palette style
const ActionC3 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="Command palette">
      <Panel style={{ width: 220 }}><SidebarContents /></Panel>
      <Panel inset style={{ flex: 1, position: "relative" }}>
        <div style={{ opacity: 0.35 }}>
          <ReadingContents briefInline />
        </div>
        <div className="glass" data-rough style={{ position: "absolute", top: 80, left: "50%", transform: "translateX(-50%)", width: 560, padding: 0, overflow: "hidden" }}>
          <div style={{ padding: "12px 16px", borderBottom: "1.25px dashed var(--line-soft)", display: "flex", alignItems: "center", gap: 10 }}>
            <span style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--ink-3)" }}>⌘K</span>
            <span style={{ fontFamily: "var(--sketch)", fontSize: 16, color: "var(--ink) " }}>send to sla<span style={{ borderLeft: "1.5px solid var(--ink)", marginLeft: 1 }}>&nbsp;</span></span>
          </div>
          <div style={{ padding: 6 }}>
            {[
              ["→", "Send summary to Slack · #sales", true],
              ["→", "Send full thread to Slack · DM Jonas", false],
              ["→", "Log to HubSpot · Acme Deal", false],
              ["→", "Add Notion task · Deals/Acme", false],
              ["→", "Push to Salesforce · Opp-2418", false],
            ].map(([g, label, sel], i) => (
              <div key={i} style={{ display: "flex", alignItems: "center", gap: 10, padding: "10px 12px", borderRadius: 8, background: sel ? "var(--paper-3)" : "transparent", boxShadow: sel ? "inset 2px 0 0 var(--citron)" : "none" }}>
                <span style={{ fontFamily: "var(--mono)", fontSize: 12, color: "var(--ink-3)" }}>{g}</span>
                <span style={{ fontFamily: "var(--sketch)", fontSize: 13, flex: 1 }}>{label}</span>
                {sel && <span style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--ink-3)" }}>↵ to preview</span>}
              </div>
            ))}
          </div>
          <div style={{ borderTop: "1.25px dashed var(--line-soft)", padding: "8px 16px", display: "flex", justifyContent: "space-between", fontFamily: "var(--mono)", fontSize: 10, color: "var(--ink-3)" }}>
            <span>↑↓ navigate · ↵ select</span>
            <span>LOCAL AI</span>
          </div>
        </div>
      </Panel>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>C3 · Command palette</Note>
    <Note style={{ top: 0, right: 36 }} right>type → match → preview.<br/>keyboard-first.</Note>
    <Arrow x={690} y={155} dx={-40} dy={20} />
  </div>
);

// ---------- C4 · Side drawer w/ full preview
const ActionC4 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="Side drawer">
      <Panel style={{ width: 220 }}><SidebarContents /></Panel>
      <Panel inset style={{ flex: 1 }}>
        <ReadingContents briefInline />
      </Panel>
      <Panel style={{ width: 380, background: "var(--paper)" }}>
        <div className="panel__head"><span>SEND TO ↗</span><span>× close</span></div>
        <div style={{ padding: 16, display: "flex", flexDirection: "column", gap: 14 }}>
          <div style={{ display: "flex", gap: 6 }}>
            {["Slack", "Notion", "HubSpot", "Salesforce"].map((t, i) => (
              <span key={t} className={"chip " + (i === 0 ? "chip--citron" : "")}>{t}</span>
            ))}
          </div>
          <div className="brief" data-rough style={{ padding: 12 }}>
            <div className="brief__eyebrow">PAYLOAD · SLACK</div>
            <div style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--ink-3)", marginBottom: 6 }}>channel</div>
            <div style={{ display: "flex", alignItems: "center", gap: 8, padding: 6, border: "1.25px solid var(--line)", borderRadius: 6, marginBottom: 10, fontFamily: "var(--sketch)", fontSize: 12 }}>#sales <span style={{ marginLeft: "auto", color: "var(--ink-3)" }}>change</span></div>
            <div style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--ink-3)", marginBottom: 6 }}>message</div>
            <div style={{ background: "var(--paper-2)", borderRadius: 6, padding: 10, fontFamily: "var(--sketch)", fontSize: 12, lineHeight: 1.45 }}>
              "Contract approval — Acme GmbH. Marta wants the draft by Friday. Pricing approved. I'll send today."
            </div>
            <div style={{ display: "flex", gap: 6, marginTop: 10, flexWrap: "wrap" }}>
              <Chip tone="ghost">+ link to thread</Chip>
              <Chip tone="ghost">+ pdf</Chip>
            </div>
          </div>
          <div>
            <div style={{ fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--ink-3)", textTransform: "uppercase", marginBottom: 6 }}>What leaves your Mac</div>
            <ul style={{ paddingLeft: 18, margin: 0, fontFamily: "var(--sketch)", fontSize: 12, color: "var(--ink-2)", lineHeight: 1.5 }}>
              <li>summary text (above)</li>
              <li>thread link (re:box://)</li>
              <li>nothing else.</li>
            </ul>
          </div>
          <Btn primary style={{ justifyContent: "center" }}>Approve & send to Slack</Btn>
        </div>
      </Panel>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>C4 · Side drawer</Note>
    <Note style={{ top: 0, right: 36 }} right>persistent drawer, never overlay.<br/>shows <span className="u-scribble">exactly</span> what leaves.</Note>
  </div>
);

Object.assign(window, { ActionC1, ActionC2, ActionC3, ActionC4 });
