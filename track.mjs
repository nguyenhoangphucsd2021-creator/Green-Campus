import {createClient} from '@supabase/supabase-js';
const json=(d,s=200)=>new Response(JSON.stringify(d),{status:s,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store'}});
const allowed=new Set(['page_view','catalog_search','image_classify','reuse_open','product_open','news_open','assistant_question','reuse_report']);
export default async request=>{
 if(request.method!=='POST')return json({error:'Chỉ chấp nhận POST.'},405);
 const declaredSize=Number(request.headers.get('content-length')||0);
 if(declaredSize>4096)return json({error:'Yêu cầu vượt giới hạn 4 KB.'},413);
 if(!process.env.SUPABASE_URL||!process.env.SUPABASE_SERVICE_ROLE_KEY)return json({configured:false},503);
 try{const raw=await request.text();if(raw.length>4096)return json({error:'Yêu cầu vượt giới hạn 4 KB.'},413);
 const b=JSON.parse(raw);if(!allowed.has(b?.eventName))return json({error:'Sự kiện không hợp lệ.'},400);
 const payload={};if(b.eventName==='page_view'&&typeof b.payload?.path==='string')payload.path=b.payload.path.slice(0,100);if(Number.isFinite(b.payload?.queryLength))payload.queryLength=Math.min(120,Math.max(0,b.payload.queryLength));if(Number.isFinite(b.payload?.questionLength))payload.questionLength=Math.min(1200,Math.max(0,b.payload.questionLength));if(b.eventName==='reuse_report'&&['reuse_general','reuse_paper','reuse_plastic','reuse_other'].includes(b.payload?.kind))payload.kind=b.payload.kind;
 const db=createClient(process.env.SUPABASE_URL,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});const {error}=await db.from('activity_events').insert({event_name:b.eventName,payload});if(error)throw error;return json({ok:true});
 }catch(e){return json({error:'Không thể ghi nhận hoạt động.'},500)}
};
