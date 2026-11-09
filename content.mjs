import { createClient } from '@supabase/supabase-js';
const json=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'content-type':'application/json; charset=utf-8','cache-control':'public, max-age=60'}});
export default async(request)=>{
  if(request.method!=='GET'&&request.method!=='HEAD')return json({error:'Chỉ chấp nhận GET.'},405);
  if(!process.env.SUPABASE_URL||!process.env.SUPABASE_SERVICE_ROLE_KEY)return json({items:[],configured:false});
  const db=createClient(process.env.SUPABASE_URL,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});
  const {data,error}=await db.from('content_items').select('id,title,excerpt,body,category,icon,image_url,source_url,source_name,published_at').eq('status','published').order('published_at',{ascending:false}).limit(60);
  if(error)return json({error:'Không thể tải nội dung công khai.'},502);
  return json({items:data||[],configured:true});
};
