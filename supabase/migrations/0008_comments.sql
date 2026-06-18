-- Catch SNS — 0008 댓글 + 캡션/좋아요 보조

-- ---------------------------------------------------------------- comments
create table public.comments (
  id uuid primary key default gen_random_uuid(),
  catch_id uuid not null references public.catches(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 300),
  created_at timestamptz not null default now()
);
create index comments_catch on public.comments(catch_id, created_at);

-- 댓글 수(트리거로만 갱신; catches update 컬럼 화이트리스트라 클라 직접 수정 불가)
alter table public.catches add column if not exists comment_count int not null default 0;

create or replace function public.bump_comment_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.catches set comment_count = comment_count + 1 where id = new.catch_id;
  elsif tg_op = 'DELETE' then
    update public.catches set comment_count = greatest(0, comment_count - 1) where id = old.catch_id;
  end if;
  return null;
end; $$;
drop trigger if exists trg_comment_count on public.comments;
create trigger trg_comment_count after insert or delete on public.comments
  for each row execute function public.bump_comment_count();

-- ---------------------------------------------------------------- RLS
alter table public.comments enable row level security;

-- 볼 수 있는 캐치(catches RLS가 가시성 강제)의 댓글만, 차단한 작성자 제외.
create policy comments_select on public.comments for select to authenticated
  using (
    exists (select 1 from public.catches c where c.id = catch_id)
    and not public.is_blocked(auth.uid(), author_id)
  );
create policy comments_insert on public.comments for insert to authenticated
  with check (
    author_id = auth.uid()
    and exists (
      select 1 from public.catches c
      where c.id = catch_id and not public.is_blocked(auth.uid(), c.owner_id)
    )
  );
-- 본인 댓글 또는 캐치 주인이 삭제 가능.
create policy comments_delete on public.comments for delete to authenticated
  using (
    author_id = auth.uid()
    or exists (select 1 from public.catches c where c.id = catch_id and c.owner_id = auth.uid())
  );

-- ---------------------------------------------------------------- RPC
-- 댓글 + 작성자 정보(가시성/차단은 RLS가 강제).
create or replace function public.comments_for(p_catch uuid)
returns table(id uuid, author_id uuid, body text, created_at timestamptz, username citext, display_name text)
language sql stable set search_path = public as $$
  select cm.id, cm.author_id, cm.body, cm.created_at, p.username, p.display_name
  from public.comments cm
  join public.profiles p on p.id = cm.author_id
  where cm.catch_id = p_catch
  order by cm.created_at asc;
$$;
grant execute on function public.comments_for(uuid) to authenticated;
