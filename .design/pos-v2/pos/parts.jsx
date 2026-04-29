// Reusable UI parts for the POS.
const { useState, useMemo, useEffect, useRef } = React;

const chf = (n) => n.toLocaleString('de-CH', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

function Rail({ active, onChange }) {
  const items = [
    { id: 'tables', name: 'Tische',  icon: Icons.Tables },
    { id: 'sale',   name: 'Verkauf', icon: Icons.Sale },
    { id: 'bill',   name: 'Bon',     icon: Icons.Bill },
    { id: 'cash',   name: 'Kasse',   icon: Icons.Cash },
    { id: 'menu',   name: 'Menü',    icon: Icons.Menu },
    { id: 'report', name: 'Bericht', icon: Icons.Report },
  ];
  const bottom = [
    { id: 'cancel', name: 'Stornieren', icon: Icons.Cancel, danger: true },
    { id: 'print',  name: 'Drucken',    icon: Icons.Print },
    { id: 'comp',   name: 'Gratis',     icon: Icons.Gift },
    { id: 'lock',   name: 'Sperren',    icon: Icons.Lock },
  ];
  return (
    <aside className="rail" aria-label="Navigation">
      <div className="logo" title="Gastro POS">
        <div className="mark">G</div>
      </div>
      {items.map(it => {
        const Ico = it.icon;
        return (
          <button key={it.id} className={`rail-btn ${active === it.id ? 'active' : ''}`} onClick={() => onChange(it.id)}>
            <Ico />
            <span>{it.name}</span>
          </button>
        );
      })}
      <div className="rail-spacer" />
      {bottom.map(it => {
        const Ico = it.icon;
        return (
          <button key={it.id} className={`rail-btn ${it.danger ? 'danger' : ''}`} title={it.name}>
            <Ico />
            <span>{it.name}</span>
          </button>
        );
      })}
    </aside>
  );
}

function Topbar({ ticket, mode, setMode, guests, setGuests, query, setQuery, user }) {
  return (
    <header className="topbar">
      <div className="brand-lockup">
        <span className="name">Gastro<em>Core</em></span>
        <span className="tag">POS · v2</span>
      </div>
      <div className="ticket-meta">
        <span className="t-id">TICKET {ticket}</span>
        <span className="t-sub">Terminal 01 · {user}</span>
      </div>

      <div className="mode-switch" role="tablist" aria-label="Servicemodus">
        {[
          { id: 'dinein',   label: 'Im Haus' },
          { id: 'takeaway', label: 'Takeaway' },
          { id: 'counter',  label: 'Theke' },
        ].map(m => (
          <button key={m.id} className={mode === m.id ? 'on' : ''} onClick={() => setMode(m.id)} role="tab" aria-selected={mode === m.id}>
            {m.label}
          </button>
        ))}
      </div>

      <div className="spacer" />

      <div className="search">
        <Icons.Search />
        <input placeholder="Produkt oder Bon suchen…" value={query} onChange={e => setQuery(e.target.value)} />
        <kbd>⌘K</kbd>
      </div>

      <button className="icon-btn" title="Aktualisieren"><Icons.Refresh /></button>
      <button className="icon-btn" title="Einstellungen"><Icons.Gear /></button>

      <div className="user">
        <div className="av">A</div>
        <span className="name">Admin</span>
      </div>
    </header>
  );
}

function OrderPanel({ order, setOrder, onOpenPay, onToast, onLinePress }) {
  const activeGangId = order.gangs.find(g => g.active)?.id ?? order.gangs[0].id;
  const pressTimer = useRef(null);
  const pressFired = useRef(false);
  const startPress = (gid, lid) => {
    pressFired.current = false;
    pressTimer.current = setTimeout(() => {
      pressFired.current = true;
      onLinePress?.(gid, lid);
    }, 380);
  };
  const endPress = () => { if (pressTimer.current) { clearTimeout(pressTimer.current); pressTimer.current = null; } };

  const setActiveGang = (gid) => {
    setOrder(o => ({ ...o, gangs: o.gangs.map(g => ({ ...g, active: g.id === gid })) }));
  };

  const addGang = () => {
    setOrder(o => {
      const n = o.gangs.length + 1;
      const nid = 'g' + (Math.random().toString(36).slice(2,6));
      return { ...o, gangs: [...o.gangs.map(g => ({...g, active:false})), { id: nid, label: `Gang ${n}`, sent: false, active: true, items: [] }] };
    });
  };

  const toggleSelect = (gid, lid) => {
    setOrder(o => ({
      ...o,
      gangs: o.gangs.map(g => g.id !== gid ? g : { ...g, items: g.items.map(it => it.id === lid ? { ...it, selected: !it.selected } : { ...it, selected: false }) })
    }));
  };
  const changeQty = (gid, lid, d) => {
    setOrder(o => ({
      ...o,
      gangs: o.gangs.map(g => g.id !== gid ? g : { ...g, items: g.items.flatMap(it => {
        if (it.id !== lid) return [it];
        const q = it.qty + d;
        if (q <= 0) return [];
        return [{ ...it, qty: q }];
      }) })
    }));
  };
  const removeLine = (gid, lid) => {
    setOrder(o => ({ ...o, gangs: o.gangs.map(g => g.id !== gid ? g : { ...g, items: g.items.filter(it => it.id !== lid) }) }));
  };
  const sendGang = (gid) => {
    setOrder(o => ({ ...o, gangs: o.gangs.map(g => g.id !== gid ? g : { ...g, sent: true, items: g.items.map(it => ({ ...it, sent: true })) }) }));
    onToast?.('An Küche gesendet');
  };

  // Totals
  const subtotal = useMemo(() => order.gangs.reduce((s, g) => s + g.items.reduce((a,i) => a + i.qty * i.price, 0), 0), [order]);
  const mwst = subtotal - subtotal / 1.081; // 8.1% CH VAT inclusive
  const net = subtotal - mwst;

  return (
    <section className="order" aria-label="Bestellung">
      <div className="order-head">
        <div className="row">
          <h2>Bestellung</h2>
          <div className="guests">
            <span>Gäste</span>
            <div className="stepper">
              <button onClick={() => setGuests?.(Math.max(1, order.guests - 1))} aria-label="Minus"><Icons.Minus /></button>
              <span className="val mono">{order.guests}</span>
              <button onClick={() => setGuests?.(order.guests + 1)} aria-label="Plus"><Icons.Plus /></button>
            </div>
          </div>
        </div>
        <div className="gang-tabs">
          {order.gangs.map(g => (
            <button key={g.id} className={activeGangId === g.id ? 'on' : ''} onClick={() => setActiveGang(g.id)}>
              <span>{g.label}</span>
              <span className="g-count">{g.items.length}</span>
            </button>
          ))}
          <button className="add" onClick={addGang} aria-label="Gang hinzufügen" title="Gang hinzufügen"><Icons.Plus /></button>
        </div>
      </div>

      <div className="order-list">
        {order.gangs.map(g => (
          <div key={g.id} className="gang-section" data-screen-label={`Gang ${g.label}`}>
            <div className="gang-h">
              <span>{g.label} · {g.items.length} Pos.</span>
              <div className="ops">
                {g.sent
                  ? <span className="chip sent">Gesendet</span>
                  : <>
                      <button className="chip" onClick={() => setOrder(o => ({...o, gangs: o.gangs.map(x => x.id === g.id ? {...x, held:!x.held} : x)}))}>Halten</button>
                      <button className="chip send" onClick={() => sendGang(g.id)}>Senden</button>
                    </>
                }
              </div>
            </div>
            {g.items.length === 0 && <div className="empty-line">Leer — Artikel aus dem Menü hinzufügen</div>}
            {g.items.map(li => {
              const p = ITEMS.find(i => i.id === li.itemId);
              if (!p) return null;
              return (
                <div key={li.id}
                     className={`line-item ${li.selected?'selected':''} ${li.sent?'sent':''}`}
                     onPointerDown={() => startPress(g.id, li.id)}
                     onPointerUp={(e) => { endPress(); if (!pressFired.current) toggleSelect(g.id, li.id); }}
                     onPointerLeave={endPress}
                     onPointerCancel={endPress}
                     onContextMenu={(e) => { e.preventDefault(); onLinePress?.(g.id, li.id); }}>
                  <div className="qty">{li.qty}×</div>
                  <div>
                    <div className="title">{p.name}</div>
                    {li.note && <div className="note">{li.note}</div>}
                  </div>
                  <div className="price mono">{chf(li.qty * li.price)}</div>
                </div>
              );
            })}
          </div>
        ))}
      </div>

      <div className="order-foot">
        <div className="row-kv"><span className="k">Netto</span><span className="v">CHF {chf(net)}</span></div>
        <div className="row-kv"><span className="k">MWST (8.1 %, inkl.)</span><span className="v">CHF {chf(mwst)}</span></div>
        <div className="row-kv total"><span className="k">Zu bezahlen</span><span className="v">CHF {chf(subtotal)}</span></div>
      </div>
    </section>
  );
}

function CategoryList({ activeCat, setActiveCat, onAdd, total, onPay }) {
  return (
    <nav className="cats" aria-label="Kategorien">
      <div className="cat-grid">
        {CATEGORIES.map(c => (
          <button key={c.id} className={`cat ${activeCat === c.id ? 'on' : ''}`} onClick={() => setActiveCat(c.id)}
            style={{'--cat':`var(--c-${c.id})`, '--cat-wk':`var(--c-${c.id}-wk)`}}>
            <span className="name">{c.name}</span>
            <span className="n mono">{c.count}</span>
          </button>
        ))}
      </div>
      <div className="cats-footer">
        <button className="btn lg accent" style={{width:'100%', height:56, fontSize:15, justifyContent:'center'}} onClick={() => onPay && onPay('cash')}>
          <Icons.Banknote /> Zur Kasse · CHF {chf(total || 0)}
        </button>
      </div>
    </nav>
  );
}

function QuickBar({ onAdd }) {
  const top = [...(QUICK_TOP || []), ...(QUICK_BAR || [])].slice(0, 8);
  return (
    <section className="schnell" aria-label="Schnellmenü">
      <div className="schnell-grid">
        {top.map(q => {
          const p = ITEMS.find(i => i.id === q.itemId);
          const cat = p?.cat || 'drink';
          return (
            <button key={q.id} className="schnell-tile" onClick={() => p && onAdd(p)}
              style={{'--cat':`var(--c-${cat})`, '--cat-wk':`var(--c-${cat}-wk)`}}>
              <span className="schnell-name">{q.label}</span>
              <span className="schnell-price"><span className="c">CHF</span>{chf(q.price)}</span>
            </button>
          );
        })}
      </div>
    </section>
  );
}

function ItemsGrid({ activeCat, query, order, onAdd }) {
  const cartCounts = useMemo(() => {
    const m = {};
    order.gangs.forEach(g => g.items.forEach(li => { m[li.itemId] = (m[li.itemId] ?? 0) + li.qty; }));
    return m;
  }, [order]);

  const catName = CATEGORIES.find(c => c.id === activeCat)?.name ?? 'Menü';

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return ITEMS.filter(i => (i.cat === activeCat) && (!q || i.name.toLowerCase().includes(q) || (i.sub||'').toLowerCase().includes(q)));
  }, [activeCat, query]);

  const [view, setView] = useState('grid');

  return (
    <div className="items-wrap">
      <div className="items" role="list">
        {filtered.map(p => {
          const n = cartCounts[p.id] || 0;
          return (
            <button key={p.id} className={`p-card ${n>0?'in':''}`} role="listitem" onClick={() => onAdd(p)}
              style={{'--cat':`var(--c-${p.cat})`, '--cat-wk':`var(--c-${p.cat}-wk)`}}>
              {(window.__IMG_ON__) && (
                <div className="p-thumb" data-hint={(CAT_TINTS[p.cat]?.hint) || 'Foto'} style={{'--th-a': CAT_TINTS[p.cat]?.a, '--th-b': CAT_TINTS[p.cat]?.b}} />
              )}
              <div className="p-body">
                <div>
                  <div className="p-name">{p.name}</div>
                  {p.sub && <div className="p-sub">{p.sub}</div>}
                </div>
                <div className="p-foot">
                  <span className="p-price"><span className="p-currency">CHF</span>{chf(p.price)}</span>
                </div>
              </div>
              {n > 0 && <span className="in-cart mono">{n}</span>}
            </button>
          );
        })}
        {filtered.length === 0 && (
          <div style={{gridColumn:'1/-1', padding: 40, textAlign:'center', color:'var(--ink-3)', fontSize: 13}}>
            Keine Treffer für „{query}"
          </div>
        )}
      </div>
    </div>
  );
}

function Footer({ total, positions, gangs, mode, guests, onSplit, onPay, onNew, onClose }) {
  const modeLabel = mode === 'dinein' ? 'Im Haus' : mode === 'counter' ? 'Theke' : 'Takeaway';
  return (
    <footer className="footer">
      <div className="left">
        <button className="btn danger" onClick={onClose}><Icons.Close /> Schliessen</button>
        <button className="btn ghost" onClick={onNew}><Icons.Plus /> Neuer Bon</button>
        <button className="btn ghost" title="An Küche senden"><Icons.Flame /> Senden</button>
      </div>
    </footer>
  );
}

function TweaksPanel({ open, palette, setPalette, images, setImages }) {
  return (
    <div className={`tweaks-panel ${open ? 'open' : ''}`}>
      <h4>Tweaks</h4>
      <div style={{display:'flex', flexDirection:'column', gap: 14}}>
        <div>
          <div style={{fontSize:10.5, color:'var(--ink-3)', marginBottom:7, letterSpacing:'0.1em', textTransform:'uppercase', fontWeight:600}}>Palette</div>
          <div className="segswitch">
            <button className={palette==='core'?'on':''} onClick={() => setPalette('core')}>Ivory</button>
            <button className={palette==='midnight'?'on':''} onClick={() => setPalette('midnight')}>Midnight</button>
          </div>
        </div>
        <div>
          <div style={{fontSize:10.5, color:'var(--ink-3)', marginBottom:7, letterSpacing:'0.1em', textTransform:'uppercase', fontWeight:600}}>Produktbilder</div>
          <div className="segswitch">
            <button className={!images?'on':''} onClick={() => setImages(false)}>Aus</button>
            <button className={images?'on':''} onClick={() => setImages(true)}>An</button>
          </div>
        </div>
      </div>
    </div>
  );
}

function PayModal({ open, total, onClose, onDone, method }) {
  const [picked, setPicked] = useState('cash');
  useEffect(() => { if (open && method) setPicked(method); }, [open, method]);
  if (!open) return null;
  const tiles = [
    { id: 'cash',  label: 'Bar',       amt: total },
    { id: 'card',  label: 'Karte',     amt: total },
    { id: 'twint', label: 'TWINT',     amt: total },
  ];
  return (
    <div className="modal-scrim open" onClick={onClose}>
      <div className="modal" onClick={e => e.stopPropagation()}>
        <h3>Zahlung</h3>
        <p>Wählen Sie eine Zahlungsart. Gesamt: <span className="mono">CHF {chf(total)}</span></p>
        <div className="body">
          <div className="pay-tiles">
            {tiles.map(t => (
              <button key={t.id} className={`pay-tile ${picked===t.id?'on':''}`} onClick={() => setPicked(t.id)}>
                {t.label}
                <span className="amt">CHF {chf(t.amt)}</span>
              </button>
            ))}
          </div>
        </div>
        <div className="foot">
          <button className="btn ghost" onClick={onClose}>Abbrechen</button>
          <button className="btn accent" onClick={() => onDone(picked)}><Icons.Check /> Bestätigen</button>
        </div>
      </div>
    </div>
  );
}

function ActionSheet({ open, line, product, onClose, onQty, onRemove, onNote, onDiscount, onSplit }) {
  if (!open || !line || !product) return null;
  return (
    <div className="sheet-scrim open" onClick={onClose}>
      <div className="sheet" onClick={e => e.stopPropagation()}>
        <div className="sheet-grab" />
        <div className="sheet-head">
          <div>
            <div className="t">{product.name}</div>
            {product.sub && <div style={{fontSize:12, color:'var(--ink-3)', marginTop:2}}>{product.sub}</div>}
          </div>
          <div className="p mono">CHF {chf(line.qty * line.price)}</div>
        </div>
        <div className="sheet-qty">
          <button className="minus" onClick={() => onQty(-1)} aria-label="Reduzieren">−</button>
          <span className="big">{line.qty}</span>
          <button className="plus" onClick={() => onQty(1)} aria-label="Erhöhen">+</button>
        </div>
        <div className="sheet-acts">
          <button onClick={onNote}><Icons.Note /><span>Notiz</span></button>
          <button onClick={onDiscount}><Icons.Percent /><span>Rabatt</span></button>
          <button onClick={onSplit}><Icons.Split /><span>Teilen</span></button>
          <button className="del" onClick={onRemove}><Icons.Trash /><span>Entfernen</span></button>
        </div>
        <button className="sheet-close" onClick={onClose}>Fertig</button>
      </div>
    </div>
  );
}

function PayScreen({ open, order, total, onClose, onDone }) {
  const [method, setMethod] = useState('cash');
  const [tender, setTender] = useState('');
  useEffect(() => { if (open) { setMethod('cash'); setTender(''); } }, [open]);
  if (!open) return null;

  const tenderNum = tender ? parseFloat(tender) : 0;
  const change = Math.max(0, tenderNum - total);
  const press = (k) => {
    if (k === '⌫') { setTender(t => t.slice(0, -1)); return; }
    if (k === '.') { if (tender.includes('.')) return; setTender(t => (t || '0') + '.'); return; }
    // digit
    if (tender.includes('.')) {
      const [, dec] = tender.split('.');
      if (dec && dec.length >= 2) return;
    }
    if (tender === '0' && k !== '.') { setTender(k); return; }
    setTender(t => t + k);
  };
  const quickAmts = [total, Math.ceil(total / 10) * 10, Math.ceil(total / 20) * 20, Math.ceil(total / 50) * 50, Math.ceil(total / 100) * 100]
    .filter((v, i, a) => a.indexOf(v) === i).slice(0, 5);

  const methods = [
    { id: 'cash',  label: 'Bar',      icon: Icons.Banknote },
    { id: 'card',  label: 'Karte',    icon: Icons.Card },
    { id: 'twint', label: 'TWINT',    icon: Icons.Qr },
  ];
  const allGangItems = order.gangs.flatMap(g => g.items.map(li => ({ ...li, gangLabel: g.label })));

  return (
    <div className={`pay-screen ${open?'open':''}`} data-screen-label="Zahlung">
      <div className="pay-head">
        <div style={{display:'flex', alignItems:'baseline', gap:16}}>
          <h2>Zahlung <em>abschliessen</em></h2>
          <span className="pay-ticket">TICKET {order.ticket} · {allGangItems.reduce((s,i)=>s+i.qty,0)} Positionen</span>
        </div>
        <button className="close" onClick={onClose}><Icons.Close /> Abbrechen</button>
      </div>

      <div className="pay-left">
        <div className="pay-total">
          <span className="k">Zu bezahlen</span>
          <span className="v"><span className="cur">CHF</span>{chf(total)}</span>
        </div>

        <div>
          <div className="pay-tender-h" style={{marginBottom:10}}>Zahlungsart</div>
          <div className="pay-methods">
            {methods.map(m => {
              const Ico = m.icon;
              return (
                <button key={m.id} className={`pay-method ${method===m.id?'on':''}`} onClick={() => setMethod(m.id)}>
                  <Ico /><span>{m.label}</span>
                </button>
              );
            })}
          </div>
        </div>

        <div style={{display:'flex', flexDirection:'column', gap:10}}>
          <div className="pay-tender-h">Einzug</div>
          <div className="tender-input">
            <span className="cur">CHF</span>
            <span className="val">{tender || '0.00'}</span>
          </div>
          <div className="tender-quick">
            {quickAmts.map(v => (
              <button key={v} onClick={() => setTender(v.toFixed(2))}>{v.toFixed(0)}.–</button>
            ))}
          </div>
          {method === 'cash' && tenderNum >= total && total > 0 && (
            <div className="change-row">
              <span className="k">Rückgeld</span>
              <span className="v">CHF {chf(change)}</span>
            </div>
          )}
        </div>

        <div style={{marginTop:'auto', display:'flex', gap:8, paddingTop:12, borderTop:'1px solid var(--line)'}}>
          <button className="btn ghost" style={{flex:1}}><Icons.Receipt /> Beleg drucken</button>
          <button className="btn ghost" style={{flex:1}}><Icons.Split /> Rechnung teilen</button>
        </div>
      </div>

      <div className="pay-right">
        <div className="keypad-h">Ziffernblock</div>
        <div className="keypad">
          {['1','2','3','4','5','6','7','8','9','.','0','⌫'].map(k => (
            <button key={k} className={k==='⌫'?'back':''} onClick={() => press(k)}>{k}</button>
          ))}
        </div>
        <button className="pay-confirm" onClick={() => onDone(method)}>
          <Icons.Check /> {method === 'cash' ? `Bar ${tenderNum >= total ? 'kassieren' : 'bestätigen'}` : method === 'card' ? 'Karte aktivieren' : 'TWINT QR anzeigen'}
        </button>
      </div>
    </div>
  );
}

// Deterministic floor plan — rendered once, re-used across renders.
const TABLE_AREAS = [
  { id: 'all',     name: 'Alle',           ct: 24 },
  { id: 'saal',    name: 'Hauptsaal',      ct: 12 },
  { id: 'terr',    name: 'Terrasse',       ct: 8 },
  { id: 'bar',     name: 'Barbereich',     ct: 4 },
  { id: 'priv',    name: 'Privatraum',     ct: 2 },
];

const FLOOR = [
  // Hauptsaal — left cluster of rectangular 4-tops and a 6-top
  { id: 1,  area:'saal', num: 1,  seats: 2, x:  40, y:  40, w: 100, h: 78,  status:'busy',     total: 48.50, dur: '1h 12' },
  { id: 2,  area:'saal', num: 2,  seats: 4, x: 170, y:  40, w: 120, h: 78,  status:'busy',     total: 94.00, dur: '0h 42' },
  { id: 3,  area:'saal', num: 3,  seats: 4, x: 320, y:  40, w: 120, h: 78,  status:'free',     total: 0 },
  { id: 4,  area:'saal', num: 4,  seats: 6, x:  40, y: 148, w: 260, h: 82,  status:'bill',     total: 212.50, dur: '2h 05' },
  { id: 5,  area:'saal', num: 5,  seats: 4, x: 320, y: 148, w: 120, h: 82,  status:'reserved', total: 0, dur: '19:30' },
  { id: 6,  area:'saal', num: 6,  seats: 2, x:  40, y: 256, w: 100, h: 78,  status:'free',     total: 0 },
  { id: 7,  area:'saal', num: 7,  seats: 4, x: 170, y: 256, w: 120, h: 78,  status:'busy',     total: 63.00, dur: '0h 18' },
  { id: 8,  area:'saal', num: 8,  seats: 4, x: 320, y: 256, w: 120, h: 78,  status:'free',     total: 0 },
  { id: 9,  area:'saal', num: 9,  seats: 2, x:  40, y: 362, w: 100, h: 68,  status:'free',     total: 0 },
  { id: 10, area:'saal', num: 10, seats: 2, x: 170, y: 362, w: 100, h: 68,  status:'busy',     total: 27.50, dur: '0h 08' },
  { id: 11, area:'saal', num: 11, seats: 2, x: 300, y: 362, w: 100, h: 68,  status:'free',     total: 0 },
  { id: 12, area:'saal', num: 12, seats: 8, x: 460, y: 148, w: 130, h: 82,  status:'reserved', total: 0, dur: '20:00' },

  // Terrasse — round tables at right
  { id: 13, area:'terr', num: 21, seats: 2, x: 610, y:  40, w: 80,  h: 80, round:true, status:'busy',     total: 34.00, dur: '0h 55' },
  { id: 14, area:'terr', num: 22, seats: 2, x: 706, y:  40, w: 80,  h: 80, round:true, status:'free',     total: 0 },
  { id: 15, area:'terr', num: 23, seats: 4, x: 610, y: 140, w: 96,  h: 96, round:true, status:'busy',     total: 76.50, dur: '1h 30' },
  { id: 16, area:'terr', num: 24, seats: 4, x: 720, y: 140, w: 96,  h: 96, round:true, status:'bill',     total: 118.00, dur: '1h 50' },
  { id: 17, area:'terr', num: 25, seats: 2, x: 610, y: 252, w: 80,  h: 80, round:true, status:'free',     total: 0 },
  { id: 18, area:'terr', num: 26, seats: 2, x: 706, y: 252, w: 80,  h: 80, round:true, status:'free',     total: 0 },
  { id: 19, area:'terr', num: 27, seats: 6, x: 610, y: 348, w: 180, h: 80,  status:'busy',     total: 142.50, dur: '0h 35' },
  { id: 20, area:'terr', num: 28, seats: 2, x: 610, y: 448, w: 80,  h: 60, round:true, status:'free',     total: 0 },

  // Bar — stools
  { id: 21, area:'bar', num: 'B1', seats: 1, x: 40,  y: 462, w: 60, h: 60, round:true, status:'busy',  total: 12.00, dur:'0h 06' },
  { id: 22, area:'bar', num: 'B2', seats: 1, x: 110, y: 462, w: 60, h: 60, round:true, status:'busy',  total:  5.50, dur:'0h 02' },
  { id: 23, area:'bar', num: 'B3', seats: 1, x: 180, y: 462, w: 60, h: 60, round:true, status:'free',  total: 0 },
  { id: 24, area:'bar', num: 'B4', seats: 1, x: 250, y: 462, w: 60, h: 60, round:true, status:'free',  total: 0 },
];

function TablesScreen({ open, onClose, onPick }) {
  const [area, setArea] = useState('all');
  if (!open) return null;
  const shown = FLOOR.filter(t => area === 'all' || t.area === area);
  const counts = {
    free: FLOOR.filter(t => t.status==='free').length,
    busy: FLOOR.filter(t => t.status==='busy').length,
    bill: FLOOR.filter(t => t.status==='bill').length,
    reserved: FLOOR.filter(t => t.status==='reserved').length,
  };
  return (
    <div className={`tables-screen ${open?'open':''}`} data-screen-label="Tischplan">
      <div className="tables-head">
        <div style={{display:'flex', alignItems:'baseline', gap:18}}>
          <h2>Tisch<em>plan</em></h2>
          <span style={{font:'500 12px/1 "JetBrains Mono", monospace', color:'var(--ink-3)'}}>
            {counts.busy} belegt · {counts.bill} Rechnung · {counts.reserved} reserviert · {counts.free} frei
          </span>
        </div>
        <div style={{display:'flex', gap:8}}>
          <button className="btn ghost"><Icons.Users /> Reservation</button>
          <button className="btn ghost" onClick={onClose}><Icons.Close /> Schliessen</button>
        </div>
      </div>

      <aside className="tables-areas">
        <h5>Bereiche</h5>
        {TABLE_AREAS.map(a => (
          <button key={a.id} className={`area-btn ${area===a.id?'on':''}`} onClick={() => setArea(a.id)}>
            <span>{a.name}</span><span className="ct">{a.ct}</span>
          </button>
        ))}
        <div style={{height:18}} />
        <h5>Legende</h5>
        <div style={{padding:'6px 10px', fontSize:12, color:'var(--ink-3)', display:'flex', flexDirection:'column', gap:8}}>
          <div><span style={{display:'inline-block', width:10, height:10, borderRadius:3, background:'var(--surface)', border:'2px solid var(--line-strong)', verticalAlign:-1, marginRight:8}}/>Frei</div>
          <div><span style={{display:'inline-block', width:10, height:10, borderRadius:3, background:'var(--c-haupt-wk)', border:'2px solid var(--c-haupt)', verticalAlign:-1, marginRight:8}}/>Belegt</div>
          <div><span style={{display:'inline-block', width:10, height:10, borderRadius:3, background:'var(--accent-weak)', border:'2px solid var(--accent)', verticalAlign:-1, marginRight:8}}/>Rechnung</div>
          <div><span style={{display:'inline-block', width:10, height:10, borderRadius:3, background:'oklch(96% 0.05 65)', border:'2px solid var(--warn)', verticalAlign:-1, marginRight:8}}/>Reserviert</div>
        </div>
      </aside>

      <section className="tables-floor">
        <div className="floor">
          {/* labels for zones */}
          <div style={{position:'absolute', top:14, left:14, font:'500 10px/1 "Inter Tight", sans-serif', letterSpacing:'0.16em', textTransform:'uppercase', color:'var(--ink-4)'}}>Hauptsaal</div>
          <div style={{position:'absolute', top:14, left:606, font:'500 10px/1 "Inter Tight", sans-serif', letterSpacing:'0.16em', textTransform:'uppercase', color:'var(--ink-4)'}}>Terrasse</div>
          <div style={{position:'absolute', top:440, left:14, font:'500 10px/1 "Inter Tight", sans-serif', letterSpacing:'0.16em', textTransform:'uppercase', color:'var(--ink-4)'}}>Bar</div>

          {/* dividers */}
          <div style={{position:'absolute', top: 20, left: 590, width: 1, height: 500, background:'var(--line)'}}/>
          <div style={{position:'absolute', top: 448, left: 20, width: 560, height: 1, background:'var(--line)'}}/>

          {shown.map(t => (
            <button key={t.id}
              className={`t-node ${t.status} ${t.round?'round':''}`}
              style={{left: t.x, top: t.y, width: t.w, height: t.h}}
              onClick={() => onPick?.(t)}>
              {t.dur && <span className="dur">{t.dur}</span>}
              <span className="num">{t.num}</span>
              <span className="seats">{t.seats} P.</span>
              {t.total > 0 && <span className="total">CHF {chf(t.total)}</span>}
            </button>
          ))}
        </div>
      </section>
    </div>
  );
}

Object.assign(window, { Rail, Topbar, OrderPanel, CategoryList, QuickBar, ItemsGrid, Footer, TweaksPanel, PayModal, ActionSheet, PayScreen, TablesScreen, chf });
