-- Catch SNS — 0004 storage bucket & policies
insert into storage.buckets (id, name, public)
  values ('stickers', 'stickers', false)
  on conflict (id) do nothing;

-- 쓰기/수정/삭제: 경로 catches/{owner}/... 의 owner가 본인일 때만
create policy "stickers_insert_own" on storage.objects for insert to authenticated
  with check ( bucket_id = 'stickers'
    and (storage.foldername(name))[1] = 'catches'
    and (storage.foldername(name))[2] = auth.uid()::text );

create policy "stickers_update_own" on storage.objects for update to authenticated
  using ( bucket_id = 'stickers' and (storage.foldername(name))[2] = auth.uid()::text );

create policy "stickers_delete_own" on storage.objects for delete to authenticated
  using ( bucket_id = 'stickers' and (storage.foldername(name))[2] = auth.uid()::text );

-- 읽기: 본인 것이거나, 가시성(공개 캐치 + 공개 폴더 + 비차단) 통과한 객체만
create policy "stickers_read_visible" on storage.objects for select to authenticated
  using (
    bucket_id = 'stickers' and (
      (storage.foldername(name))[2] = auth.uid()::text
      or exists (
        select 1 from public.catches c
        where (c.image_path = name or c.body_path = name)
          and c.is_public
          and (c.folder_id is null
               or exists(select 1 from public.folders f where f.id = c.folder_id and f.is_public))
          and not public.is_blocked(auth.uid(), c.owner_id)
      )
    )
  );
