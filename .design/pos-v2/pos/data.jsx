// Menu data — Gastro Core restaurant menu.
// Tint palettes per category for image-variant placeholder thumbnails.
const CAT_TINTS = {
  vor:    { a: 'oklch(88% 0.06 145)', b: 'oklch(78% 0.09 150)', hint: 'Starter' },
  salat:  { a: 'oklch(88% 0.07 130)', b: 'oklch(78% 0.10 135)', hint: 'Salat' },
  haupt:  { a: 'oklch(85% 0.08 40)',  b: 'oklch(75% 0.10 30)',  hint: 'Hauptgang' },
  pasta:  { a: 'oklch(88% 0.07 70)',  b: 'oklch(78% 0.10 60)',  hint: 'Pasta' },
  dessert:{ a: 'oklch(90% 0.05 20)',  b: 'oklch(82% 0.08 15)',  hint: 'Dessert' },
  drink:  { a: 'oklch(86% 0.06 230)', b: 'oklch(76% 0.09 235)', hint: 'Drink' },
};
const CATEGORIES = [
  { id: 'vor',      name: 'Vorspeisen',    count: 5  },
  { id: 'salat',    name: 'Salate',        count: 3  },
  { id: 'haupt',    name: 'Hauptspeisen',  count: 6  },
  { id: 'pasta',    name: 'Pasta & Pizza', count: 5  },
  { id: 'dessert',  name: 'Desserts',      count: 4  },
  { id: 'drink',    name: 'Getränke',      count: 6  },
];

// Quick buttons — shown in the sidebar top (Schnellmenü) and bottom quickbar.
// These are the items staff reach for constantly: water, coffee, bread, tip, etc.
const QUICK_TOP = [
  { id: 'min',  label: 'Wasser',    sub: '5 dl',   price: 3.50, itemId: 'min'  },
  { id: 'esp',  label: 'Espresso',  sub: 'Einfach',price: 4.00, itemId: 'esp'  },
  { id: 'cap',  label: 'Cappuccino',sub: 'Klein',  price: 5.50, itemId: 'cap', accent: true },
  { id: 'bier', label: 'Bier',      sub: 'Stange', price: 5.50, itemId: 'bier' },
];

const QUICK_BAR = [
  { id: 'min',   label: 'Wasser',     price: 3.50, itemId: 'min',  glyph: 'W' },
  { id: 'cola',  label: 'Cola',       price: 4.50, itemId: 'cola', glyph: 'C' },
  { id: 'esp',   label: 'Espresso',   price: 4.00, itemId: 'esp',  glyph: 'E', hot: true },
  { id: 'cap',   label: 'Cappuccino', price: 5.50, itemId: 'cap',  glyph: 'Ca' },
  { id: 'wein',  label: 'Hauswein',   price: 6.00, itemId: 'wein', glyph: 'W' },
  { id: 'bier',  label: 'Bier',       price: 5.50, itemId: 'bier', glyph: 'B' },
  { id: 'brus',  label: 'Brot',       price: 8.50, itemId: 'brus', glyph: 'Br' },
  { id: 'tsup',  label: 'Tagessuppe', price: 7.00, itemId: 'tsup', glyph: 'T' },
];

const ITEMS = [
  { id: 'caesar', name: 'Caesar Salat',          cat: 'salat',   price: 12.50, sub: 'mit Hähnchen' },
  { id: 'brus',   name: 'Bruschetta',            cat: 'vor',     price:  8.50 },
  { id: 'tsup',   name: 'Tagessuppe',            cat: 'vor',     price:  7.00, sub: 'Kürbis · heute' },
  { id: 'vteller',name: 'Gem. Vorspeisenteller', cat: 'vor',     price: 15.00 },
  { id: 'zges',   name: 'Zürich Geschnetzeltes', cat: 'haupt',   price: 28.50, sub: 'mit Rösti' },
  { id: 'wsch',   name: 'Wiener Schnitzel',      cat: 'haupt',   price: 26.00 },
  { id: 'rind',   name: 'Grilliertes Rindsfilet',cat: 'haupt',   price: 38.00, sub: '200g · medium' },
  { id: 'lachs',  name: 'Lachsfilet',            cat: 'haupt',   price: 32.00 },
  { id: 'carb',   name: 'Pasta Carbonara',       cat: 'pasta',   price: 19.50 },
  { id: 'burg',   name: 'Burger Classic',        cat: 'haupt',   price: 22.00, sub: 'mit Pommes' },
  { id: 'marg',   name: 'Margherita',            cat: 'pasta',   price: 16.00 },
  { id: 'quat',   name: 'Quattro Formaggi',      cat: 'pasta',   price: 19.00 },
  { id: 'prosc',  name: 'Prosciutto e Rucola',   cat: 'pasta',   price: 21.00 },
  { id: 'bolo',   name: 'Pasta Bolognese',       cat: 'pasta',   price: 19.50 },
  { id: 'tira',   name: 'Tiramisu',              cat: 'dessert', price:  9.50 },
  { id: 'crem',   name: 'Crème Brûlée',          cat: 'dessert', price:  8.50 },
  { id: 'scho',   name: 'Schokoladen-Fondue',    cat: 'dessert', price: 18.00, sub: 'für 2 Personen' },
  { id: 'apfel',  name: 'Apfelstrudel',          cat: 'dessert', price:  9.00 },
  { id: 'min',    name: 'Mineralwasser',         cat: 'drink',   price:  3.50, sub: '5 dl' },
  { id: 'cola',   name: 'Coca-Cola',             cat: 'drink',   price:  4.50 },
  { id: 'wein',   name: 'Hauswein',              cat: 'drink',   price:  6.00, sub: 'Rot · 1 dl' },
  { id: 'bier',   name: 'Bier vom Fass',         cat: 'drink',   price:  5.50 },
  { id: 'esp',    name: 'Espresso',              cat: 'drink',   price:  4.00 },
  { id: 'cap',    name: 'Cappuccino',            cat: 'drink',   price:  5.50 },
];

const INITIAL_ORDER = {
  ticket: '#09001',
  mode: 'takeaway',
  table: 'Takeaway · 1 P.',
  guests: 1,
  gangs: [
    {
      id: 'g1', label: 'Gang 1', sent: true,
      items: [
        { id: 'l1', itemId: 'marg',  qty: 1, note: 'ohne Basilikum', price: 16.00, sent: true },
        { id: 'l2', itemId: 'quat',  qty: 1, price: 19.00, sent: true },
        { id: 'l3', itemId: 'rind',  qty: 1, price: 38.00, sent: true },
        { id: 'l4', itemId: 'caesar',qty: 1, price: 12.50, sent: true },
        { id: 'l5', itemId: 'tsup',  qty: 1, price:  7.00, sent: true },
      ]
    },
    {
      id: 'g2', label: 'Gang 2', sent: false, active: true,
      items: [
        { id: 'l6', itemId: 'tira', qty: 1, price:  9.50 },
        { id: 'l7', itemId: 'crem', qty: 1, price:  8.50, selected: true },
        { id: 'l8', itemId: 'esp',  qty: 2, price:  4.00 },
      ]
    },
  ]
};

Object.assign(window, { CATEGORIES, ITEMS, INITIAL_ORDER, CAT_TINTS, QUICK_TOP, QUICK_BAR });
