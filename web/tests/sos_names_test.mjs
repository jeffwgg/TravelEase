import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const request = { id: 'completed-task', status: 'resolved', traveller: null }
const query = new Proxy({}, { get: (_target, key) => {
  if (key === 'then') return resolve => resolve({ data: [request], error: null })
  if (key === 'single') return async () => ({ data: request, error: null })
  return () => query
} })
globalThis.__sosNamesClient = {
  from: () => query,
  rpc: async (name, args) => {
    assert.equal(name, 'get_sos_traveller_names')
    assert.deepEqual(args.p_request_ids, ['completed-task'])
    return { data: [{ request_id: 'completed-task', full_name: 'Actual Traveller Name' }], error: null }
  },
}
try {
  const source = (await readFile(new URL('../src/repositories/sosRequestRepository.js', import.meta.url), 'utf8'))
    .replace("import { supabase } from '../lib/supabase'", 'const supabase = globalThis.__sosNamesClient')
  const { sosRequestRepository: repository } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
  assert.equal((await repository.listForInstitution('institution', 'staff'))[0].traveller.full_name, 'Actual Traveller Name')
  assert.equal((await repository.updateStatus('institution', 'completed-task', 'en_route', 'resolved')).traveller.full_name, 'Actual Traveller Name')
  console.log('PASS: Completed-task list and resolution retain traveller names when profile join is hidden')
} finally { delete globalThis.__sosNamesClient }
