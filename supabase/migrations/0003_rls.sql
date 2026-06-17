-- Catch SNS — 0003 RLS policies
alter table public.profiles          enable row level security;
alter table public.reserved_usernames enable row level security;  -- 정책 없음 = 클라 접근 불가(트리거는 definer)
alter table public.folders           enable row level security;
alter table public.catches           enable row level security;
alter table public.follows           enable row level security;
alter table public.likes             enable row level security;
alter table public.blocks            enable row level security;
alter table public.reports           enable row level security;
alter table public.entitlements      enable row level security;

-- ---------------------------------------------------------------- profiles
create policy profiles_select on public.profiles for select to authenticated
  using ( id = auth.uid() or not public.is_blocked(auth.uid(), id) );
create policy profiles_update on public.profiles for update to authenticated
  using ( id = auth.uid() ) with check ( id = auth.uid() );

-- ---------------------------------------------------------------- folders
create policy folders_select on public.folders for select to authenticated
  using ( owner_id = auth.uid()
          or (is_public and not public.is_blocked(auth.uid(), owner_id)) );
create policy folders_insert on public.folders for insert to authenticated
  with check ( owner_id = auth.uid() );
create policy folders_update on public.folders for update to authenticated
  using ( owner_id = auth.uid() ) with check ( owner_id = auth.uid() );
create policy folders_delete on public.folders for delete to authenticated
  using ( owner_id = auth.uid() );

-- ---------------------------------------------------------------- catches (가시성 핵심)
create policy catches_select on public.catches for select to authenticated
  using (
    owner_id = auth.uid()
    or (
      is_public
      and (folder_id is null
           or exists(select 1 from public.folders f where f.id = folder_id and f.is_public))
      and not public.is_blocked(auth.uid(), owner_id)
    )
  );
create policy catches_insert on public.catches for insert to authenticated
  with check ( owner_id = auth.uid() );
create policy catches_update on public.catches for update to authenticated
  using ( owner_id = auth.uid() ) with check ( owner_id = auth.uid() );
create policy catches_delete on public.catches for delete to authenticated
  using ( owner_id = auth.uid() );

-- like_count 클라 직접 수정 차단: update 컬럼 화이트리스트(트리거는 definer라 영향 없음)
revoke update on public.catches from authenticated, anon;
grant update (folder_id, title, is_public) on public.catches to authenticated;

-- ---------------------------------------------------------------- follows
create policy follows_select on public.follows for select to authenticated
  using ( not public.is_blocked(auth.uid(), follower_id)
          and not public.is_blocked(auth.uid(), followee_id) );
create policy follows_insert on public.follows for insert to authenticated
  with check ( follower_id = auth.uid()
               and not public.is_blocked(auth.uid(), followee_id) );
create policy follows_delete on public.follows for delete to authenticated
  using ( follower_id = auth.uid() );

-- ---------------------------------------------------------------- likes
create policy likes_select on public.likes for select to authenticated using ( true );
create policy likes_insert on public.likes for insert to authenticated
  with check ( user_id = auth.uid()
               and not public.is_blocked(auth.uid(),
                     (select owner_id from public.catches c where c.id = catch_id)) );
create policy likes_delete on public.likes for delete to authenticated
  using ( user_id = auth.uid() );

-- ---------------------------------------------------------------- blocks
create policy blocks_select on public.blocks for select to authenticated
  using ( blocker_id = auth.uid() );
create policy blocks_insert on public.blocks for insert to authenticated
  with check ( blocker_id = auth.uid() );
create policy blocks_delete on public.blocks for delete to authenticated
  using ( blocker_id = auth.uid() );

-- ---------------------------------------------------------------- reports
create policy reports_insert on public.reports for insert to authenticated
  with check ( reporter_id = auth.uid() );
create policy reports_select on public.reports for select to authenticated
  using ( reporter_id = auth.uid() );

-- ---------------------------------------------------------------- entitlements (읽기만, 쓰기는 서버)
create policy entitlements_select on public.entitlements for select to authenticated
  using ( user_id = auth.uid() );
