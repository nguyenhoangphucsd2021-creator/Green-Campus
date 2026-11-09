import { createClient } from '@supabase/supabase-js';
const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store'}});
const shuffle=a=>{a=[...a];for(let i=a.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[a[i],a[j]]=[a[j],a[i]];}return a;};
export default async request=>{
 if(request.method!=='POST')return reply({error:'Method not allowed'},405);
 const url=process.env.SUPABASE_URL,service=process.env.SUPABASE_SERVICE_ROLE_KEY,anon=process.env.SUPABASE_ANON_KEY;
 if(!url||!service||!anon)return reply({error:'Quiz backend chưa được cấu hình đầy đủ.'},503);
 const token=(request.headers.get('authorization')||'').replace(/^Bearer\s+/i,'');if(!token)return reply({error:'Bạn cần đăng nhập.'},401);
 const auth=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}});const {data:{user},error:authError}=await auth.auth.getUser(token);if(authError||!user)return reply({error:'Phiên đăng nhập không hợp lệ.'},401);
 const db=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
 try{
  const {count:recentSessions}=await db.from('eco_quiz_sessions').select('id',{count:'exact',head:true}).eq('user_id',user.id).gte('created_at',new Date(Date.now()-10*60*1000).toISOString());
  if((recentSessions||0)>=5)return reply({error:'Bạn đã bắt đầu quá nhiều lượt trong thời gian ngắn. Vui lòng chờ một chút.'},429);
  const {data:progress}=await db.from('eco_quiz_progress').select('current_level,total_answered,total_correct,current_streak,best_streak').eq('user_id',user.id).maybeSingle();
  const level=Math.min(4,Math.max(1,progress?.current_level||1));
  const {data:seenRows}=await db.from('eco_quiz_seen').select('question_id').eq('user_id',user.id).order('seen_at',{ascending:false}).limit(100);
  const seen=new Set((seenRows||[]).map(x=>x.question_id));
  const {data:pool,error}=await db.from('eco_quiz_questions').select('id,question,options,topic,difficulty,source_name,source_url').eq('status','approved').limit(500);
  if(error)throw error;
  const candidates=shuffle((pool||[]).filter(q=>!seen.has(q.id)));
  if(candidates.length<5)return reply({error:'Bạn đã gặp gần hết câu hỏi hiện có. Quản trị viên cần bổ sung và duyệt thêm câu hỏi mới trước lượt tiếp theo.'},409);
  const chosen=candidates.sort((a,b)=>Math.abs(a.difficulty-level)-Math.abs(b.difficulty-level)).slice(0,5);
  const {data:session,error:insertError}=await db.from('eco_quiz_sessions').insert({user_id:user.id,question_ids:chosen.map(q=>q.id),difficulty:level}).select('id').single();
  if(insertError)throw insertError;
  const {error:seenError}=await db.from('eco_quiz_seen').upsert(chosen.map(q=>({user_id:user.id,question_id:q.id,seen_at:new Date().toISOString()})),{onConflict:'user_id,question_id'});if(seenError)throw seenError;
  const questions=chosen.map(q=>({id:q.id,question:q.question,options:q.options,topic:q.topic,difficulty:q.difficulty}));
  return reply({sessionId:session.id,level,questions,progress:{totalAnswered:progress?.total_answered||0,totalCorrect:progress?.total_correct||0,currentStreak:progress?.current_streak||0,bestStreak:progress?.best_streak||0}});
 }catch(e){return reply({error:e.message||'Không thể tạo lượt chơi.'},500)}
};
