(() => {
  const state = { global: [], decomposition: [], cities: [], crime: "murder", city: "", page: "overview" };
  const $ = id => document.getElementById(id);
  const csv = text => {
    const rows = []; let row = [], cell = "", quote = false;
    for (let i = 0; i < text.length; i++) { const ch = text[i], next = text[i + 1];
      if (ch === '"' && quote && next === '"') { cell += '"'; i++; }
      else if (ch === '"') quote = !quote;
      else if (ch === ',' && !quote) { row.push(cell); cell = ""; }
      else if ((ch === '\n' || ch === '\r') && !quote) { if (ch === '\r' && next === '\n') i++; row.push(cell); rows.push(row); row=[]; cell=""; }
      else cell += ch;
    }
    if (cell || row.length) { row.push(cell); rows.push(row); }
    const heads = rows.shift().map(x => x.trim());
    return rows.filter(r => r.length > 1).map(r => Object.fromEntries(heads.map((h,i) => [h, r[i] ?? ""])));
  };
  const n = x => Number(x); const f = x => Number.isFinite(x) ? x.toFixed(2) : "—";
  const extent = (rows, key) => { const x=rows.map(r=>n(r[key])).filter(Number.isFinite); return [Math.min(...x),Math.max(...x)]; };
  const scale = (x,a,b,c,d) => c + (x-a)*(d-c)/((b-a)||1);
  const path = (rows,key,x0,x1,y0,y1) => rows.map((r,i) => ` ${i?'L':'M'}${scale(new Date(r.date),x0,x1,66,1010).toFixed(1)},${scale(n(r[key]),y1,y0,38,290).toFixed(1)}`).join("");
  const base = (title, ymin, ymax, x0, x1, ylabel, height=330) => { let s=`<svg viewBox="0 0 1060 ${height}"><text x="66" y="22" class="chart-title">${title}</text>`; [0,.25,.5,.75,1].forEach(t=>{const y=38+t*(height-72),v=ymax-t*(ymax-ymin);s+=`<line x1="66" x2="1010" y1="${y}" y2="${y}" class="grid"/><text x="58" y="${y+4}" text-anchor="end" class="axis-label">${f(v)}</text>`;}); s+=`<line x1="66" x2="1010" y1="${height-40}" y2="${height-40}" class="axis"/><text x="17" y="${height/2}" transform="rotate(-90 17 ${height/2})" class="axis-label">${ylabel}</text><text x="66" y="${height-14}" class="axis-label">${x0.toISOString().slice(0,10)}</text><text x="1010" y="${height-14}" text-anchor="end" class="axis-label">${x1.toISOString().slice(0,10)}</text>`; return s; };
  const line = (rows,key,x0,x1,ymin,ymax,color,height=330) => `<path d="${rows.map((r,i)=>` ${i?'L':'M'}${scale(new Date(r.date),x0,x1,66,1010).toFixed(1)},${scale(n(r[key]),ymax,ymin,38,height-40).toFixed(1)}`).join("")}" fill="none" stroke="${color}" class="legend-line"/>`;
  const finish = (s, items) => `${s}${items.map((x,i)=>`<line x1="${790+i*120}" x2="${815+i*120}" y1="22" y2="22" stroke="${x[1]}" class="legend-line"/><text x="${822+i*120}" y="26" class="legend">${x[0]}</text>`).join("")}</svg>`;

  function renderGlobal() {
    const rows=state.global.filter(r=>r.crime_type===state.crime); if(!rows.length)return;
    const x0=new Date(rows[0].date),x1=new Date(rows[rows.length-1].date), all=rows.flatMap(r=>[n(r.observed_rate),n(r.trend_rate),n(r.global_rate)]), ymax=Math.max(...all)*1.08;
    let s=base(`${state.crime} — global annualized rate`,0,ymax,x0,x1,"Rate per 100,000"); s+=line(rows,"observed_rate",x0,x1,0,ymax,"#9aa8aa")+line(rows,"trend_rate",x0,x1,0,ymax,"#1a657c")+line(rows,"global_rate",x0,x1,0,ymax,"#d77942"); $("global-chart").innerHTML=finish(s,[["observed","#9aa8aa"],["trend","#1a657c"],["trend + season","#d77942"]]);
    const ymax2=Math.max(...rows.map(r=>Math.abs(n(r.seasonal_rate_delta))),.1)*1.15; let q=base(`${state.crime} — seasonal effect`, -ymax2,ymax2,x0,x1,"Annualized rate change",270); q+=line(rows,"seasonal_rate_delta",x0,x1,-ymax2,ymax2,"#d77942",270); $("seasonal-chart").innerHTML=finish(q,[["seasonal effect","#d77942"]]);
  }

  function renderCity() {
    const rows=state.decomposition.filter(r=>r.city_id===state.city&&r.crime_type===state.crime); const selected=state.cities.find(r=>r.city_id===state.city); const name=selected?selected.city_label:state.city; if(!rows.length){$("city-title").textContent=`${name} — ${state.crime}`;$("city-chart").innerHTML='<p class="caption">No valid component count rows are available for this city and crime type.</p>';$("overdispersion-chart").innerHTML='';return;}
    $("city-title").textContent=`${name} — ${state.crime}`; const x0=new Date(rows[0].date),x1=new Date(rows[rows.length-1].date),all=rows.flatMap(r=>[n(r.observed_rate),n(r.city_fitted_rate),n(r.global_rate)]),ymax=Math.max(...all)*1.08;
    let s=base(`${name} — annualized rate`,0,ymax,x0,x1,"Rate per 100,000"); s+=line(rows,"observed_rate",x0,x1,0,ymax,"#9aa8aa")+line(rows,"global_rate",x0,x1,0,ymax,"#1a657c"); $("city-chart").innerHTML=finish(s,[["observed","#9aa8aa"],["global baseline","#1a657c"]]);
    const yd=extent(rows,"overdispersion_logit"), ymin=Math.min(yd[0]*1.1,-.2), ymaxd=Math.max(yd[1]*1.1,.2); let q=base(`${name} — city × crime × month overdispersion`,ymin,ymaxd,x0,x1,"Logit overdispersion",270); q+=line(rows,"overdispersion_logit",x0,x1,ymin,ymaxd,"#ae3e3e",270); $("overdispersion-chart").innerHTML=finish(q,[["overdispersion term","#ae3e3e"]]);
  }

  function renderMap() {
    const lookup=Object.fromEntries(state.citySummary.filter(r=>r.crime_type===state.crime).map(r=>[r.city_id,r])); const points=state.cities.filter(r=>Number.isFinite(n(r.latitude))&&Number.isFinite(n(r.longitude))); let s='<svg viewBox="0 0 900 560"><rect x="20" y="25" width="860" height="500" rx="12" fill="#eef4f3" stroke="#d6e0e2"/><text x="40" y="54" class="chart-title">US city map — click a city</text>';
    points.forEach(r=>{const x=scale(n(r.longitude),-125,-66,45,855),y=scale(n(r.latitude),25,50,495,80),v=lookup[r.city_id]?n(lookup[r.city_id].mean_city_minus_global_logit):0,c=v>=0?'#d77942':'#1a657c',rad=r.city_id===state.city?6:4;s+=`<circle class="dot" data-city="${r.city_id}" cx="${x}" cy="${y}" r="${rad}" fill="${c}"/><title>${r.city_label}: ${f(v)} logit</title>`;}); s+='</svg>';
    $("map-chart").innerHTML=s; $("map-chart").querySelectorAll(".dot").forEach(el=>el.addEventListener("click",()=>{state.city=el.dataset.city; $("city").value=state.city; showPage("city");}));
  }
  function showPage(page){state.page=page;document.querySelectorAll(".page").forEach(x=>x.classList.toggle("active",x.id===page));document.querySelectorAll(".tab").forEach(x=>x.classList.toggle("active",x.dataset.page===page)); if(page==="overview")renderGlobal(); if(page==="city")renderCity(); if(page==="map")renderMap();}
  function setup(){ const crimes=[...new Set(state.global.map(r=>r.crime_type))];state.crime=crimes[0];$("crime").innerHTML=crimes.map(x=>`<option value="${x}">${x}</option>`).join(""); const cities=state.cities.slice().sort((a,b)=>a.city_label.localeCompare(b.city_label));state.city=cities[0].city_id;$("city").innerHTML=cities.map(x=>`<option value="${x.city_id}">${x.city_label}</option>`).join("");$("crime").addEventListener("change",e=>{state.crime=e.target.value;renderGlobal();renderCity();renderMap();});$("city").addEventListener("change",e=>{state.city=e.target.value;renderCity();});$("reset").addEventListener("click",()=>{state.crime=crimes[0];state.city=cities[0].city_id;$("crime").value=state.crime;$("city").value=state.city;showPage("overview");});document.querySelectorAll(".tab").forEach(x=>x.addEventListener("click",()=>showPage(x.dataset.page)));showPage("overview");$("status").textContent=`${state.cities.length.toLocaleString()} cities · ${state.decomposition.length.toLocaleString()} city-month-crime observations · annualized rates`;
  }
  Promise.all(["global_stl.csv","decomposition.csv","cities.csv","city_summary.csv"].map(f=>fetch(`data/${f}`).then(r=>r.text()).then(csv))).then(([global,decomposition,cities,summary])=>{state.global=global;state.decomposition=decomposition;state.cities=cities;state.citySummary=summary;setup();}).catch(e=>$("status").textContent=`Could not load model outputs: ${e}. Run scripts/run_model.R first.`);
})();
