# Design Document: Pagination for Immediate Assistance Requests & Barrier Reports

**Date**: 2026-09-18  
**Status**: Approved  

## Overview
Implement pagination and consistent search fields for both "Immediate Assistance Requests" and "Accessibility Barrier Reports" on the web portal's `AssistanceRequestPage.jsx`, following the design pattern established in `AnnouncementPage.jsx` and `QueueUpdatePage.jsx`.

## Motivation
Currently, all requests and barrier reports are rendered in a single unending table without pagination. In high-traffic venues with numerous requests or historical barrier reports, this increases DOM load and makes table navigation cumbersome. `AnnouncementPage` and `QueueUpdatePage` use `ListPagination` (page size 10) with integrated `ListFilterSearchField`. Adopting this pattern provides visual consistency and standardizes navigation.

## Design Specifications

### 1. Reused Components
- `ListPagination` from `web/src/components/ListPagination.jsx`
- `ListFilterSearchField` from `web/src/components/ListPagination.jsx`

### 2. State & Page Size
- Constant: `const pageSize = 10`
- Immediate Assistance Requests:
  - State: `const [requestPage, setRequestPage] = useState(1)`
  - Reset hook: `useEffect(() => { setRequestPage(1) }, [searchQuery, statusFilter])`
  - Slicing:
    - `requestTotalPages = Math.max(1, Math.ceil(filteredRequests.length / pageSize))`
    - `currentRequestPage = Math.min(requestPage, requestTotalPages)`
    - `pageRequests = filteredRequests.slice((currentRequestPage - 1) * pageSize, currentRequestPage * pageSize)`
- Accessibility Barrier Reports:
  - State: `const [barrierPage, setBarrierPage] = useState(1)`
  - Reset hook: `useEffect(() => { setBarrierPage(1) }, [barrierSearchQuery, barrierStatusFilter])`
  - Slicing:
    - `barrierTotalPages = Math.max(1, Math.ceil(filteredBarriers.length / pageSize))`
    - `currentBarrierPage = Math.min(barrierPage, barrierTotalPages)`
    - `pageBarriers = filteredBarriers.slice((currentBarrierPage - 1) * pageSize, currentBarrierPage * pageSize)`

### 3. UI Changes in `AssistanceRequestPage.jsx`
- **Immediate Assistance Requests**:
  - Replace `<input className="input" placeholder="Search traveler, code..." ... />` with `<ListFilterSearchField value={searchQuery} onChange={setSearchQuery} placeholder="Search traveler, code..." label="Search assistance requests" />`.
  - Render rows using `pageRequests.map(...)`.
  - Append `<ListPagination page={currentRequestPage} totalItems={filteredRequests.length} pageSize={pageSize} onPageChange={setRequestPage} label="Assistance requests" />` inside the card below the table when not loading.
- **Accessibility Barrier Reports**:
  - Replace custom input container with `<ListFilterSearchField value={barrierSearchQuery} onChange={setBarrierSearchQuery} placeholder="Search code, zone, issue..." label="Search barrier reports" />`.
  - Render rows using `pageBarriers.map(...)`.
  - Append `<ListPagination page={currentBarrierPage} totalItems={filteredBarriers.length} pageSize={pageSize} onPageChange={setBarrierPage} label="Barrier reports" />` inside the card below the table when not loading.

## Verification
- Verify search and status filter reset page numbers back to 1.
- Verify Next/Previous buttons function and disable on boundaries.
- Verify "Showing X–Y of Z" counts are exact.
- Verify `npm run build` or Vite dev server hot module replacement without errors.
