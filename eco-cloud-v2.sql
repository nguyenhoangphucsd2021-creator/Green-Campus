-- GREEN CAMPUS / ECO CHALLENGE CLOUD V2
-- Chạy SAU supabase/schema.sql. Supabase Auth + RLS; không đưa service_role vào trình duyệt.
create extension if not exists pgcrypto;

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin'); $$;

-- Nhiệm vụ ảnh do quản trị viên đăng, hiển thị cho mọi tài khoản đã đăng nhập.
create table if not exists public.eco_daily_tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 3 and 140),
  description text not null default '' check (char_length(description) <= 2000),
  image_path text,
  task_date date not null default (now() at time zone 'Asia/Ho_Chi_Minh')::date,
  expires_at timestamptz,
  is_published boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists eco_daily_tasks_published_idx on public.eco_daily_tasks(is_published, task_date desc);
alter table public.eco_daily_tasks enable row level security;
drop policy if exists "eco tasks visible to signed users" on public.eco_daily_tasks;
create policy "eco tasks visible to signed users" on public.eco_daily_tasks for select to authenticated using (is_published or public.is_admin());
drop policy if exists "eco admins manage tasks" on public.eco_daily_tasks;
create policy "eco admins manage tasks" on public.eco_daily_tasks for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Sổ điểm tài khoản: người chơi chỉ đọc điểm của mình; quản trị ghi qua RPC.
create table if not exists public.eco_account_ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  delta integer not null check (delta between -100000 and 100000),
  reason text not null check (char_length(reason) between 2 and 300),
  actor uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists eco_account_ledger_user_idx on public.eco_account_ledger(user_id, created_at desc);
alter table public.eco_account_ledger enable row level security;
drop policy if exists "eco points own read" on public.eco_account_ledger;
create policy "eco points own read" on public.eco_account_ledger for select to authenticated using (user_id=auth.uid() or public.is_admin());

create or replace view public.eco_account_totals with (security_invoker=false) as
select user_id, coalesce(sum(delta),0)::bigint as points
from public.eco_account_ledger group by user_id;
create or replace view public.eco_public_leaderboard with (security_invoker=false) as
select p.id as user_id, coalesce(p.display_name,'Người chơi') as display_name, coalesce(t.points,0)::bigint as points
from public.profiles p left join public.eco_account_totals t on t.user_id=p.id;

create or replace function public.eco_admin_adjust_points(p_user_id uuid, p_delta integer, p_reason text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  if p_delta=0 or abs(p_delta)>100000 then raise exception 'invalid point amount'; end if;
  if p_reason is null or char_length(trim(p_reason))<2 then raise exception 'reason required'; end if;
  if not exists(select 1 from public.profiles where id=p_user_id) then raise exception 'account not found'; end if;
  if (select coalesce(sum(delta),0) from public.eco_account_ledger where user_id=p_user_id)+p_delta<0 then raise exception 'point balance cannot be negative'; end if;
  insert into public.eco_account_ledger(user_id,delta,reason,actor)
  values(p_user_id,p_delta,left(trim(p_reason),300),auth.uid());
end $$;
revoke all on function public.eco_admin_adjust_points(uuid,integer,text) from public;
grant execute on function public.eco_admin_adjust_points(uuid,integer,text) to authenticated;

-- Cây xanh: vốn và lợi nhuận được máy chủ tự tính, không nhận số điểm từ trình duyệt.
-- Trồng: -20 điểm; tối đa 2 lần tưới, mỗi lần -5 điểm và rút ngắn 6 giờ;
-- cây trưởng thành sau 24 giờ tự nhiên (tối thiểu 12 giờ nếu dùng đủ 2 lượt tưới);
-- thu hoạch: +40 điểm. Lợi nhuận tối đa theo chu kỳ là +10 điểm khi dùng đủ hai lượt tưới.
create table if not exists public.eco_tree_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  planted_at timestamptz,
  water_boosts integer not null default 0 check (water_boosts between 0 and 2),
  harvest_count integer not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.eco_tree_state enable row level security;
drop policy if exists "eco tree own read" on public.eco_tree_state;
create policy "eco tree own read" on public.eco_tree_state for select to authenticated using (user_id=auth.uid() or public.is_admin());

create or replace function public.eco_tree_action(p_action text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_user uuid:=auth.uid(); v_tree public.eco_tree_state; v_points bigint; v_elapsed interval;
  v_required interval; v_delta integer:=0; v_message text;
begin
  if v_user is null then raise exception 'login required'; end if;
  insert into public.eco_tree_state(user_id) values(v_user) on conflict(user_id) do nothing;
  select * into v_tree from public.eco_tree_state where user_id=v_user for update;
  select coalesce(sum(delta),0) into v_points from public.eco_account_ledger where user_id=v_user;
  if p_action='plant' then
    if v_tree.planted_at is not null then raise exception 'tree already growing'; end if;
    if v_points<20 then raise exception 'not enough points'; end if;
    v_delta:=-20; v_message:='Đã trồng cây mới';
    update public.eco_tree_state set planted_at=now(),water_boosts=0,updated_at=now() where user_id=v_user;
    insert into public.eco_account_ledger(user_id,delta,reason,actor) values(v_user,v_delta,'Đầu tư trồng cây xanh',v_user);
  elsif p_action='water' then
    if v_tree.planted_at is null then raise exception 'plant first'; end if;
    if v_tree.water_boosts>=2 then raise exception 'maximum boosts reached'; end if;
    if now()-v_tree.planted_at >= interval '24 hours'-(v_tree.water_boosts*interval '6 hours') then raise exception 'tree ready to harvest'; end if;
    if v_points<5 then raise exception 'not enough points'; end if;
    v_delta:=-5; v_message:='Đã tưới cây, rút ngắn 6 giờ';
    update public.eco_tree_state set water_boosts=water_boosts+1,updated_at=now() where user_id=v_user;
    insert into public.eco_account_ledger(user_id,delta,reason,actor) values(v_user,v_delta,'Đầu tư chăm sóc cây xanh',v_user);
  elsif p_action='harvest' then
    if v_tree.planted_at is null then raise exception 'no growing tree'; end if;
    v_elapsed:=now()-v_tree.planted_at;
    v_required:=interval '24 hours'-(v_tree.water_boosts*interval '6 hours');
    if v_elapsed<v_required then raise exception 'tree not ready'; end if;
    v_delta:=40; v_message:='Thu hoạch thành công: +40 điểm';
    update public.eco_tree_state set planted_at=null,water_boosts=0,harvest_count=harvest_count+1,updated_at=now() where user_id=v_user;
    insert into public.eco_account_ledger(user_id,delta,reason,actor) values(v_user,v_delta,'Thưởng thu hoạch cây xanh',v_user);
  else raise exception 'unknown action'; end if;
  select * into v_tree from public.eco_tree_state where user_id=v_user;
  select coalesce(sum(delta),0) into v_points from public.eco_account_ledger where user_id=v_user;
  return jsonb_build_object('message',v_message,'delta',v_delta,'points',v_points,'planted_at',v_tree.planted_at,'water_boosts',v_tree.water_boosts,'harvest_count',v_tree.harvest_count);
end $$;
revoke all on function public.eco_tree_action(text) from public;
grant execute on function public.eco_tree_action(text) to authenticated;

-- Bucket công khai chỉ để đọc ảnh nhiệm vụ; quyền tải lên/xóa dành cho biên tập viên/quản trị viên.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('eco-task-images','eco-task-images',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists "eco task images public read" on storage.objects;
create policy "eco task images public read" on storage.objects for select using (bucket_id='eco-task-images');
drop policy if exists "eco task images editor upload" on storage.objects;
create policy "eco task images editor upload" on storage.objects for insert to authenticated with check (bucket_id='eco-task-images' and public.is_admin());
drop policy if exists "eco task images editor update" on storage.objects;
create policy "eco task images editor update" on storage.objects for update to authenticated using (bucket_id='eco-task-images' and public.is_admin()) with check (bucket_id='eco-task-images' and public.is_admin());
drop policy if exists "eco task images editor delete" on storage.objects;
create policy "eco task images editor delete" on storage.objects for delete to authenticated using (bucket_id='eco-task-images' and public.is_admin());

-- Cho phép người quản trị xem danh sách tài khoản để chọn đúng người nhận điểm.
drop policy if exists "editors read member profiles" on public.profiles;
create policy "editors read member profiles" on public.profiles for select to authenticated using (public.is_editor());

revoke all on public.eco_account_totals from anon;
revoke all on public.eco_public_leaderboard from anon;
grant select on public.eco_account_totals to authenticated;
grant select on public.eco_public_leaderboard to authenticated;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;
grant select on public.eco_daily_tasks, public.eco_account_ledger, public.eco_tree_state to authenticated;
