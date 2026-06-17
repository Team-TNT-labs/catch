-- Catch SNS — 0001 schema
create extension if not exists "citext";
create extension if not exists "pg_trgm";

-- ---------------------------------------------------------------- profiles
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username citext unique check (username ~ '^[a-z0-9_]{3,20}$'),  -- null 허용(온보딩에서 설정)
  display_name text check (char_length(display_name) <= 50),
  avatar_url text,
  bio text check (char_length(bio) <= 300),
  username_changed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index profiles_username_trgm on public.profiles using gin (username gin_trgm_ops);

create table public.reserved_usernames ( name citext primary key );
insert into public.reserved_usernames(name) values
 ('admin'),('administrator'),('catch'),('support'),('help'),('official'),
 ('root'),('system'),('moderator'),('staff'),('about'),('terms'),
 ('privacy'),('api'),('null'),('me'),('settings') on conflict do nothing;

-- ---------------------------------------------------------------- folders
create table public.folders (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 50),
  is_public boolean not null default true,
  sort int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index folders_owner on public.folders(owner_id);

-- ---------------------------------------------------------------- catches
create table public.catches (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  folder_id uuid references public.folders(id) on delete set null,
  image_path text not null,           -- storage object name: catches/{owner}/{id}.png
  body_path text,                     -- catches/{owner}/{id}_body.png
  width int, height int,
  title text check (char_length(title) <= 100),
  is_public boolean not null default true,
  like_count int not null default 0,  -- 트리거로만 갱신(컬럼 grant로 클라 차단)
  caught_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index catches_owner_feed on public.catches(owner_id, is_public, caught_at desc);
create index catches_folder on public.catches(folder_id);
create index catches_keyset on public.catches(caught_at desc, id desc);

-- ---------------------------------------------------------------- follows
create table public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followee_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index follows_followee on public.follows(followee_id);

-- ---------------------------------------------------------------- likes
create table public.likes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  catch_id uuid not null references public.catches(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, catch_id)
);
create index likes_catch on public.likes(catch_id);

-- ---------------------------------------------------------------- blocks
create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index blocks_blocked on public.blocks(blocked_id);

-- ---------------------------------------------------------------- reports
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('catch','user')),
  target_id uuid not null,
  reason text check (char_length(reason) <= 500),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- entitlements (서버만 기록)
create table public.entitlements (
  user_id uuid not null references public.profiles(id) on delete cascade,
  product_id text not null,
  acquired_at timestamptz not null default now(),
  primary key (user_id, product_id)
);
