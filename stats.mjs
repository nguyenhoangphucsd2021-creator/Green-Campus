import {createClient} from '@supabase/supabase-js';
const json=(d,s=200)=>new Response(JSON.stringify(d),{status:s,headers:{'content-type':'application/json; charset=utf-8','cache-control':'public, max-age=60'}});
export default async(request)=>{
 if(request.method!=='GET'&&request.method!=='HEAD')return json({error:'Chỉ chấp nhận GET.'},405);
 if(!process.env.SUPABASE_URL||!process.env.SUPABASE_SERVICE_ROLE_KEY)return json({configured:false});
 try{const db=createClient(process.env.SUPABASE_URL,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});const since=new Date(Date.now()-30*86400000).toISOString();
 const names=['page_view','catalog_search','reuse_report'];const results=await Promise.all(names.map(name=>db.from('activity_events').select('id',{count:'exact',head:true}).eq('event_name',name).gte('created_at',since)));
 if(results.some(x=>x.error))throw new Error('stats');return json({configured:true,periodDays:30,visits:results[0].count||0,searches:results[1].count||0,reuseActions:results[2].count||0});
 }catch(e){return json({configured:false,error:'Không thể tải thống kê.'},502)}
};
