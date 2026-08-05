(() => {
  const state = { global: [], decomposition: [], cities: [], citySummary: [], crime: "murder", city: "" };
  let mapInstance = null;
  const $ = id => document.getElementById(id);
  const csv = text => {
    const rows = [];
    let row = [], cell = "", quote = false;
    for (let i = 0; i < text.length; i++) {
      const ch = text[i], next = text[i + 1];
      if (ch === '"' && quote && next === '"') { cell += '"'; i++; }
      else if (ch === '"') quote = !quote;
      else if (ch === ',' && !quote) { row.push(cell); cell = ""; }
      else if ((ch === '\n' || ch === '\r') && !quote) {
        if (ch === '\r' && next === '\n') i++;
        row.push(cell); rows.push(row); row = []; cell = "";
      } else cell += ch;
    }
    if (cell || row.length) { row.push(cell); rows.push(row); }
    const heads = rows.shift().map(x => x.trim());
    return rows.filter(r => r.length > 1).map(r => Object.fromEntries(heads.map((h, i) => [h, r[i] ?? ""])));
  };
  const n = x => Number(x);
  const f = x => Number.isFinite(x) ? x.toFixed(2) : "-";
  const scale = (x, a, b, c, d) => c + (x - a) * (d - c) / ((b - a) || 1);
  const line = (rows, key, x0, x1, ymin, ymax, color, height = 330) =>
    `<path d="${rows.map((r, i) => ` ${i ? 'L' : 'M'}${scale(new Date(r.date), x0, x1, 66, 1010).toFixed(1)},${scale(n(r[key]), ymax, ymin, 38, height - 40).toFixed(1)}`).join("")}" fill="none" stroke="${color}" class="legend-line"/>`;
  const base = (title, ymin, ymax, x0, x1, ylabel, height = 330) => {
    let s = `<svg viewBox="0 0 1060 ${height}" role="img" aria-label="${title}"><text x="66" y="22" class="chart-title">${title}</text>`;
    [0, .25, .5, .75, 1].forEach(t => {
      const y = 38 + t * (height - 72), v = ymax - t * (ymax - ymin);
      s += `<line x1="66" x2="1010" y1="${y}" y2="${y}" class="grid"/><text x="58" y="${y + 4}" text-anchor="end" class="axis-label">${f(v)}</text>`;
    });
    if (ymin < 0 && ymax > 0) {
      const zeroY = scale(0, ymax, ymin, 38, height - 40);
      s += `<line x1="66" x2="1010" y1="${zeroY}" y2="${zeroY}" class="zero-line"/>`;
    }
    s += `<line x1="66" x2="1010" y1="${height - 40}" y2="${height - 40}" class="axis"/><text x="17" y="${height / 2}" transform="rotate(-90 17 ${height / 2})" class="axis-label">${ylabel}</text><text x="66" y="${height - 14}" class="axis-label">${x0.toISOString().slice(0, 10)}</text><text x="1010" y="${height - 14}" text-anchor="end" class="axis-label">${x1.toISOString().slice(0, 10)}</text>`;
    return s;
  };
  const finish = (s, items) => {
    const start = 800 - (items.length - 1) * 70;
    const legend = items.map((x, i) => `<line x1="${start + i * 140}" x2="${start + 25 + i * 140}" y1="22" y2="22" stroke="${x[1]}" class="legend-line"/><text x="${start + 32 + i * 140}" y="26" class="legend">${x[0]}</text>`).join("");
    return `${s}${legend}</svg>`;
  };

  function renderGlobal() {
    const rows = state.global.filter(r => r.crime_type === state.crime);
    if (!rows.length) return;
    const x0 = new Date(rows[0].date), x1 = new Date(rows[rows.length - 1].date);
    const all = rows.flatMap(r => [n(r.observed_rate), n(r.trend_rate), n(r.global_rate)]).filter(Number.isFinite);
    const ymax = Math.max(...all) * 1.08;
    let s = base(`${state.crime} - global annualized rate`, 0, ymax, x0, x1, "Rate per 100,000");
    s += line(rows, "observed_rate", x0, x1, 0, ymax, "#9aa8aa") + line(rows, "trend_rate", x0, x1, 0, ymax, "#1a657c") + line(rows, "global_rate", x0, x1, 0, ymax, "#d77942");
    $("global-chart").innerHTML = finish(s, [["observed", "#9aa8aa"], ["trend", "#1a657c"], ["trend + season", "#d77942"]]);
    const seasonalMax = Math.max(...rows.map(r => Math.abs(n(r.seasonal_rate_delta))).filter(Number.isFinite), .1) * 1.15;
    let q = base(`${state.crime} - seasonal effect`, -seasonalMax, seasonalMax, x0, x1, "Annualized rate change", 270);
    q += line(rows, "seasonal_rate_delta", x0, x1, -seasonalMax, seasonalMax, "#d77942", 270);
    $("seasonal-chart").innerHTML = finish(q, [["seasonal effect", "#d77942"]]);
    const residualValues = rows.map(r => Math.abs(n(r.global_residual_logit))).filter(Number.isFinite);
    if (!residualValues.length) {
      $("global-residual-chart").innerHTML = '<p class="caption">Global residual data are missing. Rerun <code>src/run_model.R</code>.</p>';
    } else {
      const residualMax = Math.max(...residualValues, .05) * 1.15;
      let z = base(`${state.crime} - global residual`, -residualMax, residualMax, x0, x1, "Centered logit residual", 270);
      z += line(rows, "global_residual_logit", x0, x1, -residualMax, residualMax, "#ae3e3e", 270);
      $("global-residual-chart").innerHTML = finish(z, [["global residual", "#ae3e3e"]]);
    }
  }

  function renderCity() {
    const rows = state.decomposition.filter(r => r.city_id === state.city && r.crime_type === state.crime);
    const selected = state.cities.find(r => r.city_id === state.city);
    const name = selected ? selected.city_label : state.city;
    if (!rows.length) {
      $("city-title").textContent = `${name} - ${state.crime}`;
      $("city-chart").innerHTML = '<p class="caption">No valid component count rows are available for this city and crime type.</p>';
      $("overdispersion-chart").innerHTML = "";
      return;
    }
    $("city-title").textContent = `${name} - ${state.crime}`;
    const x0 = new Date(rows[0].date), x1 = new Date(rows[rows.length - 1].date);
    const all = rows.flatMap(r => [n(r.observed_rate), n(r.city_fitted_rate), n(r.global_rate)]).filter(Number.isFinite);
    const ymax = Math.max(...all) * 1.08;
    let s = base(`${name} - annualized rate`, 0, ymax, x0, x1, "Rate per 100,000");
    s += line(rows, "observed_rate", x0, x1, 0, ymax, "#9aa8aa") + line(rows, "global_rate", x0, x1, 0, ymax, "#1a657c");
    $("city-chart").innerHTML = finish(s, [["observed", "#9aa8aa"], ["global baseline", "#1a657c"]]);
    const values = rows.map(r => n(r.overdispersion_logit)).filter(Number.isFinite);
    const ymin = Math.min(...values, -.2) * 1.1, ymaxd = Math.max(...values, .2) * 1.1;
    let q = base(`${name} - city x crime x month overdispersion`, ymin, ymaxd, x0, x1, "Centered logit overdispersion", 270);
    q += line(rows, "overdispersion_logit", x0, x1, ymin, ymaxd, "#ae3e3e", 270);
    $("overdispersion-chart").innerHTML = finish(q, [["overdispersion term", "#ae3e3e"]]);
  }

  function renderMap() {
    const container = $("map-chart");
    if (!window.L) { container.innerHTML = '<p class="caption">Leaflet did not load. Check the network connection and reload.</p>'; return; }
    if (mapInstance) { mapInstance.remove(); mapInstance = null; }
    mapInstance = L.map(container, { worldCopyJump: true }).setView([39, -96], 4);
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 18, attribution: '&copy; OpenStreetMap contributors' }).addTo(mapInstance);
    const lookup = Object.fromEntries(state.citySummary.filter(r => r.crime_type === state.crime).map(r => [r.city_id, r]));
    state.cities.filter(r => Number.isFinite(n(r.latitude)) && Number.isFinite(n(r.longitude))).forEach(r => {
      const value = lookup[r.city_id] ? n(lookup[r.city_id].mean_abs_overdispersion_logit) : 0;
      const marker = L.circleMarker([n(r.latitude), n(r.longitude)], { radius: r.city_id === state.city ? 7 : 4, color: "#ae3e3e", fillColor: "#ae3e3e", fillOpacity: Math.min(.95, .35 + value), weight: 1 });
      marker.bindTooltip(`${r.city_label}: ${f(value)} mean absolute overdispersion`);
      marker.on("click", () => { state.city = r.city_id; $("city").value = state.city; showPage("city"); });
      marker.addTo(mapInstance);
    });
    setTimeout(() => mapInstance.invalidateSize(), 0);
  }

  function showPage(page) {
    document.querySelectorAll(".page").forEach(x => x.classList.toggle("active", x.id === page));
    document.querySelectorAll(".tab").forEach(x => x.classList.toggle("active", x.dataset.page === page));
    if (page === "overview") renderGlobal();
    if (page === "city") renderCity();
    if (page === "map") renderMap();
  }

  function setup() {
    const crimes = [...new Set(state.global.map(r => r.crime_type))].sort();
    const cities = state.cities.slice().sort((a, b) => a.city_label.localeCompare(b.city_label));
    state.crime = crimes[0];
    state.city = cities[0].city_id;
    $("crime").innerHTML = crimes.map(x => `<option value="${x}">${x}</option>`).join("");
    $("city").innerHTML = cities.map(x => `<option value="${x.city_id}">${x.city_label}</option>`).join("");
    $("crime").addEventListener("change", e => { state.crime = e.target.value; renderGlobal(); renderCity(); if (document.getElementById("map").classList.contains("active")) renderMap(); });
    $("city").addEventListener("change", e => { state.city = e.target.value; renderCity(); });
    $("reset").addEventListener("click", () => { state.crime = crimes[0]; $("crime").value = state.crime; showPage("overview"); });
    document.querySelectorAll(".tab").forEach(x => x.addEventListener("click", () => showPage(x.dataset.page)));
    showPage("overview");
    $("status").textContent = `${state.cities.length.toLocaleString()} cities - ${state.decomposition.length.toLocaleString()} city-month-crime observations - full date range - annualized rates`;
  }

  Promise.all(["global_stl.csv", "decomposition.csv", "cities.csv", "city_summary.csv"].map(file => fetch(`../data/app/${file}`).then(r => { if (!r.ok) throw new Error(`${file}: ${r.status}`); return r.text(); }).then(csv)))
    .then(([global, decomposition, cities, summary]) => { state.global = global; state.decomposition = decomposition; state.cities = cities; state.citySummary = summary; setup(); })
    .catch(error => { $("status").textContent = `Could not load model outputs: ${error}. Run src/run_model.R from the repository root first.`; });
})();
