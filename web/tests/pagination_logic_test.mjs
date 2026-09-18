import assert from 'node:assert/strict'

function paginate(items, page, pageSize = 10) {
  const totalPages = Math.max(1, Math.ceil(items.length / pageSize))
  const currentPage = Math.min(Math.max(1, page), totalPages)
  const pageItems = items.slice((currentPage - 1) * pageSize, currentPage * pageSize)
  return {
    totalPages,
    currentPage,
    pageItems,
    start: items.length === 0 ? 0 : (currentPage - 1) * pageSize + 1,
    end: Math.min(currentPage * pageSize, items.length),
  }
}

// 1. Empty list test
{
  const result = paginate([], 1)
  assert.equal(result.totalPages, 1)
  assert.equal(result.currentPage, 1)
  assert.equal(result.pageItems.length, 0)
}

// 2. Exactly 10 items (1 page)
{
  const items = Array.from({ length: 10 }, (_, i) => ({ id: i + 1 }))
  const result = paginate(items, 1)
  assert.equal(result.totalPages, 1)
  assert.equal(result.currentPage, 1)
  assert.equal(result.pageItems.length, 10)
  assert.equal(result.start, 1)
  assert.equal(result.end, 10)
}

// 3. 25 items across 3 pages
{
  const items = Array.from({ length: 25 }, (_, i) => ({ id: i + 1 }))
  
  // Page 1
  const p1 = paginate(items, 1)
  assert.equal(p1.totalPages, 3)
  assert.equal(p1.currentPage, 1)
  assert.equal(p1.pageItems.length, 10)
  assert.equal(p1.pageItems[0].id, 1)
  assert.equal(p1.pageItems[9].id, 10)
  assert.equal(p1.start, 1)
  assert.equal(p1.end, 10)

  // Page 2
  const p2 = paginate(items, 2)
  assert.equal(p2.totalPages, 3)
  assert.equal(p2.currentPage, 2)
  assert.equal(p2.pageItems.length, 10)
  assert.equal(p2.pageItems[0].id, 11)
  assert.equal(p2.pageItems[9].id, 20)
  assert.equal(p2.start, 11)
  assert.equal(p2.end, 20)

  // Page 3
  const p3 = paginate(items, 3)
  assert.equal(p3.totalPages, 3)
  assert.equal(p3.currentPage, 3)
  assert.equal(p3.pageItems.length, 5)
  assert.equal(p3.pageItems[0].id, 21)
  assert.equal(p3.pageItems[4].id, 25)
  assert.equal(p3.start, 21)
  assert.equal(p3.end, 25)

  // Out of range (page 99) clamps to page 3
  const pClamped = paginate(items, 99)
  assert.equal(pClamped.currentPage, 3)
  assert.equal(pClamped.pageItems.length, 5)
}

console.log('All pagination logic unit tests passed successfully!')
