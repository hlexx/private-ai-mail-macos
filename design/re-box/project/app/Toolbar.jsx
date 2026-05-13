/* global React, Icon */
function Toolbar({ accounts, activeAccount, onSwitchAccount, onCompose, onOpenCommand }) {
  const a = accounts.find(x => x.id === activeAccount) || accounts[0];
  const [theme, setTheme] = React.useState(() => {
    try { return localStorage.getItem("rb-theme") || document.documentElement.getAttribute("data-theme") || "dark"; } catch (_) { return "dark"; }
  });
  React.useEffect(() => {
    document.documentElement.setAttribute("data-theme", theme);
    try { localStorage.setItem("rb-theme", theme); } catch (_) {}
  }, [theme]);
  const isLight = theme === "light";
  return (
    <div className="rb-toolbar">
      <div className="rb-toolbar-left">
        <div className="rb-traffic"><span className="l r" /><span className="l y" /><span className="l g" /></div>
        <button className="rb-account-switch" onClick={() => {
          const i = accounts.findIndex(x => x.id === activeAccount);
          onSwitchAccount(accounts[(i + 1) % accounts.length].id);
        }}>
          <span className="d" style={{ background: a.color }} />
          <span>{a.label}</span>
          <span style={{ color: "var(--fg-3)" }}>▾</span>
        </button>
      </div>
      <div className="rb-toolbar-right">
        <div className="rb-search" onClick={onOpenCommand}>
          <Icon name="search" />
          <input placeholder="Search or ask Re:Box (last week, contracts, due Friday…)" onClick={e => e.stopPropagation()} />
          <span className="kbd">⌘K</span>
        </div>
        <div className="rb-tb-actions">
          <button className="rb-iconbtn" title="Filter"><Icon name="filter" /></button>
          <button className="rb-iconbtn" title={isLight ? "Switch to dark" : "Switch to light"} onClick={() => setTheme(isLight ? "dark" : "light")}>
            <Icon name={isLight ? "moon" : "sun"} />
          </button>
          <button className="rb-iconbtn" title="Settings"><Icon name="settings" /></button>
          <button className="rb-iconbtn" title="Compose" onClick={onCompose}><Icon name="pencil" /></button>
        </div>
      </div>
    </div>
  );
}
window.Toolbar = Toolbar;
