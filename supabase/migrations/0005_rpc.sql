-- Catch SNS — 0005 RPCs

-- username 사용 가능 여부(형식 + 예약어 + 중복)
create or replace function public.username_available(name citext)
returns boolean language sql stable security definer set search_path = public as $$
  select name ~ '^[a-z0-9_]{3,20}$'
     and not exists (select 1 from public.reserved_usernames r where r.name = username_available.name)
     and not exists (select 1 from public.profiles p where p.username = username_available.name);
$$;
grant execute on function public.username_available(citext) to authenticated;

-- 팔로잉 피드(키셋 페이지네이션). catches RLS가 가시성/차단을 그대로 강제.
create or replace function public.following_feed(
  p_limit int default 20,
  p_before_caught_at timestamptz default null,
  p_before_id uuid default null
) returns setof public.catches language sql stable set search_path = public as $$
  select c.* from public.catches c
  where c.owner_id in (select followee_id from public.follows where follower_id = auth.uid())
    and ( p_before_caught_at is null
          or (c.caught_at, c.id) < (p_before_caught_at, p_before_id) )
  order by c.caught_at desc, c.id desc
  limit greatest(1, least(p_limit, 50));
$$;
grant execute on function public.following_feed(int, timestamptz, uuid) to authenticated;

-- 프로필 카운트(수집/팔로워/팔로잉)
create or replace function public.profile_counts(p_user uuid)
returns table(collections bigint, followers bigint, following bigint)
language sql stable set search_path = public as $$
  select
    (select count(*) from public.catches c
       where c.owner_id = p_user and (c.owner_id = auth.uid() or c.is_public)),
    (select count(*) from public.follows f where f.followee_id = p_user),
    (select count(*) from public.follows f where f.follower_id = p_user);
$$;
grant execute on function public.profile_counts(uuid) to authenticated;
