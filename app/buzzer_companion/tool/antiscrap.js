// Anti-scrap sur la banque entiere, versions SERVIES : une retouche > remplace
// la ligne au-dessus, un retrait - la supprime. C'est ce que le joueur entend.
const fs = require('fs');
const base = 'D:/dev/Arduino/Buzzer/app/buzzer_companion/tool/questions/';

const norm = s => s.toLowerCase()
  .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
  .replace(/[\u2019']/g, ' ')
  .replace(/[^a-z0-9 ]/g, ' ')
  .replace(/\s+/g, ' ').trim();

const vides = new Set(('le la les un une des du de d au aux a et ou en dans sur sous pour par avec sans que qui quoi dont ' +
  'est sont fait font se s on n ne pas plus tout toute tous toutes son sa ses leur leurs ce cet cette ces il elle ils elles ' +
  'comment appelle quel quelle quels quelles combien quand pourquoi y t l dit dire deux trois').split(' '));

const servies = [];
for (const f of fs.readdirSync(base).filter(x => x.endsWith('.txt'))) {
  const cat = f.replace('.txt', '');
  const lignes = fs.readFileSync(base + f, 'utf8').split(/\r?\n/);
  for (let i = 0; i < lignes.length; i++) {
    const t = lignes[i].trim();
    if (!t || /^[#=]/.test(t)) continue;
    if (/^[>-]/.test(t)) continue;                 // traites avec la ligne du dessus
    const p = t.split('|');
    if (p.length !== 4) continue;
    const suite = (lignes[i + 1] || '').trim();
    if (suite.startsWith('-')) continue;           // retiree du catalogue
    if (suite.startsWith('>')) {
      const r = suite.slice(1).trim().split('|');
      servies.push({ cat, q: r[0], r: r[1], retouchee: true });
    } else {
      servies.push({ cat, q: p[0], r: p[1], retouchee: false });
    }
  }
}

const echos = [];
for (const l of servies) {
  const q = norm(l.q), r = norm(l.r);
  const mots = r.split(' ').filter(w => w.length > 3 && !vides.has(w));
  if (!mots.length) continue;
  const donnes = mots.filter(w => q.includes(w.slice(0, Math.max(5, w.length - 2))));
  if (donnes.length === mots.length) echos.push(l);
}

console.log(servies.length + ' questions servies\n');
console.log('== la reponse entiere est deja dans la question : ' + echos.length);
for (const e of echos) console.log('   [' + e.cat + ']' + (e.retouchee ? ' (retouchee)' : '') + ' ' + e.q + '  ->  ' + e.r);
