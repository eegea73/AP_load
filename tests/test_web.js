/* The browser calculator must reproduce manuscript Table 5, like the other
 * implementations. Run with:  node tests/test_web.js
 *
 * apload.js exports its tables and scoring functions when there is no document
 * to render, so this test drives exactly the code the web page runs.
 */
'use strict';
var fs = require('fs');
var path = require('path');
var ROOT = path.dirname(__dirname);
var app = require(path.join(ROOT, 'web', 'apload.js'));

function readCsv(file) {
  var lines = fs.readFileSync(path.join(ROOT, 'examples', file), 'utf8')
                .replace(/^﻿/, '').trim().split(/\r?\n/);
  var head = lines.shift().split(',');
  return lines.map(function (line) {
    var cells = line.split(',');
    var row = {};
    head.forEach(function (h, i) { row[h.trim()] = (cells[i] || '').trim(); });
    return row;
  });
}

function capitalise(s) { return s.charAt(0).toUpperCase() + s.slice(1).toLowerCase(); }

function keyFor(row) {
  var name = capitalise(row.drug);
  if ((row.route || '').toLowerCase() === 'lai') {
    var hit = app.LAI.filter(function (a) {
      return a.name.split(' ')[0] === name && a.interval === row.interval;
    })[0];
    if (!hit) throw new Error('no depot row for ' + row.drug + ' ' + row.interval);
    return 'lai:' + hit.name + '|' + hit.interval;
  }
  return 'oral:' + name;
}

var regimens = readCsv('table5_regimens.csv');
var expected = {};
readCsv('table5_expected.csv').forEach(function (r) {
  expected[r.patient_id] = { value: Number(r.AP_Load2026_rounded), label: r.regimen };
});

var byPatient = {};
regimens.forEach(function (r) {
  (byPatient[r.patient_id] = byPatient[r.patient_id] || []).push(r);
});

var fails = [];
Object.keys(expected).forEach(function (pid) {
  var rows = byPatient[pid] || [];
  app.state.sex = rows[0].sex.toLowerCase().charAt(0) === 'f' ? 'F' : 'M';
  app.state.cigs = Number(rows[0].cigarettes_per_day) || 0;
  app.state.scheme = 'rh';
  var total = rows.reduce(function (sum, r) {
    var scored = app.scoreRow({ key: keyFor(r), dose: Number(r.dose) });
    if (!scored) throw new Error('no agent matched for ' + r.drug);
    return sum + scored.apLoad;
  }, 0);
  var ok = Math.round(total) === expected[pid].value;
  console.log('  ' + pid + '  ' + expected[pid].label.padEnd(52) +
              total.toFixed(1).padStart(8) + '  Table 5: ' +
              String(expected[pid].value).padStart(3) + '  ' + (ok ? 'ok' : 'MISMATCH'));
  if (!ok) fails.push(pid);
});

console.log('');
if (fails.length) {
  console.log('FAILURES: ' + fails.join(', '));
  process.exit(1);
}
console.log('The browser calculator reproduces all 16 Table 5 regimens.');
