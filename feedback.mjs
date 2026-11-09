import {createClient} from '@supabase/supabase-js';
const json=(d,s=200)=>new Response(JSON.stringify(d),{status:s,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store'}});
export default async request=>{
 if(request.method!=='POST')return json({error:'Chỉ chấp nhận POST.'},405);
 const declaredSize=Number(request.headers.get('content-length')||0);
 if(declaredSize>8192)return json({error:'Yêu cầu vượt giới hạn 8 KB.'},413);
 if(!process.env.SUPABASE_URL||!process.env.SUPABASE_SERVICE_ROLE_KEY)return json({error:'Biểu mẫu phản hồi chưa được cấu hình.'},503);
 try{const raw=await request.text();if(raw.length>8192)return json({error:'Yêu cầu vượt giới hạn 8 KB.'},413);
 const b=JSON.parse(raw);if(b?.website)return json({ok:true});const message=String(b?.message||'').trim(),kind=String(b?.kind||'general');if(message.length<3||message.length>2000)return json({error:'Nội dung cần từ 3 đến 2.000 ký tự.'},400);if(!['general','data','reuse','bug'].includes(kind))return json({error:'Loại phản hồi không hợp lệ.'},400);
 const db=createClient(process.env.SUPABASE_URL,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});const {error}=await db.from('feedback').insert({kind,message});if(error)throw error;return json({ok:true});
 }catch(e){return json({error:'Không thể lưu phản hồi.'},500)}
};
