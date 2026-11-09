import { XMLParser } from 'fast-xml-parser';
import { createClient } from '@supabase/supabase-js';

const parser = new XMLParser({ ignoreAttributes:false, attributeNamePrefix:'@_', textNodeName:'#text', trimValues:true });
const asArray = value => value == null ? [] : Array.isArray(value) ? value : [value];
const clean = value => String(typeof value === 'object' ? (value['#text'] || '') : (value || '')).replace(/<[^>]*>/g,' ').replace(/\s+/g,' ').trim().slice(0,1200);
const hash = async value => [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)))].map(x=>x.toString(16).padStart(2,'0')).join('');

export default async () => {
  const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GC_FEED_URLS } = process.env;
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) return new Response('Thiếu cấu hình Supabase.', { status:500 });
  const feeds = (GC_FEED_URLS || '').split(',').map(x=>x.trim()).filter(Boolean);
  if (!feeds.length) return new Response('Chưa cấu hình GC_FEED_URLS; không có nguồn nào được thu thập.', { status:200 });
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth:{ persistSession:false } });
  const report = [];
  for (const feedUrl of feeds.slice(0,12)) {
    try {
      const url = new URL(feedUrl);
      if (!['https:'].includes(url.protocol)) throw new Error('Chỉ chấp nhận nguồn HTTPS.');
      const response = await fetch(url, { headers:{ 'user-agent':'GreenCampusFeedBot/2.0 (+educational use)' }, signal:AbortSignal.timeout(12000) });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const xml = await response.text();
      if (xml.length > 2_000_000) throw new Error('Nguồn vượt giới hạn 2 MB.');
      const parsed = parser.parse(xml);
      const entries = asArray(parsed.rss?.channel?.item || parsed.feed?.entry).slice(0,30);
      let inserted = 0;
      for (const entry of entries) {
        const title = clean(entry.title);
        const linkRaw = entry.link?.['@_href'] || entry.link || entry.guid?.['#text'] || entry.guid || '';
        const link = typeof linkRaw === 'string' ? linkRaw : '';
        const description = clean(entry.description || entry.summary || entry.content);
        if (!title || !link.startsWith('https://')) continue;
        const fingerprint = await hash(`${title.toLowerCase()}|${link}`);
        const row = { title, excerpt:description, source_url:link, source_name:url.hostname, fingerprint, category:'external', status:'pending_review', collected_at:new Date().toISOString() };
        const { error } = await supabase.from('content_items').upsert(row, { onConflict:'fingerprint', ignoreDuplicates:true });
        if (!error) inserted++;
      }
      report.push({ source:url.hostname, inserted });
    } catch (error) { report.push({ source:feedUrl, error:error.message }); }
  }
  return new Response(JSON.stringify({ ok:true, report, note:'Tất cả nội dung thu thập được lưu ở trạng thái chờ duyệt, không tự động công khai.' }), { headers:{ 'content-type':'application/json; charset=utf-8' } });
};
export const config = { schedule:'17 2 * * *' };
