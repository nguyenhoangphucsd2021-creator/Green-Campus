export default async (request) => {
 if(request.method!=='GET'&&request.method!=='HEAD')return new Response('Method not allowed',{status:405});
 return new Response(JSON.stringify({
  ok: true, service: 'green-campus-api', version: '2.2.0', timestamp: new Date().toISOString(),
  integrations: { database: Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY), scheduledFeeds: Boolean(process.env.GC_FEED_URLS) }
}), { headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } });
};
