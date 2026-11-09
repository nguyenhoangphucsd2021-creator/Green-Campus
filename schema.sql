-- Green Campus database schema (Supabase / PostgreSQL)
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role text not null default 'member' check (role in ('member','editor','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.content_items (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  excerpt text not null default '',
  body text not null default '',
  category text not null default 'news',
  icon text not null default '🌱',
  image_url text,
  source_url text,
  source_name text,
  fingerprint text unique,
  status text not null default 'draft' check (status in ('draft','pending_review','published','rejected','archived')),
  created_by uuid references auth.users(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  collected_at timestamptz,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists content_items_status_category_idx on public.content_items(status, category);
create index if not exists content_items_created_at_idx on public.content_items(created_at desc);

create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  content_id uuid references public.content_items(id) on delete set null,
  kind text not null default 'general',
  message text not null,
  contact text,
  created_at timestamptz not null default now()
);

create table if not exists public.activity_events (
  id uuid primary key default gen_random_uuid(),
  event_name text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.is_editor()
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('editor','admin')); $$;

alter table public.profiles enable row level security;
alter table public.content_items enable row level security;
alter table public.feedback enable row level security;
alter table public.activity_events enable row level security;

-- Public can only read published content.
drop policy if exists "public read published content" on public.content_items;
create policy "public read published content" on public.content_items for select using (status = 'published');
drop policy if exists "editors read all content" on public.content_items;
create policy "editors read all content" on public.content_items for select to authenticated using (public.is_editor());
drop policy if exists "editors insert content" on public.content_items;
create policy "editors insert content" on public.content_items for insert to authenticated with check (public.is_editor());
drop policy if exists "editors update content" on public.content_items;
create policy "editors update content" on public.content_items for update to authenticated using (public.is_editor()) with check (public.is_editor());
drop policy if exists "editors delete content" on public.content_items;
create policy "editors delete content" on public.content_items for delete to authenticated using (public.is_editor());

drop policy if exists "users read own profile" on public.profiles;
create policy "users read own profile" on public.profiles for select to authenticated using (id = auth.uid() or public.is_editor());
-- Least privilege: authenticated users may change only their own display name.
-- Never allow an editor to update role (including their own role) through PostgREST.
drop policy if exists "editors manage profiles" on public.profiles;
drop policy if exists "users update own profile" on public.profiles;
revoke update on public.profiles from public, anon, authenticated;
grant update (display_name) on public.profiles to authenticated;
create policy "users update own profile" on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists "public submit feedback" on public.feedback;
create policy "public submit feedback" on public.feedback for insert with check (char_length(message) between 3 and 2000);
drop policy if exists "editors read feedback" on public.feedback;
create policy "editors read feedback" on public.feedback for select to authenticated using (public.is_editor());

-- Public analytics are aggregate-only inserts; do not place personal or sensitive data in payload.
drop policy if exists "public record activity" on public.activity_events;
create policy "public record activity" on public.activity_events for insert with check (char_length(event_name) between 1 and 80);
drop policy if exists "editors read activity" on public.activity_events;
create policy "editors read activity" on public.activity_events for select to authenticated using (public.is_editor());

-- Create the first admin manually after signing up:
-- update public.profiles set role='admin' where id='AUTH_USER_UUID';
-- Add a profile row for each auth user using a trusted server-side trigger or dashboard.

-- Automatically create a least-privilege member profile for new signups.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)), 'member')
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created_green_campus on auth.users;
create trigger on_auth_user_created_green_campus
after insert on auth.users for each row execute procedure public.handle_new_user();

-- Operational indexes and safe defaults for Green Campus metrics / feedback.
create index if not exists activity_events_name_created_idx on public.activity_events(event_name, created_at desc);
create index if not exists feedback_created_idx on public.feedback(created_at desc);
