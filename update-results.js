// Chicken Dinner: automatic results updater
// Runs on a schedule via GitHub Actions (see .github/workflows/update-results.yml)
//
// What it does:
// 1. Asks Supabase for every fixture that doesn't have a result yet
// 2. Asks football-data.org for recently finished Premier League matches
// 3. Matches them up by team names, works out H/D/A, and writes the
//    result + score back into Supabase
//
// It NEVER touches a fixture that already has a result — so any result
// you enter by hand is always safe and won't be overwritten.

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const FOOTBALL_DATA_API_KEY = process.env.FOOTBALL_DATA_API_KEY;

if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !FOOTBALL_DATA_API_KEY) {
  console.error('Missing one of: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, FOOTBALL_DATA_API_KEY');
  process.exit(1);
}

function normalizeTeamName(name) {
  return name
    .toLowerCase()
    .replace(/\bfc\b/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

async function getUnresultedFixtures() {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/fixtures?result=is.null&select=id,home_team,away_team,kickoff`,
    {
      headers: {
        apikey: SERVICE_ROLE_KEY,
      },
    }
  );
  if (!res.ok) throw new Error(`Failed to read fixtures: ${res.status} ${await res.text()}`);
  return res.json();
}

async function getFinishedMatches() {
  const dateTo = new Date();
  const dateFrom = new Date(dateTo.getTime() - 5 * 24 * 60 * 60 * 1000); // last 5 days
  const fmt = (d) => d.toISOString().slice(0, 10);

  const res = await fetch(
    `https://api.football-data.org/v4/competitions/PL/matches?status=FINISHED&dateFrom=${fmt(dateFrom)}&dateTo=${fmt(dateTo)}`,
    { headers: { 'X-Auth-Token': FOOTBALL_DATA_API_KEY } }
  );
  if (!res.ok) throw new Error(`football-data.org error: ${res.status} ${await res.text()}`);
  const data = await res.json();
  return data.matches || [];
}

async function updateFixtureResult(fixtureId, result, homeScore, awayScore) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/fixtures?id=eq.${fixtureId}`, {
    method: 'PATCH',
    headers: {
      apikey: SERVICE_ROLE_KEY,
      'Content-Type': 'application/json',
      Prefer: 'return=minimal',
    },
    body: JSON.stringify({ result, home_score: homeScore, away_score: awayScore }),
  });
  if (!res.ok) throw new Error(`Failed to update fixture ${fixtureId}: ${res.status} ${await res.text()}`);
}

async function main() {
  const unresulted = await getUnresultedFixtures();
  console.log(`Fixtures waiting for a result: ${unresulted.length}`);
  if (unresulted.length === 0) {
    console.log('Nothing to do.');
    return;
  }

  const finished = await getFinishedMatches();
  console.log(`Finished matches found on football-data.org: ${finished.length}`);

  let updated = 0;

  for (const fixture of unresulted) {
    const home = normalizeTeamName(fixture.home_team);
    const away = normalizeTeamName(fixture.away_team);

    const match = finished.find(
      (m) =>
        normalizeTeamName(m.homeTeam.name) === home &&
        normalizeTeamName(m.awayTeam.name) === away
    );

    if (!match) continue;

    const homeScore = match.score.fullTime.home;
    const awayScore = match.score.fullTime.away;
    if (homeScore == null || awayScore == null) continue;

    const result = homeScore > awayScore ? 'H' : homeScore < awayScore ? 'A' : 'D';

    await updateFixtureResult(fixture.id, result, homeScore, awayScore);
    updated++;
    console.log(
      `Updated: ${fixture.home_team} ${homeScore}-${awayScore} ${fixture.away_team} -> ${result}`
    );
  }

  console.log(`Done. ${updated} fixture(s) updated.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
