# Changes

## 1.1.0 — 21 November 2026

Reference tables re-dated `2026-11`, after checking every entry against the current WHO
ATC/DDD Index (accessed 21 November 2026) during peer review.

### Reference doses that change

| agent | WHO DDD | reference, 2026-09 | reference, 2026-11 | basis |
|---|---|---|---|---|
| brexpiprazole | 3 mg (new) | 4 mg (label max) | 3.46 mg | geometric mean |
| cariprazine | 3 mg (new) | 6 mg (label max) | 4.24 mg | geometric mean |
| iloperidone | 18 mg (new) | 24 mg (label max) | 20.8 mg | geometric mean |

A regimen containing any of these three agents now scores higher than under `2026-09`.
No other reference dose changes, and the sixteen regimens of manuscript Table 5 score
exactly as before.

Depot DDDs added for olanzapine (10 mg), flupentixol (4 mg), zuclopenthixol (15 mg) and
fluphenazine (1 mg), and for six-monthly paliperidone (2.5 mg). These feed only the
DDD/day comparison column; depots are still referenced to the licensed formulation
maximum, so no depot score changes.

### Code

- Python: type annotations throughout (checked with `mypy`) and formatting with `black`;
  the build scripts and Python tests likewise.
- `generate_web.py` now stops with a clear message if `web/apload.js` is missing, and the
  whole `web/` folder is part of the repository (a clone without it could not build or
  pass the tests). Compiled `__pycache__` files removed from the repository.
- The non-finite dose check reads `math.isfinite` rather than `value != value`.
- `normalise_sex` simplified; behaviour unchanged (`1` = male, `0` = female, anything
  else, including `2`, refused).

### Browser calculator

- A bold research-use-only notice at the top of the page.
- The selected sex is now a filled button with a tick, so which one is on is clear.
- "ten cigarettes per day. E-cigarettes…" as two sentences.
- Dose boxes say "Oral dose" or "Depot dose", and the regimen note says that intravenous
  and short-acting intramuscular doses are not covered.

### README

Links to the browser calculator and states that the tool is for research use only.

## 1.0.2 — 19 September 2026

Browser calculator only; no change to the index or to any reference number.

- The regimen opens as one empty line rather than a worked example, so nothing is
  assumed about the patient in front of you.
- Reference table: the `AP_Load = 50` column removed, `BNF / label max` renamed
  `BNFmax`, and the column headers set larger (10.5px was too small to read).
- Table headers enlarged throughout, and the drug notes no longer repeat the
  Basis column (`1.5 x DDD (no current UK max)` beside a basis of `1.5 × DDD (no
  current UK maximum)` said the same thing twice).
- On a phone, both tables now stack one drug per block with every figure
  labelled, instead of hiding the AP_Load column off the right edge.
- The "What this is, and what it is not" section removed; its one essential line
  ("a research normalisation of prescribed dose, not a prescribing or regulatory
  instrument") moved into the footer.

## 1.0.1 — 18 September 2026

Corrections arising from a pre-release code review. The index itself is unchanged:
all sixteen regimens of manuscript Table 5 score exactly as published, in Python, R,
SPSS and the browser calculator.

### Doses that could mean two things are now refused, not guessed

The free-text dose parser took the first number in the field and ignored the rest,
which contradicted the design principle that anything unresolvable is refused. The
following were read wrongly and are now refused with a reason:

| written as | was read as | now |
|---|---|---|
| `1,000 mg` (chlorpromazine) | 1 mg — a score of 0.2 instead of 222 | refused, `ambiguous_decimal_or_thousands_separator` |
| `300 mg bd` | 300 mg/day instead of 600 | refused, `dose_is_per_administration_not_daily_total` |
| `2 x 100 mg` | 2 mg | refused, same code |
| `100-0-200` | 100 mg | refused, same code |
| `10mg mane, 5mg nocte` | 10 mg | refused, `more_than_one_dose_in_field` |
| `30 ml` | 30 mg | refused, `dose_unit_not_recognised` |
| `-10` | 10 mg | refused, `dose_not_positive` |

`500 microgram` and `1 g` are now converted to mg rather than read as 500 mg and 1 mg.
A numeric zero and the string `"0"` are now treated the same way (both refused);
previously one was refused and the other accepted.

Doses stated once a day (`od`, `nocte`, `mane`, `daily`, `450mg/d`) and doses carrying a
schedule (`400 mg/mes`, `960/2meses`) are still accepted, as before.

### A dosing interval can be named in any of the usual ways

`monthly` and `4-weekly` were matched as literal strings, so haloperidol decanoate
"monthly" was refused (the table files it as 4-weekly) and aripiprazole "4-weekly" was
refused (the table says monthly). Intervals are now resolved to the schedule they name,
in days, and the depot is found either way. The vocabulary — English and Spanish,
including `every 4 weeks`, `q4w`, `28 days`, `mensual`, `quincenal` — is a new reference
file, `reference/ap_load2026_intervals.csv`, read by Python and R and compiled into the
SPSS syntax.

### Brand names are recognised after the generic name

`Risperidone Consta 50 mg` was refused as an unresolvable formulation: the prefix match
went to `risper` and the Consta two-weekly hint, being later in the string, was never
seen. A brand name that fixes the interval is now looked for anywhere in the drug field.

### The browser calculator is generated from the reference tables

`web/apload.js` carried the reference tables typed out by hand, and
`web/apload-squarespace.html` carried a second copy of the whole script. Both are now
written by `build/generate_web.py` from `reference/*.csv`, in the same way as the SPSS
syntax, and `tests/test_generated.py` fails if either has fallen behind. Two consequences
for the calculator's comparison columns:

- the WHO depot DDD for six-monthly paliperidone is not tabulated, and the column now
  shows that rather than borrowing the monthly product's value;
- the DDD/day column is documented as using the calendar month the WHO derives depot
  DDDs over (30, 60, 90, 180 days). The AP_Load2026 score never uses those numbers.

### Smaller

- `--review-csv` and `--detail-csv` are written with their header even when there is
  nothing to report, so a previous run's file can no longer be read as this one's.
- Citation headers added to the Python, R and SPSS implementations, and the author list
  and paper title in the README and on the web pages corrected to the v1.0 list.
- `LICENSE` (MIT for the code, with the reference tables' sources acknowledged) and
  `CITATION.cff` added for the Zenodo release.

### Tests

New: `tests/test_dose_parsing.py` and `tests/test_dose_parsing.R` (the fourteen awkward
doses in `examples/tricky_doses.csv`), `tests/test_generated.py` (SPSS and web tables
match `reference/`), `tests/test_web.js` (the browser calculator reproduces Table 5),
`tests/run_all.sh`. `tests/test_agreement.py` now compares Python and R on the new
fixture as well.
