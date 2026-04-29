const { useState, useEffect, useCallback } = React;

function App() {
  const [active, setActive] = useState('sale');
  const [mode, setMode] = useState('takeaway');
  const [activeCat, setActiveCat] = useState('haupt');
  const [query, setQuery] = useState('');
  const [order, setOrder] = useState(INITIAL_ORDER);
  const [payOpen, setPayOpen] = useState(false);
  const [tablesOpen, setTablesOpen] = useState(false);
  const [sheet, setSheet] = useState(null); // { gid, lid }
  const [toasts, setToasts] = useState([]);

  // Tweaks
  const initialTweaks = window.__TWEAKS__ || { palette: 'core', images: false };
  const [palette, setPaletteState] = useState(initialTweaks.palette || 'core');
  const [images, setImagesState] = useState(!!initialTweaks.images);
  const [tweaksOpen, setTweaksOpen] = useState(false);

  useEffect(() => {
    document.documentElement.setAttribute('data-palette', palette);
  }, [palette]);
  useEffect(() => {
    document.documentElement.setAttribute('data-images', images ? 'on' : 'off');
    window.__IMG_ON__ = images;
  }, [images]);

  const setPalette = (p) => {
    setPaletteState(p);
    try { window.parent.postMessage({ type: '__edit_mode_set_keys', edits: { palette: p } }, '*'); } catch (e) {}
  };
  const setImages = (v) => {
    setImagesState(v);
    try { window.parent.postMessage({ type: '__edit_mode_set_keys', edits: { images: v } }, '*'); } catch (e) {}
  };

  useEffect(() => {
    const onMsg = (e) => {
      const d = e?.data;
      if (!d) return;
      if (d.type === '__activate_edit_mode') setTweaksOpen(true);
      if (d.type === '__deactivate_edit_mode') setTweaksOpen(false);
    };
    window.addEventListener('message', onMsg);
    try { window.parent.postMessage({ type: '__edit_mode_available' }, '*'); } catch(e) {}
    return () => window.removeEventListener('message', onMsg);
  }, []);

  const setGuests = (g) => setOrder(o => ({ ...o, guests: g }));

  const toast = useCallback((msg) => {
    const id = Math.random().toString(36).slice(2);
    setToasts(t => [...t, { id, msg }]);
    setTimeout(() => setToasts(t => t.filter(x => x.id !== id)), 1800);
  }, []);

  const addToOrder = (product) => {
    setOrder(o => {
      const gangs = [...o.gangs];
      const activeIdx = gangs.findIndex(g => g.active);
      let idx = activeIdx;
      if (idx === -1) idx = gangs.length - 1;
      let gang = gangs[idx];
      if (gang.sent) {
        const n = gangs.length + 1;
        gang = { id: 'g' + Math.random().toString(36).slice(2,6), label: `Gang ${n}`, sent:false, active:true, items: [] };
        gangs.forEach(g => g.active = false);
        gangs.push(gang);
        idx = gangs.length - 1;
      }
      const existing = gang.items.find(it => it.itemId === product.id && !it.sent && !it.note);
      if (existing) {
        gang.items = gang.items.map(it => it === existing ? { ...it, qty: it.qty + 1 } : it);
      } else {
        gang.items = [...gang.items, { id: 'l' + Math.random().toString(36).slice(2,6), itemId: product.id, qty: 1, price: product.price }];
      }
      gangs[idx] = gang;
      return { ...o, gangs };
    });
    toast(`${product.name} hinzugefügt`);
  };

  const total = order.gangs.reduce((s,g) => s + g.items.reduce((a,i) => a + i.qty*i.price, 0), 0);
  const positions = order.gangs.reduce((s,g) => s + g.items.reduce((a,i) => a + i.qty, 0), 0);

  const onPay = (method) => { setPayOpen(true); };
  const onPayDone = (method) => {
    setPayOpen(false);
    toast(`Bezahlung ${method === 'cash' ? 'bar' : method === 'card' ? 'Karte' : 'TWINT'} bestätigt`);
    setTimeout(() => {
      setOrder({
        ticket: '#0' + Math.floor(9002 + Math.random()*98),
        mode, table: 'Neuer Bon',
        guests: 1,
        gangs: [{ id: 'g1', label: 'Gang 1', sent: false, active: true, items: [] }]
      });
    }, 400);
  };

  // ----- Action sheet (long-press on line) -----
  const onLinePress = (gid, lid) => setSheet({ gid, lid });
  const sheetLine = sheet ? order.gangs.find(g => g.id === sheet.gid)?.items.find(l => l.id === sheet.lid) : null;
  const sheetProduct = sheetLine ? ITEMS.find(i => i.id === sheetLine.itemId) : null;
  const sheetQty = (d) => {
    if (!sheet) return;
    setOrder(o => ({
      ...o,
      gangs: o.gangs.map(g => g.id !== sheet.gid ? g : {
        ...g,
        items: g.items.flatMap(it => {
          if (it.id !== sheet.lid) return [it];
          const q = it.qty + d;
          if (q <= 0) return [];
          return [{ ...it, qty: q }];
        })
      })
    }));
    // close if removed
    const cur = order.gangs.find(g => g.id === sheet.gid)?.items.find(l => l.id === sheet.lid);
    if (cur && cur.qty + d <= 0) setSheet(null);
  };
  const sheetRemove = () => {
    if (!sheet) return;
    setOrder(o => ({
      ...o,
      gangs: o.gangs.map(g => g.id !== sheet.gid ? g : { ...g, items: g.items.filter(it => it.id !== sheet.lid) })
    }));
    setSheet(null);
    toast('Position entfernt');
  };
  const sheetNote = () => { setSheet(null); toast('Notiz hinzufügen…'); };
  const sheetDisc = () => { setSheet(null); toast('Rabatt…'); };
  const sheetSplit = () => { setSheet(null); toast('Position teilen…'); };

  // ----- Rail nav -----
  const onRailChange = (id) => {
    setActive(id);
    if (id === 'tables') setTablesOpen(true);
  };
  const onPickTable = (t) => {
    setTablesOpen(false);
    setActive('sale');
    setMode('dinein');
    setOrder(o => ({ ...o, table: `Tisch ${t.num}`, ticket: '#T' + String(t.num).padStart(3, '0') }));
    toast(`Tisch ${t.num} geöffnet`);
  };

  const onNew = () => {
    setOrder({
      ticket: '#0' + Math.floor(9002 + Math.random()*98),
      mode, table: 'Neuer Bon',
      guests: 1,
      gangs: [{ id: 'g1', label: 'Gang 1', sent: false, active: true, items: [] }]
    });
    toast('Neuer Bon gestartet');
  };

  const onClose = () => toast('Bon geschlossen');

  return (
    <>
      <div className="app">
        <Rail active={active} onChange={onRailChange} />
        <Topbar
          ticket={order.ticket}
          mode={mode} setMode={setMode}
          guests={order.guests} setGuests={setGuests}
          query={query} setQuery={setQuery}
          user="Admin"
        />
        <OrderPanel order={order} setOrder={setOrder} onOpenPay={onPay} onToast={toast} onLinePress={onLinePress} />
        <div className="menu" data-screen-label="Menü">
          <CategoryList activeCat={activeCat} setActiveCat={setActiveCat} onAdd={addToOrder} total={total} onPay={onPay} />
          <ItemsGrid activeCat={activeCat} query={query} order={order} onAdd={addToOrder} />
          <QuickBar onAdd={addToOrder} />
        </div>
        <Footer total={total} positions={positions} gangs={order.gangs.length} mode={mode} guests={order.guests}
                onSplit={() => toast('Rechnung teilen…')} onPay={onPay} onNew={onNew} onClose={onClose} />
      </div>

      <TweaksPanel open={tweaksOpen} palette={palette} setPalette={setPalette} images={images} setImages={setImages} />

      <PayScreen open={payOpen} order={order} total={total} onClose={() => setPayOpen(false)} onDone={onPayDone} />
      <TablesScreen open={tablesOpen} onClose={() => { setTablesOpen(false); setActive('sale'); }} onPick={onPickTable} />
      <ActionSheet
        open={!!sheet}
        line={sheetLine}
        product={sheetProduct}
        onClose={() => setSheet(null)}
        onQty={sheetQty}
        onRemove={sheetRemove}
        onNote={sheetNote}
        onDiscount={sheetDisc}
        onSplit={sheetSplit}
      />

      <div className="toasts" aria-live="polite">
        {toasts.map(t => <div key={t.id} className="toast">{t.msg}</div>)}
      </div>
    </>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
