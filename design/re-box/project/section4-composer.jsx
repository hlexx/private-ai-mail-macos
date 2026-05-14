// Re:Box — Section 4: Composer / reply variations
// How does AI surface during reply drafting?

// ---------- D1 · Inline composer at bottom of thread
const ComposerD1 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="Inline composer">
      <Panel style={{ width: 220 }}><SidebarContents /></Panel>
      <Panel inset style={{ flex: 1, display: "flex", flexDirection: "column" }}>
        <div style={{ flex: 1, overflow: "hidden", opacity: 0.7 }}>
          <ReadingContents briefInline />
        </div>
        <div style={{ borderTop: "1.25px dashed var(--line-soft)", padding: 16, background: "var(--paper-2)" }}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8 }}>
            <span className="brief__eyebrow" style={{ margin: 0 }}>REPLY TO MARTA</span>
            <div style={{ display: "flex", gap: 6 }}>
              <Chip tone="ghost">tone · warm</Chip>
              <Chip tone="ghost">length · short</Chip>
              <Chip tone="citron">DRAFTED BY LOCAL AI</Chip>
            </div>
          </div>
          <div style={{ background: "var(--paper)", border: "1.25px solid var(--line)", borderRadius: 10, padding: "12px 14px", minHeight: 110, fontFamily: "var(--sketch)", fontSize: 13, lineHeight: 1.5 }}>
            Hi Marta — yes, contract draft will be in your inbox <span style={{ background: "var(--citron)", padding: "0 3px", borderRadius: 3 }}>before Friday EOD</span>. I'll attach the redlines too so legal can move on Monday.<br /><br />
            Thanks,<br/>Alex
          </div>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: 10 }}>
            <div style={{ display: "flex", gap: 6 }}>
              <Btn ghost sm>regenerate</Btn>
              <Btn ghost sm>shorter</Btn>
              <Btn ghost sm>more formal</Btn>
            </div>
            <div style={{ display: "flex", gap: 8 }}>
              <Btn ghost sm>save draft</Btn>
              <Btn primary>Send</Btn>
            </div>
          </div>
        </div>
      </Panel>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>D1 · Inline composer</Note>
    <Note style={{ top: 0, right: 36 }} right>composer docks under thread.<br/>AI is just <span className="u-scribble">in the box</span>.</Note>
    <Arrow x={760} y={620} dx={-60} dy={-30} />
    <Note small style={{ top: 600, left: 660 }}>citron = AI-generated text</Note>
  </div>
);

// ---------- D2 · Floating composer overlay
const ComposerD2 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="Floating composer">
      <Panel style={{ width: 220 }}><SidebarContents /></Panel>
      <Panel inset style={{ flex: 1, position: "relative" }}>
        <div style={{ opacity: 0.35 }}>
          <ReadingContents briefInline />
        </div>
        <div className="glass" data-rough style={{ position: "absolute", bottom: 30, left: "50%", transform: "translateX(-50%)", width: 640, padding: 18, boxShadow: "0 8px 32px rgba(28,24,20,0.18)" }}>
          <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 10 }}>
            <span style={{ fontFamily: "var(--sketch)", fontSize: 14 }}>Reply to Marta · Acme</span>
            <span style={{ fontFamily: "var(--mono)", fontSize: 10, color: "var(--ink-3)" }}>esc · stash</span>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 5, marginBottom: 12 }}>
            <span className="placeholder-line" />
            <span className="placeholder-line" />
            <span className="placeholder-line placeholder-line--mid" />
            <span className="placeholder-line placeholder-line--short" />
          </div>
          <div style={{ display: "flex", justifyContent: "space-between", borderTop: "1px dashed var(--line-soft)", paddingTop: 10 }}>
            <div style={{ display: "flex", gap: 6 }}>
              <Chip tone="citron">◉ LOCAL DRAFT</Chip>
              <Chip tone="ghost">⌖ msg 1 · pdf p.2</Chip>
            </div>
            <Btn primary>Send</Btn>
          </div>
        </div>
        <span className="region-label" style={{ top: 14, left: 22 }}>thread behind glass</span>
      </Panel>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>D2 · Floating overlay</Note>
    <Note style={{ top: 0, right: 36 }} right>can be dragged, stashed,<br/>or popped to a window</Note>
  </div>
);

// ---------- D3 · Multiple draft cards — pick one
const ComposerD3 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="3 drafts — pick one">
      <Panel style={{ width: 220 }}><SidebarContents /></Panel>
      <Panel inset style={{ flex: 1 }}>
        <div style={{ padding: "16px 24px" }}>
          <div style={{ fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--ink-3)", textTransform: "uppercase", marginBottom: 4 }}>Reply to Marta — contract approval</div>
          <div style={{ fontFamily: "Instrument Serif, serif", fontStyle: "italic", fontSize: 26, marginBottom: 4 }}>Three ways to answer</div>
          <div style={{ fontFamily: "var(--sketch)", fontSize: 13, color: "var(--ink-2)", marginBottom: 18 }}>Local AI drafted these from the brief + your reply history. Pick, edit, or regenerate.</div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12 }}>
            {[
              { tag: "WARM", chosen: true, body: "Hi Marta — yes, draft will be in your inbox before Friday EOD. Attaching redlines for legal." },
              { tag: "DIRECT", body: "Marta, draft Friday EOD. Will include redlines." },
              { tag: "ASK 1 DAY", body: "Marta, can we push to Monday AM? Will give legal a cleaner window. Otherwise Friday works." },
            ].map((d, i) => (
              <div key={i} style={{ border: "1.5px " + (d.chosen ? "solid var(--citron)" : "solid var(--line)"), borderRadius: "12px 10px 14px 10px", padding: 14, background: d.chosen ? "color-mix(in oklch, var(--citron) 12%, var(--paper))" : "var(--paper)", position: "relative" }}>
                <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 8 }}>
                  <span className="chip" style={{ background: d.chosen ? "var(--citron)" : "var(--paper)" }}>{d.tag}</span>
                  <span style={{ fontFamily: "var(--mono)", fontSize: 9, color: "var(--ink-3)" }}>{i + 1}/3</span>
                </div>
                <div style={{ fontFamily: "var(--sketch)", fontSize: 13, lineHeight: 1.45 }}>{d.body}</div>
                <div style={{ marginTop: 14, display: "flex", gap: 6 }}>
                  <Btn ghost sm>edit</Btn>
                  <Btn sm primary={d.chosen}>{d.chosen ? "use this" : "pick"}</Btn>
                </div>
              </div>
            ))}
          </div>
          <div style={{ marginTop: 18, display: "flex", gap: 8, alignItems: "center" }}>
            <Btn ghost sm>↻ regenerate all</Btn>
            <span style={{ fontFamily: "var(--sketch)", fontSize: 12, color: "var(--ink-3)" }}>· model: phi-3 · 0.9s · on-device</span>
          </div>
        </div>
      </Panel>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>D3 · Pick a draft</Note>
    <Note style={{ top: 0, right: 36 }} right>3 distinct voices.<br/>committing forces a <span className="u-scribble">choice</span>, not a tweak.</Note>
    <Arrow x={420} y={335} dx={20} dy={-30} />
  </div>
);

// ---------- D4 · Side-by-side draft + evidence
const ComposerD4 = () => (
  <div style={{ position: "relative", width: 1240, height: 760, padding: 36 }}>
    <Win title="Draft + evidence side by side">
      <Panel style={{ width: 220 }}><SidebarContents /></Panel>
      <Panel style={{ width: 380, background: "var(--paper)" }}>
        <div className="panel__head"><span>EVIDENCE · what the AI used</span></div>
        <div style={{ padding: 14, display: "flex", flexDirection: "column", gap: 10 }}>
          {[
            { eyebrow: "⌖ MSG 1 · Mon 09:12", body: "\"…send the contract draft by Friday so we can sign next week\"" },
            { eyebrow: "⌖ MSG 3 · Tue 11:42", body: "\"Friday EOD would be ideal, otherwise we miss the legal window\"" },
            { eyebrow: "⌖ CONTRACT.PDF · p.2", body: "\"Term: 12 months · Pricing: per quote 2025-Q2\"" },
          ].map((e, i) => (
            <div key={i} style={{ border: "1.25px solid var(--line-softer)", borderRadius: 10, padding: 10, background: "var(--paper-2)" }}>
              <div style={{ fontFamily: "var(--mono)", fontSize: 9, letterSpacing: "0.14em", color: "var(--ink-3)", textTransform: "uppercase", marginBottom: 6 }}>{e.eyebrow}</div>
              <div style={{ fontFamily: "var(--sketch)", fontSize: 12, fontStyle: "italic", lineHeight: 1.4, color: "var(--ink-2)" }}>{e.body}</div>
            </div>
          ))}
          <div style={{ marginTop: 4, fontFamily: "var(--sketch)", fontSize: 12, color: "var(--ink-3)" }}>tap any quote → jump to source</div>
        </div>
      </Panel>
      <Panel inset style={{ flex: 1 }}>
        <div className="panel__head"><span>DRAFT REPLY</span><span>0.88 confidence</span></div>
        <div style={{ padding: 18, display: "flex", flexDirection: "column", gap: 12 }}>
          <div style={{ fontFamily: "Instrument Serif, serif", fontStyle: "italic", fontSize: 22 }}>Re: Contract approval — Acme GmbH</div>
          <div style={{ fontFamily: "var(--sketch)", fontSize: 14, lineHeight: 1.55 }}>
            Hi Marta,<br/><br/>
            Yes — <span style={{ background: "color-mix(in oklch, var(--citron) 60%, transparent)", padding: "0 3px" }}>contract draft will be in your inbox before Friday EOD <sup style={{ fontFamily: "var(--mono)", fontSize: 9 }}>⌖1</sup></span>.
            I'll include the redlines so <span style={{ background: "color-mix(in oklch, var(--citron) 60%, transparent)", padding: "0 3px" }}>legal has the window Monday <sup style={{ fontFamily: "var(--mono)", fontSize: 9 }}>⌖2</sup></span>.
            Term stays at 12 months <sup style={{ fontFamily: "var(--mono)", fontSize: 9 }}>⌖3</sup>; pricing as quoted.<br/><br/>
            Thanks,<br/>Alex
          </div>
          <div style={{ display: "flex", gap: 6, alignItems: "center", marginTop: 4 }}>
            <Chip tone="citron">◉ LOCAL AI</Chip>
            <Chip tone="ghost">3 citations</Chip>
            <span style={{ flex: 1 }} />
            <Btn ghost sm>edit</Btn>
            <Btn primary>Send</Btn>
          </div>
        </div>
      </Panel>
    </Win>
    <Note big style={{ top: 0, left: 36 }}>D4 · Draft + evidence</Note>
    <Note style={{ top: 0, right: 36 }} right>every AI claim cites its source.<br/>auditable.</Note>
    <Note small style={{ top: 480, left: 730, transform: "rotate(-2deg)" }}>⌖ = jump to evidence</Note>
    <Arrow x={920} y={490} dx={-40} dy={20} />
  </div>
);

Object.assign(window, { ComposerD1, ComposerD2, ComposerD3, ComposerD4 });
