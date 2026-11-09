-- Chay MỘT LẦN trong Supabase SQL Editor sau schema.sql.
-- Quản trị viên/editor tạo điểm ở trạng thái pending; chỉ điểm verified mới công khai.
create table if not exists public.collection_points (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 3 and 140),
  address text not null check (char_length(trim(address)) between 5 and 300),
  materials text not null default '' check (char_length(materials) <= 500),
  hours text not null default '' check (char_length(hours) <= 160),
  contact text not null default '' check (char_length(contact) <= 160),
  notes text not null default '' check (char_length(notes) <= 500),
  status text not null default 'pending' check (status in ('pending','verified','rejected')),
  created_by uuid references auth.users(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists collection_points_status_created_idx on public.collection_points(status, created_at desc);
alter table public.collection_points enable row level security;
drop policy if exists "public read verified collection points" on public.collection_points;
create policy "public read verified collection points" on public.collection_points for select using (status='verified');
drop policy if exists "editors read all collection points" on public.collection_points;
create policy "editors read all collection points" on public.collection_points for select to authenticated using (public.is_editor());
drop policy if exists "editors insert collection points" on public.collection_points;
create policy "editors insert collection points" on public.collection_points for insert to authenticated with check (public.is_editor() and (created_by is null or created_by=auth.uid()));
drop policy if exists "editors update collection points" on public.collection_points;
create policy "editors update collection points" on public.collection_points for update to authenticated using (public.is_editor()) with check (public.is_editor());
drop policy if exists "editors delete collection points" on public.collection_points;
create policy "editors delete collection points" on public.collection_points for delete to authenticated using (public.is_editor());
grant select on public.collection_points to anon, authenticated;
grant insert, update, delete on public.collection_points to authenticated;
