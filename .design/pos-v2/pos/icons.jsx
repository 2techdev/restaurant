// Minimal stroked icons — 24x24 viewBox, 1.6 stroke.
const _i = (d, extra = null) => (p) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
    {typeof d === 'string' ? <path d={d} /> : d}
    {extra}
  </svg>
);

const Icons = {
  Tables: _i(<><rect x="3" y="6" width="18" height="10" rx="2"/><path d="M7 16v3M17 16v3"/></>),
  Sale: _i(<><path d="M4 7h16l-1.5 11a2 2 0 0 1-2 1.8H7.5a2 2 0 0 1-2-1.8L4 7Z"/><path d="M9 7V5a3 3 0 0 1 6 0v2"/></>),
  Bill: _i(<><path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Z"/><path d="M9 8h6M9 12h6M9 16h4"/></>),
  Cash: _i(<><rect x="3" y="7" width="18" height="10" rx="2"/><circle cx="12" cy="12" r="2.2"/></>),
  Menu: _i(<><path d="M4 6h16M4 12h16M4 18h10"/></>),
  Report: _i(<><path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/></>),
  Cancel: _i(<><circle cx="12" cy="12" r="9"/><path d="M8 8l8 8M16 8l-8 8"/></>),
  Print: _i(<><path d="M6 9V3h12v6"/><rect x="4" y="9" width="16" height="8" rx="2"/><path d="M7 17v4h10v-4"/></>),
  Gift: _i(<><rect x="3" y="8" width="18" height="5" rx="1"/><path d="M12 8v13M3 13v8h18v-8M8 8a2 2 0 1 1 0-4c2 0 4 4 4 4M16 8a2 2 0 1 0 0-4c-2 0-4 4-4 4"/></>),
  Lock: _i(<><rect x="4" y="11" width="16" height="9" rx="2"/><path d="M8 11V8a4 4 0 1 1 8 0v3"/></>),
  Pay: _i(<><rect x="2" y="6" width="20" height="12" rx="2"/><path d="M2 10h20"/></>),
  Search: _i(<><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></>),
  Refresh: _i(<><path d="M3 12a9 9 0 0 1 15-6.7L21 8M21 4v4h-4"/><path d="M21 12a9 9 0 0 1-15 6.7L3 16M3 20v-4h4"/></>),
  Gear: _i(<><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></>),
  User: _i(<><circle cx="12" cy="8" r="4"/><path d="M4 20a8 8 0 0 1 16 0"/></>),
  Plus: _i("M12 5v14M5 12h14"),
  Minus: _i("M5 12h14"),
  Split: _i(<><path d="M4 6h5l6 12h5M4 18h5l2-4M19 6h-4"/><path d="M19 4l2 2-2 2M19 14l2 2-2 2"/></>),
  Card: _i(<><rect x="2" y="6" width="20" height="12" rx="2"/><path d="M2 10h20M6 15h4"/></>),
  Banknote: _i(<><rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="2.2"/><path d="M6 10v4M18 10v4"/></>),
  Check: _i("M4 12l5 5L20 6"),
  Close: _i("M6 6l12 12M18 6 6 18"),
  Grid: _i(<><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></>),
  List: _i(<><path d="M8 6h13M8 12h13M8 18h13"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/></>),
  Flame: _i("M12 3s4 4 4 8a4 4 0 1 1-8 0c0-2 1-3 2-4 0 2 2 3 2 3s0-4 0-7Z"),
  Note: _i(<><path d="M5 4h10l4 4v12H5z"/><path d="M14 4v4h5"/></>),
  Sparkle: _i("M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M6 18l2.5-2.5M15.5 8.5 18 6"),
  ArrowRight: _i("M5 12h14M13 6l6 6-6 6"),
  Chevron: _i("M9 6l6 6-6 6"),
  Sun: _i(<><circle cx="12" cy="12" r="4"/><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M5.6 18.4 7 17M17 7l1.4-1.4"/></>),
  Moon: _i("M20 15a8 8 0 1 1-11-11 7 7 0 0 0 11 11Z"),
  Percent: _i(<><circle cx="7" cy="7" r="2"/><circle cx="17" cy="17" r="2"/><path d="M19 5 5 19"/></>),
  Trash: _i(<><path d="M4 7h16M9 7V4h6v3M7 7l1 13h8l1-13M10 11v6M14 11v6"/></>),
  Tag: _i(<><path d="M12 3H5a2 2 0 0 0-2 2v7l9 9 9-9-9-9Z"/><circle cx="8" cy="8" r="1.5"/></>),
  Users: _i(<><circle cx="9" cy="8" r="3"/><path d="M3 20a6 6 0 0 1 12 0"/><circle cx="17" cy="9" r="2.5"/><path d="M15 20a5 5 0 0 1 6 0"/></>),
  Clock: _i(<><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/></>),
  Qr: _i(<><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3zM20 14v3M14 20h3M20 20h1"/></>),
  Receipt: _i(<><path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Z"/><path d="M9 7h6M9 11h6M9 15h4"/></>),
};

window.Icons = Icons;
