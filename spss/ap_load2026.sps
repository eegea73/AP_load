* Encoding: UTF-8.
* ----------------------------------------------------------------------------.
* AP_Load2026 - the Antipsychotic Dose Load.
* Fernandez-Egea E, Krishnadas R, Jenkins C, Patel R, Cardinal RN, Wolpe N (2026).
* The Antipsychotic Dose Load (AP_Load2026): a normalised prescribed-dose index
* for schizophrenia research. [citation to be completed on acceptance].
* Reference table 2026-11. GENERATED FILE - do not edit by hand.
* Regenerate with:  python3 build/generate_spss.py
* ----------------------------------------------------------------------------.
*
* Expects one row per PATIENT (wide), with up to 4 antipsychotic slots:
*
*   patient_id   any type
*   sex          NUMERIC, 1 = male, 0 = female
*   cigs_per_day NUMERIC, cigarettes per day (0 for a non-smoker)
*   AP_1 .. AP_4          STRING, drug name (generic or brand, English or Spanish)
*   AP_1_dose .. AP_4_dose      NUMERIC, mg per day (oral) or mg per interval (depot)
*   AP_1_route .. AP_4_route    STRING, 'oral' or 'LAI'   (optional)
*   AP_1_interval .. AP_4_interval  STRING, e.g. 'monthly' (depots only)
*
* Unlike the Python and R implementations, this syntax does NOT read free text
* doses. Doses must already be numeric. Anything that cannot be resolved without
* guessing is flagged in apl_flag and left out of the score - never scored as 0.
*
* apl_flag:  0 scored   1 drug not recognised   2 dose missing or not numeric
*            3 oral or depot could not be told apart   4 depot interval missing
*            5 sex missing (clozapine)   6 smoking missing (clozapine)
* ----------------------------------------------------------------------------.
*
* If your data has no route/interval columns, create empty ones first:
*   STRING AP_1_route AP_2_route AP_3_route AP_4_route (A8)
*          AP_1_interval AP_2_interval AP_3_interval AP_4_interval (A12).
* An oral-only agent (clozapine, quetiapine, amisulpride) then still scores;
* an agent with both forms is flagged rather than guessed.
* ----------------------------------------------------------------------------.

* ---- 1. restructure the slots to one row per prescription --------------------.

DATASET COPY apl_work.
DATASET ACTIVATE apl_work.

VARSTOCASES
  /MAKE apl_drug FROM AP_1 AP_2 AP_3 AP_4
  /MAKE apl_dose FROM AP_1_dose AP_2_dose AP_3_dose AP_4_dose
  /MAKE apl_route FROM AP_1_route AP_2_route AP_3_route AP_4_route
  /MAKE apl_interval FROM AP_1_interval AP_2_interval AP_3_interval AP_4_interval
  /INDEX = apl_slot
  /KEEP = patient_id sex cigs_per_day
  /NULL = DROP.

STRING apl_nm (A64) apl_gen (A24) apl_stem (A14) apl_form (A4) apl_int (A24)
       apl_basis (A48).
NUMERIC apl_ref (F10.4) apl_score (F10.4) apl_flag (F1.0) apl_frac (F6.4).
COMPUTE apl_flag = 0.
COMPUTE apl_nm = LOWER(LTRIM(RTRIM(apl_drug))).
COMPUTE apl_gen = ''.
COMPUTE apl_basis = ''.
COMPUTE apl_form = LOWER(LTRIM(RTRIM(apl_route))).
COMPUTE apl_int = LOWER(LTRIM(RTRIM(apl_interval))).

* ---- 2. drug names, matched on stems anchored at the start of the string -----.
* Longest stem first, so a short stem can never shadow a longer one.
* Matching is by prefix, NOT by INDEX(): INDEX() would read amisulpride as
* sulpiride. To support another country, add a branch here and to the CSV.

DO IF (SUBSTR(apl_nm, 1, 12) = 'trifluoperaz').
+  COMPUTE apl_gen = 'trifluoperazine'.
+  COMPUTE apl_stem = 'trifluoperaz'.
+ELSE IF (SUBSTR(apl_nm, 1, 11) = 'levomeproma').
+  COMPUTE apl_gen = 'levomepromazine'.
+  COMPUTE apl_stem = 'levomeproma'.
+ELSE IF (SUBSTR(apl_nm, 1, 10) = 'chlorproma').
+  COMPUTE apl_gen = 'chlorpromazine'.
+  COMPUTE apl_stem = 'chlorproma'.
+ELSE IF (SUBSTR(apl_nm, 1, 10) = 'zucloplent').
+  COMPUTE apl_gen = 'zuclopenthixol'.
+  COMPUTE apl_stem = 'zucloplent'.
+ELSE IF (SUBSTR(apl_nm, 1, 10) = 'cisordinol').
+  COMPUTE apl_gen = 'zuclopenthixol'.
+  COMPUTE apl_stem = 'cisordinol'.
+ELSE IF (SUBSTR(apl_nm, 1, 10) = 'cariprazin').
+  COMPUTE apl_gen = 'cariprazine'.
+  COMPUTE apl_stem = 'cariprazin'.
+ELSE IF (SUBSTR(apl_nm, 1, 10) = 'brexpipraz').
+  COMPUTE apl_gen = 'brexpiprazole'.
+  COMPUTE apl_stem = 'brexpipraz'.
+ELSE IF (SUBSTR(apl_nm, 1, 10) = 'lumatepero').
+  COMPUTE apl_gen = 'lumateperone'.
+  COMPUTE apl_stem = 'lumatepero'.
+ELSE IF (SUBSTR(apl_nm, 1, 9) = 'denzapine').
+  COMPUTE apl_gen = 'clozapine'.
+  COMPUTE apl_stem = 'denzapine'.
+ELSE IF (SUBSTR(apl_nm, 1, 9) = 'zypadhera').
+  COMPUTE apl_gen = 'olanzapine'.
+  COMPUTE apl_stem = 'zypadhera'.
+ELSE IF (SUBSTR(apl_nm, 1, 9) = 'paliperid').
+  COMPUTE apl_gen = 'paliperidone'.
+  COMPUTE apl_stem = 'paliperid'.
+ELSE IF (SUBSTR(apl_nm, 1, 9) = 'tepazepan').
+  COMPUTE apl_gen = 'sulpiride'.
+  COMPUTE apl_stem = 'tepazepan'.
+ELSE IF (SUBSTR(apl_nm, 1, 9) = 'haloperid').
+  COMPUTE apl_gen = 'haloperidol'.
+  COMPUTE apl_stem = 'haloperid'.
+ELSE IF (SUBSTR(apl_nm, 1, 9) = 'clorproma').
+  COMPUTE apl_gen = 'chlorpromazine'.
+  COMPUTE apl_stem = 'clorproma'.
+ELSE IF (SUBSTR(apl_nm, 1, 9) = 'largactil').
+  COMPUTE apl_gen = 'chlorpromazine'.
+  COMPUTE apl_stem = 'largactil'.
+ELSE IF (SUBSTR(apl_nm, 1, 9) = 'fluphenaz').
+  COMPUTE apl_gen = 'fluphenazine'.
+  COMPUTE apl_stem = 'fluphenaz'.
+ELSE IF (SUBSTR(apl_nm, 1, 9) = 'zuclopent').
+  COMPUTE apl_gen = 'zuclopenthixol'.
+  COMPUTE apl_stem = 'zuclopent'.
+ELSE IF (SUBSTR(apl_nm, 1, 9) = 'stelazine').
+  COMPUTE apl_gen = 'trifluoperazine'.
+  COMPUTE apl_stem = 'stelazine'.
+ELSE IF (SUBSTR(apl_nm, 1, 9) = 'penflurid').
+  COMPUTE apl_gen = 'penfluridol'.
+  COMPUTE apl_stem = 'penflurid'.
+ELSE IF (SUBSTR(apl_nm, 1, 9) = 'blonanser').
+  COMPUTE apl_gen = 'blonanserin'.
+  COMPUTE apl_stem = 'blonanser'.
+ELSE IF (SUBSTR(apl_nm, 1, 9) = 'xanomelin').
+  COMPUTE apl_gen = 'xanomeline-trospium'.
+  COMPUTE apl_stem = 'xanomelin'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'perseris').
+  COMPUTE apl_gen = 'risperidone'.
+  COMPUTE apl_stem = 'perseris'.
+  COMPUTE apl_form = 'lai'.
+  IF (LTRIM(RTRIM(apl_int)) = '') apl_int = 'monthly'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'seroquel').
+  COMPUTE apl_gen = 'quetiapine'.
+  COMPUTE apl_stem = 'seroquel'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'trevicta').
+  COMPUTE apl_gen = 'paliperidone'.
+  COMPUTE apl_stem = 'trevicta'.
+  COMPUTE apl_form = 'lai'.
+  IF (LTRIM(RTRIM(apl_int)) = '') apl_int = '3-monthly'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'maintena').
+  COMPUTE apl_gen = 'aripiprazole'.
+  COMPUTE apl_stem = 'maintena'.
+  COMPUTE apl_form = 'lai'.
+  IF (LTRIM(RTRIM(apl_int)) = '') apl_int = 'monthly'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'aristada').
+  COMPUTE apl_gen = 'aripiprazole'.
+  COMPUTE apl_stem = 'aristada'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'dolmatil').
+  COMPUTE apl_gen = 'sulpiride'.
+  COMPUTE apl_stem = 'dolmatil'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'dogmatil').
+  COMPUTE apl_gen = 'sulpiride'.
+  COMPUTE apl_stem = 'dogmatil'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'serenace').
+  COMPUTE apl_gen = 'haloperidol'.
+  COMPUTE apl_stem = 'serenace'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'flufenaz').
+  COMPUTE apl_gen = 'fluphenazine'.
+  COMPUTE apl_stem = 'flufenaz'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'modecate').
+  COMPUTE apl_gen = 'fluphenazine'.
+  COMPUTE apl_stem = 'modecate'.
+  COMPUTE apl_form = 'lai'.
+  IF (LTRIM(RTRIM(apl_int)) = '') apl_int = '2-weekly'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'flupenth').
+  COMPUTE apl_gen = 'flupentixol'.
+  COMPUTE apl_stem = 'flupenth'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'fluanxol').
+  COMPUTE apl_gen = 'flupentixol'.
+  COMPUTE apl_stem = 'fluanxol'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'clopixol').
+  COMPUTE apl_gen = 'zuclopenthixol'.
+  COMPUTE apl_stem = 'clopixol'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'eskazine').
+  COMPUTE apl_gen = 'trifluoperazine'.
+  COMPUTE apl_stem = 'eskazine'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'ziprasid').
+  COMPUTE apl_gen = 'ziprasidone'.
+  COMPUTE apl_stem = 'ziprasid'.
+ELSE IF (SUBSTR(apl_nm, 1, 8) = 'iloperid').
+  COMPUTE apl_gen = 'iloperidone'.
+  COMPUTE apl_stem = 'iloperid'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'leponex').
+  COMPUTE apl_gen = 'clozapine'.
+  COMPUTE apl_stem = 'leponex'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'zaponex').
+  COMPUTE apl_gen = 'clozapine'.
+  COMPUTE apl_stem = 'zaponex'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'olanzap').
+  COMPUTE apl_gen = 'olanzapine'.
+  COMPUTE apl_stem = 'olanzap'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'zyprexa').
+  COMPUTE apl_gen = 'olanzapine'.
+  COMPUTE apl_stem = 'zyprexa'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'zalasta').
+  COMPUTE apl_gen = 'olanzapine'.
+  COMPUTE apl_stem = 'zalasta'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'quetiap').
+  COMPUTE apl_gen = 'quetiapine'.
+  COMPUTE apl_stem = 'quetiap'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'xeplion').
+  COMPUTE apl_gen = 'paliperidone'.
+  COMPUTE apl_stem = 'xeplion'.
+  COMPUTE apl_form = 'lai'.
+  IF (LTRIM(RTRIM(apl_int)) = '') apl_int = 'monthly'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'byannli').
+  COMPUTE apl_gen = 'paliperidone'.
+  COMPUTE apl_stem = 'byannli'.
+  COMPUTE apl_form = 'lai'.
+  IF (LTRIM(RTRIM(apl_int)) = '') apl_int = '6-monthly'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'abilify').
+  COMPUTE apl_gen = 'aripiprazole'.
+  COMPUTE apl_stem = 'abilify'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'amisulp').
+  COMPUTE apl_gen = 'amisulpride'.
+  COMPUTE apl_stem = 'amisulp'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'guastil').
+  COMPUTE apl_gen = 'sulpiride'.
+  COMPUTE apl_stem = 'guastil'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'sinogan').
+  COMPUTE apl_gen = 'levomepromazine'.
+  COMPUTE apl_stem = 'sinogan'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'nozinan').
+  COMPUTE apl_gen = 'levomepromazine'.
+  COMPUTE apl_stem = 'nozinan'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'flupent').
+  COMPUTE apl_gen = 'flupentixol'.
+  COMPUTE apl_stem = 'flupent'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'depixol').
+  COMPUTE apl_gen = 'flupentixol'.
+  COMPUTE apl_stem = 'depixol'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'pimozid').
+  COMPUTE apl_gen = 'pimozide'.
+  COMPUTE apl_stem = 'pimozid'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'lurasid').
+  COMPUTE apl_gen = 'lurasidone'.
+  COMPUTE apl_stem = 'lurasid'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'sycrest').
+  COMPUTE apl_gen = 'asenapine'.
+  COMPUTE apl_stem = 'sycrest'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'saphris').
+  COMPUTE apl_gen = 'asenapine'.
+  COMPUTE apl_stem = 'saphris'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'reagila').
+  COMPUTE apl_gen = 'cariprazine'.
+  COMPUTE apl_stem = 'reagila'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'vraylar').
+  COMPUTE apl_gen = 'cariprazine'.
+  COMPUTE apl_stem = 'vraylar'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'rexulti').
+  COMPUTE apl_gen = 'brexpiprazole'.
+  COMPUTE apl_stem = 'rexulti'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'caplyta').
+  COMPUTE apl_gen = 'lumateperone'.
+  COMPUTE apl_stem = 'caplyta'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'lonasen').
+  COMPUTE apl_gen = 'blonanserin'.
+  COMPUTE apl_stem = 'lonasen'.
+ELSE IF (SUBSTR(apl_nm, 1, 7) = 'cobenfy').
+  COMPUTE apl_gen = 'xanomeline-trospium'.
+  COMPUTE apl_stem = 'cobenfy'.
+ELSE IF (SUBSTR(apl_nm, 1, 6) = 'risper').
+  COMPUTE apl_gen = 'risperidone'.
+  COMPUTE apl_stem = 'risper'.
+ELSE IF (SUBSTR(apl_nm, 1, 6) = 'consta').
+  COMPUTE apl_gen = 'risperidone'.
+  COMPUTE apl_stem = 'consta'.
+  COMPUTE apl_form = 'lai'.
+  IF (LTRIM(RTRIM(apl_int)) = '') apl_int = '2-weekly'.
+ELSE IF (SUBSTR(apl_nm, 1, 6) = 'invega').
+  COMPUTE apl_gen = 'paliperidone'.
+  COMPUTE apl_stem = 'invega'.
+ELSE IF (SUBSTR(apl_nm, 1, 6) = 'solian').
+  COMPUTE apl_gen = 'amisulpride'.
+  COMPUTE apl_stem = 'solian'.
+ELSE IF (SUBSTR(apl_nm, 1, 6) = 'sulpir').
+  COMPUTE apl_gen = 'sulpiride'.
+  COMPUTE apl_stem = 'sulpir'.
+ELSE IF (SUBSTR(apl_nm, 1, 6) = 'sulpor').
+  COMPUTE apl_gen = 'sulpiride'.
+  COMPUTE apl_stem = 'sulpor'.
+ELSE IF (SUBSTR(apl_nm, 1, 6) = 'digton').
+  COMPUTE apl_gen = 'sulpiride'.
+  COMPUTE apl_stem = 'digton'.
+ELSE IF (SUBSTR(apl_nm, 1, 6) = 'haldol').
+  COMPUTE apl_gen = 'haloperidol'.
+  COMPUTE apl_stem = 'haldol'.
+ELSE IF (SUBSTR(apl_nm, 1, 6) = 'latuda').
+  COMPUTE apl_gen = 'lurasidone'.
+  COMPUTE apl_stem = 'latuda'.
+ELSE IF (SUBSTR(apl_nm, 1, 6) = 'zeldox').
+  COMPUTE apl_gen = 'ziprasidone'.
+  COMPUTE apl_stem = 'zeldox'.
+ELSE IF (SUBSTR(apl_nm, 1, 6) = 'geodon').
+  COMPUTE apl_gen = 'ziprasidone'.
+  COMPUTE apl_stem = 'geodon'.
+ELSE IF (SUBSTR(apl_nm, 1, 6) = 'asenap').
+  COMPUTE apl_gen = 'asenapine'.
+  COMPUTE apl_stem = 'asenap'.
+ELSE IF (SUBSTR(apl_nm, 1, 6) = 'fanapt').
+  COMPUTE apl_gen = 'iloperidone'.
+  COMPUTE apl_stem = 'fanapt'.
+ELSE IF (SUBSTR(apl_nm, 1, 5) = 'uzedy').
+  COMPUTE apl_gen = 'risperidone'.
+  COMPUTE apl_stem = 'uzedy'.
+ELSE IF (SUBSTR(apl_nm, 1, 5) = 'semap').
+  COMPUTE apl_gen = 'penfluridol'.
+  COMPUTE apl_stem = 'semap'.
+ELSE IF (SUBSTR(apl_nm, 1, 4) = 'cloz').
+  COMPUTE apl_gen = 'clozapine'.
+  COMPUTE apl_stem = 'cloz'.
+ELSE IF (SUBSTR(apl_nm, 1, 4) = 'arip').
+  COMPUTE apl_gen = 'aripiprazole'.
+  COMPUTE apl_stem = 'arip'.
+ELSE IF (SUBSTR(apl_nm, 1, 4) = 'orap').
+  COMPUTE apl_gen = 'pimozide'.
+  COMPUTE apl_stem = 'orap'.
+ELSE.
+  COMPUTE apl_flag = 1.
END IF.

* ---- 3. dose, formulation and sex --------------------------------------------.

IF (apl_flag = 0 AND MISSING(apl_dose)) apl_flag = 2.
IF (apl_flag = 0 AND apl_dose <= 0) apl_flag = 2.

* an explicit route wins; a depot brand has already set one above.
IF (apl_form = 'po' OR apl_form = 'oral') apl_form = 'oral'.
IF (apl_form = 'im' OR apl_form = 'depot' OR apl_form = 'lai') apl_form = 'lai'.

* an agent with both an oral and a depot form cannot be scored without a route.
DO IF (apl_flag = 0 AND apl_form <> 'oral' AND apl_form <> 'lai').
+  DO IF (apl_gen = 'aripiprazole' OR apl_gen = 'flupentixol' OR apl_gen = 'fluphenazine' OR apl_gen = 'haloperidol' OR apl_gen = 'olanzapine' OR apl_gen = 'paliperidone' OR apl_gen = 'risperidone' OR apl_gen = 'zuclopenthixol').
+    COMPUTE apl_flag = 3.
+  ELSE.
+    COMPUTE apl_form = 'oral'.
+  END IF.
END IF.

IF (apl_flag = 0 AND apl_form = 'lai' AND LTRIM(RTRIM(apl_int)) = '') apl_flag = 4.

* ---- 3b. the dosing schedule, in days -----------------------------------------.
* 'monthly' and '4-weekly' name one schedule, and a prescriber may write
* either; the depot table below is looked up on the number of days, so both
* find the same row. The vocabulary is reference/ap_load2026_intervals.csv -
* add local spellings there and regenerate.

NUMERIC apl_days (F6.1).
COMPUTE apl_days = $SYSMIS.
IF (apl_int = 'cada 2 semanas') apl_days = 14.
IF (apl_int = 'cada 4 semanas') apl_days = 28.
IF (apl_int = 'every 2 months') apl_days = 56.
IF (apl_int = 'every 3 months') apl_days = 84.
IF (apl_int = 'every 6 months') apl_days = 168.
IF (apl_int = 'every 2 weeks') apl_days = 14.
IF (apl_int = 'every 4 weeks') apl_days = 28.
IF (apl_int = 'cada 15 dias') apl_days = 14.
IF (apl_int = 'cada 2 meses') apl_days = 56.
IF (apl_int = 'cada 3 meses') apl_days = 84.
IF (apl_int = 'cada 6 meses') apl_days = 168.
IF (apl_int = 'cada semana') apl_days = 7.
IF (apl_int = 'every month') apl_days = 28.
IF (apl_int = 'fortnightly') apl_days = 14.
IF (apl_int = 'every week') apl_days = 7.
IF (apl_int = 'trimestral') apl_days = 84.
IF (apl_int = '2-monthly') apl_days = 56.
IF (apl_int = '3-monthly') apl_days = 84.
IF (apl_int = '6-monthly') apl_days = 168.
IF (apl_int = 'bimensual') apl_days = 56.
IF (apl_int = 'quincenal') apl_days = 14.
IF (apl_int = 'semestral') apl_days = 168.
IF (apl_int = '1-weekly') apl_days = 7.
IF (apl_int = '168 days') apl_days = 168.
IF (apl_int = '180 days') apl_days = 168.
IF (apl_int = '2-weekly') apl_days = 14.
IF (apl_int = '4-weekly') apl_days = 28.
IF (apl_int = 'cada mes') apl_days = 28.
IF (apl_int = '14 days') apl_days = 14.
IF (apl_int = '14 dias') apl_days = 14.
IF (apl_int = '28 days') apl_days = 28.
IF (apl_int = '28 dias') apl_days = 28.
IF (apl_int = '56 days') apl_days = 56.
IF (apl_int = '84 days') apl_days = 84.
IF (apl_int = '90 days') apl_days = 84.
IF (apl_int = 'mensual') apl_days = 28.
IF (apl_int = 'monthly') apl_days = 28.
IF (apl_int = 'semanal') apl_days = 7.
IF (apl_int = '7 days') apl_days = 7.
IF (apl_int = '7 dias') apl_days = 7.
IF (apl_int = 'weekly') apl_days = 7.
IF (apl_int = 'q12w') apl_days = 84.
IF (apl_int = 'q24w') apl_days = 168.
IF (apl_int = 'q1w') apl_days = 7.
IF (apl_int = 'q2w') apl_days = 14.
IF (apl_int = 'q4w') apl_days = 28.
IF (apl_int = 'q8w') apl_days = 56.
IF (apl_int = 'qw') apl_days = 7.
IF (apl_flag = 0 AND apl_form = 'lai' AND MISSING(apl_days)) apl_flag = 4.

* ---- 4. reference doses ------------------------------------------------------.

* 4a. clozapine: target individualised for sex and cigarettes per day.
* Rostami-Hodjegan-derived anchors (the reference configuration).
* For the Reeves-derived configuration substitute: male 275/358, female 226/293.
DO IF (apl_flag = 0 AND apl_gen = 'clozapine').
+  DO IF (MISSING(sex) OR (sex <> 0 AND sex <> 1)).
+    COMPUTE apl_flag = 5.
+  ELSE IF (MISSING(cigs_per_day)).
+    COMPUTE apl_flag = 6.
+  ELSE.
+    COMPUTE apl_frac = MIN(1, MAX(0, cigs_per_day / 10)).
+    DO IF (sex = 1).
+      COMPUTE apl_ref = 323 + (525 - 323) * apl_frac.
+      COMPUTE apl_basis = 'individualised clozapine target (male)'.
+    ELSE.
+      COMPUTE apl_ref = 265 + (431 - 265) * apl_frac.
+      COMPUTE apl_basis = 'individualised clozapine target (female)'.
+    END IF.
+  END IF.
END IF.

* 4b. other oral agents: geometric mean of licensed maximum and WHO DDD,
*     capped at 1.5 x DDD. Values computed from the reference table.
DO IF (apl_flag = 0 AND apl_form = 'oral' AND apl_gen <> 'clozapine').
+  DO IF (apl_gen = 'amisulpride').
+    COMPUTE apl_ref = 600.000000.
+    COMPUTE apl_basis = 'capped geometric mean'.
+  ELSE IF (apl_gen = 'aripiprazole').
+    COMPUTE apl_ref = 21.213203.
+    COMPUTE apl_basis = 'geometric mean'.
+  ELSE IF (apl_gen = 'asenapine').
+    COMPUTE apl_ref = 20.000000.
+    COMPUTE apl_basis = 'geometric mean'.
+  ELSE IF (apl_gen = 'blonanserin').
+    COMPUTE apl_ref = 24.000000.
+    COMPUTE apl_basis = 'label maximum (no WHO DDD)'.
+  ELSE IF (apl_gen = 'brexpiprazole').
+    COMPUTE apl_ref = 3.464102.
+    COMPUTE apl_basis = 'geometric mean'.
+  ELSE IF (apl_gen = 'cariprazine').
+    COMPUTE apl_ref = 4.242641.
+    COMPUTE apl_basis = 'geometric mean'.
+  ELSE IF (apl_gen = 'chlorpromazine').
+    COMPUTE apl_ref = 450.000000.
+    COMPUTE apl_basis = 'capped geometric mean'.
+  ELSE IF (apl_gen = 'flupentixol').
+    COMPUTE apl_ref = 9.000000.
+    COMPUTE apl_basis = 'capped geometric mean'.
+  ELSE IF (apl_gen = 'haloperidol').
+    COMPUTE apl_ref = 12.000000.
+    COMPUTE apl_basis = 'capped geometric mean'.
+  ELSE IF (apl_gen = 'iloperidone').
+    COMPUTE apl_ref = 20.784610.
+    COMPUTE apl_basis = 'geometric mean'.
+  ELSE IF (apl_gen = 'lumateperone').
+    COMPUTE apl_ref = 42.000000.
+    COMPUTE apl_basis = 'label maximum (no WHO DDD)'.
+  ELSE IF (apl_gen = 'lurasidone').
+    COMPUTE apl_ref = 90.000000.
+    COMPUTE apl_basis = 'capped geometric mean'.
+  ELSE IF (apl_gen = 'olanzapine').
+    COMPUTE apl_ref = 14.142136.
+    COMPUTE apl_basis = 'geometric mean'.
+  ELSE IF (apl_gen = 'paliperidone').
+    COMPUTE apl_ref = 8.485281.
+    COMPUTE apl_basis = 'geometric mean'.
+  ELSE IF (apl_gen = 'pimozide').
+    COMPUTE apl_ref = 6.000000.
+    COMPUTE apl_basis = 'capped geometric mean'.
+  ELSE IF (apl_gen = 'quetiapine').
+    COMPUTE apl_ref = 547.722558.
+    COMPUTE apl_basis = 'geometric mean'.
+  ELSE IF (apl_gen = 'risperidone').
+    COMPUTE apl_ref = 7.500000.
+    COMPUTE apl_basis = 'capped geometric mean'.
+  ELSE IF (apl_gen = 'sulpiride').
+    COMPUTE apl_ref = 1200.000000.
+    COMPUTE apl_basis = 'capped geometric mean'.
+  ELSE IF (apl_gen = 'trifluoperazine').
+    COMPUTE apl_ref = 20.000000.
+    COMPUTE apl_basis = 'geometric mean'.
+  ELSE IF (apl_gen = 'xanomeline-trospium').
+    COMPUTE apl_ref = 250.000000.
+    COMPUTE apl_basis = 'label maximum (no WHO DDD)'.
+  ELSE IF (apl_gen = 'ziprasidone').
+    COMPUTE apl_ref = 113.137085.
+    COMPUTE apl_basis = 'geometric mean'.
+  ELSE IF (apl_gen = 'zuclopenthixol').
+    COMPUTE apl_ref = 45.000000.
+    COMPUTE apl_basis = 'capped geometric mean'.
+  ELSE IF (apl_gen = 'fluphenazine').
+    COMPUTE apl_ref = 15.000000.
+    COMPUTE apl_basis = '1.5 x DDD (no current licensed maximum)'.
+  ELSE IF (apl_gen = 'levomepromazine').
+    COMPUTE apl_ref = 450.000000.
+    COMPUTE apl_basis = '1.5 x DDD (no current licensed maximum)'.
+  ELSE IF (apl_gen = 'penfluridol').
+    COMPUTE apl_ref = 9.000000.
+    COMPUTE apl_basis = '1.5 x DDD (no current licensed maximum)'.
+  ELSE.
+    COMPUTE apl_flag = 1.
+  END IF.
END IF.

* 4c. long-acting injectables: licensed maximum for the same interval.
* Matched on the schedule in days rather than on the label, so a depot
* filed as 4-weekly is found by 'monthly' and the reverse.
DO IF (apl_flag = 0 AND apl_form = 'lai').
+  DO IF (apl_gen = 'aripiprazole' AND apl_days = 28).
+    COMPUTE apl_ref = 400.000000.
+    COMPUTE apl_basis = 'licensed formulation maximum per monthly'.
+  ELSE IF (apl_gen = 'aripiprazole' AND apl_days = 56).
+    COMPUTE apl_ref = 960.000000.
+    COMPUTE apl_basis = 'licensed formulation maximum per 2-monthly'.
+  ELSE IF (apl_gen = 'paliperidone' AND apl_days = 28).
+    COMPUTE apl_ref = 150.000000.
+    COMPUTE apl_basis = 'licensed formulation maximum per monthly'.
+  ELSE IF (apl_gen = 'paliperidone' AND apl_days = 84).
+    COMPUTE apl_ref = 525.000000.
+    COMPUTE apl_basis = 'licensed formulation maximum per 3-monthly'.
+  ELSE IF (apl_gen = 'paliperidone' AND apl_days = 168).
+    COMPUTE apl_ref = 1000.000000.
+    COMPUTE apl_basis = 'licensed formulation maximum per 6-monthly'.
+  ELSE IF (apl_gen = 'risperidone' AND apl_days = 14).
+    COMPUTE apl_ref = 50.000000.
+    COMPUTE apl_basis = 'licensed formulation maximum per 2-weekly'.
+  ELSE IF (apl_gen = 'olanzapine' AND apl_days = 14).
+    COMPUTE apl_ref = 300.000000.
+    COMPUTE apl_basis = 'licensed formulation maximum per 2-weekly'.
+  ELSE IF (apl_gen = 'olanzapine' AND apl_days = 28).
+    COMPUTE apl_ref = 405.000000.
+    COMPUTE apl_basis = 'licensed formulation maximum per 4-weekly'.
+  ELSE IF (apl_gen = 'haloperidol' AND apl_days = 28).
+    COMPUTE apl_ref = 300.000000.
+    COMPUTE apl_basis = 'licensed formulation maximum per 4-weekly'.
+  ELSE IF (apl_gen = 'flupentixol' AND apl_days = 7).
+    COMPUTE apl_ref = 400.000000.
+    COMPUTE apl_basis = 'licensed formulation maximum per weekly'.
+  ELSE IF (apl_gen = 'zuclopenthixol' AND apl_days = 7).
+    COMPUTE apl_ref = 600.000000.
+    COMPUTE apl_basis = 'licensed formulation maximum per weekly'.
+  ELSE IF (apl_gen = 'fluphenazine' AND apl_days = 14).
+    COMPUTE apl_ref = 100.000000.
+    COMPUTE apl_basis = 'licensed formulation maximum per 2-weekly'.
+  ELSE.
+    COMPUTE apl_flag = 4.
+  END IF.
END IF.

* ---- 5. score ----------------------------------------------------------------.

IF (apl_flag = 0 AND apl_ref > 0) apl_score = apl_dose / apl_ref * 100.
IF (apl_flag <> 0) apl_score = $SYSMIS.
NUMERIC apl_refused (F1.0).
COMPUTE apl_refused = (apl_flag <> 0).

VARIABLE LABELS
  apl_gen 'AP_Load2026: matched generic'
  apl_stem 'AP_Load2026: stem that matched'
  apl_ref 'AP_Load2026: reference dose (mg)'
  apl_basis 'AP_Load2026: basis of the reference dose'
  apl_score 'AP_Load2026: score for this prescription (%)'
  apl_flag 'AP_Load2026: 0 = scored, >0 = refused (see header)'.
VALUE LABELS apl_flag
  0 'scored' 1 'drug not recognised' 2 'dose missing or not numeric'
  3 'oral or depot could not be told apart' 4 'depot interval missing or not tabulated'
  5 'sex missing (clozapine)' 6 'smoking missing (clozapine)'.

* ---- 6. back to one row per patient ------------------------------------------.

DATASET DECLARE apl_scores.
AGGREGATE OUTFILE = apl_scores
  /BREAK = patient_id
  /AP_Load2026 = SUM(apl_score)
  /drugs_scored = NU(apl_score)
  /rows_refused = SUM(apl_refused).
DATASET ACTIVATE apl_scores.
STRING complete (A3) reference_table (A8).
COMPUTE complete = 'yes'.
IF (rows_refused > 0) complete = 'NO'.
COMPUTE reference_table = '2026-11'.
VARIABLE LABELS
  AP_Load2026 'Antipsychotic Dose Load (pct), reference table 2026-11'
  rows_refused 'prescriptions that could not be scored'
  complete 'no prescription refused for this patient'.
EXECUTE.

* A patient with rows_refused > 0 has an UNDERSTATED load. Report the counts:
FREQUENCIES VARIABLES = complete.

* Reasons, for correction at source:
DATASET ACTIVATE apl_work.
FREQUENCIES VARIABLES = apl_flag.
TEMPORARY.
SELECT IF (apl_flag = 1).
FREQUENCIES VARIABLES = apl_drug.
