/* global React, Icon */
function ThreadList({ threads, activeId, onSelect, accounts, filter, setFilter }) {
  const filters = [
    { id: "all", label: "All" },
    { id: "reply", label: "Needs reply" },
    { id: "due", label: "Has deadline" },
    { id: "att", label: "Attachments" },
    { id: "ai", label: "AI handled" }
  ];
  const matches = (t, f) => f === "all" || (t.chips || []).some(c => c.kind === f);
  const visible = threads.filter(t => matches(t, filter));
  const renderChip = (c, i) => {
    switch (c.kind) {
      case "due":
        return (
          <span key={i} className={"rb-sig rb-sig-due" + (c.urgent ? " urgent" : "")} title={`Due ${c.label}`}>
            <Icon name="clock" size={11} />
            <span className="rb-sig-t">{c.label}</span>
          </span>
        );
      case "reply":
        return (
          <span key={i} className="rb-sig rb-sig-reply" title={`Reply by ${c.label}`}>
            <Icon name="reply" size={11} />
            <span className="rb-sig-t">{c.label}</span>
          </span>
        );
      case "att":
        return (
          <span key={i} className="rb-sig rb-sig-att" title={`${c.pages} page${c.pages > 1 ? "s" : ""} attached`}>
            <Icon name="paperclip" size={11} />
            <span className="rb-sig-t">{c.pages}</span>
          </span>
        );
      case "ai":
        return (
          <span key={i} className="rb-sig rb-sig-ai" title="AI handled">
            <span className="rb-sig-dot" />
            <span className="rb-sig-t">{c.label || "AI"}</span>
          </span>
        );
      case "logged":
        return (
          <span key={i} className="rb-sig rb-sig-logged" title={`Logged to ${c.target}`}>
            <Icon name="check" size={11} />
            <span className="rb-sig-t">{c.target}</span>
          </span>
        );
      case "cc":
        return <span key={i} className="rb-sig rb-sig-ghost" title="External CC">{c.label}</span>;
      case "cal":
        return (
          <span key={i} className="rb-sig rb-sig-cal" title={`Event ${c.label}`}>
            <Icon name="clock" size={11} />
            <span className="rb-sig-t">{c.label}</span>
          </span>
        );
      case "paid":
        return <span key={i} className="rb-sig rb-sig-paid" title="Paid">{c.label}</span>;
      default:
        return null;
    }
  };
  return (
    <section className="rb-list">
      <div className="rb-list-header">
        <span className="h">Inbox</span>
        <span className="meta">{visible.length} threads · 2 need reply</span>
      </div>
      <div className="rb-list-filters">
        {filters.map(f => (
          <button key={f.id} className={"rb-fc" + (filter === f.id ? " on" : "")} onClick={() => setFilter(f.id)}>{f.label}</button>
        ))}
      </div>
      {visible.map(t => {
        const a = accounts.find(x => x.id === t.account);
        return (
          <div key={t.id} className={"rb-row" + (t.unread ? " unread" : "") + (t.id === activeId ? " active" : "")} onClick={() => onSelect(t.id)}>
            <div className="av" style={{ background: t.fromColor, color: t.fromTextColor || "#fff" }}>{t.fromHandle}</div>
            <div className="body">
              <div className="top">
                <span className="from">{t.unread && <span className="udot" />}{t.from}</span>
                <span className="acct" style={{ color: a?.color }}>{a?.label.split(" · ")[1] || ""}</span>
              </div>
              <span className="subj">{t.subject}</span>
              <span className="preview">{t.preview}</span>
              {(t.chips || []).length > 0 && (
                <div className="rb-sigs">
                  {(t.chips || []).map(renderChip)}
                </div>
              )}
            </div>
            <div className="meta">
              <span className="time">{t.time}</span>
            </div>
          </div>
        );
      })}
    </section>
  );
}
window.ThreadList = ThreadList;
