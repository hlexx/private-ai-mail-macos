/* global React */
const { useState } = React;

function Icon({ name, size = 14 }) {
  const s = size;
  const stroke = { stroke: "currentColor", strokeWidth: 1.6, fill: "none", strokeLinecap: "round", strokeLinejoin: "round" };
  const paths = {
    inbox: <><path d="M3 13l3-7h12l3 7v6H3z" {...stroke} /><path d="M3 13h5l1 2h6l1-2h5" {...stroke} /></>,
    reply: <><path d="M9 14L4 9l5-5" {...stroke} /><path d="M4 9h9a7 7 0 017 7v2" {...stroke} /></>,
    clock: <><circle cx="12" cy="12" r="8" {...stroke} /><path d="M12 8v4l3 2" {...stroke} /></>,
    paperclip: <path d="M21 11l-8.5 8.5a5 5 0 01-7-7L14 4a3.5 3.5 0 015 5l-8.5 8.5a2 2 0 01-3-3L15 7" {...stroke} />,
    check: <path d="M5 12l5 5L20 7" {...stroke} />,
    star: <path d="M12 3l3 6 6 .9-4.5 4.3 1 6.3L12 17.5 6.5 20.5l1-6.3L3 9.9 9 9z" {...stroke} />,
    send: <><path d="M21 3L3 11l7 2 2 7z" {...stroke} /><path d="M21 3l-11 11" {...stroke} /></>,
    archive: <><rect x="3" y="5" width="18" height="4" rx="1" {...stroke} /><path d="M5 9v10h14V9M10 13h4" {...stroke} /></>,
    search: <><circle cx="11" cy="11" r="6" {...stroke} /><path d="M20 20l-4-4" {...stroke} /></>,
    sparkle: <><path d="M12 3l1.8 4.5L18 9l-4.2 1.5L12 15l-1.8-4.5L6 9l4.2-1.5z" {...stroke} /><path d="M19 16l.7 1.8L21 18.5l-1.3.7L19 21l-.7-1.8L17 18.5l1.3-.7z" {...stroke} /></>,
    filter: <path d="M4 5h16l-6 8v6l-4-2v-4z" {...stroke} />,
    settings: <><circle cx="12" cy="12" r="3" {...stroke} /><path d="M19.4 15a1.7 1.7 0 00.3 1.8l.1.1a2 2 0 11-2.8 2.8l-.1-.1a1.7 1.7 0 00-1.8-.3 1.7 1.7 0 00-1 1.5V21a2 2 0 11-4 0v-.1a1.7 1.7 0 00-1-1.5 1.7 1.7 0 00-1.8.3l-.1.1a2 2 0 11-2.8-2.8l.1-.1a1.7 1.7 0 00.3-1.8 1.7 1.7 0 00-1.5-1H3a2 2 0 110-4h.1A1.7 1.7 0 004.6 9a1.7 1.7 0 00-.3-1.8L4.2 7A2 2 0 117 4.2l.1.1a1.7 1.7 0 001.8.3H9a1.7 1.7 0 001-1.5V3a2 2 0 114 0v.1a1.7 1.7 0 001 1.5 1.7 1.7 0 001.8-.3l.1-.1A2 2 0 1119.8 7l-.1.1a1.7 1.7 0 00-.3 1.8V9a1.7 1.7 0 001.5 1H21a2 2 0 110 4h-.1a1.7 1.7 0 00-1.5 1z" {...stroke} /></>,
    arrowUp: <path d="M12 19V5M5 12l7-7 7 7" {...stroke} />,
    x: <path d="M6 6l12 12M18 6L6 18" {...stroke} />,
    pencil: <><path d="M4 20h4l10-10-4-4L4 16z" {...stroke} /><path d="M14 6l4 4" {...stroke} /></>,
    cmd: <path d="M9 9h6v6H9zM6 6h3v3H6a2 2 0 110-4zm12 0h-3v3h3a2 2 0 100-4zM6 15h3v-3H6a2 2 0 100 4zm12 0h-3v-3h3a2 2 0 110 4z" {...stroke} />,
    lock: <><rect x="5" y="11" width="14" height="9" rx="2" {...stroke} /><path d="M8 11V7a4 4 0 018 0v4" {...stroke} /></>,
    trash: <><path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13" {...stroke} /></>,
    eye: <><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z" {...stroke} /><circle cx="12" cy="12" r="3" {...stroke} /></>,
    sun: <><circle cx="12" cy="12" r="4" {...stroke} /><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" {...stroke} /></>,
    moon: <path d="M21 13A9 9 0 0111 3a7 7 0 1010 10z" {...stroke} />
  };
  return <svg width={s} height={s} viewBox="0 0 24 24">{paths[name] || null}</svg>;
}

window.Icon = Icon;
