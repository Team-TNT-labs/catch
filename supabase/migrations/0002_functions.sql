-- Catch SNS — 0002 functions & triggers

-- 양방향 차단 여부 (security definer로 blocks RLS 우회)
create or replace function public.is_blocked(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select a is not null and b is not null and exists(
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  );
$$;

-- 신규 auth.users → profiles 자동 생성
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',
                           new.raw_user_meta_data->>'name'))
  on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- username 예약어 거부 + 변경 쿨다운(30일)
create or replace function public.check_username()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.username is not null then
    if exists(select 1 from public.reserved_usernames where name = new.username) then
      raise exception 'username_reserved';
    end if;
    if tg_op = 'UPDATE' and old.username is not null and new.username <> old.username then
      if old.username_changed_at is not null and old.username_changed_at > now() - interval '30 days' then
        raise exception 'username_change_cooldown';
      end if;
      new.username_changed_at := now();
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists trg_check_username on public.profiles;
create trigger trg_check_username before insert or update of username on public.profiles
  for each row execute function public.check_username();

-- like_count 유지 (security definer → 컬럼 grant와 무관하게 갱신)
create or replace function public.bump_like_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.catches set like_count = like_count + 1 where id = new.catch_id;
  elsif tg_op = 'DELETE' then
    update public.catches set like_count = greatest(0, like_count - 1) where id = old.catch_id;
  end if;
  return null;
end; $$;
drop trigger if exists trg_like_count on public.likes;
create trigger trg_like_count after insert or delete on public.likes
  for each row execute function public.bump_like_count();

-- updated_at 자동 갱신
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;
drop trigger if exists trg_touch_profiles on public.profiles;
create trigger trg_touch_profiles before update on public.profiles for each row execute function public.touch_updated_at();
drop trigger if exists trg_touch_folders on public.folders;
create trigger trg_touch_folders before update on public.folders for each row execute function public.touch_updated_at();
drop trigger if exists trg_touch_catches on public.catches;
create trigger trg_touch_catches before update on public.catches for each row execute function public.touch_updated_at();

-- 계정 삭제(본인): auth.users 삭제 → cascade. Storage는 클라/Edge에서 별도 정리.
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  delete from auth.users where id = auth.uid();
end; $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
