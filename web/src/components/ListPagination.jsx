import React from 'react'
import { Search, X } from 'lucide-react'

export function ListFilterSearchField({ value, onChange, placeholder, label, className = '' }) {
  return <label className={`list-filter-search ${className}`.trim()}>
    <Search size={17} aria-hidden="true" />
    <input className="input" type="text" value={value} onChange={(event) => onChange(event.target.value)} placeholder={placeholder} aria-label={label} />
    {value && <button type="button" className="list-filter-search-clear" onClick={() => onChange('')} aria-label={`Clear ${label}`} title="Clear"><X size={16} /></button>}
  </label>
}

export default function ListPagination({ page, totalItems, pageSize, onPageChange, label }) {
  const totalPages = Math.max(1, Math.ceil(totalItems / pageSize))
  const currentPage = Math.min(page, totalPages)
  if (totalItems <= pageSize) return null

  const start = (currentPage - 1) * pageSize + 1
  const end = Math.min(currentPage * pageSize, totalItems)
  return <div className="list-pagination" aria-label={`${label} pagination`}>
    <span>Showing {start}–{end} of {totalItems}</span>
    <div>
      <button className="btn btn-outline btn-sm" disabled={currentPage === 1} onClick={() => onPageChange(currentPage - 1)}>Previous</button>
      <span>Page {currentPage} of {totalPages}</span>
      <button className="btn btn-outline btn-sm" disabled={currentPage === totalPages} onClick={() => onPageChange(currentPage + 1)}>Next</button>
    </div>
  </div>
}
