import { createClient } from '@supabase/supabase-js';
const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store'}});
export default async request=>{
 if(!['GET','POST'].includes(request.method))return reply({error:'Method not allowed'},405);
 const {SUPABASE_URL,SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY}=process.env;if(!SUPABASE_URL||!SUPABASE_ANON_KEY||!SUPABASE_SERVICE_ROLE_KEY)return reply({error:'Quiz backend chưa cấu hình.'},503);
 const token=(request.headers.get('authorization')||'').replace(/^Bearer\s+/i,'');if(!token)return reply({error:'Cần đăng nhập quản trị.'},401);
 const auth=createClient(SUPABASE_URL,SUPABASE_ANON_KEY,{auth:{persistSession:false}});const {data:{user},error}=await auth.auth.getUser(token);if(error||!user)return reply({error:'Phiên đăng nhập không hợp lệ.'},401);
 const db=createClient(SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});const {data:profile}=await db.from('profiles').select('role').eq('id',user.id).maybeSingle();if(!['admin','editor'].includes(profile?.role))return reply({error:'Không đủ quyền quản trị.'},403);
 try{
  if(request.method==='GET'){const {data,error:e}=await db.from('eco_quiz_questions').select('id,question,options,correct_answer,explanation,topic,difficulty,source_name,source_url,created_at').eq('status','pending_review').order('created_at',{ascending:false}).limit(100);if(e)throw e;return reply({questions:data||[]})}
  const b=await request.json();if(!['approved','rejected'].includes(b.status)||typeof b.id!=='string')return reply({error:'Yêu cầu không hợp lệ.'},400);
  const {data,error:e}=await db.from('eco_quiz_questions').update({status:b.status,reviewed_by:user.id,reviewed_at:new Date().toISOString()}).eq('id',b.id).eq('status','pending_review').select('id').maybeSingle();if(e)throw e;if(!data)return reply({error:'Câu hỏi không tồn tại hoặc đã được xử lý.'},404);return reply({ok:true,status:b.status});
 }catch(e){return reply({error:e.message||'Lỗi quản trị ngân hàng câu hỏi.'},500)}
};
