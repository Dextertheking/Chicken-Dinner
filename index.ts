import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

Deno.serve(async () => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  const { data: fixtures, error } = await supabase
    .from('fixtures')
    .select('id')
    .eq('status', 'finished')
    .not('home_score', 'is', null)
    .not('away_score', 'is', null);

  if (error) return new Response(error.message, { status: 500 });
  for (const fixture of fixtures ?? []) {
    const { error: scoreError } = await supabase.rpc('score_fixture', { p_fixture_id: fixture.id });
    if (scoreError) return new Response(scoreError.message, { status: 500 });
  }
  return Response.json({ ok: true, scored: fixtures?.length ?? 0 });
});
