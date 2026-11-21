/* AP_Load2026 calculator
 * Reference implementation of the Antipsychotic Dose Load, reference table dated 2026.
 * Fernandez-Egea E, Krishnadas R, Jenkins C, Patel R, Cardinal RN, Wolpe N (2026).
 *
 * The index: prescribed daily dose as a percentage of a reference dose, summed
 * across agents without an upper cap.
 *   - clozapine  -> reference is a target dose individualised for sex and cigarettes/day
 *   - other oral -> reference is min( sqrt(BNFmax x DDD), 1.5 x DDD )
 *   - injectables-> reference is the licensed maximum for the same dosing interval
 * Nothing here is a prescribing tool.
 */
(function () {
  'use strict';

  /* ------------------------------------------------------------------ data */

  /* BEGIN GENERATED TABLES - do not edit by hand.
     Written from reference/*.csv by:  python3 build/generate_web.py
     These are the same tables the Python, R and SPSS implementations read.
     Display names are cosmetic and come from the generator; every number
     comes from the reference CSVs. */

  // bnfMax: UK BNF 2026 maximum, or national label maximum (mg/day). null = none current.
  // ddd: WHO Defined Daily Dose (mg/day). null = no assigned DDD.
  var ORAL = [
    { name: 'Amisulpride', bnfMax: 1200, ddd: 400 },
    { name: 'Aripiprazole', bnfMax: 30, ddd: 15 },
    { name: 'Asenapine', bnfMax: 20, ddd: 20 },
    { name: 'Blonanserin', bnfMax: 24, ddd: null },
    { name: 'Brexpiprazole', bnfMax: 4, ddd: 3 },
    { name: 'Cariprazine', bnfMax: 6, ddd: 3 },
    { name: 'Chlorpromazine', bnfMax: 1000, ddd: 300 },
    { name: 'Clozapine', bnfMax: 900, ddd: 300, individualised: true },
    { name: 'Flupentixol', bnfMax: 18, ddd: 6 },
    { name: 'Fluphenazine', bnfMax: null, ddd: 10, note: 'oral form discontinued in the UK' },
    { name: 'Haloperidol', bnfMax: 20, ddd: 8 },
    { name: 'Iloperidone', bnfMax: 24, ddd: 18 },
    { name: 'Levomepromazine', bnfMax: null, ddd: 300 },
    { name: 'Lumateperone', bnfMax: 42, ddd: null },
    { name: 'Lurasidone', bnfMax: 148, ddd: 60 },
    { name: 'Olanzapine', bnfMax: 20, ddd: 10 },
    { name: 'Paliperidone', bnfMax: 12, ddd: 6 },
    { name: 'Penfluridol', bnfMax: null, ddd: 6, note: 'weekly oral; daily equivalent' },
    { name: 'Pimozide', bnfMax: 20, ddd: 4 },
    { name: 'Quetiapine', bnfMax: 750, ddd: 400 },
    { name: 'Risperidone', bnfMax: 16, ddd: 5 },
    { name: 'Sulpiride', bnfMax: 2400, ddd: 800 },
    { name: 'Trifluoperazine', bnfMax: 20, ddd: 20 },
    { name: 'Xanomeline-trospium', bnfMax: 250, ddd: null, note: 'xanomeline component' },
    { name: 'Ziprasidone', bnfMax: 160, ddd: 80 },
    { name: 'Zuclopenthixol', bnfMax: 150, ddd: 30 }
  ];

  // maxPerInterval: licensed maximum for one injection interval (mg).
  // depotDDD: WHO defined daily dose for the depot (mg/day); dddDays is the
  // calendar length WHO derives it over, and is used only for that column.
  var LAI = [
    { name: 'Aripiprazole', interval: 'monthly', dddDays: 30, maxPerInterval: 400, depotDDD: 13.3 },
    { name: 'Aripiprazole', interval: '2-monthly', dddDays: 60, maxPerInterval: 960, depotDDD: 13.3 },
    { name: 'Paliperidone', interval: 'monthly', dddDays: 30, maxPerInterval: 150, depotDDD: 2.5 },
    { name: 'Paliperidone', interval: '3-monthly', dddDays: 90, maxPerInterval: 525, depotDDD: 2.5 },
    { name: 'Paliperidone', interval: '6-monthly', dddDays: 180, maxPerInterval: 1000, depotDDD: 2.5 },
    { name: 'Risperidone', interval: '2-weekly', dddDays: 14, maxPerInterval: 50, depotDDD: 2.7 },
    { name: 'Olanzapine', interval: '2-weekly', dddDays: 14, maxPerInterval: 300, depotDDD: 10 },
    { name: 'Olanzapine', interval: '4-weekly', dddDays: 28, maxPerInterval: 405, depotDDD: 10 },
    { name: 'Haloperidol decanoate', interval: '4-weekly', dddDays: 28, maxPerInterval: 300, depotDDD: 3.3 },
    { name: 'Flupentixol decanoate', interval: 'weekly', dddDays: 7, maxPerInterval: 400, depotDDD: 4 },
    { name: 'Zuclopenthixol decanoate', interval: 'weekly', dddDays: 7, maxPerInterval: 600, depotDDD: 15 },
    { name: 'Fluphenazine decanoate', interval: '2-weekly', dddDays: 14, maxPerInterval: 100, depotDDD: 1 }
  ];

  // Individualised clozapine target doses (mg/day) for a plasma clozapine of 0.35 mg/L.
  var CLOZ_ANCHORS = {
    rh:     { label: 'Rostami-Hodjegan-derived (standard)', F: { ns: 265, s: 431 }, M: { ns: 323, s: 525 } },
    reeves: { label: 'Reeves-derived', F: { ns: 226, s: 293 }, M: { ns: 275, s: 358 } }
  };
  var CLOZ_BNF_MAX = 900;
  var CLOZ_DDD = 300;
  var SATURATION_CIGS = 10;   // CYP1A2 induction saturates at ~10 cigarettes/day

  /* END GENERATED TABLES */

  /* ------------------------------------------------------------- the index */

  // Reference dose for a non-clozapine oral agent.
  function oralReference(agent) {
    if (agent.ddd && agent.bnfMax) return Math.min(Math.sqrt(agent.bnfMax * agent.ddd), 1.5 * agent.ddd);
    if (agent.ddd) return 1.5 * agent.ddd;                   // no current label maximum
    return agent.bnfMax;                                     // no assigned WHO DDD
  }

  function oralBasis(agent) {
    if (!agent.ddd) return 'Label maximum (no WHO DDD)';
    if (!agent.bnfMax) return '1.5 × DDD (no current UK maximum)';
    return Math.sqrt(agent.bnfMax * agent.ddd) > 1.5 * agent.ddd ? '1.5 × DDD (cap)' : 'Geometric mean';
  }

  // Clozapine target dose for this sex and tobacco consumption.
  function clozapineTarget(scheme, sex, cigs) {
    var a = CLOZ_ANCHORS[scheme][sex];
    var induction = Math.min(1, Math.max(0, cigs) / SATURATION_CIGS);
    return a.ns + (a.s - a.ns) * induction;
  }

  /* ------------------------------------------------------------------ state */

  var state = {
    sex: 'M',
    cigs: 20,
    scheme: 'rh',
    // opens empty: one line, nothing chosen, nothing assumed about the patient's regimen
    rows: [ { key: '', dose: '' } ]
  };

  var nf = function (v, dp) {
    if (v === null || v === undefined || isNaN(v)) return '—';
    return v.toLocaleString('en-GB', { minimumFractionDigits: dp, maximumFractionDigits: dp });
  };

  function agentByKey(key) {
    var bits = key.split(':');
    if (bits[0] === 'oral') {
      var o = ORAL.filter(function (a) { return a.name === bits[1]; })[0];
      return o ? { kind: 'oral', agent: o } : null;
    }
    var l = LAI.filter(function (a) { return a.name + '|' + a.interval === bits[1]; })[0];
    return l ? { kind: 'lai', agent: l } : null;
  }

  // One regimen line -> AP_Load, DDD/day and %BNFmax.
  function scoreRow(row) {
    var found = agentByKey(row.key);
    if (!found) return null;
    var dose = Number(row.dose) || 0;
    var a = found.agent;

    if (found.kind === 'lai') {
      return {
        label: a.name + ' LAI',
        detail: a.interval,
        unit: 'mg / ' + a.interval.replace('-', ' '),
        reference: a.maxPerInterval,
        apLoad: dose / a.maxPerInterval * 100,
        dddDay: a.depotDDD ? (dose / a.dddDays) / a.depotDDD : null,
        bnfPct: dose / a.maxPerInterval * 100
      };
    }
    if (a.name === 'Clozapine') {
      var target = clozapineTarget(state.scheme, state.sex, state.cigs);
      return {
        label: 'Clozapine',
        detail: 'individualised target ' + nf(target, 0) + ' mg/day',
        unit: 'mg/day',
        reference: target,
        apLoad: dose / target * 100,
        dddDay: dose / CLOZ_DDD,
        bnfPct: dose / CLOZ_BNF_MAX * 100
      };
    }
    var ref = oralReference(a);
    return {
      label: a.name,
      detail: a.note || oralBasis(a),
      unit: 'mg/day',
      reference: ref,
      apLoad: dose / ref * 100,
      dddDay: a.ddd ? dose / a.ddd : null,
      bnfPct: a.bnfMax ? dose / a.bnfMax * 100 : null
    };
  }

  /* -------------------------------------------------------------- rendering */

  var $ = function (id) { return document.getElementById(id); };

  // Decimal places for a reference dose: enough to match the published tables
  // (3.46 mg brexpiprazole, 20.8 mg iloperidone, 600 mg amisulpride).
  function refDp(v) { return v < 10 ? 2 : (v < 50 ? 1 : 0); }

  // Oral unless a depot is chosen, said in the label: an intravenous or short-acting
  // intramuscular dose (haloperidol IV, say) must not be typed into an oral box.
  function doseLabel(key) {
    var found = agentByKey(key || '');
    return found && found.kind === 'lai' ? 'Depot dose' : 'Oral dose';
  }

  function agentOptions(selected) {
    var html = '<option value="">Select an antipsychotic…</option>';
    html += '<optgroup label="Oral (tablets, liquids)">';
    ORAL.forEach(function (a) {
      var k = 'oral:' + a.name;
      html += '<option value="' + k + '"' + (k === selected ? ' selected' : '') + '>' + a.name + '</option>';
    });
    html += '</optgroup><optgroup label="Long-acting injectable">';
    LAI.forEach(function (a) {
      var k = 'lai:' + a.name + '|' + a.interval;
      html += '<option value="' + k + '"' + (k === selected ? ' selected' : '') +
              '>' + a.name + ', ' + a.interval + '</option>';
    });
    return html + '</optgroup>';
  }

  function renderRows() {
    var host = $('rows');
    host.innerHTML = '';
    state.rows.forEach(function (row, i) {
      var scored = scoreRow(row);
      var div = document.createElement('div');
      div.className = 'row';
      div.innerHTML =
        '<div class="field">' +
          '<label for="agent' + i + '">Antipsychotic</label>' +
          '<select id="agent' + i + '" data-i="' + i + '" class="js-agent">' + agentOptions(row.key) + '</select>' +
        '</div>' +
        '<div class="field">' +
          '<label for="dose' + i + '">' + doseLabel(row.key) + ' <span class="unit">' + (scored ? scored.unit : 'mg/day') + '</span></label>' +
          '<input type="number" id="dose' + i + '" data-i="' + i + '" class="js-dose" min="0" step="any" value="' +
            (row.dose === '' ? '' : row.dose) + '">' +
        '</div>' +
        '<button type="button" class="icon-btn js-remove" data-i="' + i + '" aria-label="Remove ' +
          (scored ? scored.label : 'this line') + '">×</button>';
      host.appendChild(div);
    });
    if (!state.rows.length) {
      host.innerHTML = '<p class="empty">No antipsychotic yet. Add one to score a regimen.</p>';
    }
  }

  function flagFor(total) {
    if (total > 150) return '<span class="flag flag--high">above 150</span>';
    if (total > 100) return '<span class="flag flag--over">above reference</span>';
    return '';
  }

  function renderResult() {
    var scored = state.rows.map(scoreRow).filter(Boolean);
    var totals = scored.reduce(function (acc, s) {
      acc.ap += s.apLoad;
      if (s.dddDay !== null) acc.ddd += s.dddDay; else acc.dddPartial = true;
      if (s.bnfPct !== null) acc.bnf += s.bnfPct; else acc.bnfPartial = true;
      return acc;
    }, { ap: 0, ddd: 0, bnf: 0, dddPartial: false, bnfPartial: false });

    $('total-value').textContent = scored.length ? nf(totals.ap, 0) : '—';
    $('total-value').classList.toggle('is-empty', !scored.length);
    $('total-flag').innerHTML = scored.length ? flagFor(totals.ap) : '';
    $('cmp-ddd').textContent = scored.length ? nf(totals.ddd, 2) + (totals.dddPartial ? '*' : '') : '—';
    $('cmp-bnf').textContent = scored.length ? nf(totals.bnf, 0) + (totals.bnfPartial ? '*' : '') : '—';

    var hasCloz = state.rows.some(function (r) { return r.key === 'oral:Clozapine'; });
    var box = $('cloz-target');
    box.hidden = !hasCloz;
    if (hasCloz) {
      var t = clozapineTarget(state.scheme, state.sex, state.cigs);
      box.innerHTML = 'Clozapine target for a ' + (state.sex === 'F' ? 'woman' : 'man') +
        ' smoking ' + nf(state.cigs, 0) + ' cigarettes/day: <b>' + nf(t, 0) + ' mg/day</b> ' +
        '— the dose expected to give a plasma clozapine of about 0.35 mg/L, and so the dose that scores 100.';
    }

    var body = $('breakdown-body');
    body.innerHTML = '';
    if (!scored.length) {
      body.innerHTML = '<tr><td colspan="5" class="empty">Add an antipsychotic to see the breakdown.</td></tr>';
    } else {
      scored.forEach(function (s) {
        var tr = document.createElement('tr');
        tr.innerHTML =
          '<td class="agent-cell">' + s.label + '<br><span class="drug-note">' + s.detail + '</span></td>' +
          '<td class="num" data-label="Ref.">' + nf(s.reference, refDp(s.reference)) + '</td>' +
          '<td class="num" data-label="AP_Load">' + nf(s.apLoad, 0) + '</td>' +
          '<td class="num" data-label="DDD/d">' + (s.dddDay === null ? '—' : nf(s.dddDay, 2)) + '</td>' +
          '<td class="num" data-label="%BNF">' + (s.bnfPct === null ? '—' : nf(s.bnfPct, 0)) + '</td>';
        body.appendChild(tr);
      });
    }
    $('foot-ap').textContent = scored.length ? nf(totals.ap, 0) : '—';
    $('foot-ddd').textContent = scored.length ? nf(totals.ddd, 2) : '—';
    $('foot-bnf').textContent = scored.length ? nf(totals.bnf, 0) : '—';
    $('partial-note').hidden = !(totals.dddPartial || totals.bnfPartial);
  }

  function renderReference() {
    var q = ($('ref-search').value || '').trim().toLowerCase();
    var body = $('ref-body');
    body.innerHTML = '';

    function add(html) { var tr = document.createElement('tr'); tr.innerHTML = html; body.appendChild(tr); }

    var orals = ORAL.filter(function (a) {
      return !a.individualised && a.name.toLowerCase().indexOf(q) > -1;
    });
    if (orals.length) {
      add('<td colspan="5" class="group-cell">Oral antipsychotics — mg/day</td>');
      body.lastChild.className = 'group';
      orals.forEach(function (a) {
        var ref = oralReference(a);
        add('<td class="agent-cell">' + a.name + (a.note ? '<br><span class="drug-note">' + a.note + '</span>' : '') + '</td>' +
            '<td class="num" data-label="BNFmax">' + (a.bnfMax === null ? '—' : nf(a.bnfMax, 0)) + '</td>' +
            '<td class="num" data-label="WHO DDD">' + (a.ddd === null ? '—' : nf(a.ddd, 0)) + '</td>' +
            '<td class="num" data-label="AP_Load = 100">' + nf(ref, refDp(ref)) + '</td>' +
            '<td data-label="Basis">' + oralBasis(a) + '</td>');
      });
    }

    if ('clozapine'.indexOf(q) > -1 || q === '') {
      add('<td colspan="5">Clozapine — individualised, mg/day</td>');
      body.lastChild.className = 'group';
      [['Female, non-smoker', 'F', 0], ['Male, non-smoker', 'M', 0],
       ['Female, smoker (≥10/day)', 'F', 10], ['Male, smoker (≥10/day)', 'M', 10]
      ].forEach(function (row) {
        var t = clozapineTarget(state.scheme, row[1], row[2]);
        add('<td class="agent-cell">' + row[0] + '</td>' +
            '<td class="num" data-label="BNFmax">900</td>' +
            '<td class="num" data-label="WHO DDD">300</td>' +
            '<td class="num" data-label="AP_Load = 100">' + nf(t, 0) + '</td>' +
            '<td data-label="Basis">Target for 0.35 mg/L</td>');
      });
    }

    var lais = LAI.filter(function (a) { return (a.name + ' ' + a.interval).toLowerCase().indexOf(q) > -1; });
    if (lais.length) {
      add('<td colspan="5">Long-acting injectables — mg per dosing interval</td>');
      body.lastChild.className = 'group';
      lais.forEach(function (a) {
        add('<td class="agent-cell">' + a.name + ', ' + a.interval + '</td>' +
            '<td class="num" data-label="Licensed max">' + nf(a.maxPerInterval, 0) + '</td>' +
            '<td class="num" data-label="WHO depot DDD">' + (a.depotDDD === null ? '—' : nf(a.depotDDD, 1)) + '</td>' +
            '<td class="num" data-label="AP_Load = 100">' + nf(a.maxPerInterval, 0) + '</td>' +
            '<td data-label="Basis">Licensed maximum per interval</td>');
      });
    }

    if (!body.children.length) {
      add('<td colspan="5" class="empty">Nothing matches that name.</td>');
    }
  }

  function render() { renderRows(); renderResult(); renderReference(); }

  /* ----------------------------------------------------------------- events */

  function bind() {
    $('rows').addEventListener('change', function (e) {
      if (e.target.classList.contains('js-agent')) {
        state.rows[+e.target.dataset.i].key = e.target.value;
        render();
      }
    });
    $('rows').addEventListener('input', function (e) {
      if (e.target.classList.contains('js-dose')) {
        state.rows[+e.target.dataset.i].dose = e.target.value === '' ? '' : Number(e.target.value);
        renderResult();
      }
    });
    $('rows').addEventListener('click', function (e) {
      var btn = e.target.closest('.js-remove');
      if (!btn) return;
      state.rows.splice(+btn.dataset.i, 1);
      render();
    });
    $('add-row').addEventListener('click', function () {
      state.rows.push({ key: '', dose: '' });
      render();
      var sel = document.querySelectorAll('.js-agent');
      if (sel.length) sel[sel.length - 1].focus();
    });
    $('clear-rows').addEventListener('click', function () {
      state.rows = [];
      render();
    });

    Array.prototype.forEach.call(document.querySelectorAll('input[name="sex"]'), function (r) {
      r.addEventListener('change', function () { state.sex = r.value; render(); });
    });
    $('cigs').addEventListener('input', function () {
      state.cigs = Number($('cigs').value) || 0;
      $('cigs-num').value = state.cigs;
      renderResult(); renderReference();
    });
    $('cigs-num').addEventListener('input', function () {
      state.cigs = Math.max(0, Math.min(60, Number($('cigs-num').value) || 0));
      $('cigs').value = state.cigs;
      renderResult(); renderReference();
    });
    $('scheme').addEventListener('change', function () {
      state.scheme = $('scheme').value;
      render();
    });
    $('ref-search').addEventListener('input', renderReference);

    $('copy').addEventListener('click', function () {
      var scored = state.rows.map(scoreRow).filter(Boolean);
      if (!scored.length) return;
      var total = scored.reduce(function (t, s) { return t + s.apLoad; }, 0);
      var lines = ['AP_Load2026 — ' + (state.sex === 'F' ? 'female' : 'male') + ', ' +
                   state.cigs + ' cigarettes/day, ' + CLOZ_ANCHORS[state.scheme].label + ' clozapine anchors'];
      scored.forEach(function (s) {
        lines.push('  ' + s.label + ': ' + nf(s.apLoad, 0) + '% of ' + nf(s.reference, 0) + ' ' + s.unit);
      });
      lines.push('  Total AP_Load2026: ' + nf(total, 0));
      var text = lines.join('\n');
      var done = function () {
        $('copy').textContent = 'Copied';
        setTimeout(function () { $('copy').textContent = 'Copy summary'; }, 1600);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () { window.prompt('Copy the summary:', text); });
      } else {
        window.prompt('Copy the summary:', text);
      }
    });
  }

  /* Under node (the test in tests/test_web.js) there is no page to render: the
     tables and the scoring functions are exported instead, so the calculator is
     checked against manuscript Table 5 like the other implementations. */
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      ORAL: ORAL, LAI: LAI, CLOZ_ANCHORS: CLOZ_ANCHORS, state: state,
      oralReference: oralReference, clozapineTarget: clozapineTarget, scoreRow: scoreRow
    };
    return;
  }

  bind();
  render();
})();
