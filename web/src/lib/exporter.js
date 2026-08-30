// Shared export helpers: every dashboard section can offer "export what you
// see" by building a simple spec — { title, metaLines, kpis, tables } — and
// handing it to downloadCsv / downloadPdf. The Report Generation page uses the
// exact same spec shape, so preview and exports always match.

export function buildCsv({ title, metaLines = [], kpis = [], tables = [] }) {
  const lines = []
  lines.push(`"${title}"`)
  metaLines.forEach((m) => lines.push(m.map((c) => `"${String(c ?? '')}"`).join(',')))
  if (kpis.length) {
    lines.push('')
    lines.push('Key Metrics')
    lines.push('Metric,Value')
    kpis.forEach((k) => lines.push(`"${k.label}","${k.value}"`))
  }
  tables.forEach((t) => {
    lines.push('')
    lines.push(`"${t.title}"`)
    lines.push(t.headers.join(','))
    t.rows.forEach((row) => lines.push(row.map((c) => `"${String(c ?? '')}"`).join(',')))
  })
  return lines.join('\n')
}

export function downloadFile(content, filename, mime) {
  const blob = new Blob([content], { type: mime })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}

export function downloadCsv(filename, spec) {
  downloadFile(buildCsv(spec), filename, 'text/csv;charset=utf-8')
}

export async function downloadPdf(filename, spec) {
  const [{ jsPDF }, autoTableMod] = await Promise.all([import('jspdf'), import('jspdf-autotable')])
  const autoTable = autoTableMod.default
  const doc = new jsPDF({ orientation: 'portrait', unit: 'pt', format: 'a4' })
  const pageWidth = doc.internal.pageSize.getWidth()
  const pageHeight = doc.internal.pageSize.getHeight()

  doc.setFontSize(16)
  doc.text(spec.title, 40, 48)
  doc.setFontSize(10)
  let y = 66
  ;(spec.metaLines || []).forEach((line) => {
    doc.text(line.map(String).join('   '), 40, y)
    y += 14
  })

  if (spec.kpis?.length) {
    autoTable(doc, {
      startY: y + 6,
      head: [['Metric', 'Value']],
      body: spec.kpis.map((k) => [k.label, String(k.value)]),
      theme: 'grid',
      styles: { fontSize: 9 },
      headStyles: { fillColor: [59, 130, 246] }
    })
    y = (doc.lastAutoTable?.finalY ?? y + 40) + 28
  }

  ;(spec.tables || []).forEach((t) => {
    if (y > pageHeight - 130) {
      doc.addPage()
      y = 60
    }
    doc.setFontSize(11)
    doc.setTextColor(30)
    doc.text(t.title, 40, y)
    autoTable(doc, {
      startY: y + 8,
      head: [t.headers],
      body: t.rows.map((r) => r.map((c) => String(c))),
      theme: 'striped',
      styles: { fontSize: 8.5 },
      headStyles: { fillColor: [30, 41, 59] }
    })
    y = (doc.lastAutoTable?.finalY ?? y + 40) + 24
  })

  const pages = doc.internal.getNumberOfPages()
  for (let i = 1; i <= pages; i++) {
    doc.setPage(i)
    doc.setFontSize(8)
    doc.setTextColor(120)
    doc.text(`TravelEase export — page ${i} of ${pages}`, pageWidth - 220, pageHeight - 20)
  }
  doc.save(filename)
}
