# Pagination for Immediate Assistance Requests & Barrier Reports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add pagination and consistent search controls to Immediate Assistance Requests and Accessibility Barrier Reports in `AssistanceRequestPage.jsx`, matching `AnnouncementPage.jsx` and `QueueUpdatePage.jsx`.

**Architecture:** Import and utilize `ListPagination` and `ListFilterSearchField` from `../components/ListPagination`. Manage independent pagination states (`requestPage`, `barrierPage`) with a fixed page size of 10, resetting to page 1 upon filter changes, and slicing filtered lists for rendering.

**Tech Stack:** React 19, Lucide React, Vite.

## Global Constraints
- Target component: `web/src/pages/AssistanceRequestPage.jsx`
- Page size fixed to 10 (`pageSize = 10`)
- Must reset page to 1 whenever search text or status filter changes
- Must not break staff-only view (`staffOnly={true}`) or existing assignment modals

---

### Task 1: Add Pagination and Search Field to Immediate Assistance Requests

**Files:**
- Modify: `web/src/pages/AssistanceRequestPage.jsx`

**Interfaces:**
- Consumes: `ListPagination`, `ListFilterSearchField` from `../components/ListPagination.jsx`
- Produces: Paginated rendering of `filteredRequests` as `pageRequests` with `requestPage` state and `<ListPagination>` footer.

- [ ] **Step 1: Import ListPagination and ListFilterSearchField**
In `web/src/pages/AssistanceRequestPage.jsx`, import `ListPagination` and `ListFilterSearchField`:
```javascript
import ListPagination, { ListFilterSearchField } from '../components/ListPagination'
```
Define page size constant outside the component:
```javascript
const pageSize = 10
```

- [ ] **Step 2: Add requestPage state, filter-reset effect, and slice calculation**
Inside `AssistanceRequestPage`:
```javascript
const [requestPage, setRequestPage] = useState(1)

useEffect(() => {
  setRequestPage(1)
}, [searchQuery, statusFilter])

const requestTotalPages = Math.max(1, Math.ceil(filteredRequests.length / pageSize))
const currentRequestPage = Math.min(requestPage, requestTotalPages)
const pageRequests = filteredRequests.slice((currentRequestPage - 1) * pageSize, currentRequestPage * pageSize)
```

- [ ] **Step 3: Update Search Bar and Table Mapping in Requests Tab**
Replace the plain `<input>` search field with:
```jsx
<ListFilterSearchField
  value={searchQuery}
  onChange={setSearchQuery}
  placeholder="Search traveler, code..."
  label="Search assistance requests"
/>
```
Update row mapping from `filteredRequests.map(...)` to `pageRequests.map(...)`.

- [ ] **Step 4: Render ListPagination footer inside the requests card**
Immediately after `</table>` (before closing the card):
```jsx
{!loading && (
  <ListPagination
    page={currentRequestPage}
    totalItems={filteredRequests.length}
    pageSize={pageSize}
    onPageChange={setRequestPage}
    label="Assistance requests"
  />
)}
```

- [ ] **Step 5: Verify via build and lint**
Run `npm run lint` and `npm run build` in `web`.

- [ ] **Step 6: Commit**
```bash
git add web/src/pages/AssistanceRequestPage.jsx
git commit -m "feat(web): add pagination and search field to immediate assistance requests"
```

---

### Task 2: Add Pagination and Search Field to Accessibility Barrier Reports

**Files:**
- Modify: `web/src/pages/AssistanceRequestPage.jsx`

**Interfaces:**
- Consumes: `ListPagination`, `ListFilterSearchField` from `../components/ListPagination.jsx`
- Produces: Paginated rendering of `filteredBarriers` as `pageBarriers` with `barrierPage` state and `<ListPagination>` footer.

- [ ] **Step 1: Add barrierPage state, filter-reset effect, and slice calculation**
Inside `AssistanceRequestPage`:
```javascript
const [barrierPage, setBarrierPage] = useState(1)

useEffect(() => {
  setBarrierPage(1)
}, [barrierSearchQuery, barrierStatusFilter])

const barrierTotalPages = Math.max(1, Math.ceil(filteredBarriers.length / pageSize))
const currentBarrierPage = Math.min(barrierPage, barrierTotalPages)
const pageBarriers = filteredBarriers.slice((currentBarrierPage - 1) * pageSize, currentBarrierPage * pageSize)
```

- [ ] **Step 2: Update Search Bar and Table Mapping in Barriers Tab**
Replace custom search container with:
```jsx
<ListFilterSearchField
  value={barrierSearchQuery}
  onChange={setBarrierSearchQuery}
  placeholder="Search code, zone, issue..."
  label="Search barrier reports"
/>
```
Update row mapping from `filteredBarriers.map(...)` to `pageBarriers.map(...)`.

- [ ] **Step 3: Render ListPagination footer inside the barrier reports card**
Immediately after `</table>` (before closing the card):
```jsx
{!loadingBarriers && (
  <ListPagination
    page={currentBarrierPage}
    totalItems={filteredBarriers.length}
    pageSize={pageSize}
    onPageChange={setBarrierPage}
    label="Barrier reports"
  />
)}
```

- [ ] **Step 4: Verify via build and test**
Run `npm run lint` and `npm run build` in `web`.

- [ ] **Step 5: Commit**
```bash
git add web/src/pages/AssistanceRequestPage.jsx
git commit -m "feat(web): add pagination and search field to accessibility barrier reports"
```

---

### Task 3: End-to-End Verification of Pagination & Clean-up

**Files:**
- Test: automated verification script or browser test to verify page slicing, boundaries, and reset behavior.

- [ ] **Step 1: Create a test script to verify pagination logic and rendering invariants**
Test that:
- Slicing 0 items returns 0 items and page 1.
- Slicing 25 items produces 3 pages (10, 10, 5 items).
- Resetting filter changes page back to 1.
- Boundaries (disabling next on last page, previous on page 1).

- [ ] **Step 2: Run verification**
Execute `node web/tests/pagination_logic_test.mjs` and `npm run build`.

- [ ] **Step 3: Commit**
```bash
git add web/tests/
git commit -m "test(web): add verification test for request and barrier pagination logic"
```
