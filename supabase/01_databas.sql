-- =====================================================================
--  Stallboken Eggebyberg – databas
--  Klistra in hela filen i Supabase: SQL Editor → New query → Run.
--  Går att köra flera gånger utan att något förstörs.
-- =====================================================================

create extension if not exists btree_gist;

-- ---------- Profiler (en per inloggad person) ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  name       text not null default '',
  email      text,
  is_admin   boolean not null default false,
  created_at timestamptz not null default now()
);

-- Skapa profil automatiskt när någon bjuds in eller läggs till
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'name', ''))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Hjälpfunktion: är den inloggade admin?
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
$$;

-- ---------- Hästar ----------
create table if not exists public.horses (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 40),
  riders     text[] not null default '{}',
  created_at timestamptz not null default now()
);

-- ---------- Bokningar ----------
create table if not exists public.bookings (
  id         uuid primary key default gen_random_uuid(),
  horse_id   uuid not null references public.horses(id) on delete cascade,
  date       date not null,
  start_time time not null,
  end_time   time not null,
  rider      text not null check (char_length(rider) between 1 and 40),
  note       text not null default '' check (char_length(note) <= 80),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (end_time > start_time),
  -- samma häst kan inte bokas två gånger samtidigt
  constraint ingen_dubbelbokning exclude using gist (
    horse_id with =,
    tsrange(date + start_time, date + end_time) with &&
  )
);
create index if not exists bookings_date_idx on public.bookings (date);

-- ---------- Sysslor (listan) ----------
create table if not exists public.chores (
  id         text primary key,
  name       text not null check (char_length(name) between 1 and 40),
  sort       int  not null default 0,
  created_at timestamptz not null default now()
);
insert into public.chores (id, name, sort) values
  ('c-mocka',  'Mocka boxar',        1),
  ('c-vatten', 'Fylla på vatten',    2),
  ('c-ut',     'Släppa ut hästarna', 3),
  ('c-in',     'Ta in hästarna',     4),
  ('c-sopa',   'Sopa stallgången',   5)
on conflict (id) do nothing;

-- ---------- Avbockat (fodring och sysslor per dag) ----------
create table if not exists public.checks (
  date       date not null,
  slot       text not null,           -- 'morgon' | 'lunch' | 'kvall' | syssla-id
  done_by    text not null,
  done_at    timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  primary key (date, slot)
);

-- ---------- Anteckningar ----------
create table if not exists public.notes (
  id         uuid primary key default gen_random_uuid(),
  text       text not null default '' check (char_length(text) <= 1000),
  author     text not null default '',
  photo      text,                     -- sökväg i lagringen 'photos'
  pinned     boolean not null default false,
  pinned_at  timestamptz,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- ---------- Chatt ----------
create table if not exists public.chat (
  id         uuid primary key default gen_random_uuid(),
  text       text not null default '' check (char_length(text) <= 1000),
  author     text not null default '',
  photo      text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists chat_created_idx on public.chat (created_at desc);

-- =====================================================================
--  Säkerhet: bara inloggade kommer åt något. Ingen utan inbjudan.
-- =====================================================================
alter table public.profiles enable row level security;
alter table public.horses   enable row level security;
alter table public.bookings enable row level security;
alter table public.chores   enable row level security;
alter table public.checks   enable row level security;
alter table public.notes    enable row level security;
alter table public.chat     enable row level security;

-- Profiler: alla inloggade ser namnen, var och en ändrar bara sin egen
drop policy if exists "profiler läses av inloggade" on public.profiles;
create policy "profiler läses av inloggade" on public.profiles
  for select to authenticated using (true);
drop policy if exists "egen profil ändras" on public.profiles;
create policy "egen profil ändras" on public.profiles
  for update to authenticated using (id = auth.uid())
  with check (id = auth.uid() and is_admin = public.is_admin());

-- Gemensamma tabeller: alla inloggade får läsa och ändra
do $$
declare t text;
begin
  foreach t in array array['horses','bookings','chores','checks','notes','chat'] loop
    execute format('drop policy if exists "inloggade läser" on public.%I', t);
    execute format('create policy "inloggade läser" on public.%I for select to authenticated using (true)', t);
    execute format('drop policy if exists "inloggade skriver" on public.%I', t);
    execute format('create policy "inloggade skriver" on public.%I for insert to authenticated with check (true)', t);
    execute format('drop policy if exists "inloggade ändrar" on public.%I', t);
    execute format('create policy "inloggade ändrar" on public.%I for update to authenticated using (true) with check (true)', t);
    execute format('drop policy if exists "inloggade tar bort" on public.%I', t);
    execute format('create policy "inloggade tar bort" on public.%I for delete to authenticated using (true)', t);
  end loop;
end $$;

-- Chattmeddelanden: bara den som skrev (eller admin) kan ta bort
drop policy if exists "inloggade tar bort" on public.chat;
drop policy if exists "egna meddelanden tas bort" on public.chat;
create policy "egna meddelanden tas bort" on public.chat
  for delete to authenticated using (created_by = auth.uid() or public.is_admin());
drop policy if exists "inloggade ändrar" on public.chat;

-- =====================================================================
--  Fotolagring
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists "inloggade ser foton" on storage.objects;
create policy "inloggade ser foton" on storage.objects
  for select to authenticated using (bucket_id = 'photos');
drop policy if exists "inloggade laddar upp foton" on storage.objects;
create policy "inloggade laddar upp foton" on storage.objects
  for insert to authenticated with check (bucket_id = 'photos');
drop policy if exists "inloggade tar bort foton" on storage.objects;
create policy "inloggade tar bort foton" on storage.objects
  for delete to authenticated using (bucket_id = 'photos');

-- =====================================================================
--  Direktuppdatering (chatten och bokningar syns direkt för alla)
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['horses','bookings','chores','checks','notes','chat','profiles'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Klart!
select 'Stallbokens databas är klar' as status;
