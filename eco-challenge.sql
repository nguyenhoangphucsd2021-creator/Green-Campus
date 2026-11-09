-- GREEN CAMPUS · ECO CHALLENGE — chạy SAU supabase/schema.sql (dùng public.profiles và public.is_editor()).
-- Nguyên tắc: điểm trực tuyến do máy chủ chấm; điểm thực tiễn chỉ do quản trị viên quyết định;
-- mọi thay đổi điểm là một dòng trong sổ điểm (eco_ledger), không sửa/xóa.
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public
as $$ select exists (select 1 from public.profiles p where p.id=auth.uid() and p.role='admin'); $$;

create table if not exists public.eco_seasons (
  id bigint generated always as identity primary key,
  status text not null default 'idle' check (status in ('idle','running','paused','ended')),
  duration_days int not null default 7 check (duration_days between 1 and 30),
  elapsed_ms bigint not null default 0,            -- thời gian đã chạy (không tính lúc tạm dừng)
  resumed_at timestamptz,
  allow_activity_when_paused boolean not null default false,
  created_at timestamptz not null default now());

create table if not exists public.eco_questions (   -- ngân hàng câu hỏi đã kiểm duyệt
  id bigint generated always as identity primary key,
  theme text not null check (theme in ('sort','recycle','eco','res','life')),
  difficulty int not null check (difficulty between 1 and 3),
  prompt text not null, options jsonb not null, correct_index int not null, explanation text,
  status text not null default 'pending_review' check (status in ('pending_review','approved','retired')));

create table if not exists public.eco_attempts (    -- 1 lượt / người / khung 2 giờ hoặc ngày
  id bigint generated always as identity primary key,
  season_id bigint not null references public.eco_seasons(id),
  user_id uuid not null references auth.users(id),
  kind text not null check (kind in ('slot','daily')), slot_key int not null,
  question_ids bigint[] not null, correct int not null default 0, points int not null default 0,
  created_at timestamptz not null default now(),
  unique (season_id,user_id,kind,slot_key));

create table if not exists public.eco_activities (
  id bigint generated always as identity primary key,
  season_id bigint not null references public.eco_seasons(id),
  user_id uuid not null references auth.users(id),
  activity_type text not null, description text not null check (char_length(description)>=20),
  place_time text, evidence_paths text[] not null default '{}', content_hash text,
  possible_duplicate boolean not null default false,
  status text not null default 'pending' check (status in ('pending','approved','rejected','revoked')),
  points int check (points is null or points>=0),   -- do quản trị viên nhập, không có mức tự động
  reviewer_note text, reviewed_by uuid references auth.users(id), reviewed_at timestamptz,
  created_at timestamptz not null default now());

create table if not exists public.eco_ledger (      -- sổ điểm: chỉ thêm
  id bigint generated always as identity primary key,
  season_id bigint not null references public.eco_seasons(id),
  user_id uuid not null references auth.users(id),
  entry_type text not null check (entry_type in ('quiz','activity','adjust','revoke')),
  points int not null, ref_id bigint, note text,
  actor uuid references auth.users(id), created_at timestamptz not null default now());

create or replace view public.eco_leaderboard with (security_invoker=false) as
select l.season_id, l.user_id, p.display_name,
  coalesce(sum(points) filter (where entry_type='quiz'),0) as online_points,
  coalesce(sum(points) filter (where entry_type<>'quiz'),0) as practical_points,
  sum(points) as total_points
from public.eco_ledger l join public.profiles p on p.id=l.user_id
group by l.season_id,l.user_id,p.display_name;

-- Admin duyệt hoạt động + ghi điểm trong MỘT giao dịch (kiểm tra quyền ở máy chủ)
create or replace function public.eco_review_activity(p_id bigint,p_decision text,p_points int,p_note text)
returns void language plpgsql security definer set search_path=public as $$
declare a public.eco_activities; delta int;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  select * into a from public.eco_activities where id=p_id for update;
  if p_decision='approve' then
    if p_points is null or p_points<0 then raise exception 'points required'; end if;
    delta:=p_points-coalesce(case when a.status='approved' then a.points end,0);
    update public.eco_activities set status='approved',points=p_points,reviewer_note=p_note,reviewed_by=auth.uid(),reviewed_at=now() where id=p_id;
    if delta<>0 then insert into public.eco_ledger(season_id,user_id,entry_type,points,ref_id,note,actor)
      values(a.season_id,a.user_id,case when a.status='approved' then 'adjust' else 'activity' end,delta,p_id,p_note,auth.uid()); end if;
  elsif p_decision='revoke' and a.status='approved' then
    update public.eco_activities set status='revoked',reviewer_note=p_note,reviewed_by=auth.uid(),reviewed_at=now() where id=p_id;
    insert into public.eco_ledger(season_id,user_id,entry_type,points,ref_id,note,actor) values(a.season_id,a.user_id,'revoke',-a.points,p_id,p_note,auth.uid());
  elsif p_decision='reject' then
    update public.eco_activities set status='rejected',reviewer_note=p_note,reviewed_by=auth.uid(),reviewed_at=now() where id=p_id;
  end if;
end $$;
revoke all on function public.eco_review_activity(bigint,text,integer,text) from public, anon;
grant execute on function public.eco_review_activity(bigint,text,integer,text) to authenticated;

alter table public.eco_seasons enable row level security;   alter table public.eco_questions enable row level security;
alter table public.eco_attempts enable row level security;  alter table public.eco_activities enable row level security;
alter table public.eco_ledger enable row level security;
drop policy if exists "seasons read" on public.eco_seasons;
create policy "seasons read" on public.eco_seasons for select to authenticated using (true);
drop policy if exists "seasons admin" on public.eco_seasons;
create policy "seasons admin" on public.eco_seasons for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "questions admin" on public.eco_questions;
create policy "questions admin" on public.eco_questions for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "attempts own" on public.eco_attempts;
create policy "attempts own" on public.eco_attempts for select to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists "activities own read" on public.eco_activities;
create policy "activities own read" on public.eco_activities for select to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists "activities insert pending" on public.eco_activities;
create policy "activities insert pending" on public.eco_activities for insert to authenticated with check (user_id=auth.uid() and status='pending' and points is null);
drop policy if exists "ledger own read" on public.eco_ledger;
create policy "ledger own read" on public.eco_ledger for select to authenticated using (user_id=auth.uid() or public.is_admin());
-- Không có policy insert/update/delete cho eco_ledger: chỉ hàm máy chủ (security definer / service role) được ghi.
-- Lưu ý: nhánh chấm điểm trắc nghiệm (ghi eco_attempts + eco_ledger) cần Netlify Function dùng service role.
-- Storage: tạo bucket riêng tư "eco-evidence"; người chơi chỉ tải lên thư mục <user_id>/.

-- Tiến trình cây xanh theo tài khoản (đồng bộ nhiều thiết bị qua Supabase Auth). Chỉ ghi qua hàm máy chủ.
create table if not exists public.eco_tree (
  user_id uuid primary key references auth.users(id), season_id bigint references public.eco_seasons(id),
  water int not null default 0, fertilizer int not null default 0, growth int not null default 0,
  invested int not null default 0, harvests int not null default 0, updated_at timestamptz not null default now());
alter table public.eco_tree enable row level security;
drop policy if exists "tree own read" on public.eco_tree;
create policy "tree own read" on public.eco_tree for select to authenticated using (user_id=auth.uid() or public.is_admin());
