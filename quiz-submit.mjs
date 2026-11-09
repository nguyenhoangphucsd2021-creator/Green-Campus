import { createClient } from '@supabase/supabase-js';
const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store'}});
export default async request=>{
 if(request.method!=='POST')return reply({error:'Method not allowed'},405);
 const url=process.env.SUPABASE_URL,anon=process.env.SUPABASE_ANON_KEY;if(!url||!anon)return reply({error:'Quiz backend chưa được cấu hình.'},503);
 const token=(request.headers.get('authorization')||'').replace(/^Bearer\s+/i,'');if(!token)return reply({error:'Bạn cần đăng nhập.'},401);
 const db=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:`Bearer ${token}`}}});
 const {data:{user},error:authError}=await db.auth.getUser(token);if(authError||!user)return reply({error:'Phiên đăng nhập không hợp lệ.'},401);
 try{const body=await request.json();if(typeof body.sessionId!=='string'||!Array.isArray(body.answers)||body.answers.length>10)return reply({error:'Dữ liệu nộp bài không hợp lệ.'},400);
  const {data,error}=await db.rpc('eco_quiz_submit',{p_session_id:body.sessionId,p_answers:body.answers});if(error)return reply({error:error.message},400);return reply(data);
 }catch(e){return reply({error:e.message||'Không thể chấm bài.'},500)}
};
