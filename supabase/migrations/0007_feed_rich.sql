-- 팔로잉 피드(소유자 정보 + 좋아요 여부 포함, 키셋). catches RLS가 가시성 강제.
create or replace function public.following_feed_rich(
  p_limit int default 20,
  p_before timestamptz default null,
  p_before_id uuid default null
) returns table(
  id uuid, owner_id uuid, image_path text, body_path text,
  like_count int, caught_at timestamptz,
  username citext, display_name text, liked boolean
) language sql stable set search_path = public as $$
  select c.id, c.owner_id, c.image_path, c.body_path, c.like_count, c.caught_at,
         p.username, p.display_name,
         exists(select 1 from public.likes l where l.catch_id = c.id and l.user_id = auth.uid()) as liked
  from public.catches c
  join public.profiles p on p.id = c.owner_id
  where c.owner_id in (select followee_id from public.follows where follower_id = auth.uid())
    and (p_before is null or (c.caught_at, c.id) < (p_before, p_before_id))
  order by c.caught_at desc, c.id desc
  limit greatest(1, least(p_limit, 50));
$$;
grant execute on function public.following_feed_rich(int, timestamptz, uuid) to authenticated;
