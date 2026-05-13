/* global React, Toolbar, Sidebar, ThreadList, ReadingPane, ActionSheet, Composer, RB_ACCOUNTS, RB_FOLDERS, RB_THREADS */
const { useState: useStateA, useEffect } = React;

function App() {
  const [account, setAccount] = useStateA("g1");
  const [folder, setFolder] = useStateA("inbox");
  const [filter, setFilter] = useStateA("all");
  const [activeThread, setActiveThread] = useStateA("t1");
  const [sheet, setSheet] = useStateA(false);
  const [composer, setComposer] = useStateA(false);

  const thread = RB_THREADS.find(t => t.id === activeThread);

  useEffect(() => {
    const h = (e) => {
      if (e.key === "Escape") { setSheet(false); setComposer(false); }
      if ((e.metaKey || e.ctrlKey) && e.key === "k") { e.preventDefault(); setSheet(s => !s); }
    };
    window.addEventListener("keydown", h);
    return () => window.removeEventListener("keydown", h);
  }, []);

  return (
    <div className="rb-window" data-screen-label="01 Inbox · Re:Box">
      <Toolbar
        accounts={RB_ACCOUNTS}
        activeAccount={account}
        onSwitchAccount={setAccount}
        onCompose={() => setComposer(true)}
        onOpenCommand={() => setSheet(true)}
      />
      <div className="rb-panes">
        <Sidebar folders={RB_FOLDERS} activeFolder={folder} onSelect={setFolder} accounts={RB_ACCOUNTS} />
        <ThreadList
          threads={RB_THREADS}
          activeId={activeThread}
          onSelect={setActiveThread}
          accounts={RB_ACCOUNTS}
          filter={filter}
          setFilter={setFilter}
        />
        <ReadingPane
          thread={thread}
          onDraft={() => setComposer(true)}
          onSchedule={() => setSheet(true)}
          onLog={() => setSheet(true)}
        />
      </div>
      {sheet && <ActionSheet thread={thread} onClose={() => setSheet(false)} />}
      {composer && <Composer onClose={() => setComposer(false)} />}
    </div>
  );
}

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);
