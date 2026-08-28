(() => {
  const state = {
    global: [], decomposition: [], loadedCrime: "", cities: [],
    cityTrends: [], citySeasons: [], residualSE: new Map(), cityById: new Map(),
    loadedCurvesCrime: "",
    crime: "murder", city: "", selectedState: ""
  };
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
  const f1 = x => Number.isFinite(x) ? x.toFixed(1) : "-";
  const esc = x => String(x).replace(/[&<>"']/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));
  const crimeLabel = crime => ({ motor: "Motor Vehicle Theft" }[crime] || crime[0].toUpperCase() + crime.slice(1));
  const cityDisplayLabel = (cityId, fallback) => {
    const city = state.cityById.get(cityId);
    return city?.agency_type === "County"
      ? `${fallback} (Sheriff's Office)` : fallback;
  };
  const scale = (x, a, b, c, d) => c + (x - a) * (d - c) / ((b - a) || 1);
  const line = (rows, key, x0, x1, ymin, ymax, color, height = 330) =>
    `<path d="${rows.map((r, i) => ` ${i ? 'L' : 'M'}${scale(new Date(r.date), x0, x1, 66, 1010).toFixed(1)},${scale(n(r[key]), ymax, ymin, 38, height - 40).toFixed(1)}`).join("")}" fill="none" stroke="${color}" class="legend-line"/>`;
  const ribbon = (rows, lowerKey, upperKey, x0, x1, ymin, ymax, height = 330) => {
    const upper = rows.map((r, i) => `${i ? "L" : "M"}${scale(new Date(r.date), x0, x1, 66, 1010).toFixed(1)},${scale(n(r[upperKey]), ymax, ymin, 38, height - 40).toFixed(1)}`).join(" ");
    const lower = rows.slice().reverse().map(r => `L${scale(new Date(r.date), x0, x1, 66, 1010).toFixed(1)},${scale(n(r[lowerKey]), ymax, ymin, 38, height - 40).toFixed(1)}`).join(" ");
    return `<path d="${upper} ${lower} Z" class="interval-band"/>`;
  };
  const intervalLine = (rows, key, x0, x1, ymin, ymax, height = 330) =>
    `<path d="${rows.map((r, i) => ` ${i ? 'L' : 'M'}${scale(new Date(r.date), x0, x1, 66, 1010).toFixed(1)},${scale(n(r[key]), ymax, ymin, 38, height - 40).toFixed(1)}`).join("")}" class="interval-boundary"/>`;
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
    s += `<line x1="66" x2="1010" y1="${height - 40}" y2="${height - 40}" class="axis"/><text x="17" y="${height / 2}" transform="rotate(-90 17 ${height / 2})" class="axis-label">${ylabel}</text>`;
    let quarter = new Date(Date.UTC(x0.getUTCFullYear(), Math.floor(x0.getUTCMonth() / 3) * 3, 1));
    while (quarter <= x1) {
      const x = scale(quarter, x0, x1, 66, 1010);
      s += `<line x1="${x}" x2="${x}" y1="${height - 40}" y2="${height - 34}" class="x-tick"/>`;
      quarter.setUTCMonth(quarter.getUTCMonth() + 3);
    }
    for (let year = x0.getUTCFullYear(); year <= x1.getUTCFullYear(); year++) {
      const tick = new Date(Date.UTC(year, 0, 1));
      if (tick < x0 || tick > x1) continue;
      const x = scale(tick, x0, x1, 66, 1010);
      s += `<text x="${x}" y="${height - 14}" text-anchor="middle" class="axis-label">${year}</text>`;
    }
    return s;
  };
  const monthLine = (rows, key, ymin, ymax, color, height = 290) =>
    `<path d="${rows.map((r, i) => ` ${i ? 'L' : 'M'}${scale(n(r.month), 1, 12, 66, 1010).toFixed(1)},${scale(n(r[key]), ymax, ymin, 38, height - 40).toFixed(1)}`).join("")}" fill="none" stroke="${color}" class="legend-line"/>`;
  const monthRibbon = (rows, lowerKey, upperKey, ymin, ymax, height = 290) => {
    const upper = rows.map((r, i) => `${i ? "L" : "M"}${scale(n(r.month), 1, 12, 66, 1010).toFixed(1)},${scale(n(r[upperKey]), ymax, ymin, 38, height - 40).toFixed(1)}`).join(" ");
    const lower = rows.slice().reverse().map(r => `L${scale(n(r.month), 1, 12, 66, 1010).toFixed(1)},${scale(n(r[lowerKey]), ymax, ymin, 38, height - 40).toFixed(1)}`).join(" ");
    return `<path d="${upper} ${lower} Z" class="interval-band"/>`;
  };
  const monthIntervalLine = (rows, key, ymin, ymax, height = 290) =>
    `<path d="${rows.map((r, i) => ` ${i ? 'L' : 'M'}${scale(n(r.month), 1, 12, 66, 1010).toFixed(1)},${scale(n(r[key]), ymax, ymin, 38, height - 40).toFixed(1)}`).join("")}" class="interval-boundary"/>`;
  const monthBase = (title, ymin, ymax, ylabel, height = 290) => {
    let s = `<svg viewBox="0 0 1060 ${height}" role="img" aria-label="${esc(title)}"><text x="66" y="22" class="chart-title">${esc(title)}</text>`;
    [0, .25, .5, .75, 1].forEach(t => {
      const y = 38 + t * (height - 72), value = ymax - t * (ymax - ymin);
      s += `<line x1="66" x2="1010" y1="${y}" y2="${y}" class="grid"/><text x="58" y="${y + 4}" text-anchor="end" class="axis-label">${f(value)}</text>`;
    });
    if (ymin < 0 && ymax > 0) {
      const zeroY = scale(0, ymax, ymin, 38, height - 40);
      s += `<line x1="66" x2="1010" y1="${zeroY}" y2="${zeroY}" class="zero-line"/>`;
    }
    s += `<line x1="66" x2="1010" y1="${height - 40}" y2="${height - 40}" class="axis"/><text x="17" y="${height / 2}" transform="rotate(-90 17 ${height / 2})" class="axis-label">${esc(ylabel)}</text>`;
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].forEach((label, index) => {
      const x = scale(index + 1, 1, 12, 66, 1010);
      s += `<line x1="${x}" x2="${x}" y1="${height - 40}" y2="${height - 34}" class="x-tick"/><text x="${x}" y="${height - 14}" text-anchor="middle" class="axis-label">${label}</text>`;
    });
    return s;
  };
  const symmetricLimit = values => Math.max(
    ...values.map(Math.abs).filter(Number.isFinite), .02
  ) * 1.12;
  const finish = (s, items) => {
    const step = 135, start = Math.max(70, 1010 - items.length * step);
    const legend = items.map((x, i) => {
      const key = x[2] === "interval"
        ? `<rect x="${start + i * step}" y="15" width="25" height="12" class="interval-key"/>`
        : `<line x1="${start + i * step}" x2="${start + 25 + i * step}" y1="22" y2="22" stroke="${x[1]}" class="legend-line"/>`;
      return `${key}<text x="${start + 32 + i * step}" y="26" class="legend">${x[0]}</text>`;
    }).join("");
    return `${s}${legend}</svg>`;
  };

  function renderGlobal() {
    const rows = state.global.filter(r => r.crime_type === state.crime);
    if (!rows.length) return;
    const x0 = new Date(rows[0].date), x1 = new Date(rows[rows.length - 1].date);
    const all = rows.flatMap(r => [n(r.observed_rate), n(r.city_fitted_rate), n(r.trend_rate), n(r.global_rate)]).filter(Number.isFinite);
    const ymax = Math.max(...all) * 1.08;
    let s = base(`${crimeLabel(state.crime)} - global annualized rate`, 0, ymax, x0, x1, "Rate per 100,000");
    s += line(rows, "observed_rate", x0, x1, 0, ymax, "#7f8c8d") + line(rows, "city_fitted_rate", x0, x1, 0, ymax, "#17343d") + line(rows, "trend_rate", x0, x1, 0, ymax, "#1a657c") + line(rows, "global_rate", x0, x1, 0, ymax, "#d77942");
    $("global-chart").innerHTML = finish(s, [["observed", "#7f8c8d"], ["sample fitted", "#17343d"], ["global trend", "#1a657c"], ["global + season", "#d77942"]]);
    const seasonalMax = Math.max(...rows.map(r => Math.abs(n(r.seasonal_rate_delta))).filter(Number.isFinite), .1) * 1.15;
    let q = base(`${crimeLabel(state.crime)} - seasonal effect`, -seasonalMax, seasonalMax, x0, x1, "Annualized rate change", 270);
    q += line(rows, "seasonal_rate_delta", x0, x1, -seasonalMax, seasonalMax, "#d77942", 270);
    $("seasonal-chart").innerHTML = finish(q, [["seasonal effect", "#d77942"]]);
    const residualValues = rows.map(r => Math.abs(n(r.global_residual_rate))).filter(Number.isFinite);
    if (!residualValues.length) {
      $("global-residual-chart").innerHTML = '<p class="caption">Global residual data are missing. Rerun <code>src/run_model.R</code>.</p>';
    } else {
      const residualMax = Math.max(...residualValues, .05) * 1.15;
      let z = base(`${crimeLabel(state.crime)} - shared time period effect`, -residualMax, residualMax, x0, x1, "Annualized rate change", 270);
      z += line(rows, "global_residual_rate", x0, x1, -residualMax, residualMax, "#ae3e3e", 270);
      $("global-residual-chart").innerHTML = finish(z, [["shared time period effect", "#ae3e3e"]]);
    }
  }

  function renderCity() {
    const componentCharts = ["city-chart", "city-trend-chart", "city-season-chart", "city-residual-chart"];
    const crime = crimeLabel(state.crime);
    $("city-trend-title").textContent = `${crime}: City and US-wide trends`;
    $("city-season-title").textContent = `${crime}: City and US-wide seasonal patterns`;
    $("city-residual-title").textContent = `${crime}: City and US-wide residuals`;
    if (state.loadedCrime !== state.crime || state.loadedCurvesCrime !== state.crime) {
      componentCharts.forEach((id, index) => {
        $(id).innerHTML = index === 0
          ? '<p class="caption">Loading this crime type...</p>' : "";
      });
      $("city-month-table").innerHTML = '<p class="table-note">Loading this crime type...</p>';
      return;
    }
    const rows = state.decomposition.filter(r => r.city_id === state.city && r.crime_type === state.crime);
    const trendRows = state.cityTrends.filter(r => r.city_id === state.city);
    const seasonRows = state.citySeasons.filter(r => r.city_id === state.city);
    const selected = state.cities.find(r => r.city_id === state.city);
    const name = selected ? cityDisplayLabel(selected.city_id, selected.city_label) : state.city;
    if (!rows.length || !trendRows.length || !seasonRows.length) {
      $("city-title").textContent = `${name} - ${crimeLabel(state.crime)}`;
      $("city-chart").innerHTML = '<p class="caption">No valid component count rows are available for this city and crime type.</p>';
      componentCharts.slice(1).forEach(id => { $(id).innerHTML = ""; });
      $("city-month-table").innerHTML = '<p class="table-note">No monthly rows are available for this selection.</p>';
      return;
    }
    $("city-title").textContent = `${name} - ${crimeLabel(state.crime)}`;
    const x0 = new Date(rows[0].date), x1 = new Date(rows[rows.length - 1].date);
    const all = rows.flatMap(r => [n(r.observed_rate), n(r.city_fitted_rate), n(r.global_rate)]).filter(Number.isFinite);
    const ymax = Math.max(...all) * 1.08;
    let s = base(`${name} - annualized rate`, 0, ymax, x0, x1, "Rate per 100,000");
    s += line(rows, "observed_rate", x0, x1, 0, ymax, "#9aa8aa") + line(rows, "global_rate", x0, x1, 0, ymax, "#1a657c") + line(rows, "city_fitted_rate", x0, x1, 0, ymax, "#d77942");
    $("city-chart").innerHTML = finish(s, [["observed", "#9aa8aa"], ["global baseline", "#1a657c"], ["city fitted", "#d77942"]]);

    const intervalMultiplier = 1.959963984540054;
    trendRows.forEach(row => {
      row.city_trend_lower = n(row.city_trend_centered) - intervalMultiplier * n(row.city_trend_se);
      row.city_trend_upper = n(row.city_trend_centered) + intervalMultiplier * n(row.city_trend_se);
    });
    const trendLimit = symmetricLimit(trendRows.flatMap(r => [
      n(r.global_trend_centered), n(r.city_trend_lower), n(r.city_trend_upper)
    ]));
    const trendX0 = new Date(trendRows[0].date);
    const trendX1 = new Date(trendRows[trendRows.length - 1].date);
    let trend = base(`${name} - ${crime} centered trend`, -trendLimit, trendLimit,
      trendX0, trendX1, "Centered trend (logit)", 270);
    trend += ribbon(trendRows, "city_trend_lower", "city_trend_upper",
      trendX0, trendX1, -trendLimit, trendLimit, 270);
    trend += intervalLine(trendRows, "city_trend_lower", trendX0, trendX1,
      -trendLimit, trendLimit, 270);
    trend += intervalLine(trendRows, "city_trend_upper", trendX0, trendX1,
      -trendLimit, trendLimit, 270);
    trend += line(trendRows, "global_trend_centered", trendX0, trendX1,
      -trendLimit, trendLimit, "#1a657c", 270);
    trend += line(trendRows, "city_trend_centered", trendX0, trendX1,
      -trendLimit, trendLimit, "#d77942", 270);
    $("city-trend-chart").innerHTML = finish(trend, [
      ["US-wide", "#1a657c"], [name, "#d77942"], ["95% interval", "#d77942", "interval"]
    ]);

    seasonRows.forEach(row => {
      row.city_season_lower = n(row.city_season_centered) - intervalMultiplier * n(row.city_season_se);
      row.city_season_upper = n(row.city_season_centered) + intervalMultiplier * n(row.city_season_se);
    });
    const seasonLimit = symmetricLimit(seasonRows.flatMap(r => [
      n(r.global_season_centered), n(r.city_season_lower), n(r.city_season_upper)
    ]));
    let season = monthBase(`${name} - ${crime} seasonal pattern`, -seasonLimit,
      seasonLimit, "Seasonal component (logit)", 290);
    season += monthRibbon(seasonRows, "city_season_lower", "city_season_upper",
      -seasonLimit, seasonLimit, 290);
    season += monthIntervalLine(seasonRows, "city_season_lower", -seasonLimit,
      seasonLimit, 290);
    season += monthIntervalLine(seasonRows, "city_season_upper", -seasonLimit,
      seasonLimit, 290);
    season += monthLine(seasonRows, "global_season_centered", -seasonLimit,
      seasonLimit, "#1a657c", 290);
    season += monthLine(seasonRows, "city_season_centered", -seasonLimit,
      seasonLimit, "#d77942", 290);
    $("city-season-chart").innerHTML = finish(season, [
      ["US-wide", "#1a657c"], [name, "#d77942"], ["95% interval", "#d77942", "interval"]
    ]);

    const residualRows = rows.map(row => ({
      ...row,
      city_residual_logit: n(row.time_effect_logit) + n(row.overdispersion_logit),
      city_residual_se: state.residualSE.get(`${row.city_id}|${row.date}`)
    }));
    residualRows.forEach(row => {
      row.city_residual_lower = row.city_residual_logit -
        intervalMultiplier * row.city_residual_se;
      row.city_residual_upper = row.city_residual_logit +
        intervalMultiplier * row.city_residual_se;
    });
    const residualLimit = symmetricLimit(residualRows.flatMap(r => [
      n(r.time_effect_logit), n(r.city_residual_lower), n(r.city_residual_upper)
    ]));
    let residual = base(`${name} - ${crime} residual comparison`, -residualLimit,
      residualLimit, x0, x1, "Residual component (logit)", 270);
    residual += ribbon(residualRows, "city_residual_lower", "city_residual_upper",
      x0, x1, -residualLimit, residualLimit, 270);
    residual += intervalLine(residualRows, "city_residual_lower", x0, x1,
      -residualLimit, residualLimit, 270);
    residual += intervalLine(residualRows, "city_residual_upper", x0, x1,
      -residualLimit, residualLimit, 270);
    residual += line(residualRows, "time_effect_logit", x0, x1,
      -residualLimit, residualLimit, "#1a657c", 270);
    residual += line(residualRows, "city_residual_logit", x0, x1,
      -residualLimit, residualLimit, "#d77942", 270);
    $("city-residual-chart").innerHTML = finish(residual, [
      ["US-wide", "#1a657c"], [name, "#d77942"], ["95% interval", "#d77942", "interval"]
    ]);

    const tableRows = rows.slice().reverse().map(row => {
      const expectedRate = n(row.city_time_fitted_rate);
      const expectedCount = expectedRate * n(row.population) / (12 * 100000);
      const error = n(row.overdispersion_logit);
      const errorSE = state.residualSE.get(`${row.city_id}|${row.date}`);
      const residualClass = Number.isFinite(errorSE) && error > 2 * errorSE
        ? "residual-increase"
        : Number.isFinite(errorSE) && error < -2 * errorSE
          ? "residual-decrease"
          : "";
      const date = new Date(row.date);
      const month = date.toLocaleDateString("en-US", {
        month: "short", year: "numeric", timeZone: "UTC"
      });
      return `<tr class="${residualClass}"><td>${esc(month)}</td><td>${f1(expectedCount)}</td><td>${Math.round(n(row.count)).toLocaleString()}</td><td>${f1(expectedRate)}</td><td>${f1(n(row.observed_rate))}</td><td>${f(error)}</td><td>${f(errorSE)}</td></tr>`;
    }).join("");
    $("city-month-table").innerHTML = `<table class="data-table"><thead><tr><th>Month</th><th>Expected count</th><th>Observed count</th><th>Expected rate</th><th>Observed rate</th><th><em>e</em></th><th>SE(<em>e</em>)</th></tr></thead><tbody>${tableRows}</tbody></table>`;
  }

  function loadCrime(crime) {
    state.loadedCrime = "";
    state.loadedCurvesCrime = "";
    renderCity();
    return Promise.all([
      `decomposition_${crime}.csv`, `city_trends_${crime}.csv`,
      `city_seasons_${crime}.csv`, `residual_se_${crime}.csv`
    ].map(file => fetch(`../data/app/${file}`).then(response => {
      if (!response.ok) throw new Error(`${file}: ${response.status}`);
      return response.text();
    }).then(csv))).then(([rows, trends, seasons, residualSE]) => {
        if (crime !== state.crime) return;
        state.decomposition = rows;
        state.cityTrends = trends;
        state.citySeasons = seasons;
        state.residualSE = new Map(residualSE.map(row => [
          `${row.city_id}|${row.date}`, n(row.overdispersion_logit_se)
        ]));
        state.loadedCrime = crime;
        state.loadedCurvesCrime = crime;
        renderCity();
        if (document.getElementById("all-cities").classList.contains("active")) {
          renderAllCities();
        }
        $("status").textContent = `${state.cities.length.toLocaleString()} cities - ${rows.length.toLocaleString()} ${crimeLabel(crime).toLowerCase()} observations loaded - annualized rates`;
      })
      .catch(error => { $("status").textContent = `Could not load city detail: ${error}`; });
  }

  function bindCurveHover(container) {
    const tooltip = $("chart-tooltip");
    container.querySelectorAll(".city-curve").forEach(path => {
      path.addEventListener("mouseenter", () => {
        path.ownerSVGElement.classList.add("has-highlight");
        path.classList.add("highlighted");
        tooltip.textContent = path.dataset.label;
        tooltip.style.display = "block";
      });
      path.addEventListener("mousemove", event => {
        tooltip.style.left = `${event.clientX + 12}px`;
        tooltip.style.top = `${event.clientY + 12}px`;
      });
      path.addEventListener("mouseleave", () => {
        path.classList.remove("highlighted");
        path.ownerSVGElement.classList.remove("has-highlight");
        tooltip.style.display = "none";
      });
    });
  }

  function renderCurveCollection(containerId, rows, options) {
    const container = $(containerId);
    if (!rows.length) {
      container.innerHTML = '<p class="caption">Loading city curves...</p>';
      return;
    }
    const groups = new Map();
    rows.forEach(row => {
      if (!groups.has(row.city_id)) groups.set(row.city_id, []);
      groups.get(row.city_id).push(row);
    });
    groups.forEach(group => group.sort((a, b) => options.x(a) - options.x(b)));
    const allValues = rows.map(row => n(row[options.cityKey])).filter(Number.isFinite);
    const globalRows = [...new Map(rows.map(row => [options.x(row), row])).values()]
      .sort((a, b) => options.x(a) - options.x(b));
    const globalValues = globalRows.map(row => n(row[options.globalKey])).filter(Number.isFinite);
    let ymin = Infinity, ymax = -Infinity;
    allValues.concat(globalValues).forEach(value => {
      if (value < ymin) ymin = value;
      if (value > ymax) ymax = value;
    });
    if (options.zeroBased) {
      ymin = 0;
      ymax = Math.max(ymax, 0.02) * 1.08;
    } else if (options.symmetric) {
      const limit = Math.max(Math.abs(ymin), Math.abs(ymax), 0.02) * 1.08;
      ymin = -limit;
      ymax = limit;
    } else {
      const padding = Math.max((ymax - ymin) * 0.08, 0.02);
      ymin -= padding; ymax += padding;
    }
    let xmin = Infinity, xmax = -Infinity;
    rows.forEach(row => {
      const value = options.x(row);
      if (value < xmin) xmin = value;
      if (value > xmax) xmax = value;
    });
    const xScale = value => scale(value, xmin, xmax, 66, 1010);
    const yScale = value => scale(value, ymax, ymin, 38, 320);
    const pathFor = (group, key) => group.map((row, index) =>
      `${index ? "L" : "M"}${xScale(options.x(row)).toFixed(1)},${yScale(n(row[key])).toFixed(1)}`
    ).join(" ");
    let svg = `<svg viewBox="0 0 1060 370" role="img" aria-label="${esc(options.title)}"><text x="66" y="22" class="chart-title">${esc(options.title)}</text>`;
    [0, .25, .5, .75, 1].forEach(t => {
      const y = 38 + t * 282, value = ymax - t * (ymax - ymin);
      svg += `<line x1="66" x2="1010" y1="${y}" y2="${y}" class="grid"/><text x="58" y="${y + 4}" text-anchor="end" class="axis-label">${f(value)}</text>`;
    });
    const zeroY = yScale(0);
    if (ymin < 0 && ymax > 0) svg += `<line x1="66" x2="1010" y1="${zeroY}" y2="${zeroY}" class="zero-line"/>`;
    groups.forEach(group => {
      svg += `<path d="${pathFor(group, options.cityKey)}" class="city-curve" data-label="${esc(cityDisplayLabel(group[0].city_id, group[0].city_label))}"/>`;
    });
    svg += `<path d="${pathFor(globalRows, options.globalKey)}" class="global-curve"/>`;
    svg += `<line x1="66" x2="1010" y1="320" y2="320" class="axis"/><text x="17" y="180" transform="rotate(-90 17 180)" class="axis-label">${esc(options.ylabel)}</text>`;
    options.ticks.forEach(tick => {
      const x = xScale(tick.value);
      svg += `<line x1="${x}" x2="${x}" y1="320" y2="326" class="x-tick"/><text x="${x}" y="345" text-anchor="middle" class="axis-label">${esc(tick.label)}</text>`;
    });
    svg += `<line x1="710" x2="735" y1="22" y2="22" class="city-key"/><text x="742" y="26" class="legend">${esc(options.cityLabel || "cities")}</text><line x1="880" x2="905" y1="22" y2="22" class="global-key"/><text x="912" y="26" class="legend">${esc(options.globalLabel || "global")}</text></svg>`;
    container.innerHTML = svg;
    bindCurveHover(container);
  }

  function renderAllCities() {
    if (state.loadedCurvesCrime !== state.crime) {
      $("all-rates-chart").innerHTML = '<p class="caption">Loading city rates...</p>';
      $("all-trends-chart").innerHTML = '<p class="caption">Loading city trends...</p>';
      $("all-seasons-chart").innerHTML = '<p class="caption">Loading city seasonal curves...</p>';
      $("all-residuals-chart").innerHTML = '<p class="caption">Loading city-month residuals...</p>';
      return;
    }
    const trendExtent = state.cityTrends.reduce((extent, row) => {
      const value = new Date(row.date).getTime();
      return [Math.min(extent[0], value), Math.max(extent[1], value)];
    }, [Infinity, -Infinity]);
    const firstYear = new Date(trendExtent[0]).getUTCFullYear();
    const lastYear = new Date(trendExtent[1]).getUTCFullYear();
    const trendTicks = [];
    for (let year = firstYear; year <= lastYear; year += 2) trendTicks.push({ value: Date.UTC(year, 0, 1), label: year });
    renderCurveCollection("all-rates-chart", state.decomposition, {
      title: `${crimeLabel(state.crime)} - annualized city rates`,
      x: row => new Date(row.date).getTime(), cityKey: "city_fitted_rate",
      globalKey: "global_rate", ylabel: "Annualized rate per 100,000",
      ticks: trendTicks, zeroBased: true, cityLabel: "city fitted",
      globalLabel: "global + season"
    });
    renderCurveCollection("all-trends-chart", state.cityTrends, {
      title: `${crimeLabel(state.crime)} - centered city trends`,
      x: row => new Date(row.date).getTime(), cityKey: "city_trend_centered",
      globalKey: "global_trend_centered", ylabel: "Centered trend (logit)", ticks: trendTicks
    });
    renderCurveCollection("all-seasons-chart", state.citySeasons, {
      title: `${crimeLabel(state.crime)} - centered city seasonal curves`,
      x: row => n(row.month), cityKey: "city_season_centered",
      globalKey: "global_season_centered", ylabel: "Seasonal component (logit)",
      ticks: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        .map((label, index) => ({ value: index + 1, label }))
    });
    const residualRows = state.decomposition.map(row => ({
      ...row,
      residual_zero: 0
    }));
    renderCurveCollection("all-residuals-chart", residualRows, {
      title: `${crimeLabel(state.crime)} - city-specific monthly residuals`,
      x: row => new Date(row.date).getTime(), cityKey: "overdispersion_logit",
      globalKey: "residual_zero", ylabel: "City-month residual (logit)",
      ticks: trendTicks, symmetric: true, cityLabel: "residuals", globalLabel: "zero"
    });
  }

  function showPage(page) {
    document.querySelectorAll(".page").forEach(x => x.classList.toggle("active", x.id === page));
    document.querySelectorAll(".tab").forEach(x => x.classList.toggle("active", x.dataset.page === page));
    const showDataControls = page !== "about";
    $("data-controls").hidden = !showDataControls;
    $("status").hidden = !showDataControls;
    if (page === "overview") renderGlobal();
    if (page === "city") renderCity();
    if (page === "all-cities") renderAllCities();
  }

  function syncUrl(page = document.querySelector(".page.active")?.id || "overview") {
    const url = new URL(window.location.href);
    url.searchParams.set("crime", state.crime);
    if (state.city) url.searchParams.set("city", state.city);
    url.hash = page;
    history.replaceState(null, "", url);
  }

  function populateCitySelect(preferredCity = "") {
    const cities = state.cities
      .filter(city => city.state === state.selectedState)
      .sort((a, b) => cityDisplayLabel(a.city_id, a.city_label).localeCompare(cityDisplayLabel(b.city_id, b.city_label)));
    $("city-select").innerHTML = cities
      .map(city => `<option value="${esc(city.city_id)}">${esc(cityDisplayLabel(city.city_id, city.city_label))}</option>`)
      .join("");
    state.city = cities.some(city => city.city_id === preferredCity)
      ? preferredCity : (cities[0]?.city_id || "");
    $("city-select").value = state.city;
  }

  function setup() {
    const crimes = [...new Set(state.global.map(r => r.crime_type))].sort();
    const cities = state.cities.slice().sort((a, b) => a.city_label.localeCompare(b.city_label));
    const states = [...new Set(cities.map(city => city.state).filter(Boolean))].sort();
    state.cityById = new Map(cities.map(city => [city.city_id, city]));
    const params = new URLSearchParams(location.search);
    const requestedCrime = (params.get("crime") || "").toLowerCase();
    const requestedCityId = (params.get("city") || "").toUpperCase();
    state.crime = crimes.includes(requestedCrime) ? requestedCrime : crimes[0];
    const initialCity = cities.find(city => city.city_id === requestedCityId) ||
      cities.find(city => city.city_id === "PAPEP0000") || cities[0];
    state.selectedState = initialCity.state;
    $("crime").innerHTML = crimes.map(x => `<option value="${x}">${crimeLabel(x)}</option>`).join("");
    $("crime").value = state.crime;
    $("state-select").innerHTML = states.map(value => `<option value="${esc(value)}">${esc(value)}</option>`).join("");
    $("state-select").value = state.selectedState;
    populateCitySelect(initialCity.city_id);
    $("crime").addEventListener("change", e => {
      state.crime = e.target.value;
      renderGlobal();
      loadCrime(state.crime);
      syncUrl();
    });
    $("state-select").addEventListener("change", e => {
      state.selectedState = e.target.value;
      populateCitySelect();
      renderCity();
      syncUrl();
    });
    $("city-select").addEventListener("change", e => {
      state.city = e.target.value;
      renderCity();
      syncUrl();
    });
    $("reset").addEventListener("click", () => {
      state.crime = crimes[0];
      $("crime").value = state.crime;
      renderGlobal();
      loadCrime(state.crime);
      showPage("overview");
      syncUrl("overview");
    });
    document.querySelectorAll(".tab").forEach(x => x.addEventListener("click", () => {
      showPage(x.dataset.page);
      syncUrl(x.dataset.page);
    }));
    const requestedPage = location.hash.slice(1);
    const initialPage = ["overview", "city", "all-cities", "about"].includes(requestedPage)
      ? requestedPage : (requestedCityId ? "city" : "overview");
    showPage(initialPage);
    syncUrl(initialPage);
    $("status").textContent = `${state.cities.length.toLocaleString()} cities - loading ${crimeLabel(state.crime).toLowerCase()} city detail...`;
    loadCrime(state.crime);
  }

  Promise.all(["global_stl.csv", "cities.csv"].map(file => fetch(`../data/app/${file}`).then(r => { if (!r.ok) throw new Error(`${file}: ${r.status}`); return r.text(); }).then(csv)))
    .then(([global, cities]) => { state.global = global; state.cities = cities; setup(); })
    .catch(error => { $("status").textContent = `Could not load model outputs: ${error}. Run src/run_model.R from the repository root first.`; });
})();
