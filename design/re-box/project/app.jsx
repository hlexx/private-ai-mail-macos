// Re:Box wireframes — entry component
// Wires the design canvas, tweaks panel, and the 4 sections together.

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "color":   "color",
  "rough":   true,
  "annotations": true
}/*EDITMODE-END*/;

function App() {
  const [tweaks, setTweak] = useTweaks(TWEAK_DEFAULTS);

  // Mode affects document attributes that styles.css keys off of.
  React.useEffect(() => {
    document.body.dataset.color = tweaks.color === "bw" ? "bw" : "color";
    document.body.dataset.annotations = tweaks.annotations ? "on" : "off";
    document.body.dataset.rough = tweaks.rough ? "on" : "off";
    // hide all .note + .arrow when annotations off
    const style = document.getElementById("__annotations-style") || (() => {
      const s = document.createElement("style"); s.id = "__annotations-style"; document.head.appendChild(s); return s;
    })();
    style.textContent = tweaks.annotations
      ? ""
      : ".note,.arrow,.circled,.region-label{display:none!important}";
  }, [tweaks]);

  return (
    <>
      <DesignCanvas>
        <DCSection id="inbox" title="1 · Inbox layout" subtitle="Where does the AI brief live? How dense is the list?">
          <DCArtboard id="a1" label="A1 · Classic 3-pane" width={1240} height={760}><InboxA1 /></DCArtboard>
          <DCArtboard id="a2" label="A2 · AI rail right"  width={1240} height={760}><InboxA2 /></DCArtboard>
          <DCArtboard id="a3" label="A3 · Editorial 2-pane" width={1240} height={760}><InboxA3 /></DCArtboard>
          <DCArtboard id="a4" label="A4 · Command-driven"  width={1240} height={760}><InboxA4 /></DCArtboard>
        </DCSection>

        <DCSection id="brief" title="2 · AI brief placement" subtitle="Same thread, four different homes for the brief.">
          <DCArtboard id="b1" label="B1 · Banner"     width={1240} height={760}><BriefB1 /></DCArtboard>
          <DCArtboard id="b2" label="B2 · Floating"   width={1240} height={760}><BriefB2 /></DCArtboard>
          <DCArtboard id="b3" label="B3 · Inline expandable" width={1240} height={760}><BriefB3 /></DCArtboard>
          <DCArtboard id="b4" label="B4 · Split brief/thread" width={1240} height={760}><BriefB4 /></DCArtboard>
        </DCSection>

        <DCSection id="actions" title="3 · Send to Slack / Notion / HubSpot / SF" subtitle="How does the action surface — sheet, chips, palette, drawer?">
          <DCArtboard id="c1" label="C1 · Bottom sheet"      width={1240} height={760}><ActionC1 /></DCArtboard>
          <DCArtboard id="c2" label="C2 · Inline chip morph" width={1240} height={760}><ActionC2 /></DCArtboard>
          <DCArtboard id="c3" label="C3 · Command palette"   width={1240} height={760}><ActionC3 /></DCArtboard>
          <DCArtboard id="c4" label="C4 · Side drawer"       width={1240} height={760}><ActionC4 /></DCArtboard>
        </DCSection>

        <DCSection id="composer" title="4 · Composer & reply" subtitle="Where AI drafts live during reply, and how evidence is cited.">
          <DCArtboard id="d1" label="D1 · Inline composer"   width={1240} height={760}><ComposerD1 /></DCArtboard>
          <DCArtboard id="d2" label="D2 · Floating overlay"  width={1240} height={760}><ComposerD2 /></DCArtboard>
          <DCArtboard id="d3" label="D3 · Pick a draft"      width={1240} height={760}><ComposerD3 /></DCArtboard>
          <DCArtboard id="d4" label="D4 · Draft + evidence"  width={1240} height={760}><ComposerD4 /></DCArtboard>
        </DCSection>
      </DesignCanvas>

      <TweaksPanel title="Tweaks">
        <TweakSection title="Wireframe style">
          <TweakRadio
            label="Color"
            value={tweaks.color}
            onChange={(v) => setTweak("color", v)}
            options={[
              { value: "color", label: "B&W + citron" },
              { value: "bw",    label: "Pure B&W" },
            ]}
          />
          <TweakToggle
            label="Rough corners"
            description="Slightly asymmetric border-radius on cards & buttons."
            value={tweaks.rough}
            onChange={(v) => setTweak("rough", v)}
          />
          <TweakToggle
            label="Annotations"
            description="Handwritten notes and arrows layered over the wireframes."
            value={tweaks.annotations}
            onChange={(v) => setTweak("annotations", v)}
          />
        </TweakSection>
      </TweaksPanel>
    </>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
