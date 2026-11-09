-- GREEN CAMPUS QUIZ ENGINE v1
-- Chạy SAU schema.sql và eco-cloud-v2.sql trong Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.eco_quiz_questions (
  id uuid primary key default gen_random_uuid(),
  question text not null check (char_length(question) between 10 and 700),
  options jsonb not null check (jsonb_typeof(options)='array' and jsonb_array_length(options)=4),
  correct_answer text not null check (correct_answer in ('A','B','C','D')),
  explanation text not null default '' check (char_length(explanation)<=1200),
  topic text not null default 'Môi trường',
  difficulty smallint not null check (difficulty between 1 and 4),
  source_name text not null default 'Ngân hàng Green Campus',
  source_url text,
  origin text not null default 'bank' check (origin in ('bank','ai')),
  status text not null default 'approved' check (status in ('pending_review','approved','rejected','archived')),
  created_by uuid references auth.users(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists eco_quiz_questions_pool_idx on public.eco_quiz_questions(status,difficulty,topic);

create table if not exists public.eco_quiz_progress (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_level smallint not null default 1 check (current_level between 1 and 4),
  total_answered integer not null default 0,
  total_correct integer not null default 0,
  current_streak integer not null default 0,
  best_streak integer not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.eco_quiz_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  question_ids uuid[] not null,
  difficulty smallint not null check (difficulty between 1 and 4),
  status text not null default 'open' check (status in ('open','submitted','expired')),
  result jsonb,
  score integer not null default 0,
  created_at timestamptz not null default now(),
  submitted_at timestamptz
);
create index if not exists eco_quiz_sessions_user_idx on public.eco_quiz_sessions(user_id,created_at desc);

create table if not exists public.eco_quiz_seen (
  user_id uuid not null references auth.users(id) on delete cascade,
  question_id uuid not null references public.eco_quiz_questions(id) on delete cascade,
  seen_at timestamptz not null default now(),
  primary key(user_id,question_id)
);

alter table public.eco_quiz_questions enable row level security;
alter table public.eco_quiz_progress enable row level security;
alter table public.eco_quiz_sessions enable row level security;
alter table public.eco_quiz_seen enable row level security;

drop policy if exists "quiz questions public approved read" on public.eco_quiz_questions;
create policy "quiz questions public approved read" on public.eco_quiz_questions for select to authenticated using (status='approved' or public.is_editor());
drop policy if exists "quiz editors manage questions" on public.eco_quiz_questions;
create policy "quiz editors manage questions" on public.eco_quiz_questions for all to authenticated using(public.is_editor()) with check(public.is_editor());
drop policy if exists "quiz progress own read" on public.eco_quiz_progress;
create policy "quiz progress own read" on public.eco_quiz_progress for select to authenticated using(user_id=auth.uid() or public.is_editor());
drop policy if exists "quiz sessions own read" on public.eco_quiz_sessions;
create policy "quiz sessions own read" on public.eco_quiz_sessions for select to authenticated using(user_id=auth.uid() or public.is_editor());
drop policy if exists "quiz seen own read" on public.eco_quiz_seen;
create policy "quiz seen own read" on public.eco_quiz_seen for select to authenticated using(user_id=auth.uid());

grant select on public.eco_quiz_questions, public.eco_quiz_progress, public.eco_quiz_sessions, public.eco_quiz_seen to authenticated;
revoke insert,update,delete on public.eco_quiz_questions,public.eco_quiz_progress,public.eco_quiz_sessions,public.eco_quiz_seen from anon,authenticated;

-- Điểm và cấp độ được tính trong hàm máy chủ; trình duyệt không gửi số điểm.
create or replace function public.eco_quiz_submit(p_session_id uuid,p_answers jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_uid uuid:=auth.uid(); v_session public.eco_quiz_sessions; v_q record; v_answer text;
  v_correct boolean; v_count integer:=0; v_right integer:=0; v_points integer:=0;
  v_items jsonb:='[]'::jsonb; v_level smallint:=1; v_streak integer:=0; v_best integer:=0;
begin
  if v_uid is null then raise exception 'Bạn cần đăng nhập.'; end if;
  if coalesce(jsonb_typeof(p_answers),'')<>'array' then raise exception 'Dữ liệu câu trả lời không hợp lệ.'; end if;
  select * into v_session from public.eco_quiz_sessions where id=p_session_id and user_id=v_uid for update;
  if not found then raise exception 'Không tìm thấy lượt chơi.'; end if;
  if v_session.status<>'open' then raise exception 'Lượt chơi này đã được nộp.'; end if;
  if v_session.created_at<now()-interval '45 minutes' then update public.eco_quiz_sessions set status='expired' where id=p_session_id; raise exception 'Lượt chơi đã hết hạn, hãy bắt đầu lượt mới.'; end if;
  for v_q in select id,question,options,correct_answer,explanation,difficulty,topic,source_name,source_url from public.eco_quiz_questions where id=any(v_session.question_ids) and status='approved' order by array_position(v_session.question_ids,id) loop
    v_count:=v_count+1;
    select upper(coalesce(x->>'answer','')) into v_answer from jsonb_array_elements(p_answers) x where x->>'question_id'=v_q.id::text limit 1;
    v_correct:=coalesce(v_answer=v_q.correct_answer,false);
    if v_correct then v_right:=v_right+1; v_points:=v_points+case v_q.difficulty when 1 then 2 when 2 then 3 when 3 then 4 else 5 end; end if;
    v_items:=v_items||jsonb_build_array(jsonb_build_object('question_id',v_q.id,'correct',v_correct,'correct_answer',v_q.correct_answer,'explanation',v_q.explanation,'source_name',v_q.source_name,'source_url',v_q.source_url));
    insert into public.eco_quiz_seen(user_id,question_id) values(v_uid,v_q.id) on conflict(user_id,question_id) do update set seen_at=now();
  end loop;
  if v_count=0 then raise exception 'Không có câu hỏi hợp lệ trong lượt chơi.'; end if;
  select current_level,current_streak,best_streak into v_level,v_streak,v_best from public.eco_quiz_progress where user_id=v_uid for update;
  if not found then v_level:=1;v_streak:=0;v_best:=0; end if;
  if v_right=v_count then v_streak:=v_streak+v_right; else v_streak:=0; end if;
  v_best:=greatest(v_best,v_streak);
  if v_right>=4 and v_count>=5 then v_level:=least(4,v_level+1);
  elsif v_right<=1 and v_count>=5 then v_level:=greatest(1,v_level-1); end if;
  insert into public.eco_quiz_progress(user_id,current_level,total_answered,total_correct,current_streak,best_streak,updated_at)
  values(v_uid,v_level,v_count,v_right,v_streak,v_best,now())
  on conflict(user_id) do update set current_level=excluded.current_level,total_answered=public.eco_quiz_progress.total_answered+excluded.total_answered,total_correct=public.eco_quiz_progress.total_correct+excluded.total_correct,current_streak=excluded.current_streak,best_streak=greatest(public.eco_quiz_progress.best_streak,excluded.best_streak),updated_at=now();
  if v_points>0 then insert into public.eco_account_ledger(user_id,delta,reason,actor) values(v_uid,v_points,'Điểm trắc nghiệm Green Campus',v_uid); end if;
  update public.eco_quiz_sessions set status='submitted',score=v_points,result=jsonb_build_object('total',v_count,'correct',v_right,'points',v_points,'items',v_items,'next_level',v_level),submitted_at=now() where id=p_session_id;
  return jsonb_build_object('total',v_count,'correct',v_right,'points',v_points,'items',v_items,'next_level',v_level,'current_streak',v_streak,'best_streak',v_best);
end $$;
revoke all on function public.eco_quiz_submit(uuid,jsonb) from public,anon;
grant execute on function public.eco_quiz_submit(uuid,jsonb) to authenticated;

-- Một số câu hỏi mẫu đã biên soạn; câu hỏi AI luôn ở trạng thái chờ duyệt.
insert into public.eco_quiz_questions(question,options,correct_answer,explanation,topic,difficulty,source_name,origin,status)
select x.question,x.options::jsonb,x.answer,x.explanation,x.topic,x.level,'Ngân hàng kiến thức Green Campus','bank','approved'
from (values
('Theo nguyên tắc 3R, hành động nào nên được ưu tiên trước tiên?','["Tái chế vật liệu","Giảm lượng tiêu dùng và rác phát sinh","Đốt rác để thu hồi năng lượng","Chôn lấp rác đã phân loại"]','B','Giảm thiểu từ nguồn giúp tránh phát sinh chất thải ngay từ đầu.','Lối sống xanh',1),
('Vì sao cần làm sạch và để ráo bao bì trước khi đưa vào tái chế?','["Để tăng khối lượng rác","Để giảm nhiễm bẩn và hỗ trợ quy trình tái chế","Để biến mọi loại nhựa thành phân hữu cơ","Để không cần phân loại vật liệu"]','B','Thức ăn và chất lỏng còn sót có thể làm bẩn vật liệu tái chế.','Phân loại rác',1),
('Nguồn năng lượng nào được xem là tái tạo?','["Than đá","Dầu mỏ","Năng lượng mặt trời","Khí tự nhiên"]','C','Năng lượng mặt trời được bổ sung tự nhiên và không cần khai thác nhiên liệu hóa thạch.','Năng lượng',1),
('Hành động nào giúp tiết kiệm điện khi rời phòng học?','["Để máy chiếu ở chế độ chờ","Tắt đèn và thiết bị không cần thiết","Mở điều hòa khi cửa mở","Cắm sạc liên tục dù không dùng"]','B','Tắt thiết bị không cần thiết giúp giảm điện năng tiêu thụ.','Năng lượng',1),
('Rừng ngập mặn có vai trò quan trọng nào đối với vùng ven biển?','["Làm tăng xói lở bờ biển","Giảm tác động sóng, giữ trầm tích và tạo sinh cảnh","Loại bỏ hoàn toàn nước mặn","Ngăn mọi loài thủy sinh di chuyển"]','B','Rừng ngập mặn góp phần bảo vệ bờ biển và duy trì sinh cảnh cho nhiều loài.','Đa dạng sinh học',2),
('Đa dạng sinh học thường được xem xét ở những cấp độ nào?','["Gen, loài và hệ sinh thái","Chỉ số lượng cá thể","Chỉ số lượng rừng","Chỉ đất, nước và không khí"]','A','Đa dạng sinh học bao gồm đa dạng di truyền, đa dạng loài và đa dạng hệ sinh thái.','Đa dạng sinh học',2),
('Hiện tượng phú dưỡng trong hồ thường liên quan đến điều gì?','["Thiếu hoàn toàn ánh sáng mặt trời","Dư thừa chất dinh dưỡng như nitơ và phốt pho","Nước có độ mặn cao tự nhiên","Sự biến mất của mọi vi sinh vật"]','B','Nitơ và phốt pho dư thừa có thể thúc đẩy tảo phát triển quá mức và làm suy giảm oxy hòa tan.','Nước',3),
('Vì sao phát thải khí nhà kính làm biến đổi khí hậu?','["Chúng làm giảm hoàn toàn trọng lực","Chúng làm thay đổi cân bằng năng lượng bằng cách giữ lại nhiệt trong khí quyển","Chúng ngăn mọi bức xạ Mặt Trời tới Trái Đất","Chúng làm đại dương ngừng bốc hơi"]','B','Khí nhà kính hấp thụ và phát xạ bức xạ hồng ngoại, làm thay đổi cân bằng năng lượng của hệ thống khí hậu.','Khí hậu',3),
('Một trường học muốn giảm rác nhựa dùng một lần. Biện pháp nào tác động trực tiếp nhất đến nguồn phát sinh?','["Chỉ tăng số thùng rác","Thay chai dùng một lần bằng hệ thống bình cá nhân và điểm tiếp nước","Chuyển toàn bộ rác sang bãi chôn lấp khác","Tăng tần suất thu gom mà không đổi hành vi"]','B','Hệ thống bình cá nhân và điểm tiếp nước giảm nhu cầu sử dụng chai dùng một lần.','Kinh tế tuần hoàn',3),
('Khi đánh giá một tuyên bố về môi trường lan truyền trên mạng, cách làm nào đáng tin cậy nhất?','["Chia sẻ nếu có nhiều lượt thích","Kiểm tra phương pháp, dữ liệu, thời điểm và nguồn độc lập đáng tin cậy","Chỉ đọc tiêu đề","Tin mọi hình ảnh có biểu đồ"]','B','Cần đánh giá nguồn, phương pháp và bằng chứng độc lập thay vì dựa vào mức độ phổ biến.','Tư duy phản biện',4),
('Trong đánh giá vòng đời sản phẩm, vì sao không nên chỉ xem lượng bao bì?','["Vì bao bì không có tác động môi trường","Vì cần xem xét cả nguyên liệu, sản xuất, vận chuyển, sử dụng và cuối vòng đời","Vì chỉ giá bán quyết định tác động","Vì sản phẩm tái sử dụng luôn không có tác động"]','B','Đánh giá vòng đời xem xét nhiều giai đoạn và loại tác động môi trường của sản phẩm.','Đánh giá vòng đời',4),
('Khi hai phương án giảm phát thải có chi phí khác nhau, chỉ số nào hữu ích để so sánh hiệu quả chi phí?','["Tổng số lượt thích","Chi phí trên mỗi đơn vị phát thải được giảm tránh","Số trang quảng cáo","Màu sắc của thiết bị"]','B','Chi phí trên mỗi đơn vị phát thải giảm tránh giúp so sánh hiệu quả chi phí giữa các phương án.','Phân tích giải pháp',4)
) as x(question,options,answer,explanation,topic,level)
where not exists(select 1 from public.eco_quiz_questions q where q.question=x.question)
union all
select x.question,x.options::jsonb,x.answer,x.explanation,x.topic,x.level,'Ngân hàng kiến thức Green Campus','bank','approved'
from (values
('Loại rác nào thường cần được thu gom riêng vì có thể chứa hóa chất độc hại?','["Pin đã qua sử dụng","Vỏ chuối","Giấy báo sạch","Lá cây khô"]','A','Pin thải có thể chứa kim loại và hóa chất cần được thu gom riêng.','Phân loại rác',1),
('Cách nào giúp giảm lãng phí nước khi đánh răng?','["Mở vòi liên tục","Khóa vòi khi không sử dụng","Dùng nước uống đóng chai","Tăng áp lực vòi"]','B','Khóa vòi trong lúc chải răng tránh để nước chảy không cần thiết.','Nước',1),
('Hiệu ứng đảo nhiệt đô thị thường rõ hơn ở khu vực nào?','["Khu vực nhiều cây và mặt nước","Khu vực dày đặc bê tông, ít cây xanh","Khu bảo tồn rừng","Vùng đất ngập nước tự nhiên"]','B','Bề mặt xây dựng hấp thụ và giữ nhiệt, trong khi thiếu cây xanh làm giảm hiệu quả làm mát.','Đô thị xanh',2),
('Vì sao không nên đốt rác nhựa ngoài trời?','["Vì nhựa luôn biến thành nước","Vì có thể phát sinh khói và chất ô nhiễm gây hại","Vì làm nhựa trở thành phân bón","Vì không tạo ra khí thải"]','B','Đốt nhựa không kiểm soát có thể phát thải các chất ô nhiễm vào không khí.','Ô nhiễm không khí',2),
('Trong hệ sinh thái, loài bản địa có vai trò gì?','["Luôn gây mất cân bằng","Góp phần duy trì quan hệ sinh thái và chức năng tự nhiên tại khu vực","Không tương tác với loài khác","Chỉ tồn tại trong môi trường nhân tạo"]','B','Các loài bản địa là thành phần của mạng lưới sinh thái hình thành tại khu vực.','Đa dạng sinh học',3),
('Một sản phẩm được gắn nhãn “phân hủy sinh học” có nhất thiết phân hủy nhanh trong mọi môi trường không?','["Có, trong mọi điều kiện","Không, tốc độ và mức độ phân hủy phụ thuộc điều kiện môi trường","Có, ngay cả trong môi trường chân không","Không cần vi sinh vật hay điều kiện phù hợp"]','B','Quá trình phân hủy phụ thuộc nhiệt độ, độ ẩm, oxy, vi sinh vật và điều kiện xử lý.','Vật liệu bền vững',3),
('Khi xây dựng chỉ số đánh giá hiệu quả chương trình phân loại rác tại trường, chỉ số nào phản ánh trực tiếp chất lượng phân loại?','["Số bài đăng truyền thông","Tỷ lệ vật liệu tái chế bị lẫn tạp chất","Số màu của thùng rác","Số lượt xem trang web"]','B','Tỷ lệ tạp chất cho biết mức độ lẫn sai vật liệu trong dòng rác được phân loại.','Đo lường tác động',4),
('Trong đánh giá rủi ro khí hậu, “khả năng thích ứng” của cộng đồng chủ yếu nói đến điều gì?','["Khả năng loại bỏ hoàn toàn mọi thiên tai","Năng lực điều chỉnh, chuẩn bị và ứng phó với tác động khí hậu","Mức độ phát thải cao hơn","Khả năng dự báo chính xác mọi biến động thời tiết"]','B','Khả năng thích ứng là năng lực điều chỉnh hệ thống để giảm thiệt hại và tận dụng cơ hội trước tác động khí hậu.','Thích ứng khí hậu',4)
) as x(question,options,answer,explanation,topic,level)
where not exists(select 1 from public.eco_quiz_questions q where q.question=x.question);
