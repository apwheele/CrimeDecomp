(() => {
  const state = { global: [], decomposition: [], crime: '', agency: '', start: '', end: '', threshold: 3 };
  const $ = id => document.getElementById(id);
  const parseCsv = text => {
    const rows = []; let row = [], cell = '', quoted = false;
    for (let i = 0; i < text.length; i++) {
      const ch = text[i], next = text[i + 1];
      if (ch === '"' && quoted && next === '"') { cell += '"'; i++; }
      else if (ch === '"') quoted = !quoted;
      else if (ch === ',' && !quoted) { row.push(cell); cell = ''; }
      else if ((ch === '\n' || ch === '\r') && !quoted) { if (ch === '\r' && next === '\n') i++; row.push(cell); rows.push(row); row = []; cell = ''; }
      else cell += ch;
    }
    if (cell.length || row.length) { row.push(cell); rows.push(row); }
    const headers = rows.shift().map(x => x.trim());
    return rows.filter(r => r.length > 1).map(r => Object.fromEntries(headers.map((h, i) => [h, r[i] ?? ''])));
  };
  const num = x => Number(x);
  const fmt = x => Number.isFinite(x) ? x.toFixed(2) : '—';
  const scale = (x, a, b, c, d) => c + (x - a) * (d - c) / ((b - a) || 1);
  const linePath = (rows, key, x0, x1, ymin, ymax) => rows.map((r, i) => {
    const x = scale(new Date(r.date), x0, x1, 62, 1000), y = scale(num(r[key]), ymax, ymin, 34, 286);
    return `${i ? 'L' : 'M'}${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(' ');
  const svgBase = (title, ymin, ymax, x0, x1, yLabel) => {
    let s = `<svg viewBox="0 0 1040 330" role="img"><text x="62" y="20" class="chart-title">${title}</text>`;
    [0, .25, .5, .75, 1].forEach(t => { const y = 34 + t * 252, v = ymax - t * (ymax - ymin); s += `<line x1="62" x2="1000" y1="${y}" y2="${y}" class="grid"/><text x="55" y="${y + 4}" text-anchor="end" class="axis-label">${fmt(v)}</text>`; });
    s += `<line x1="62" x2="1000" y1="286" y2="286" class="axis"/><text x="15" y="160" transform="rotate(-90 15 160)" class="axis-label">${yLabel}</text>`;
    s += `<text x="62" y="310" class="axis-label">${x0.toISOString().slice(0, 10)}</text><text x="1000" y="310" text-anchor="end" class="axis-label">${x1.toISOString().slice(0, 10)}</text>`;
    return s;
  };
  const finishSvg = (s, legend) => `${s}<text x="780" y="20" class="legend">${legend}</text></svg>`;

  function renderGlobal() {
    const rows = state.global.filter(r => r.crime_type === state.crime && (!state.start || r.date >= state.start) && (!state.end || r.date <= state.end));
    const agency = state.decomposition.filter(r => r.crime_type === state.crime && r.agency_id === state.agency && (!state.start || r.date >= state.start) && (!state.end || r.date <= state.end));
    if (!rows.length) { $('global-chart').innerHTML = '<p class="empty">No global rows match these filters.</p>'; return; }
    const x0 = new Date(rows[0].date), x1 = new Date(rows[rows.length - 1].date);
    const all = rows.flatMap(r => [num(r.observed_rate), num(r.global_rate)]).concat(agency.map(r => num(r.fitted_rate))).filter(Number.isFinite);
    const ymax = Math.max(...all) * 1.08;
    let out = svgBase(`Global baseline and ${state.agency || 'selected agency'}`, 0, ymax, x0, x1, 'Rate per 100,000');
    out += `<path d="${linePath(rows, 'observed_rate', x0, x1, 0, ymax)}" fill="none" stroke="#9aa8aa" stroke-width="1"/><path d="${linePath(rows, 'global_rate', x0, x1, 0, ymax)}" fill="none" stroke="#1b5e75" stroke-width="3"/>`;
    if (agency.length) out += `<path d="${linePath(agency, 'fitted_rate', x0, x1, 0, ymax)}" fill="none" stroke="#d87941" stroke-width="2"/>`;
    $('global-chart').innerHTML = finishSvg(out, 'observed  ·  global baseline  ·  agency fit');
  }

  function renderResiduals() {
    const rows = state.decomposition.filter(r => r.crime_type === state.crime && r.agency_id === state.agency && (!state.start || r.date >= state.start) && (!state.end || r.date <= state.end));
    if (!rows.length) { $('residual-chart').innerHTML = '<p class="empty">No agency rows match these filters.</p>'; return; }
    const x0 = new Date(rows[0].date), x1 = new Date(rows[rows.length - 1].date), threshold = Number(state.threshold) || 3;
    const ymax = Math.max(threshold * 1.25, ...rows.map(r => Math.abs(num(r.pearson_residual))).filter(Number.isFinite)) * 1.05;
    let out = svgBase(`Monthly Pearson residuals for ${state.agency}`, -ymax, ymax, x0, x1, 'Residual');
    [-threshold, threshold].forEach(v => { const y = scale(v, ymax, -ymax, 34, 286); out += `<line x1="62" x2="1000" y1="${y}" y2="${y}" stroke="#b33a3a" stroke-dasharray="5 4"/>`; });
    rows.forEach(r => { const x = scale(new Date(r.date), x0, x1, 62, 1000), y = scale(num(r.pearson_residual), ymax, -ymax, 34, 286), c = Math.abs(num(r.pearson_residual)) >= threshold ? '#b33a3a' : '#1b5e75'; out += `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="3" fill="${c}"/>`; });
    $('residual-chart').innerHTML = finishSvg(out, `threshold ±${threshold}`);
  }

  function renderTable() {
    const threshold = Number(state.threshold) || 3;
    const rows = state.decomposition.filter(r => r.crime_type === state.crime && r.agency_id === state.agency && (!state.start || r.date >= state.start) && (!state.end || r.date <= state.end) && Math.abs(num(r.pearson_residual)) >= threshold).sort((a, b) => Math.abs(num(b.pearson_residual)) - Math.abs(num(a.pearson_residual))).slice(0, 50);
    $('outliers').querySelector('tbody').innerHTML = rows.length ? rows.map(r => `<tr><td>${r.date}</td><td>${r.agency_id}</td><td>${r.crime_type}</td><td>${fmt(num(r.observed_rate))}</td><td>${fmt(num(r.fitted_rate))}</td><td>${fmt(num(r.pearson_residual))}</td></tr>`).join('') : '<tr><td colspan="6" class="empty">No flagged months for the current filters.</td></tr>';
  }

  function update() { renderGlobal(); renderResiduals(); renderTable(); $('status').textContent = `${state.global.length.toLocaleString()} global rows and ${state.decomposition.length.toLocaleString()} agency-month-crime rows loaded.`; }
  function setup() {
    const crimes = [...new Set(state.global.map(r => r.crime_type))]; state.crime = crimes[0];
    $('crime').innerHTML = crimes.map(x => `<option>${x}</option>`).join('');
    const agencies = [...new Set(state.decomposition.map(r => r.agency_id))].sort(); state.agency = agencies[0];
    $('agency').innerHTML = agencies.map(x => `<option>${x}</option>`).join('');
    const ds = state.global.map(r => r.date).sort(); state.start = ds[0]; state.end = ds[ds.length - 1]; $('start').value = state.start; $('end').value = state.end;
    $('crime').value = state.crime; $('agency').value = state.agency;
    [['crime', 'crime'], ['agency', 'agency'], ['start', 'start'], ['end', 'end'], ['threshold', 'threshold']].forEach(([id, key]) => $(id).addEventListener('change', e => { state[key] = e.target.value; update(); }));
    $('reset').addEventListener('click', () => { $('crime').value = crimes[0]; $('agency').value = agencies[0]; $('start').value = ds[0]; $('end').value = ds[ds.length - 1]; $('threshold').value = 3; state.crime = crimes[0]; state.agency = agencies[0]; state.start = ds[0]; state.end = ds[ds.length - 1]; state.threshold = 3; update(); });
    update();
  }
  Promise.all(['global_trends.csv', 'decomposition.csv'].map(f => fetch(`data/${f}`).then(r => r.text()).then(parseCsv))).then(([global, decomposition]) => { state.global = global; state.decomposition = decomposition; setup(); }).catch(err => { $('status').textContent = `Could not load model outputs. Run scripts/run_model.R first. ${err}`; });
})();

