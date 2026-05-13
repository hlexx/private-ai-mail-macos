/* global React, Icon */
function Sidebar({ folders, activeFolder, onSelect, accounts }) {
  return (
    <aside className="rb-sidebar">
      <div className="rb-sb-section">Mail</div>
      {folders.map(f => (
        <div key={f.id} className={"rb-sb-item" + (f.id === activeFolder ? " active" : "")} onClick={() => onSelect(f.id)}>
          <Icon name={f.icon} />
          <span>{f.name}</span>
          {f.count != null && <span className="count">{f.count}</span>}
        </div>
      ))}
      <div className="rb-sb-section" style={{ marginTop: 8 }}>Accounts</div>
      {accounts.map(a => (
        <div key={a.id} className="rb-sb-acct">
          <span className="d" style={{ background: a.color }} />
          <span className="email" title={a.email}>{a.email}</span>
        </div>
      ))}
      <div className="rb-sb-section" style={{ marginTop: 8 }}>Privacy</div>
      <div className="rb-sb-footer">
        <span className="rb-localpill"><span className="dot" />Local AI · M-series</span>
      </div>
    </aside>
  );
}
window.Sidebar = Sidebar;
