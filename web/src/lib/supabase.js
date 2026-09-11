import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://pewpzfxubdgquvcahemh.supabase.co'
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBld3B6Znh1YmRncXV2Y2FoZW1oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU3NDY2NTgsImV4cCI6MjEwMTMyMjY1OH0.yyxMdTFf7cIUy5oA-e_4vRzNsR_1WXpDTf2QiKbLtiY'

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
})
