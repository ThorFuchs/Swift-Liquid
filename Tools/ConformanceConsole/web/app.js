// SPDX-License-Identifier: Apache-2.0
const $ = (id) => document.getElementById(id);
const state = { runs: [], selected: null, active: null, tab: 'cases', rows: [], offset: 0, total: 0, ready: false, checking: false, busy: false, selectedCase: null };
const labels = { passed: 'Passed', failed: 'Conformance failed', running: 'Running', error: 'Runner error', cancelled: 'Cancelled', timed_out: 'Timed out', interrupted: 'Interrupted' };
const outcomes = { matched: 'Matched', mismatched: 'Mismatched', 'operational-error': 'Operational', 'domain-divergence': 'Domain divergence', excluded: 'Excluded' };
function text(tag, value, cls) { const el = document.createElement(tag); el.textContent = value; if (cls) el.className = cls; return el; }
function notice(message) { $('notice').textContent = message || ''; $('notice').hidden = !message; }
async function api(path, value) {
  const response = await fetch(path, value === undefined ? { cache: 'no-store' } : { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(value) });
  const data = await response.json(); if (!response.ok) throw new Error(data.error || `Request failed (${response.status})`); return data;
}
function controls() { $('run').disabled = !state.ready || !!state.active || state.busy; $('check').disabled = state.checking || !!state.active; $('cancel').hidden = !state.active; }
function selected() { return state.runs.find(run => run.id === state.selected); }
function renderHistory() {
  const nodes = state.runs.map(run => { const button = text('button', `${run.source.commit.slice(0, 7)} · ${labels[run.status] || run.status}`, 'history-row' + (run.id === state.selected ? ' selected' : '')); button.append(text('small', new Date(run.startedUTC).toLocaleString())); button.addEventListener('click', () => chooseRun(run.id)); return button; });
  $('history').replaceChildren(...(nodes.length ? nodes : [text('p', 'No runs yet', 'muted')]));
}
function renderRun() {
  const run = selected();
  for (const key of ['matched', 'mismatched', 'operational', 'excluded']) $(key).textContent = run?.counts ? run.counts[key].toLocaleString() : '—';
  $('snapshot').textContent = run ? labels[run.status] || run.status : 'No run selected';
  $('progress').textContent = run ? `${run.phase} · ${run.rowsRecorded ?? 'No'} rows recorded${run.status === 'running' ? ' so far' : ''}. ${run.status === 'failed' ? 'Completion is not conformance. All nonmatching outcomes remain failures.' : ''}` : 'Run the five pinned functional suites to produce a complete case report.';
  if (run) $('source').textContent = `Run source ${run.source.commit} · ${run.source.clean ? 'Clean at launch' : 'Unqualified source'}`;
  $('run-info').textContent = run ? JSON.stringify({ source: run.source, command: run.command, startedUTC: run.startedUTC, endedUTC: run.endedUTC, exitCode: run.exitCode, status: run.status, evidenceComplete: run.evidenceComplete, matrixSHA256: run.matrixSHA256, error: run.error, scope: run.scope }, null, 2) : 'Choose a run to inspect its source and command.';
  $('downloads').replaceChildren();
  if (run) for (const [key, title] of [['run', 'Run record'], ['receipt', 'Source receipt'], ['matrix', 'Full case matrix'], ['summary', 'Suite accounting'], ['ledger', 'Diagnostic ledger'], ['trace', 'RPC traces'], ['log', 'Complete log']]) { const link = text('a', title); link.href = `/api/runs/${run.id}/files/${key}`; link.download = ''; $('downloads').append(link); }
}
async function chooseRun(id) { state.selected = id; state.offset = 0; state.selectedCase = null; renderHistory(); renderRun(); showDetail(null); await refreshView(); }
async function refresh() {
  const data = await api('/api/state'); const previousActive = state.active; const signature = JSON.stringify(data); if (signature === state.signature) { controls(); if (state.active && state.tab === 'log') await refreshView(); return; } state.signature = signature; state.runs = data.runs; state.active = data.active; state.config = data.config; if (previousActive && !data.active) { const finished = data.runs.find(run => run.id === previousActive); notice(`Run finished: ${labels[finished?.status] || 'inspect retained evidence'}. Every original result and log is preserved.`); }
  if (!state.selected && state.runs.length) state.selected = state.runs[0].id;
  renderHistory(); renderRun(); controls();
  await refreshView();
}
function showDetail(row) {
  const target = $('detail'); target.replaceChildren(); target.className = row ? '' : 'detail-empty';
  if (!row) { target.textContent = 'Select a case to compare expected and actual behavior.'; return; }
  target.append(text('h3', row.case, 'case-name'));
  const blocks = [ ['Identity', { caseID: row.caseID, parserMode: row.parserMode, renderMode: row.renderMode, sourceLocation: row.sourceLocation }], ['Verdicts', { upstream: row.comparison, qualified: row.qualificationComparison, expectedCategory: row.expectedCategory, observedCategory: row.observedCategory, selected: row.selected, reason: row.reason }], ['Expected', row.expected ?? row.expectation], ['Actual', row.actual ?? row.reportedErrors], ['Reference', { comparison: row.referenceComparison, qualification: row.referenceQualificationComparison, actual: row.referenceActual, errors: row.referenceReportedErrors }] ];
  for (const [title, value] of blocks) { const section = document.createElement('section'); section.className = 'detail-section'; section.append(text('h3', title), text('pre', typeof value === 'string' ? value : JSON.stringify(value ?? null, null, 2))); target.append(section); }
  const location = row.sourceLocation;
  if (location && /^specs\/[a-zA-Z0-9_./-]+$/.test(location.file) && Number.isInteger(location.line)) { const link = text('a', 'View pinned upstream fixture'); link.href = `https://github.com/Shopify/liquid-spec/blob/84bf25e0edbca5f7e530574788b0f875ab331f50/${location.file}#L${location.line}`; link.target = '_blank'; link.rel = 'noreferrer noopener'; target.append(link); }
}
async function loadCases() {
  if (!state.selected) return;
  const params = new URLSearchParams({ q: $('search').value, outcome: $('outcome').value, suite: $('suite').value, offset: state.offset });
  const data = await api(`/api/runs/${state.selected}/cases?${params}`); state.rows = data.rows; state.total = data.total;
  const old = $('suite').value; $('suite').replaceChildren(new Option('All suites', ''), ...data.suites.map(suite => new Option(suite, suite))); $('suite').value = old;
  $('rows').replaceChildren(...data.rows.map(row => { const tr = document.createElement('tr'); if (row.caseID === state.selectedCase) tr.className = 'selected'; const cell = document.createElement('td'); const button = text('button', row.case); button.addEventListener('click', () => { state.selectedCase = row.caseID; showDetail(row); for (const el of $('rows').children) el.classList.toggle('selected', el === tr); }); cell.append(button); const outcome = row.selected ? row.qualificationComparison : 'excluded'; tr.append(cell, text('td', row.suite), text('td', `${row.parserMode} / ${row.renderMode}`), text('td', outcomes[outcome] || outcome, `outcome ${outcome}`)); return tr; }));
  $('empty').hidden = data.rows.length > 0; $('empty').textContent = state.total ? 'No cases on this page.' : selected()?.status === 'running' ? 'Waiting for the first case checkpoint…' : 'No cases match these filters.';
  $('page-info').textContent = state.total ? `${state.offset + 1}–${Math.min(state.offset + 80, state.total)} of ${state.total.toLocaleString()}` : '0 cases'; $('previous').disabled = state.offset === 0; $('next').disabled = state.offset + 80 >= state.total;
}
async function refreshView() { if (state.tab === 'cases') await loadCases(); else if (state.tab === 'log' && state.selected) $('log-body').textContent = (await api(`/api/runs/${state.selected}/log`)).text; }
async function check() {
  state.checking = true; controls(); notice('Checking local source, tools, pins and gems…');
  try { const result = await api('/api/check', {}); state.ready = result.ready; $('source').textContent = `Current source ${result.source.commit || 'unavailable'} · ${result.source.clean ? 'Clean checkout' : 'Commit or preserve working changes before running'}`; $('checks').replaceChildren(...result.checks.map(item => { const row = document.createElement('div'); const dd = text('dd', item.passed ? 'Verified' : (item.error || item.stderr?.trim() || item.stdout?.trim() || 'Check failed'), item.passed ? 'check-passed' : 'check-failed'); row.append(text('dt', item.name), dd); return row; })); notice(result.ready ? 'Setup verified. Run suite will create a new, separately preserved result.' : 'Setup needs attention. Existing runs and evidence remain available.'); }
  catch (error) { state.ready = false; notice(error.message); }
  finally { state.checking = false; controls(); }
}
$('check').addEventListener('click', check);
$('run').addEventListener('click', async () => { state.busy = true; controls(); try { const run = await api('/api/run', {}); state.selected = run.id; state.offset = 0; state.selectedCase = null; showDetail(null); notice('Suite started. Mismatches and operational errors remain visible; there are no automatic retries.'); await refresh(); } catch (error) { notice(error.message); } finally { state.busy = false; controls(); } });
$('cancel').addEventListener('click', async () => { try { await api(`/api/runs/${state.active}/cancel`, {}); notice('Stopping this console’s run. Partial evidence will be retained.'); } catch (error) { notice(error.message); } });
for (const button of document.querySelectorAll('[data-settings]')) button.addEventListener('click', () => { for (const [key, value] of Object.entries(state.config || {})) $('settings-form').elements.namedItem(key).value = value; $('settings').showModal(); });
$('close-settings').addEventListener('click', () => $('settings').close());
$('settings-form').addEventListener('submit', async event => { event.preventDefault(); try { await api('/api/config', Object.fromEntries(new FormData(event.currentTarget))); $('settings').close(); await refresh(); await check(); } catch (error) { notice(error.message); } });
for (const button of document.querySelectorAll('[data-tab]')) button.addEventListener('click', async () => { state.tab = button.dataset.tab; for (const el of document.querySelectorAll('[data-tab]')) el.setAttribute('aria-selected', String(el === button)); for (const id of ['cases', 'log', 'evidence']) $(id).hidden = id !== state.tab; try { await refreshView(); } catch (error) { notice(error.message); } });
let debounce; $('search').addEventListener('input', () => { clearTimeout(debounce); debounce = setTimeout(() => { state.offset = 0; loadCases().catch(error => notice(error.message)); }, 180); });
for (const id of ['outcome', 'suite']) $(id).addEventListener('change', () => { state.offset = 0; loadCases().catch(error => notice(error.message)); });
for (const [id, step] of [['previous', -80], ['next', 80]]) $(id).addEventListener('click', () => { state.offset = Math.max(0, state.offset + step); loadCases().catch(error => notice(error.message)); });
async function poll() { try { await refresh(); } catch (error) { notice(error.message); } setTimeout(poll, state.active ? 1200 : 4000); }
poll();

for (const button of document.querySelectorAll("[data-tab]")) {
  button.id = `tab-${button.dataset.tab}`; button.setAttribute("aria-controls", button.dataset.tab);
  document.getElementById(button.dataset.tab).setAttribute("aria-labelledby", button.id);
  button.addEventListener("keydown", event => {
    const tabs = [...document.querySelectorAll("[data-tab]")]; let index = tabs.indexOf(button);
    if (event.key === "ArrowRight") index = (index + 1) % tabs.length;
    else if (event.key === "ArrowLeft") index = (index + tabs.length - 1) % tabs.length;
    else if (event.key === "Home") index = 0; else if (event.key === "End") index = tabs.length - 1; else return;
    event.preventDefault(); tabs[index].focus(); tabs[index].click();
  });
}
