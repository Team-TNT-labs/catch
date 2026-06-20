-- Catch SNS — 0012 아바타 스토리지 + 팔로잉 프로필 목록

-- ---------------------------------------------------------------- avatars 버킷(공개 읽기)
insert into storage.buckets (id, name, public)
  values ('avatars', 'avatars', true)
  on conflict (id) do nothing;

-- 경로 avatars/{uid}/... 의 uid가 본인일 때만 쓰기/수정/삭제
create policy "avatars_insert_own" on storage.objects for insert to authenticated
  with check ( bucket_id = 'avatars' and (storage.foldername(name))[2] = auth.uid()::text );
create policy "avatars_update_own" on storage.objects for update to authenticated
  using ( bucket_id = 'avatars' and (storage.foldername(name))[2] = auth.uid()::text );
create policy "avatars_delete_own" on storage.objects for delete to authenticated
  using ( bucket_id = 'avatars' and (storage.foldername(name))[2] = auth.uid()::text );
-- 읽기: 아바타는 공개 프로필 사진이라 인증 사용자 모두 열람
create policy "avatars_read" on storage.objects for select to authenticated
  using ( bucket_id = 'avatars' );

-- ---------------------------------------------------------------- 내가 팔로우하는 프로필 목록
create or replace function public.following_profiles()
returns setof public.profiles language sql stable set search_path = public as $$
  select p.* from public.profiles p
  join public.follows f on f.followee_id = p.id
  where f.follower_id = auth.uid()
  order by f.created_at desc;
$$;
grant execute on function public.following_profiles() to authenticated;
