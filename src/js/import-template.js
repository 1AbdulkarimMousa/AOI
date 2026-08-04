export const workbookImportTemplate = String.raw`
<section x-show="view==='imports'" class="panel workbook-import-panel">
  <div class="panel-heading"><div><span class="eyebrow">Excel workbook</span><h2>Import XLSX through the same validation preview.</h2></div><span class="privacy-chip">Admin commit</span></div>
  <label class="upload-drop workbook-drop"><input type="file" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" @change="importFile($event)"><strong>Choose an XLSX workbook</strong><small>The first sheet must include Handle / Name. No row is persisted until an administrator commits the preview above.</small></label>
</section>`;
